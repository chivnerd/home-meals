## What Corey asked for (Nov 1, iMessage)

- Public website, shareable with family for easy reading
- Only Corey and Erin as contributors
- Human-readable URLs, no weird query strings
- Both of them seeing the same collection
- Working checklists and shopping lists (his were unusable)
- Sort: newest/oldest, newest first by default

## What this PR changes (app only - no database changes, nothing goes live until merged)

**Readable URLs**
- Every recipe now has a clean URL: `hivner-meals.chivner.com/recipe/crispy-roasted-chickpeas`
- New `404.html` turns those paths into app routes on GitHub Pages (standard SPA fallback)
- The Share button copies that short public link instead of the giant encoded `#/view/...` fragment
- Legacy `#/view/...` links already sent still open exactly as before (decoder untouched)
- The family key (`?h=...`) disappears from the address bar after first open (it stays saved on the device), and the sync status line no longer prints the key on screen

**Lists that work for everyone (his reported bug)**
- Bug confirmed live: without a saved family key, the Shopping list button was hidden and `#/list` was blocked - that is why he could not use them
- Public visitors now get: Shopping list button, per-recipe "+ Shopping list", Copy recipe, Copy link, and step checklists (already existed)
- Visitor lists are on-device only (`localStorage`), and can never push into the shared family book: `saveState`/`saveCustom` only mark sync-dirty when a family key is present
- When signed in / on the family key, the shared family shopping list works exactly as today

**Contributor sign-in (email magic links - his pick, $0)**
- "Family sign-in" card on the public homepage: Corey or Erin enters their email, taps the link, done. No password, no library, no Twilio cost
- Old family key/link paste remains as a fallback during transition
- Signed-in devices call Supabase with their session token; the app learns the household from a new RPC once the backend migration lands
- `contributors.sql` is a DRAFT migration (email allowlist + RLS lockdown of `household_state`, public recipe feed untouched) - NOT applied. It needs his go-ahead and should run only after this app update is live, because it ends anonymous key access by design
- Erin's Instinct does not need GitHub access: adding recipes happens in the app, not the repo

**Sort**
- Newest first / Oldest first toggle, newest first by default, remembered per device
- Recipes carry no timestamps, so "newest" = the book's arrival order reversed; no dates fabricated

**Consistency**
- Baked offline snapshot refreshed to the live 54 recipes (was a stale 37-recipe bake from Oct 3)
- Public pages re-check the live feed every 60s and on tab focus (family mode keeps its 4s sync)
- The chickpea recipe note's private health clause is redacted in the baked snapshot - but note it is still served by the live public feed (see below)

## Tested (cloud browser, build 31 via githack preview)

- Public homepage: 54 recipes, sort toggle, Shopping list button, sign-in card, no family names shown
- Public recipe page: checklist, + Shopping list (badge counts up), Copy recipe, Copy link
- Visitor shopping list renders merged ingredients; nothing marked sync-dirty
- Family key flow: key captured, stripped from address bar and screen, live sync OK
- Legacy encoded share link still renders
- 404 redirect logic unit-tested for custom domain + legacy github.io base path

## Needs Corey's decisions (not in this PR)

1. **Apply `contributors.sql`** after merge: ends key-only access, locks the family book to his and Erin's emails (closes the known anonymous read/write gap, todo-01M5NAHBA8K9MN9P07WE6QRR31)
2. **The chickpea note**: "check against Erin's fiber sensitivities" is currently served by the live public feed. Trim the master note (removes it everywhere) or keep notes family-only later via SQL
3. Per-recipe share previews (OG) still need server routes - he said "nah its fine for now" Sept 28
