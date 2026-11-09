-- =====================================================================
--  Chasse Note — schéma Supabase
--  À coller en entier dans Supabase > SQL Editor > New query > Run.
--  Peut être relancé sans risque (idempotent).
--
--  Règle d'administration : le PREMIER compte créé devient administrateur
--  et est actif d'office. Les comptes suivants sont « en attente » jusqu'à
--  validation par un administrateur dans l'onglet Groupe de l'appli.
-- =====================================================================

-- ---------- Tables ----------
create table if not exists public.profils (
  id        uuid primary key references auth.users(id) on delete cascade,
  pseudo    text not null default '',
  commune   text not null default '',
  role      text not null default 'membre' check (role in ('admin','membre')),
  statut    text not null default 'en_attente' check (statut in ('en_attente','actif','bloque')),
  partage   boolean not null default true,
  cree_le   timestamptz not null default now()
);

-- Carnet complet de chaque chasseur (privé : lieux, notes, compagnons…)
create table if not exists public.carnets (
  user_id  uuid primary key references auth.users(id) on delete cascade,
  data     jsonb not null,
  maj_le   timestamptz not null default now()
);

-- Statistiques publiées par saison (sans lieux ni notes) : ce que voit le groupe
create table if not exists public.stats_saison (
  user_id    uuid not null references auth.users(id) on delete cascade,
  saison     int  not null,
  sorties    int  not null default 0,
  tues       int  not null default 0,
  vues       int  not null default 0,
  blessees   int  not null default 0,
  perdues    int  not null default 0,
  cartouches int  not null default 0,
  km         numeric not null default 0,
  duree_min  int  not null default 0,
  vols       int  not null default 0,
  especes    jsonb not null default '[]'::jsonb,
  maj_le     timestamptz not null default now(),
  primary key (user_id, saison)
);
create index if not exists stats_saison_saison_idx on public.stats_saison(saison);

-- ---------- Fonctions utilitaires (security definer : évite la récursion RLS) ----------
create or replace function public.est_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.profils
                where id = (select auth.uid()) and role = 'admin' and statut = 'actif');
$$;

create or replace function public.est_actif() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.profils
                where id = (select auth.uid()) and statut = 'actif');
$$;

-- Création automatique du profil à l'inscription
create or replace function public.nouveau_profil() returns trigger
language plpgsql security definer set search_path = '' as $$
declare premier boolean;
begin
  select not exists(select 1 from public.profils where role = 'admin') into premier;
  insert into public.profils(id, pseudo, role, statut)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'pseudo'), ''), split_part(new.email, '@', 1)),
    case when premier then 'admin' else 'membre' end,
    case when premier then 'actif' else 'en_attente' end
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.nouveau_profil();

-- Un membre ne peut pas changer son propre rôle ou statut ; il doit rester un admin
create or replace function public.proteger_profil() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.id := old.id;
  new.cree_le := old.cree_le;
  if (select auth.uid()) is not null and not public.est_admin() then
    new.role := old.role;
    new.statut := old.statut;
  end if;
  if old.role = 'admin' and (new.role <> 'admin' or new.statut <> 'actif')
     and (select count(*) from public.profils where role = 'admin' and statut = 'actif') <= 1 then
    raise exception 'Il doit rester au moins un administrateur actif';
  end if;
  return new;
end $$;

drop trigger if exists profils_protection on public.profils;
create trigger profils_protection
  before update on public.profils
  for each row execute function public.proteger_profil();

-- Liste des membres avec e-mail : réservée à l'administrateur
create or replace function public.admin_membres()
returns table(id uuid, pseudo text, email text, role text, statut text, partage boolean, cree_le timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.est_admin() then
    raise exception 'Réservé à l''administrateur';
  end if;
  return query
    select p.id, p.pseudo, u.email::text, p.role, p.statut, p.partage, p.cree_le
    from public.profils p join auth.users u on u.id = p.id
    order by p.cree_le;
end $$;

-- ---------- Sécurité par ligne (RLS) ----------
alter table public.profils      enable row level security;
alter table public.carnets      enable row level security;
alter table public.stats_saison enable row level security;

drop policy if exists "profils_lecture"     on public.profils;
drop policy if exists "profils_creation"    on public.profils;
drop policy if exists "profils_maj"         on public.profils;
drop policy if exists "profils_suppression" on public.profils;
create policy "profils_lecture" on public.profils for select to authenticated
  using (id = (select auth.uid()) or public.est_actif());
create policy "profils_creation" on public.profils for insert to authenticated
  with check (id = (select auth.uid()) and role = 'membre' and statut = 'en_attente');
create policy "profils_maj" on public.profils for update to authenticated
  using (id = (select auth.uid()) or public.est_admin())
  with check (id = (select auth.uid()) or public.est_admin());
create policy "profils_suppression" on public.profils for delete to authenticated
  using (public.est_admin() and id <> (select auth.uid()));

drop policy if exists "carnets_proprietaire" on public.carnets;
create policy "carnets_proprietaire" on public.carnets for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "stats_proprietaire" on public.stats_saison;
drop policy if exists "stats_groupe"       on public.stats_saison;
drop policy if exists "stats_admin_suppr"  on public.stats_saison;
create policy "stats_proprietaire" on public.stats_saison for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy "stats_groupe" on public.stats_saison for select to authenticated
  using (
    public.est_actif() and exists (
      select 1 from public.profils p
      where p.id = stats_saison.user_id and p.statut = 'actif' and p.partage
    )
  );
create policy "stats_admin_suppr" on public.stats_saison for delete to authenticated
  using (public.est_admin());

-- ---------- Droits d'accès API ----------
grant usage on schema public to authenticated;
grant select, insert, update, delete on public.profils, public.carnets, public.stats_saison to authenticated;
revoke all on public.profils, public.carnets, public.stats_saison from anon;
revoke execute on function public.admin_membres() from public, anon;
grant execute on function public.admin_membres(), public.est_admin(), public.est_actif() to authenticated;
