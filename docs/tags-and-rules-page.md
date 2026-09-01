# Tags & Rules Page — UX/UI Design

Status: **Design spec** — decisions locked, ready to implement; MVP fully
local (client-only, no backend)
Scope: client UX/UI only for the MVP. Backend endpoints, matching engine, and
tests are deliberately out of scope and called out where they matter.

## Goal

A single management page for:

1. **Tags** (the `Categories` table) — create, rename, delete.
2. **Matching rules** (the `Rules` table) — map a description pattern to a tag,
   so transactions can be auto-tagged later (auto-tagging itself is a separate
   roadmap item, this page only manages the definitions).

## Design Principles

- **The design leads; the schema follows.** Nothing in this document is
  constrained by today's database schema. Where the ideal UX needs something
  the DB cannot express, the answer is a future migration — not a weaker
  design.
- The MVP ships **fully client-side** (localStorage, no backend). Its local
  data model mirrors the payload of a future seeding endpoint, so the backend
  can drop in without reshaping the page. The Phase 2 items exist precisely
  because the design came first.
- Terminology: **tagging = assigning a category**. "Tag" and "category" are
  synonyms in this app's vocabulary.

## Placement & Navigation

Today the app has no navigation at all (the only link is on the 404 page). This
page is the natural moment to add a minimal header nav in the app shell
(`app.gleam`):

```
┌───────────────────────────────────────────────────────────┐
│  Budgeteur      Transactions   Tags & Rules               │
├───────────────────────────────────────────────────────────┤
```

- New route: `/tags-and-rules`, added to `Route` in `shared/route.gleam`.
- The header lives in `app.gleam`'s `view` so every page gets it.
- Nav items: "Transactions" (`/transactions`), "Tags & Rules" (`/tags-and-rules`).
- Active item is highlighted via the current route.

## Page Structure — Master-Detail

One page, no tabs: a **vertical list of tags** on the left, and the **rules of
the selected tag** on the right. Rules belong to exactly one tag, so this
layout shows each rule in the context that matters and avoids the clutter of a
flat all-rules table.

```
┌───────────────────────────────────────────────────────────┐
│  Tags & Rules                                              │
├──────────────────┬────────────────────────────────────────┤
│ Tags             │ Coffee                     [New rule]  │
│                  │                                         │
│  ● Coffee        │  Pattern     Actions                     │
│  ● Rent          │  STARBUCKS   Edit  Delete                │
│  ● Utilities     │  7-ELEVEN    Edit  Delete                │
│                  │                                         │
│ [+ New tag]      │  (per-tag states below)                 │
└──────────────────┴────────────────────────────────────────┘
```

- **Left panel**: every tag, one per row. The selected tag is highlighted.
- **Right panel**: rules for the selected tag, with the tag name in the panel
  header.
- **Selection**: the first tag (alphabetical) is selected by default once tags
  load, so the right panel is never empty when tags exist. Clicking a tag
  switches the right panel. If the selected tag is deleted, the next remaining
  tag is selected.
- Selection state lives in the page `Model` (`selected_tag: Option(Uuid)`).
  Both lists are loaded from the store once on `init`; switching selection
  never reloads.
- Follow the existing page conventions: `data-testid` attributes, toasts via
  `out_msg.PageRequestedToast`, modal dialogs via `effect.ShowDialog` /
  `effect.CloseDialog`.

### Primary actions

- **New tag**: a button at the bottom of the left panel, always visible.
- **New rule**: a button in the right panel header. It targets the selected
  tag and is disabled when no tag is selected.

## Left Panel — Tags

Reuse the transactions table row styling but as a plain vertical list (no
table chrome needed for a single column):

```
● Coffee
● Rent
● Utilities
```

- **Row**: color swatch + tag name. Selected row gets a subtle background +
  left accent.
- Clicking a row selects it and shows its rules on the right.
- **Edit / rename**: an inline "pencil" affordance on hover (shown on the
  selected row), or long-press — simplest is a small Edit icon next to the
  name on the selected row. Opens the tag modal prefilled.
- **Delete**: a trash icon next to Edit, on the selected row. Opens the delete
  confirm dialog.
- **New tag** button pinned at the bottom of the panel.

### Create / rename modal

Reuses the transaction form modal pattern (native `<dialog>`, single shared
component with `Create`/`Edit(id)` mode):

- **Name** (required, trimmed, ≤ 64 chars — a client constant for now; the
  future server mirrors it). Duplicate names are rejected with an inline
  error (unique tag names are a Phase 2 DB change).
- **Color** — a palette of preset swatches, one selected by default; rendered
  as the swatch in the tag list and rule badges. The `Categories.Color`
  column is already in migration 001 (default `#6366F1`, which is the
  form's default selection). Presets:
  `#64748B #EF4444 #F97316 #F59E0B #22C55E #14B8A6 #0EA5E9 #6366F1 #8B5CF6 #EC4899`
- Modal footer: Cancel + primary action ("Create tag" / "Save").
- Saving is synchronous in the local MVP (persist to the store, close the
  modal). When the backend lands, this becomes an in-flight state with a
  disabled submit button (`submitting` flag, matching
  `transaction_form.ModalState`).

### Delete confirmation

Delete has consequences that must be surfaced, so it uses the
`transaction_delete_modal`-style confirm dialog:

- **Transactions tagged with it lose their tag** (FK `ON DELETE SET NULL`).
- **Its matching rules are deleted too** (FK `ON DELETE CASCADE`).

The dialog body explains both consequences and names the tag. The "Delete"
button is red; cancelling returns to the list.

### Left panel empty state

No tags yet — the right panel is hidden and the page shows a single centered
empty state:

```
┌──────────────────────────────────────────────┐
│   No tags yet                                │
│   Tags help you categorise transactions      │
│   and power auto-tagging rules.              │
│                    [ Create your first tag ] │
└──────────────────────────────────────────────┘
```

## Right Panel — Rules for the Selected Tag

Header shows the selected tag name and the **New rule** button. Body is the
rules table:

| Pattern   | Actions     |
| --------- | ----------- |
| STARBUCKS | Edit Delete |
| 7-ELEVEN  | Edit Delete |

- **Pattern**: the literal substring, rendered in a `code`-style font.
- **Actions**: Edit / Delete per row (same styling as the transactions table).
- Rules keep insertion order — new rules append, and list order is evaluation
  order (see Matching Semantics). No timestamp field is needed in the MVP
  payload.

### Create / edit modal

Two controls:

1. **Pattern** — text input (required, trimmed, ≤ 128 chars). Matching
   semantics are fixed for now: **case-insensitive substring** on the
   transaction description (regex is a Phase 2 item).
2. **Tag** — dropdown of existing tags. **Defaults to the selected tag.**
   Changing it in the form moves the rule to another tag (the rule simply
   appears in the other tag's panel after saving). This is called out in a
   one-line hint under the field.

Validation errors, shown inline:

- empty pattern
- pattern already used for another rule (one pattern, one tag — surface as a
  friendly "This rule already exists")
- no tag selected

Saving is synchronous in the local MVP (persist and close immediately), like
the tag form; an in-flight `submitting` state arrives with the backend.

### Delete confirmation

Simpler than tags: deleting a rule only means the pattern no longer auto-tags.
No cascade warning needed. Still uses a confirm dialog for consistency
("Delete rule 'STARBUCKS' → Coffee?"), since delete is destructive.

### Right panel empty states

- **No tag selected** (can only happen transiently, e.g. after deleting the
  last tag): prompt "Select a tag to see its rules".
- **Selected tag has no rules yet**:

```
┌──────────────────────────────────────────────┐
│   No rules for "Coffee" yet                  │
│   Rules auto-tag transactions whose          │
│   description contains a pattern, e.g.       │
│   "STARBUCKS" → Coffee.                     │
│                            [ Create rule ]   │
└──────────────────────────────────────────────┘
```

## Future Enhancement: Mobile Support

The initial version is **desktop-only**. When mobile support lands, the
master-detail layout needs two navigation models at the `sm` breakpoint:

- **Desktop (≥ sm):** side-by-side, as designed above.
- **Mobile (< sm): drill-in.** The page starts at the full-width tag list.
  Tapping a tag selects it and pushes a **detail view** with a back button
  ("←" + tag name) and the rules list. Back returns to the list, keeping the
  selection highlighted. A `mobile_showing_detail: Bool` flag in the page
  `Model` decides which screen the mobile stack renders; desktop always shows
  both panels (Tailwind responsive utilities control visibility, so there is
  one view tree, no duplicate rendering). The desktop "auto-select first tag"
  default must **not** auto-drill on mobile — the list stays the entry screen
  until the user taps.

Other mobile details to fold in at that point:

- Tag rows ~44px minimum height; Edit / Delete always visible on touch (they
  are hover-revealed on desktop).
- Rules render as **stacked cards** on mobile instead of the table; the tag
  context comes from the detail header.
- Modals render near-full-screen (`w-full sm:max-w-*`).

## Future Enhancement: Rule Preview

The MVP form only validates pattern + tag. A later enhancement adds a **live
preview** as the user types the pattern:

```
Matches 12 transactions           ┌─ Preview ─────────────┐
                                  │ 2026-08-10 STARBUCKS  │
                                  │ 2026-08-03 STARBUCKS  │
                                  │ 2026-07-28 STARBUCKS  │
                                  │   … 9 more            │
                                  └───────────────────────┘
```

- The count updates on every keystroke (client-side substring match over the
  loaded transactions — approximate feedback; the authoritative numbers come
  from the server-side matching stats, see below).
- The preview list shows the most recent 3 matches and truncates with "+n
  more". Pending/untagged matches are highlighted ("2 not yet tagged") so the
  user sees what auto-tagging would do.

Deferred to keep the MVP modal simple (two fields, no list rendering).

## Future Enhancement: Matching Stats

The MVP rules table shows only pattern + actions. A later enhancement adds a
per-rule **matches** count, computed **server-side** as part of the tags/rules
payload (e.g. `matches` and `untaggedMatches` per rule, derived from one
grouped SQL query) or a dedicated stats endpoint. Counts must never come from
whatever transactions the client happens to have loaded — that is misleading
once transactions are paginated. The rule-form preview stays client-side and
approximate; the stats are the authoritative numbers.

## Matching Semantics (design decision)

- Match = case-insensitive substring containment in `Transactions.Description`.
- Transactions are tagged by the **first** rule (in creation order) whose
  pattern matches. One category per transaction, so "first match wins".
- Rules only affect **untagged** transactions (a transaction with a category is
  never re-tagged).
- A pattern maps to exactly one tag — the form forbids reusing a pattern for
  a different tag (DB-level enforcement is a Phase 2 change).
- The DB has no ordering column; rules are applied in insertion order (oldest
  first). If priority control is wanted later, a `Position` column is a schema
  change (see Phase 2).

## Data Flow (MVP) & Feedback

The MVP is **fully local** — no backend calls.

- The page's data model mirrors the response payload of a future seeding
  endpoint (`GET /api/tags`), so the backend can drop in later without
  reshaping the page:

```json
{
  "tags":  [{ "id": "uuid", "name": "Coffee", "color": "#7C3AED" }],
  "rules": [{ "id": "uuid", "pattern": "STARBUCKS", "tagId": "uuid" }]
}
```

- On `init` the page loads this payload from `localStorage` via
  `effect.LoadFromStore` (key `budgeteur.tags`, matching the transactions page
  pattern). Absent or corrupt JSON → start empty (the empty states guide the
  user).
- Every mutation (create / rename / delete tag, create / delete rule) updates
  the model and **persists the whole payload** back to `localStorage` via
  `effect.SaveToStore`.
- IDs are v7 UUIDs generated client-side on create (`uuid.v7()`).
- Deleting a tag also removes its rules from the model (mirroring the
  `ON DELETE CASCADE`).
- Only the payload is persisted; the selected tag is transient UI state.
- Color is stored as a hex string (as the future API would send it); the
  form's palette picker constrains choices to presets.
- Toasts: success / error on mutations, matching the existing usage. There is
  no fetch, so no sync-failure toasts.
- `data-testid` attributes on the primary buttons, tag rows, and per-row
  actions for future E2E coverage (consistent with the transactions page).
- The `Categories.Color` column lives in **migration 001, modified in place**
  (the project is unreleased; existing dev databases need `just db-reset`).

## Out of Scope (explicitly)

- Backend endpoints / server code — the MVP is fully local. The payload shape
  is already defined in Data Flow, so `GET /api/tags` (and its server-side
  persistence) can be built later without reshaping the page.
- The auto-tagging engine and the Tagging Queue UI (separate roadmap items;
  this page only defines rules).
- The "Exclude from statistics" toggle (`HiddenCategories`): no statistics UI
  exists yet, so a toggle would have no visible effect. Defer until the
  dashboard exists.
- Tag icons / emoji: out of scope (tag colors are in the MVP).

## Design Intent (target UX — schema follows)

The ideal UX goes beyond today's schema. These are design intentions, not
commitments — each becomes a migration when we build it. Suggested priority is
marked.

### Tag identity

- **Color per tag** — **MVP (decided)**. `Categories.Color` is in migration
  001 (modified in place; `just db-reset` for existing dev DBs). A palette
  picker in the tag form; the color appears in the tag list, rule badges, the
  transactions table, and future charts. Emoji/icon can follow later without
  further design work.
- **Tag groups / hierarchy** (e.g. Housing, Food, Transport) — Phase 2. A
  `CategoryGroups` table; the master-detail list renders groups as sections.

### Rule expressiveness

- **Enable / disable toggle** on a rule to pause it without deleting —
  Phase 2 (needs a `Rules.Enabled` migration).
- **Explicit ordering** with drag-to-reorder, rules run top-to-bottom —
  Phase 2 (`Rules.Position`, already listed below).
- **Richer match types** — starts-with / ends-with / equals, amount
  conditions, per-rule case sensitivity, selectable match fields (description,
  account) — Phase 2 (`Rules` gains match-type and match-field columns).

### Tag lifecycle

- **Archive instead of delete** so history keeps its tag while it can no
  longer be assigned to new transactions — Phase 2.
- **Merge tags** (fold one tag into another, repointing its transactions) —
  Phase 2.
- **Usage counts** (transactions per tag / per rule) served in the payload —
  Phase 2, paired with the matching stats above.

### Cross-page integration

- **"Create rule from this transaction"** on the transactions page: pre-fills
  a rule form with the transaction's description and chosen tag — Phase 2.

### One tag or many? (resolved)

- **Decided: one primary tag per transaction** — matches today's single
  `category_id` and first-match-wins auto-tagging. Tagging = assigning a
  category.
- If many-to-many tagging is added later, transactions **keep the primary
  category field** as-is; it is the one that feeds statistics, so category
  shares always add up to 100%. Additional tags are non-primary annotations
  layered on top.

## Phase 2 (schema changes required — separate discussion)

| Idea             | What it needs                           | Why                                                                            |
| ---------------- | --------------------------------------- | ------------------------------------------------------------------------------ |
| Enable/disable   | `Rules.Enabled BOOL` migration          | pause a rule without deleting it                                               |
| Regex rules      | flag/column on `Rules`                  | powerful patterns but harder to explain; decide matching semantics first       |
| Rule priority    | `Rules.Position INT`                    | explicit ordering instead of creation order                                    |
| Unique tag names | `UNIQUE(UserId, Name)` migration        | enforce at the DB rather than only in the form                                 |
| Unique patterns  | `UNIQUE(UserId, Pattern)` migration     | enforce one-pattern-one-tag at the DB rather than only in the form             |
| Apply-now button | bulk-tag endpoint + auto-tagging engine | tag all matching untagged transactions on demand instead of waiting for import |

## Decisions (resolved)

| # | Question             | Decision                                                                                                                               |
| - | -------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| 1 | Default selection    | Auto-select the first tag (alphabetical) on load                                                                                       |
| 2 | Matching semantics   | Case-insensitive substring; first matching rule wins; only untagged transactions are affected                                          |
| 3 | Conflicting patterns | Forbidden — backend rejects duplicates with `400` via `requireRuleIsUnique` (`UNIQUE(UserId, Pattern, TagId)`), backed by the DB index |
| 4 | Match scope          | Description only                                                                                                                       |
| 5 | Header nav           | Yes — minimal header in `app.gleam` with Transactions and Tags & Rules links, active item highlighted                                  |
| 6 | Tag color            | In the MVP — needs a `Categories.Color` migration                                                                                      |
| 7 | One tag or many      | One primary tag per transaction; if more are added later, the primary stays for stats                                                  |

## Suggested File Layout (for when we implement)

Follow the transactions slice layout:

Tag and rule are distinct aggregates (each with its own type, form, and
delete modal), so they get subfolders; page-level modules stay at the
`tags_and_rules/` root:

```
client/src/budgeteur/
  tags_and_rules/
    tags_and_rules_page.gleam        # page: Model, Msg, update, view, master-detail layout,
                                     # localStorage load/persist
    tags_and_rules_page_data.gleam   # TagsAndRulesPageData payload type + JSON codecs + storage key
                                     # (the future GET /api/tags payload, defined now)
    tag/
      tag.gleam            # Tag type + JSON codec (id, name, color)
      tag_form.gleam       # create/rename modal: name + color picker
      tag_delete_modal.gleam
    rule/
      rule.gleam           # Rule type + JSON codec (id, pattern, tagId)
      rule_form.gleam      # pattern + tag dropdown
      rule_delete_modal.gleam
```

Plus wiring: new `Route` variant in `shared/route.gleam`, `Page`/`Msg` variants and
header nav in `app.gleam`. No `ApiRoute` changes for the MVP — the future
endpoint's shape is mirrored by `tags_and_rules_page_data`.
