# CSV import

Design brief for importing bank statements from CSV files, and for the accounts
the statements belong to. It records what we decided, why, and what each
decision is meant to achieve. Change it when the reasoning changes.

The previous Rust project (`budgeteur`, `server/src/csv_import/`) parsed three
formats (ASB bank, ASB credit card, Kiwibank) with one hand-written parser each,
tried each parser in turn, hashed the raw CSV line to skip duplicates, upserted
an account by number, and auto-tagged in the same database transaction. When
Kiwibank replaced its export format, the parser had to be rewritten and
overlapping imports duplicated transactions, because the hash covered the raw
line. Lessons from it are cited where they shaped a decision.

## Goal

- **Less manual entry.** Transactions and account balances come from the bank
  exports the user already downloads.
- **Safe to repeat.** Importing a statement twice, or two overlapping
  statements, never duplicates a transaction, including across a change in the
  bank's export format.
- **Fail loudly.** A file the app cannot read is rejected with the reason, and
  nothing from the request is written.
- **Accounts on the balance sheet.** Account balances count towards net worth
  and working capital, update from statements where the statement has a balance,
  and can be entered by hand where it does not.
- **Accounts at a glance.** The transactions table shows which account each
  transaction belongs to, by a name the user chooses.

## Ubiquitous language

| Term              | Meaning                                                                                                                                                                                                                  |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Account           | Somewhere the user's transactions happen: chequing, savings, credit card. A source of balance sheet lines alongside items.                                                                                               |
| Item              | A balance sheet line that is not an account: a house, a car, a loan or investment the user values by hand.                                                                                                               |
| Account number    | The number a statement identifies an account by: an NZ bank account number in canonical form, or a masked card number.                                                                                                   |
| Account name      | The user's alias for an account. Defaults to the account number.                                                                                                                                                         |
| Balance           | An account's balance, signed: positive is an asset (owned), negative a liability (owed). An item's balance on the balance sheet is a magnitude instead.                                                                  |
| As-of date        | The calendar date a balance is accurate as of, from the statement or chosen by the user.                                                                                                                                 |
| Observation       | A balance and its as-of date for one account, from a statement or entered by hand. One per account and date.                                                                                                             |
| Current balance   | The observation with the latest as-of date. Unknown when the account has no observations.                                                                                                                                |
| Statement         | One CSV file from a bank, which the bank calls an export: the transactions of one account, and possibly its closing balance. The bank's sense, not the financial statement the balance sheet's statement date refers to. |
| Format            | A description, held as data, of how to read one bank's export: header, preamble, columns, date format, sign, row order, identity fields.                                                                                 |
| Identity fields   | The fields of a row that identify a transaction across exports, such as account, date, amount, and running balance.                                                                                                      |
| Import hash       | A hash of a row's identity fields, stored on the transaction. Unique per user.                                                                                                                                           |
| Duplicate         | A row whose import hash the user already has. Skipped.                                                                                                                                                                   |
| Internal transfer | A row whose other party is one of the user's own accounts. Imported with `IsTransfer` set.                                                                                                                               |

## Decisions

### 1. An account is where transactions happen

- **Decision**: an account is somewhere the user records transactions. Anything
  else the user owns or owes is a balance sheet item. The test is "do I record
  transactions in it?", and the user applies it; the app does not enforce a list
  of products. Defaults:

  | Holding                                  | Default | Why                                                                                |
  | ---------------------------------------- | ------- | ---------------------------------------------------------------------------------- |
  | Chequing, savings                        | Account | Day-to-day transactions; CSV exports exist.                                        |
  | Credit card, overdraft, revolving credit | Account | Day-to-day transactions. A liability through its sign.                             |
  | Term deposit                             | Item    | A few untagged transactions; updated by hand. An account if its statements matter. |
  | Brokerage, KiwiSaver, retirement         | Item    | Valued by market price, not by transactions. Contributions are transfers.          |
  | Mortgage, car loan                       | Item    | Repayments show on the chequing account. An account if its statements matter.      |

- **Why**: the account is what transactions reference, what statements are
  matched to, and what transfer detection compares against. A holding nobody
  records transactions for needs none of that.
- **Replaces**: the existing `Accounts` table, which predates the balance sheet
  and has no term, no way to hold an unknown balance, and no place on the sheet.
  Migration `001` is unreleased, so it is redesigned in place.
- **Goal**: one clear line between accounts and items, so a holding is not
  entered twice.

### 2. Accounts are a second source of balance sheet lines

- **Decision**: accounts have their own table: number (optional, unique per
  user), name, and term, with their balances as observations (decision 3). The
  balance sheet read model combines items and accounts. An account line uses the
  current balance, and is an asset when it is zero or more and a liability when
  it is negative, with the balance's magnitude. Totals, net worth, and working
  capital include both sources. Item rules are unchanged: positive magnitude,
  kind fixed at creation.
- **Deletion**: deleting an account deletes its observations and its
  transactions, including any entered by hand against it. Closed accounts stay
  as $0 lines (Deferred), so deletion is for mistakes, such as an account
  created by importing the wrong file, whose transactions are mistakes too.
  Re-importing a statement restores them, tagged by rules. Keeping the
  transactions without an account was rejected: a re-import skips them as
  duplicates (decision 6), so they would stay without one for good.
- **Why**: a bank account's sign changes (an overdrawn chequing account is a
  current liability), which an item's fixed kind cannot follow. Keeping accounts
  apart leaves the item invariants intact, stores each balance once, lets a
  balance be unknown, and keeps an account, and the attribution of its
  transactions, when it has no place on the sheet. Balance sheet decision 3
  anticipated this rule: a negative balance becomes a liability.
- **Rejected**:
  - Accounts as balance sheet items with an optional account number. One list
    and one form, but kind becomes editable for some items, an item created by
    import has no balance to start with, and deleting a closed account's item
    clears the account from its transactions.
  - Accounts linked to items. The account and the item each have a name and a
    balance, kept in sync by import, and every account needs linking by hand.
- **Goal**: account balances count towards net worth and working capital without
  changing what an item is.

### 3. Balances are dated observations; the latest is current

- **Decision**: every balance the app learns for an account is kept as an
  observation: the account, the as-of date, and the signed balance. An account
  has at most one observation per date. The current balance is the observation
  with the latest as-of date, so an old statement never replaces a newer
  balance. An account with no observations has an unknown balance, which is left
  out of totals and listed in a callout above the sheet, asking the user to
  enter it.
- **Current balance as a view**: a database view selects each account's latest
  observation, and reads left join accounts to it. Which observation is current
  decides nothing on the write side, so it is a read model, and a query states
  the rule once instead of each reader loading the whole history and choosing in
  memory.
- **Same date**: a new observation replaces any observation on its date, whether
  it came from a statement or was entered by hand.
- **Manual entry**: the balance form records an observation with a balance and
  an as-of date, which defaults to the client's today. A new account may take an
  opening balance the same way. An as-of date later than the server's UTC date
  plus one day is rejected, so a mistyped future date cannot stay current.
  Re-entering a balance on the same date corrects it.
- **Sources**:
  - Kiwibank: one observation per transaction (processing) date in the
    statement: the running balance after the last row of that date, by the
    format's declared row order (decision 5). The bank's balances are taken as
    given.
  - ASB credit card: none. The user enters the balance, for example from the
    monthly statement.
- **Why**: the balance sheet has no history, and regular snapshots (roadmap)
  need one. Observations make a snapshot for any date a query: for each line,
  the latest observation on or before that date. Kiwibank's running balance
  gives a daily history from the bank's own figures, which is lost unless it is
  recorded at import, since users rarely keep old exports. One rule covers
  statements and manual entry without special cases. An unknown balance is not
  $0, which would understate a credit card's liability.
- **Known limitations**:
  - Importing an older export after a newer one that covers the same last day
    replaces that day's balance with the older, partial one. The next import
    fixes it.
  - A manual entry on a date with a statement balance replaces the bank's figure
    until an import covering that date restores it.
- **Rejected**:
  - A single balance per account, overwritten by newer ones. It loses the
    history snapshots need, and still needs the rule that an older balance does
    not replace a newer one, so it saves little.
  - Statement observations taking precedence over manual ones on the same date.
    It needs a source on every observation and a rejection path, to guard
    against a manual entry on a date with a statement balance. Users have no
    reason to make one: statement-backed accounts get their balances from
    imports, and ASB cards have none.
  - Rolling a balance forward or backward from imported transactions. It is
    wrong without any sign after a gap between imports, when the cutoff date is
    ambiguous (ASB cards have a processed and a transaction date; transactions
    store the effective date, while the bank changes the balance on the
    processing date), or after transactions are edited by hand. See Deferred.
- **Goal**: each account line shows how current its balance is, a stale one is
  visible, and account balance history exists from the first import.

### 4. Account numbers are canonical and identify accounts on import

- **Decision**: the account number is a refined type in `Domain/`. It accepts an
  NZ bank account number (bank, branch, account, suffix), stored in one
  canonical form with the account padded to seven digits and the suffix to
  three, or a masked card number as the statement prints it. Import finds the
  user's account by number and creates it when missing, with term `Current`, an
  unknown balance, and the number as its name, followed by the product name in
  parentheses where the statement gives one (ASB cards' `Visa Light`). The
  number can be changed at any time. Names need not be unique.
- **Why**: banks print the same number in different forms (a two- or three-digit
  suffix, or the parts on separate fields, as in the previous project's ASB bank
  preamble), and transfer detection compares numbers from different statements.
  Creating accounts on import means the first import works without setup. The
  import hash takes the number from the statement (decision 6), so changing an
  account's number does not change which rows are duplicates; the next import of
  that statement creates an account for the old number, which the import result
  lists.
- **Double counting**: a holding kept as an item, or as an account without a
  number, gets a second line when its first statement is imported. The import
  result lists the accounts it created, and the account form takes a number, so
  the user can set it before the first import.
- **Goal**: one account per real account, matched the same way whichever
  statement mentions it.

### 5. Formats are data, read by one interpreter

- **Decision**: each supported format is a value of one format type, and one
  parser interprets it. A format holds:
  - the exact header line and, for a format with a preamble, a function that
    reads the lines before the header into the account number and product name,
    or an error. User-defined formats have no preamble (Deferred), so a preamble
    does not need to be data;
  - which named column feeds each field: date, description (one or more columns,
    joined with a space), amount, running balance, the date the balance changes
    on, account number, and other party account number;
  - for a format with a running balance, its row order, oldest or newest first,
    which decides the row that closes each date (decision 3). A file whose
    balance dates run the other way is an error (decision 7);
  - the date format, from a fixed list, parsed exactly and independent of
    culture ([dates](dates.md));
  - the amount's sign convention: as given, or negated (ASB credit cards);
  - the identity fields for the import hash (decision 6).

  Fields name their columns by header name. Because the header must match
  exactly, any change to the columns, including an added or reordered one, fails
  detection instead of reading the wrong field. Line endings and a UTF-8 byte
  order mark are normalised, and blank lines skipped, before parsing. Amounts
  are parsed as `decimal` and rounded through `Money`. A description longer than
  the domain limit is truncated; an empty one falls back to the transaction type
  column.
- **Built-in formats**:

  | Format   | Date column         | Description | Amount  | Account from     | Balance                                      |
  | -------- | ------------------- | ----------- | ------- | ---------------- | -------------------------------------------- |
  | ASB card | Date of Transaction | Description | Negated | Preamble (card)  | None                                         |
  | Kiwibank | Effective Date      | Description | As is   | `Account number` | `Balance`, on Transaction Date, oldest first |

  The dates are when the transaction happened, not when it was processed. The
  previous project used the processed date for ASB cards. ASB bank accounts are
  deferred: their export cannot currently be downloaded, so there is no sample
  to build and test the format against.
- **Detection**: a file is the format whose header equals one of its lines, with
  no lines before it for a format without a preamble, or lines its preamble
  function reads without error. No match is an error (decision 7), never a
  fallback to some format.
- **Why**: the protection against format changes is detecting them and failing
  clearly, plus a hash that survives them; generated types give neither. A
  format as data is a short declarative description per bank, testable on its
  own, and the same shape a user-defined format would take later.
- **Rejected**:
  - FSharp.Data `CsvProvider`. It infers types from sample values (ASB's `0000`
    reference becomes an integer), which an anonymiser can change, so types need
    pinning by hand. It cannot read the ASB preamble, throws instead of
    returning `Result`, and keeps samples in `src/` at compile time.
  - A hand-written parser per format, as in the previous project. More code per
    format, columns by index, and nothing shared with user-defined formats.
- **Goal**: a new or changed bank format is a data change plus a fixture, and a
  changed export fails loudly instead of importing wrong values.

### 6. The import hash covers identity fields, per user

- **Decision**: the import hash is SHA-256 over a version tag, the statement's
  account number, and the format's identity fields, each in canonical form (ISO
  date, invariant amount). Identity fields:
  - Kiwibank: transaction (processing) date, amount, running balance.
  - ASB card: the `Unique Id` column.

  The hash is unique per user. Rows whose hash the user already has, or that
  repeat a hash earlier in the same request, are skipped as duplicates.
  Transactions created by hand have no hash.
- **Why**: the previous project hashed the raw line, so Kiwibank's format change
  made every overlapping row look new. Identity fields survive changes to
  descriptions, extra columns, and quoting. The running balance tells apart two
  identical purchases on one day; Kiwibank's date is the one the balance changes
  on, so date and balance come from the same ledger entry. ASB's `Unique Id` is
  a date and sequence per card. The account number keeps identical rows in two
  accounts apart, which the raw line did not. Uniqueness per user lets two users
  import the same statement.
- **Cost**: each format chooses its identity fields deliberately, and tests pin
  hash values so a refactor cannot change them unnoticed.
- **Known limitations**:
  - A deleted imported transaction comes back on the next overlapping import.
  - Two rows in one statement with the same identity fields share a hash, so the
    second is skipped. For Kiwibank this needs two $0.00 rows on one date, which
    leave the balance unchanged.
- **Goal**: importing is safe to repeat, across overlapping statements and
  export format changes.

### 7. A request imports everything or nothing

- **Decision**: one request carries one or more files. If any file is not a
  known format, or any row fails to parse, the response is `400` listing every
  failure with its file name and line number, and nothing is written. For a file
  that matches no format, the message shows the start of the file and each
  format's expected header, to compare by eye.
- **Why**: bank exports are generated, so a row that fails means the format
  changed. Skipping it would import a statement with gaps that nobody notices.
  Listing every failure follows the rule that a client sees all validation
  failures in one response ([architecture](architecture.md#errors)).
- **Goal**: a partial import cannot happen, and a failure says what to fix.

### 8. One database transaction: accounts, duplicates, transfers, tags, balances

- **Decision**: after parsing, the handler, in one database transaction:
  1. finds or creates each statement's account;
  2. drops duplicates against the user's existing hashes and the request;
  3. marks internal transfers (decision 9);
  4. inserts the new transactions and gives each non-transfer the winning rule's
     tag, using the matcher and the tag-untagged transition in `Domain/`;
  5. records balance observations by decision 3.

  The response carries the counts (imported, skipped as duplicates, internal
  transfers, tagged by rules) and the accounts created.
- **Why**: one user action is one database transaction, so a failure leaves no
  partial import. Loading inside the write transaction holds SQLite's write
  lock, as auto-tagging does, so a concurrent import cannot insert the same
  hashes between the check and the write; the unique index is the safety net.
  Auto-tagging on import was deferred to this feature by the auto-tagging brief.
- **Goal**: an import leaves transactions, tags, and balances consistent with
  each other.

### 9. Internal transfers are detected from the other party's account

- **Decision**: a row whose other party account number, in canonical form,
  equals one of the user's account numbers, including accounts the same request
  creates, is imported with `IsTransfer` set and no tag. Only Kiwibank exports
  carry the other party's account. Rows imported earlier are not revisited when
  a new account is added.
- **Why**: untagged transfers count as income and expenses on the dashboard. In
  the sample data, a transfer from chequing to savings would show as $3,865 of
  income. Importing related accounts in one request catches both sides.
- **Goal**: transfers between the user's own accounts stay out of the income
  statement without manual marking.

### 10. The client sends file text as JSON

- **Decision**: the client reads the chosen files as UTF-8 text and sends their
  names and contents in a JSON request body. The import endpoint raises the
  request body limit for itself to 1 MB; every other endpoint keeps 64 KB.
  Parsing happens on the server only.
- **Why**: a JSON body of primitives keeps the request DTO, OpenAPI description,
  and tests the same as every other endpoint. Reading the files is an effect
  that returns their text as a message, so `update` stays pure and tests assert
  on plain data. A year of Kiwibank chequing is about 100 KB, over the global
  limit; 1 MB matches nginx's default `client_max_body_size`.
- **Rejected**: multipart form upload. It needs a browser `File` handle inside
  an effect, multipart parsing on the server, and a second request shape.
- **Goal**: imports of a year of statements fit in one request without raising
  the limit for the whole API.

### 11. Import, then review

- **Decision**: the upload imports straight away. The result shows the counts
  and the accounts created. The transactions rules did not tag join the quick
  tagging queue, reached from the "Quick tag" link next to "Import", where each
  tag saves as it is chosen. There is no review limited to one import; see
  [quick tagging](quick-tagging.md) decision 7.
- **Why**: tagging in a preview before saving holds minutes of work in unsaved
  state, needs a confirm request that re-sends the files or trusts rows parsed
  on the client, and saves nothing if the user stops halfway. Reviewing after
  the import uses the normal assignment writes, and an interrupted review leaves
  the rest in the queue. New rows are tagged by rules during the import, so
  "untagged" and "matched no rule" are the same set.
- **Rejected**: a preview with confirm. Its other use, catching the wrong file,
  is mostly covered by format detection and duplicate skipping; an undo is
  deferred.
- **Goal**: going from an import to tagging what rules missed is one click,
  while quick-tagging stays its own feature.

### 12. Slices

- **Decision**:
  - `Feature/Import/` owns `POST /api/imports`, the formats and their parser,
    and the import's workflow logic: the import hash, duplicate skipping, and
    transfer detection, as pure functions apart from the handler.
  - `Feature/Account/` owns account CRUD at `/api/accounts` and recording a
    balance at `/api/accounts/{id}/balances`. Creating an account takes an
    optional opening balance; updating one changes only its details. Recording a
    balance is its own operation because it appends to the history rather than
    replacing a field, and it takes different fields from editing the details.
  - The `Account` type, its number and name rules, and the observation rules
    (one per date, no future dates) are in `Domain/`, with their mapping in
    `Data/`, because both slices write accounts and observations. The rule that
    the latest observation is current is the current balances view (decision 3),
    which the Account and balance sheet slices both read. The transaction
    mapping moves from the Transaction slice to `Data/`, because Import also
    writes transactions.
  - The balance sheet slice reads accounts into its own read model. The
    Transaction slice reads account names for its responses.
- **Why**: the formats are the banks' model, not ours; the parser is an adapter
  (an anti-corruption layer in DDD terms) that turns it into domain types at the
  edge. Duplicate and transfer detection are rules of the import workflow, so
  they stay with it. A table's rules and mapping have one owner in the shared
  modules once a second slice writes it
  ([architecture](architecture.md#where-domain-logic-lives)). Import needs no
  other slice: the matcher and assignment transitions are already in `Domain/`.
- **Goal**: import is one slice that changes when formats or the import workflow
  change.

### 13. UI

- **Transactions page**: an "Import" button in the header opens a modal with a
  file input (several files, `.csv`). Submitting reads the files, sends the
  request, and disables the button while it runs. Success closes the modal,
  shows a toast with the counts and any accounts created, and reloads the table.
  The toast stays until dismissed, since it takes longer to read than a save
  confirmation. Failures show every listed error in the modal so the user can
  fix and retry. The table shows the account name for each transaction, and the
  transaction modal has an account select.
- **Balance sheet page**: account lines sit in the same asset and liability,
  current and non-current groups as items, marked with the account number and
  the current balance's as-of date. A callout lists accounts with an unknown
  balance. An "Add account" button sits next to the item buttons. Clicking a
  line opens the form that updates its amount: an item's form, or an account's
  balance form, since that is the action repeated most. The balance form
  switches to the account form, and deleting starts from an item's or account's
  form, so the sheet shows amounts rather than a column of buttons. The account
  form edits the name, number, and term; a new account also takes an optional
  opening balance. The balance form opens on the current balance's side and
  amount, dated today, and records an observation: an asset or liability and an
  amount without a sign. Keeping the current balance's date corrects it. The
  unknown-balance callout opens the same form. Deleting an account warns that
  its transactions and balance history are deleted with it.
- **Why separate forms**: editing details and recording a balance take different
  fields and do different things: one replaces the account's details, the other
  adds to its balance history. In one form, a blank balance meant "keep the
  current one", so changing only the side recorded nothing.
- **Goal**: importing starts where the user reviews transactions, and account
  balances are managed where they count.

### 14. Samples and the anonymiser

- **Decision**: anonymised samples of each format are test fixtures for the
  server and E2E tests, not source files. An anonymiser script, run through
  `just`, rewrites a raw export by column name and preamble line:
  - account and card numbers map to fake ones consistently across files, so
    transfer pairs still match;
  - every free-text column (description, other party name, particulars, code,
    reference, and their equivalents in other formats) is replaced with text
    built from several fixed word lists. A stable hash of the original value
    chooses the words, so the same value always gets the same replacement, in
    every file and on every run, and combining lists keeps distinct values
    apart;
  - dates, amounts, and balances stay as they are, so running balances still add
    up.

  The hash is keyed with a secret kept beside the raw exports, which live in a
  gitignored folder, so the same key gives the same replacements on every run. A
  plain hash of an account number could be reversed by trying every number.
- **Why**: when a bank changes its export, the new file is anonymised, added as
  a fixture, and the failing tests show what changed. Working by column name
  lets the script handle a format the app does not know yet. Replacing free text
  outright removes merchant names and places as well as people's names, which
  replacing names within the text cannot do reliably, so the output needs no
  review by hand. Consistent replacement keeps recurring merchants recurring,
  which rule matching, auto-tagging, and E2E tests depend on. Descriptions are
  not identity fields, so pinned hash values do not change. Parser edge cases
  (commas, quotes, a description over the length limit, non-ASCII text) are
  small inputs in the parser tests, not words in the lists, so a fixture's
  coverage does not depend on which words a hash picks, and adding a case does
  not change every replacement.
- **Rejected**: random replacement per row, which turns every recurring merchant
  into many and changes on every run; and replacement in order of first
  appearance, which has no collisions but changes every later replacement when
  an export gains a merchant.
- **Goal**: adding or updating a format starts from a real export without
  putting real data in the repository.

## Consequences

- **Schema** (migration `001`, unreleased, edited in place; then `just db-reset`
  and `just db-update`):
  - `Accounts`: id, user id, number (nullable, unique per user), name, term.
  - Account balance observations: account id, user id, as-of date, balance;
    keyed by account and date, removed with the account.
  - `Transactions`: the import hash unique per user; removed with their account,
    with an index on the account id so deletion does not scan the table.
  - `BalanceSheetItems`: an as-of date. `BalanceSheets` is removed.
- **Balance sheet**: decisions 1, 3, and 5 of [balance-sheet](balance-sheet.md)
  cover account lines. Decision 4 dates every line, so neither the Account nor
  the Import slice writes anything for the sheet itself.
- **Request body limit**: the gotcha in `AGENTS.md` and the reverse proxy notes
  in [deployment](deployment.md) change with decision 10.
- **Highest-value tests**:
  - Account number parsing and canonical form, including suffix padding.
  - Each format against its fixture: dates, signs, descriptions, detection, and
    errors with file and line. Parser edge cases (quoting, long and non-ASCII
    descriptions, blank lines) as inline inputs.
  - Kiwibank observations: one per processing date; a file out of the declared
    row order rejected.
  - Observation rules: latest is current, a new observation replaces one on its
    date, future dates rejected.
  - Pinned hash values per format, so a refactor cannot change them.
  - Import: duplicates skipped within and across requests; all or nothing on a
    bad file; accounts created; observations recorded and an older statement not
    changing the current balance; transfers marked and not tagged; rule tags
    applied; data scoped to the caller.
  - Account CRUD: deleting an account deletes its transactions; balance sheet
    totals with account lines, a negative balance, and an unknown one.
  - Client: the import modal's flow (files read, request, toast, errors shown);
    balance form conversion between asset or liability and a signed balance.
  - E2E: upload the Kiwibank chequing and savings samples; transactions appear
    with their account, the transfer is marked, and both accounts appear on the
    balance sheet.

## Deferred

- **ASB bank accounts.** The export cannot currently be downloaded. Build the
  format from an anonymised sample once it can. The previous project's parser
  shows the expected layout: a preamble with the account number split into bank,
  branch, and account (with the product name), and the ledger balance and its
  date; then `Date, Unique Id, Tran Type, Cheque Number, Payee, Memo, Amount`.
  Expected mapping: the description joins Payee and Memo (the previous project
  dropped Payee), the ledger balance is an observation, and the identity field
  is `Unique Id`. Unconfirmed until a sample exists.
- **User-defined formats.** Formats stored per user as data, created in a
  mapping wizard with a live preview, reusing the interpreter. Limited to plain
  tables with the account picked at upload; formats with preambles stay built
  in. No user code; regular expressions, if added, run without backtracking.
- **Account picked at upload.** For formats without an account column.
- **Snapshots.** Part of the regular snapshots roadmap item. The balance sheet
  as of a date the client sends: for each line, the latest observation on or
  before it, with the observation's date shown so stale lines are visible. Items
  get observations too, their balance and as-of date becoming the first, and a
  sold or repaid holding is closed with a final $0 observation instead of
  deleted, so past net worth does not change. Queried rather than stored, so no
  scheduled job or server timezone is needed.
- **Reconciliation.** Between two observations of an account, the change in
  balance should equal the sum of its transactions between them; a difference
  means missing transactions, and an incomplete income statement for that
  period. Includes checking a statement's opening balance against the previous
  import's closing balance.
- **Observation history.** Listing, editing, and deleting an account's past
  observations. Until then, a wrong entry is corrected on the same date or
  replaced by a newer one.
- **Rolling balances forward.** For formats without a balance. If added, shown
  as estimated so it is never mistaken for a statement figure.
- **Import history and undo.** An imports record on each transaction.
- **Converting an item into an account.** Until then, delete and recreate.
- **Hiding closed accounts.** Until then, a closed account is a $0 line.
- **Transfers without another party column.** ASB card payments from an ASB
  account appear in both statements and are marked by hand. A rule action that
  marks transfers belongs with rules on other fields (auto-tagging brief).
- **More banks and Wise.** Wise exports carry several currencies.

## Assumptions

- Statements are UTF-8 (or ASCII) with comma separators.
- One statement holds one account.
