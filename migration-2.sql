-- =====================================================================
--  Chasse Note — étape 2 : identifiants + historique des connexions
--  Idempotent : peut être relancé sans risque.
-- =====================================================================

-- ---------- Identifiant de connexion (ex. ollivier.a) ----------
alter table public.profils add column if not exists identifiant text;
create unique index if not exists profils_identifiant_uniq on public.profils (lower(identifiant));
alter table public.profils drop constraint if exists profils_identifiant_format;
alter table public.profils add constraint profils_identifiant_format
  check (identifiant is null or identifiant ~ '^[a-z0-9._-]{3,30}$');

-- Trouve l'e-mail de connexion à partir de l'identifiant (utilisé par l'écran de connexion)
create or replace function public.email_pour_identifiant(p text) returns text
language sql stable security definer set search_path = '' as $$
  select u.email::text from public.profils p2 join auth.users u on u.id = p2.id
  where lower(p2.identifiant) = lower(trim(p)) and p2.statut <> 'bloque' limit 1;
$$;

create or replace function public.identifiant_libre(p text) returns boolean
language sql stable security definer set search_path = '' as $$
  select not exists(select 1 from public.profils where lower(identifiant) = lower(trim(p)));
$$;

-- Le profil reprend l'identifiant choisi à l'inscription
create or replace function public.nouveau_profil() returns trigger
language plpgsql security definer set search_path = '' as $$
declare premier boolean; ident text;
begin
  select not exists(select 1 from public.profils where role = 'admin') into premier;
  ident := lower(nullif(trim(new.raw_user_meta_data->>'identifiant'), ''));
  if ident is not null and (ident !~ '^[a-z0-9._-]{3,30}$'
      or exists(select 1 from public.profils where lower(identifiant) = ident)) then
    ident := null;
  end if;
  insert into public.profils(id, pseudo, identifiant, role, statut)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'pseudo'), ''), split_part(new.email, '@', 1)),
    ident,
    case when premier then 'admin' else 'membre' end,
    case when premier then 'actif' else 'en_attente' end
  )
  on conflict (id) do nothing;
  return new;
end $$;

-- ---------- Historique des connexions ----------
create table if not exists public.connexions (
  id          bigserial primary key,
  user_id     uuid references auth.users(id) on delete cascade,
  identifiant text,
  quand       timestamptz not null default now(),
  type        text not null check (type in ('connexion','echec')),
  ip          text,
  appareil    text
);
create index if not exists connexions_quand_idx on public.connexions (quand desc);
alter table public.connexions enable row level security;

drop policy if exists "connexions_lecture" on public.connexions;
create policy "connexions_lecture" on public.connexions for select to authenticated
  using (public.est_admin() or user_id = (select auth.uid()));
grant select on public.connexions to authenticated;
revoke all on public.connexions from anon;

-- Chaque connexion réussie (nouvelle session) est enregistrée côté serveur, avec IP et appareil
create or replace function public.noter_connexion() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  begin
    insert into public.connexions(user_id, identifiant, type, ip, appareil)
    select new.user_id, p.identifiant, 'connexion', host(new.ip), left(new.user_agent, 300)
    from (select 1) x left join public.profils p on p.id = new.user_id;
  exception when others then null;  -- ne jamais bloquer une connexion
  end;
  return new;
end $$;

drop trigger if exists on_auth_session_created on auth.sessions;
create trigger on_auth_session_created
  after insert on auth.sessions
  for each row execute function public.noter_connexion();

-- Tentatives échouées (mauvais mot de passe / identifiant inconnu)
create or replace function public.noter_echec(p_identifiant text, p_appareil text) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid;
begin
  select id into uid from public.profils where lower(identifiant) = lower(trim(p_identifiant)) limit 1;
  insert into public.connexions(user_id, identifiant, type, appareil)
  values (uid, left(lower(trim(p_identifiant)), 60), 'echec', left(p_appareil, 300));
end $$;

-- ---------- Vues administrateur ----------
drop function if exists public.admin_membres();
create function public.admin_membres()
returns table(id uuid, pseudo text, identifiant text, email text, role text, statut text, partage boolean,
              cree_le timestamptz, derniere_connexion timestamptz, nb_connexions bigint, nb_echecs bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.est_admin() then raise exception 'Réservé à l''administrateur'; end if;
  return query
    select p.id, p.pseudo, p.identifiant, u.email::text, p.role, p.statut, p.partage, p.cree_le,
           u.last_sign_in_at,
           (select count(*) from public.connexions c where c.user_id = p.id and c.type = 'connexion'),
           (select count(*) from public.connexions c where c.user_id = p.id and c.type = 'echec')
    from public.profils p join auth.users u on u.id = p.id
    order by p.cree_le;
end $$;

create or replace function public.admin_connexions(p_limite int default 300)
returns table(quand timestamptz, type text, identifiant text, pseudo text, ip text, appareil text)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.est_admin() then raise exception 'Réservé à l''administrateur'; end if;
  return query
    select c.quand, c.type, coalesce(p.identifiant, c.identifiant), p.pseudo, c.ip, c.appareil
    from public.connexions c left join public.profils p on p.id = c.user_id
    order by c.quand desc limit least(greatest(p_limite, 1), 1000);
end $$;

-- ---------- Droits ----------
revoke execute on function public.admin_membres(), public.admin_connexions(int) from public, anon;
grant execute on function public.admin_membres(), public.admin_connexions(int) to authenticated;
grant execute on function public.email_pour_identifiant(text), public.identifiant_libre(text),
  public.noter_echec(text, text) to anon, authenticated;

-- ---------- Identifiant de l'administrateur ----------
update public.profils set identifiant = 'ollivier.a'
where role = 'admin' and statut = 'actif' and identifiant is null
  and (select count(*) from public.profils where role = 'admin') = 1
  and not exists (select 1 from public.profils where lower(identifiant) = 'ollivier.a');

select pseudo, identifiant, role, statut from public.profils order by cree_le;
