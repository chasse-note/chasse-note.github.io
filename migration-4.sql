-- =====================================================================
--  Chasse Note — étape 4 : l'administrateur peut changer l'e-mail d'un membre
--  Idempotent : peut être relancé sans risque.
-- =====================================================================
create or replace function public.admin_changer_email(p_user uuid, p_email text) returns text
language plpgsql security definer set search_path = '' as $$
declare e text := lower(trim(p_email));
begin
  if not public.est_admin() then
    raise exception 'Réservé à l''administrateur';
  end if;
  if e !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Adresse e-mail invalide';
  end if;
  if exists(select 1 from auth.users where lower(email) = e and id <> p_user) then
    raise exception 'Cette adresse e-mail est déjà utilisée par un autre compte';
  end if;
  update auth.users
     set email = e,
         email_confirmed_at = coalesce(email_confirmed_at, now()),
         updated_at = now()
   where id = p_user;
  if not found then
    raise exception 'Compte introuvable';
  end if;
  update auth.identities
     set identity_data = jsonb_set(coalesce(identity_data, '{}'::jsonb), '{email}', to_jsonb(e)),
         updated_at = now()
   where user_id = p_user and provider = 'email';
  return e;
end $$;

revoke execute on function public.admin_changer_email(uuid, text) from public, anon;
grant execute on function public.admin_changer_email(uuid, text) to authenticated;

select 'admin_changer_email installée' as resultat;
