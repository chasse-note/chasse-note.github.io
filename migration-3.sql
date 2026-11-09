-- =====================================================================
--  Chasse Note — étape 3 : carnets visibles par le groupe (lecture seule)
--  - Chacun ne peut MODIFIER que son propre carnet.
--  - L'administrateur peut LIRE tous les carnets.
--  - Les membres validés peuvent LIRE les carnets des membres validés
--    qui partagent (case « Partager mon carnet avec le groupe »).
--  Idempotent : peut être relancé sans risque.
-- =====================================================================
drop policy if exists "carnets_proprietaire" on public.carnets;
drop policy if exists "carnets_lecture"      on public.carnets;
drop policy if exists "carnets_creation"     on public.carnets;
drop policy if exists "carnets_maj"          on public.carnets;
drop policy if exists "carnets_suppression"  on public.carnets;

create policy "carnets_lecture" on public.carnets for select to authenticated
  using (
    user_id = (select auth.uid())
    or public.est_admin()
    or (public.est_actif() and exists (
          select 1 from public.profils p
          where p.id = carnets.user_id and p.statut = 'actif' and p.partage))
  );
create policy "carnets_creation" on public.carnets for insert to authenticated
  with check (user_id = (select auth.uid()));
create policy "carnets_maj" on public.carnets for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "carnets_suppression" on public.carnets for delete to authenticated
  using (user_id = (select auth.uid()));

-- L'administrateur voit aussi les stats de tout le monde (même masqués / en attente)
drop policy if exists "stats_admin_lecture" on public.stats_saison;
create policy "stats_admin_lecture" on public.stats_saison for select to authenticated
  using (public.est_admin());

select policyname, cmd from pg_policies where tablename = 'carnets' order by policyname;
