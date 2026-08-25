# E2E Tests — Tags & Rules Page

> **Status: plan deferred.** The MVP is fully local (localStorage), and the
> localStorage layer is a stopgap until the backend lands. Only the **smoke
> suite** (below) is worth writing now; everything else is reworked or
> obsoleted when `GET /api/tags` exists (seeding changes, toasts go async,
> uniqueness/cascade move server-side, `submitting` states appear, and the
> corrupt-storage test dies with localStorage). The domain logic the heavy
> tests would check is already covered by `just client-test`
> (`tags_and_rules_page_test.gleam`, `tag_form_test.gleam`,
> `rule_form_test.gleam`). See the "What to keep / defer" section at the end.

Proposed Playwright coverage for the tags & rules page (MVP: fully local,
localStorage-backed, no backend). Ranked by descending impact/value.

Context that shapes the suite:

- The page has **no server interaction**, so E2E's unique value here is
  real-browser integration: localStorage persistence, client-side routing,
  `<dialog>` modals, and cross-page isolation — things unit tests cannot
  capture. Keep tests end-to-end (create data in the UI, reload, verify)
  rather than seeding state.
- The E2E DB is fresh each run but **localStorage persists within a run**
  (same `auth.json` storage state). Start every test from a known state by
  clearing the key first, e.g.
  `await page.evaluate(() => localStorage.removeItem('budgeteur.tags'))`.
- Use unique names per test (timestamp-suffixed), matching the transactions
  spec pattern, so retries stay independent.
- All interactable elements already carry `data-testid` attributes
  (`new-tag-button`, `tag-row-<uuid>`, `edit-tag-<uuid>`, `delete-tag-<uuid>`,
  `new-rule-button`, `rule-row`, `edit-rule-<uuid>`, `delete-rule-<uuid>`,
  `tag-modal`, `rule-modal`, `delete-tag-modal`, `delete-rule-modal`, and the
  empty-state CTA `create-first-tag-button`).

## P0 — Core journey & persistence (highest value)

### 1. Full CRUD journey survives a reload

The single most valuable test: it exercises every mutation plus the entire
localStorage round-trip in one flow.

1. Clear storage, open `/tags-and-rules` → no-tags empty state.
2. Create two tags ("Rent", "Coffee" — deliberately non-alphabetical) via
   `new-tag-button` → both rows appear, sorted alphabetically (Coffee first).
3. **Reload the page** → both tags still there, "Coffee" auto-selected.
4. Create a rule "STARBUCKS" → Coffee via `new-rule-button` (dropdown defaults
   to the selected tag) → appears in Coffee's panel, in a `code`-style row.
5. Edit the rule pattern → "STARBUCKS " (trailing space) → reload → saved
   trimmed ("STARBUCKS").
6. Delete the rule via `delete-rule-<uuid>` → confirm → row gone, Coffee
   panel shows its empty state.
7. Delete tag "Coffee" → confirm dialog names the consequences → tag gone,
   selection moves to "Rent".
8. Reload → only "Rent" remains, selected, with its (empty) rules panel.

**Invariants under test**: every mutation persists whole payload to
localStorage; restore on init is lossless; names/patterns trimmed before
save; deletion updates both lists.

### 2. Data survives navigation, and pages don't wipe each other

Regression guard for the "page backup wiped on page change" class of bugs.

1. Create a tag on `/tags-and-rules`.
2. Navigate to `/transactions` via the header nav, create a transaction.
3. Navigate back to `/tags-and-rules` → tag still present and selected.
4. Reload `/transactions` → the transaction is still there.
5. Reload `/tags-and-rules` → tag still there.

**Invariant**: each page persists and restores its own key
(`budgeteur.tags` vs `budgeteur.transactions`); page changes never clobber
either.

## P1 — Data-integrity invariants

### 3. Delete-tag cascade and selection advance

1. Create tags A, B, C and give A two rules, B one rule.
2. Delete A → its 2 rules disappear with it; the confirm dialog stated both
   consequences; selection advances to the next alphabetical tag (B) and its
   rule shows.
3. Reload → cascade result persisted.
4. Delete the last remaining tag → page returns to the no-tags empty state.

**Invariants**: deleting a tag removes exactly its rules (FK `ON DELETE
CASCADE` mirror); selected tag never points at a deleted tag; deleting the
last tag yields the empty state, not a broken right panel.

### 4. Duplicate name / duplicate pattern are rejected, nothing persisted

1. Create tag "Coffee", then try to create "coffee " (case/whitespace variant)
   → inline error "A tag with this name already exists", modal stays open.
2. Cancel → no second tag in the list; reload → only one "Coffee".
3. Create rule "STARBUCKS" → Coffee, then create "starbucks" → "Rent" → inline
   error "This rule already exists" (case-insensitive duplicate).
4. Confirm neither duplicate was persisted across a reload.

**Invariant**: one tag name, one pattern per rule — enforced in the UI and
durable.

### 5. Rules keep insertion order (evaluation order)

1. Create rules "BETA", "ALPHA", "GAMMA" under one tag.
2. Assert the rows render in exactly that order (BETA, ALPHA, GAMMA).
3. Reload → order unchanged.

**Invariant**: insertion order is preserved (it is the future auto-tagging
"first match wins" order — a regression here silently changes tagging
semantics).

### 6. Rules belong to exactly one tag; moving a rule moves the panel

1. Create tags "Coffee" and "Rent", rule "STARBUCKS" → Coffee.
2. Edit the rule and change the tag dropdown to Rent → the row disappears from
   Coffee's panel and appears in Rent's.
3. Reload → rule still under Rent.
4. Create another rule on Coffee; verify it only ever appears in Coffee's
   panel, and that "New rule" defaults the dropdown to the selected tag.

**Invariant**: master-detail partitioning is correct; the rule form's default
tag is the selected tag; reassignment is persisted.

## P2 — States and UX correctness

### 7. Empty states

1. No tags → centered `no-tags-empty-state` with `create-first-tag-button`;
   no rules panel is rendered.
2. Tag with no rules → "No rules for \"Coffee\" yet" empty state with a
   "Create rule" affordance; `new-rule-button` is enabled.
3. New rule button disabled only when no tag is selected (transient — reach by
   deleting the last tag and re-adding? if unreachable in practice, assert the
   empty state instead).

### 8. Cancel paths don't mutate

1. Open tag form, type a name, Cancel → dialog closes, no row, no toast.
2. Open delete confirmations, Cancel → row still present, nothing persisted.
3. Reload → state unchanged from before the cancelled actions.

**Invariant**: Cancel is a true no-op (no persist effect).

### 9. Corrupt storage degrades gracefully

1. `localStorage.setItem('budgeteur.tags', 'not json')`, reload → page starts
   at the no-tags empty state, no crash, no error toast.
2. Same for a structurally wrong payload (e.g. `{"tags": 42}`).

**Invariant**: absent/corrupt JSON → fresh start (spec: "Absent or corrupt
JSON → start empty").

### 10. Toasts confirm mutations

After create/rename/delete of tag and rule, a success toast appears with the
operation ("Created tag …", "Deleted rule …"). Also assert no toast on Cancel.

## P3 — Navigation & polish (cheap, low risk)

### 11. Header nav and routing

1. Both nav links ("Transactions", "Tags & Rules") render; the active one is
   highlighted on each page.
2. Direct load of `/tags-and-rules` works (not just client-side nav).
3. `/tags-and-rules/` trailing-slash and unknown paths fall back gracefully
   (404 page) without crashing.

### 12. Color picker round-trip

1. Create a tag with a non-default preset color → swatch shown in the list.
2. Reload → color preserved; edit → previously chosen color is the selected
   preset.

## What to skip (deliberately)

- **Server-side matching/auto-tagging**: out of scope for the MVP — no engine
  exists yet; rule preview and match counts are Phase 2.
- **Synchronous-submit in-flight states**: MVP has none (`submitting` flag
  arrives with the backend).
- **Mobile drill-in layout**: desktop-only in the MVP; revisit with the mobile
  milestone.
- **Long-press / hover-revealed affordances**: covered adequately by the
  selected-row Edit/Delete buttons in E2E; hover-reveal styling is a visual
  concern better caught by the client unit tests.

## Suggested file layout

```
tests/e2e/
  tags-and-rules.spec.ts      # P0–P3 above, roughly one describe per tier
```

Follow `transactions.spec.ts` conventions: `test.describe('tags and rules')`,
timestamp-suffixed unique names, `screenshotPath` retry-aware screenshots,
`data-testid` selectors.

## What to keep now vs defer until the backend

**Keep now — thin smoke suite (survives the backend unchanged):**

1. Fresh storage → no-tags empty state renders; `create-first-tag-button`
   opens the tag modal; creating a tag shows its row.
2. Create a tag then a rule under it: dialogs open/close, rows appear,
   master-detail wiring works, `new-rule-button` targets the selected tag.
3. Header nav: both links render, active link highlighted, direct load of
   `/tags-and-rules` works.

These pin down the DOM/`data-testid` contract, dialog behaviour, and
client-side routing — the only things a real browser can catch that unit
tests cannot, and none of them change when the backend lands.

**Defer until the backend (rework or obsolete):**

- P0.1 reload-persistence journey → becomes "data persists server-side" flows
  seeded via the API.
- P0.2 cross-page wipe guard → reframe around the shell's localStorage
  serialisation (affects both pages); keep as a unit/shell concern for now.
- P1.3 cascade, P1.4 duplicates, P1.5 ordering, P1.6 rule ownership →
  server-enforced once the FKs/unique indexes land; E2E then seeds via API
  and asserts server + UI together.
- P2.8 cancel no-op, P2.9 corrupt storage, P2.10 toasts → corrupt-storage
  test dies with localStorage; toasts become async (assert in-flight
  `submitting` states instead).
- P3.12 color round-trip → picker interaction survives in the smoke suite;
  the reload-persistence half is deferred.

Rule of thumb: if a test's main assertion is "it's still there after a
reload", defer it — that's testing the stopgap, not the product.
