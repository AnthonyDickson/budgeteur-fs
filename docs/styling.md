# Styling

Design brief for how the client is styled: colours from Catppuccin, light and
dark modes, and shared UI components. It records what we decided, why, and what
each decision is meant to achieve. Change it when the reasoning changes.

Before this feature, views used Tailwind's default palette directly: about 600
colour utilities across some 40 modules, with gray for neutrals, indigo as the
accent, and red, amber, and green for status. Class strings for inputs, cards,
and banners were copied between pages; only the modal dialog, its buttons, and
clickable rows were shared. Tag colours were hex strings chosen from ten
Tailwind colours, the charts hard-coded their colours, and there was no dark
mode.

## Goal

- **Consistent colours.** A colour means the same thing on every page, and a
  view cannot use a colour outside the set.
- **Light and dark modes.** The app follows the OS setting, with Catppuccin
  Latte for light and Mocha for dark.
- **Readable in both modes.** Text meets WCAG AA (4.5:1) in both flavours.
- **Shared UI elements.** Buttons, inputs, cards, and banners are defined once
  and look and behave the same everywhere.

## Ubiquitous language

| Term           | Meaning                                                                                                            |
| -------------- | ------------------------------------------------------------------------------------------------------------------ |
| Flavour        | One Catppuccin palette: Latte (light) or Mocha (dark).                                                             |
| Mode           | Light or dark, chosen by the OS. The mode selects the flavour.                                                     |
| Palette colour | One of a flavour's 26 named colours, e.g. base, subtext1, mauve. Each name has a value in both flavours.           |
| Accent         | One of the 14 palette colours that are hues, rosewater to lavender. The other 12 are neutrals.                     |
| Role           | A colour named by purpose, e.g. surface, muted text, primary, danger. It maps to a palette colour or a mix of two. |
| Tint           | A role's colour mixed into the surface, used as a background behind normal text.                                   |
| Component      | A stateless view function in the client's `shared/ui/` that owns an element's classes.                             |
| Variant        | One of a component's closed set of looks, e.g. a primary or a danger button.                                       |

## Decisions

### 1. Catppuccin Latte and Mocha

- **Decision**: light mode uses Latte and dark mode uses Mocha, with
  Catppuccin's stock values. Frappé and Macchiato are not offered. The values
  are copied into the stylesheet rather than taken from a Catppuccin package.
- **Why**: Catppuccin is a published palette designed for both light and dark
  backgrounds, with the same names in every flavour, so one name works in both
  modes. Copying 52 values that do not change avoids a dependency.
- **Rejected**: the Catppuccin Tailwind plugin. It generates utilities named
  after palette colours, which decision 3 keeps out of views.
- **Goal**: a coherent palette for both modes without designing one.

### 2. The OS chooses the mode

- **Decision**: the mode follows the browser's `prefers-color-scheme`. There is
  no toggle and no stored preference. The stylesheet declares both colour
  schemes, so native controls such as date pickers, selects, and scrollbars
  follow the mode.
- **Why**: the stylesheet alone switches modes: no script, no state, no flash of
  the wrong mode on load, and no control to build.
- **Rejected**: a System, Light, or Dark choice in the header, saved in
  localStorage. It needs a control and a script that applies the choice before
  first paint. See Deferred.
- **Goal**: dark mode with no code outside the stylesheet.

### 3. Views use roles, never palette colours

- **Decision**: the stylesheet has two layers. The palette layer holds the 26
  colours as CSS variables, with Latte's values by default and Mocha's in dark
  mode. The role layer defines Tailwind theme colours by purpose, each referring
  to the palette layer. Views use role utilities only, e.g. a surface
  background, muted text, a primary fill. Tag swatches (decision 9) are the one
  use of the palette layer outside the stylesheet.
- **Why**: a view states what a colour means, not what it is. A role's colour
  changes in one place, and one set of classes serves both modes, with no
  `dark:` variants. Catppuccin's names also switch with the flavour, but they
  name a colour, not a purpose: "mauve means primary" would be a convention
  spread across every view.
- **Rejected**:
  - Catppuccin names in views. No translation layer, but meaning is implicit and
    changing the accent is a find and replace.
  - Catppuccin names for neutrals and role names for accents. Two naming schemes
    for one job.
- **Goal**: a colour's meaning is stated once, in the stylesheet.

### 4. The roles

- **Decision**: views use these roles. The same mapping applies in both
  flavours; mixes are computed in CSS, so they follow the mode too.

  | Role          | Used for                                               | Maps to                          |
  | ------------- | ------------------------------------------------------ | -------------------------------- |
  | page          | Page background                                        | mantle                           |
  | surface       | Header, cards, modals, inputs                          | base                             |
  | surface-hover | Hovered rows and buttons, table heads, disabled fills  | surface with 3% of text mixed in |
  | backdrop      | Behind modal dialogs, at 50% opacity                   | crust                            |
  | fg            | Body text and headings                                 | text                             |
  | fg-muted      | Secondary text: labels, dates, counts, help            | subtext1                         |
  | fg-subtle     | Icons, placeholders, disabled text                     | overlay2                         |
  | border        | Card borders and dividers                              | surface0                         |
  | border-input  | Input and secondary button borders                     | surface1                         |
  | primary       | Primary buttons, link underlines, focus rings, markers | mauve                            |
  | primary-hover | Hovered primary fills                                  | primary with 10% of fg mixed in  |
  | primary-tint  | Selected items                                         | primary 15% into surface         |
  | on-primary    | Text on primary and danger fills                       | base                             |
  | danger        | Destructive buttons, error text, invalid field borders | red                              |
  | danger-hover  | Hovered danger fills                                   | danger with 10% of fg mixed in   |
  | danger-tint   | Error banners and toasts                               | danger 15% into surface          |
  | success       | Success borders and icons; never text                  | green                            |
  | success-tint  | Success toasts, the dashboard's improvement figure     | success 15% into surface         |
  | warning       | Warning borders and icons; never text                  | yellow                           |
  | warning-tint  | Warning banners and toasts                             | warning 15% into surface         |

  Cards keep their small shadow. It barely shows in Mocha, where borders carry
  the structure.
- **Why**:
  - **Surfaces**: a mantle page with base cards keeps today's raised cards on a
    tinted page, and Catppuccin uses mantle and crust for background panes.
  - **Hover**: mixing 3% of the text colour into the surface darkens it in Latte
    and lightens it in Mocha, a little stronger than today's gray-50. At 5%,
    primary text on it falls to 4.4:1 in Latte. Stock surface0 is too heavy in
    Latte: muted text on it is 4.1:1 and primary text 3.5:1.
  - **Fill hovers**: mixing toward the text colour raises the contrast of the
    text on the fill in both flavours.
- **Rejected**: a base page with surface0 cards (muted text on cards fails AA in
  Latte), and one flat background.
- **Goal**: a small set of roles covers every colour the views use today.

### 5. Mauve is the primary

- **Decision**: the primary role maps to mauve, replacing indigo.
- **Why**: of the 14 accents, only mauve and red reach 4.5:1 on Latte's base,
  and red is danger. Mauve is also Catppuccin's signature accent and the hue
  closest to indigo. In Mocha every accent passes. The site icon (favicon and
  header logo) is a fixed image in Latte mauve with a Latte base letter; it does
  not follow the colour mode.
- **Rejected**: blue (4.3:1 in Latte, which needs a darkened Latte value or no
  use as text) and lavender (2.8:1).
- **Goal**: a primary that passes AA as text and as a fill in both flavours.

### 6. Text meets AA through role choice

- **Decision**: every role used for text reaches 4.5:1 on each background it
  appears on, in both flavours, using stock palette values. An accent that
  cannot is used only for fills, borders, icons, and chart marks. In particular:
  - subtext0 (4.4:1 on Latte's base) is not used; muted text is subtext1.
  - success and warning are never text colours (Latte green 3.0:1, yellow
    2.3:1).
  - danger text is allowed (Latte red 4.8:1).
  - Text on primary and danger fills is base.
  - Primary text sits on surfaces, not on the page background, where it is
    4.45:1 in Latte. Links within text are fg with a primary underline, so they
    read on any background; the underline needs only 3:1.
  - Text on a tint is fg or fg-muted. Primary and danger text on their own tints
    is 3.9:1 in Latte.

  | Pair                        | Latte | Mocha |
  | --------------------------- | ----- | ----- |
  | fg on surface               | 7.1   | 11.3  |
  | fg-muted on surface         | 5.5   | 9.3   |
  | fg-muted on page            | 5.1   | 9.9   |
  | fg-muted on surface-hover   | 5.3   | 8.8   |
  | primary on surface          | 4.8   | 8.1   |
  | primary on surface-hover    | 4.6   | 7.6   |
  | danger on surface           | 4.8   | 7.1   |
  | on-primary on primary       | 4.8   | 8.1   |
  | on-primary on primary-hover | 5.0   | 8.4   |
  | fg on any tint              | ≥ 5.8 | ≥ 8.0 |
  | fg-muted on any tint        | ≥ 4.5 | ≥ 6.6 |
  | fg-subtle on surface        | 3.5   | 5.8   |

  Ratios for mixed roles are computed by mixing in oklab, as the stylesheet
  does.
- **Why**: Latte's accents are pastels, too light for text on a light
  background. Choosing roles keeps Catppuccin's values unedited.
- **Cost**: secondary text loses a level of hierarchy. Today's gray-700 and
  gray-500 text both become fg-muted, and font weight carries the difference
  where one is needed. fg-subtle (3.5:1 in Latte) is only for icons, which need
  3:1, and for placeholders and disabled controls, which have no requirement.
- **Rejected**:
  - Darker Latte values for success and warning. These are departures from
    Catppuccin to maintain.
  - Stock usage that accepts Latte's failures.
- **Goal**: both modes are readable without a custom palette.

### 7. Status is a tint and normal text

- **Decision**: banners and toasts use the status tint as the background, the
  status colour as a border or icon, and fg text. The dashboard's improvement
  figure, green text today, becomes a small pill with the success tint and fg
  text; its sign still carries the direction. Field error messages stay danger
  text.
- **Why**: decision 6 rules out success and warning text. A tint with normal
  text works in both modes, and today's toasts and amber banners already look
  this way.
- **Rejected**: dropping the colour from the improvement figure. The sign alone
  carries the direction, but the colour makes good months easy to spot.
- **Goal**: status reads at a glance without coloured text.

### 8. Tailwind's default palette is removed

- **Decision**: the stylesheet clears Tailwind's default colours and defines
  only the roles, plus transparent and the current colour. A class such as
  `bg-gray-500` generates no CSS.
- **Why**: the rule enforces itself. A default-palette colour shows up as
  missing styling the first time the view renders, with no lint check to
  maintain.
- **Rejected**:
  - A lint check for default-palette class names as well. It would catch
    mistakes in CI, but they are already visible on first render.
  - Convention only. Nothing stops drift.
- **Cost**: white and black go too. Their few uses become roles.
- **Goal**: the right colour is the only one available.

### 9. Tag colours are Catppuccin accent names

- **Decision**: a tag's colour is one of the 14 accent names. In `Domain/`,
  `TagColor` becomes a union of the 14 accents instead of a hex string. It is
  parsed and printed like `TagKind` and documented as an enum in OpenAPI
  ([openapi](openapi.md)). The column stays text. The client mirrors the union
  and draws a swatch with the accent's palette variable, so it shows the active
  flavour's value. The picker offers all 14 in Catppuccin's order, with mauve as
  the default.
- **Why**: with the OS choosing the mode, a stored hex cannot suit both
  flavours. A closed set of names makes invalid colours unrepresentable and
  replaces the hex pattern check.
- **Rejected**:
  - Keeping hex and changing the picker to one flavour's values. Swatches would
    not follow the mode.
  - Keeping hex and translating known values on the client. Colour identity
    would be implicit in a lookup of hexes.
  - A curated subset, or adding a grey. The union would no longer be exactly
    Catppuccin's accents.
- **Cost**: no data migration. The only database with tags is a development
  database, which is reset.
- **Goal**: a tag keeps its colour across modes, and only valid colours can be
  stored.

### 10. Charts read roles from CSS

- **Decision**: the dashboard charts draw bars, lines, and dots in the primary
  role. Hollow "to date" dots and tooltips are filled with the surface. The
  charts refer to the roles' CSS variables, which inherit into the chart
  element's shadow root, so a mode change restyles a drawn chart without a
  redraw. Axes, grid lines, and tooltip text follow the current text colour,
  fg-muted.
- **Why**: today's hard-coded indigo and white would be wrong in dark mode.
- **Rejected**: colouring cash flow bars by sign. That is a feature, not a
  change of styling.
- **Goal**: charts follow the mode like the rest of the page.

### 11. Shared components are stateless view functions

- **Decision**: components live in the client's `shared/ui/`, one module per
  element:
  - **button**: primary, secondary, danger, danger text (opens a delete
    confirmation), and text variants.
  - **input**: text input, select, checkbox, and radio group, with field labels
    and error messages. A field holding an error is marked with `aria-invalid`,
    which also styles it, so screen readers and the eye see the same state.
  - **card**: a panel and an empty state.
  - **stat**: a figure card, a label over one headline figure, for the summary
    rows of the dashboard, balance sheet, and reports.
  - **banner**: error and warning.
  - **link**: a link within text (decision 6).
  - **dialog**, **row**, and **swatch**: today's modal dialog, clickable row,
    and tag swatch, moved from `shared/`.

  A component takes a variant, attributes for behaviour (event handlers, test
  ids, disabled), and children, and owns its classes. Where a caller needs
  layout, a class argument positions the element, as the row does today. A
  variant is a closed custom type. Layout, typography, and one-off elements stay
  inline in views, using roles.
- **Why**: this extends the pattern the modal and row modules set. The compiler
  checks variants, and focus rings, hover, and disabled states are defined once.
  The input class string copied 15 times becomes one function.
- **Rejected**:
  - Class constants for callers to apply. Lighter, but the module would not
    control the markup or accessibility attributes.
  - One `ui` module. One import, but it grows large and mixes elements that
    change for different reasons.
  - CSS component classes in the stylesheet. Styles would leave Gleam, and the
    compiler could not check variants.
  - A full design system with tables, typography, and spacing tokens. More churn
    than the goals need.
- **Goal**: a shared element is defined once and is easy to use correctly.

## Consequences

- **Stylesheet**: gains the palette layer, the role layer, the cleared default
  palette, and both colour schemes.
- **Client views**: every colour utility becomes a role, shared elements become
  components, and success and warning text becomes a tint with fg text.
- **Client `shared/ui/`**: a new folder holding the components. The dialog, row,
  and swatch modules move there.
- **Tags**: `TagColor` in `Domain/` becomes a union. Create and update return
  `400` for any other value. Tag, dashboard, and report responses carry names.
  Server tests with hex fixtures change. A development database is reset with
  `just db-reset`, or its hex colours are rewritten to names by hand; a tag with
  a hex colour fails to load.
- **Client tags**: a colour type mirroring the server's, the picker with 14
  swatches, and E2E test ids by name.
- **Charts**: colours come from roles. First check that Plot accepts CSS
  variable references as colours. If it does not, read the computed values and
  redraw on a mode change.
- **Order of work**: Mocha is enabled last, so a partly migrated app is never
  half dark. The default palette is cleared only once no view uses it. Until
  then, light mode mixes Latte and Tailwind colours.
- **Docs updated with the implementation**: AGENTS.md gains a rule that views
  use roles only. The client section of [architecture](architecture.md) gains
  styling, and the chart decision in [dashboard](dashboard.md) (decision 15's
  "dark mode works through Tailwind") points here.
- **Highest-value tests**:
  - Server: `TagColor` accepts each accent name and rejects hex and unknown
    names. Creating and updating a tag with an invalid colour is `400`.
  - Client: none beyond existing tests. Components hold no logic.
  - E2E: the tagging test picks a colour by name. One test emulates each colour
    scheme and checks that the page background is Latte's or Mocha's mantle.
  - Manual: every page in both modes, with screenshots in the review.

## Deferred

- **A mode override.** System, Light, or Dark in the header, saved in
  localStorage as a user preference and applied by a script before first paint.
- **Frappé and Macchiato.**
- **Input border contrast.** WCAG asks for 3:1 on the boundary of an input.
  border-input on surface is 1.6:1 in Latte, about the same as gray-300 on white
  today. Revisit with mobile support and UI cleanup.
- **Typography, spacing, and table components.** Part of mobile support and UI
  cleanup.
- **Charts coloured by sign.**
- **Screenshot tests.** Baselines need updating on every intentional UI change,
  and rendering in Docker is flaky.

## Assumptions

- No production database holds tags yet.
- The browsers in use support `prefers-color-scheme` and CSS colour mixing.
  Tailwind v4 already requires both.
- Fourteen colours are enough for the user's tags. Tags that share a colour are
  told apart by name.
