-- DRAFT - contributor lockdown for Hivner Meals. Direction approved by Corey
-- (Nov 1, 2026: email sign-in links, only Corey and Erin contribute).
-- DO NOT RUN without his explicit go-ahead, and only AFTER the app update that
-- understands email sign-in is live, because this migration ends anonymous
-- family-key access to household_state (older app versions lose sync by design).
--
-- Emails and the household slug stay OUT of this public repo: set them with
-- set_config in the same SQL Editor transaction, like public-recipes.sql does:
--   select set_config('home_meals.household_slug', '<current private family key>', true);
--   select set_config('home_meals.contributor_emails', '<corey-email>,<erin-email>', true);

create schema if not exists home_meals_private;
revoke all on schema home_meals_private from public, anon, authenticated;

-- 1) The contributor allowlist: these emails, and only these, may read/write
--    the family book. Sign-in itself is Supabase Auth email magic links
--    (free tier, no SMS provider, no cost).
create table if not exists home_meals_private.contributors(email text primary key);
revoke all on home_meals_private.contributors from public, anon, authenticated;
insert into home_meals_private.contributors(email)
select lower(trim(e))
from unnest(string_to_array(current_setting('home_meals.contributor_emails'), ',')) as e
on conflict (email) do nothing;

-- public-recipes.sql already stores the household slug here. If it has not
-- been applied yet, create the same private config row now.
create table if not exists home_meals_private.public_source (
  singleton boolean primary key default true check (singleton),
  household_slug text not null
);
revoke all on home_meals_private.public_source from public, anon, authenticated;
insert into home_meals_private.public_source(singleton, household_slug)
values (true, current_setting('home_meals.household_slug'))
on conflict (singleton) do update set household_slug = excluded.household_slug;

-- 2) A signed-in contributor asks the backend which household is theirs.
--    The app calls this after the magic-link session starts; the slug never
--    needs to ride in a URL again.
create or replace function public.home_meals_contributor_household()
returns text
language sql stable security definer set search_path = ''
as $$
  select cfg.household_slug
  from home_meals_private.public_source as cfg
  where exists (
    select 1 from home_meals_private.contributors as c
    where c.email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
revoke all on function public.home_meals_contributor_household() from public;
grant execute on function public.home_meals_contributor_household() to authenticated;

-- 3) Lock the family book. Public recipe reading keeps working through the
--    existing security-definer public.home_meals_public_recipes() RPC, which
--    is recipe-only and does not depend on table grants for anon.
alter table public.household_state enable row level security;
revoke all on public.household_state from anon;
revoke all on public.household_state from authenticated;
create policy home_meals_contributors_all on public.household_state
  for all to authenticated
  using (exists (
    select 1 from home_meals_private.contributors as c
    where c.email = lower(coalesce(auth.jwt() ->> 'email', ''))
  ))
  with check (exists (
    select 1 from home_meals_private.contributors as c
    where c.email = lower(coalesce(auth.jwt() ->> 'email', ''))
  ));

-- VERIFY, in this order:
--   1. select public.home_meals_public_recipes(); still returns recipe-only JSON (anon).
--   2. Signed-out app: /rest/v1/household_state returns 401/permission denied.
--   3. Corey signs in by email on his phone: app joins the family book and syncs.
--   4. Erin signs in on hers: same book, both see each other's recipes.
--   5. A third email can request a magic link but gets no household and no data.
-- ROLLBACK:
--   drop policy home_meals_contributors_all on public.household_state;
--   alter table public.household_state disable row level security;
--   grant select, insert, update on public.household_state to anon;
--   (family key works again), then drop function and the contributors table.
