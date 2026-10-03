-- Run only after approving the backend change. Keep the household slug out of this repo.
-- In the same SQL Editor transaction, set the real slug with:
-- select set_config('home_meals.household_slug', '<current private family key>', true);
-- Then run this migration. It does not change the existing family sync table or policies.
create schema if not exists home_meals_private;
revoke all on schema home_meals_private from public, anon, authenticated;
create table if not exists home_meals_private.public_source (
  singleton boolean primary key default true check (singleton),
  household_slug text not null
);
revoke all on home_meals_private.public_source from public, anon, authenticated;
insert into home_meals_private.public_source(singleton, household_slug)
values (true, current_setting('home_meals.household_slug'))
on conflict (singleton) do update set household_slug=excluded.household_slug;

create or replace function public.home_meals_public_recipes()
returns jsonb
language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(
    (select jsonb_object_agg(k, value)
     from jsonb_each(recipe) as field(k, value)
     where k in ('id','name','serves','time','tags','ingredients','steps','macros','source','note'))
    order by ordinal), '[]'::jsonb)
  from public.household_state as h
  join home_meals_private.public_source as cfg on h.slug=cfg.household_slug
  cross join lateral jsonb_array_elements(h.state->'recipes') with ordinality as items(recipe, ordinal)
  where not coalesce((h.state->>'moved')::boolean, false);
$$;
revoke all on function public.home_meals_public_recipes() from public;
grant execute on function public.home_meals_public_recipes() to anon, authenticated;
-- Verify with select public.home_meals_public_recipes(); only recipe fields should be returned.
-- Rollback: drop function public.home_meals_public_recipes(); then drop the private config table/schema.

-- ROLLOUT: This draft is NOT production-tested or applied.
-- Verify actual household_state columns/types before approval. Apply in one transaction
-- with the private set_config above. Anonymous GET to /rest/v1/rpc/home_meals_public_recipes
-- must return ONLY recipe fields. Add a recipe through normal family UI, verify it appears
-- in the public feed without a deploy, then approve merge/Pages deployment.
-- Existing anonymous household writes are unchanged; this is NOT an Auth/RLS security fix.
-- Frontend tests used a mocked RPC: fresh 390px phone shows 37 cards, public edit/shopping
-- controls absent, family Add preserved, no JS errors or database writes. Pixels inspected.
