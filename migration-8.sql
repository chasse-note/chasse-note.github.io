-- Chasse Note — étape 8 : paramètres du groupe (formulaire « Nouvelle session »)
create table if not exists public.parametres (
  cle      text primary key,
  valeur   jsonb not null default '{}'::jsonb,
  maj_le   timestamptz not null default now(),
  maj_par  uuid references auth.users(id) on delete set null
);
alter table public.parametres enable row level security;
create policy "param_lecture" on public.parametres for select to authenticated using (true);
create policy "param_creation" on public.parametres for insert to authenticated with check (public.est_admin());
create policy "param_maj" on public.parametres for update to authenticated using (public.est_admin()) with check (public.est_admin());
grant select, insert, update on public.parametres to authenticated;
