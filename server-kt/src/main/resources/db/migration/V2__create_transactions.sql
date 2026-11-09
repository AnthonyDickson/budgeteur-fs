-- Money columns are cents, declared BIGINT so jOOQ reads a Long (SQLite gives any type containing
-- INT integer affinity). Calendar dates are yyyy-MM-dd TEXT, checked with date(),
-- which normalises anything else (2026-02-30 becomes 2026-03-02), so the check fails for it. See
-- README.md.

-- Somewhere the user's transactions happen: chequing, savings, credit card. See
-- docs/csv-import.md. Only the transaction slice reads it so far.
CREATE TABLE accounts (
    -- Version 7, so ids sort by creation time.
    id        UUID NOT NULL PRIMARY KEY,
    user_id   TEXT NOT NULL,
    -- The number statements identify the account by, in canonical form: an NZ bank account number
    -- or a masked card number. NULL for an account without one.
    number    TEXT,
    -- The user's alias for the account. Defaults to the account number.
    name      TEXT NOT NULL,
    term      TEXT NOT NULL CHECK (term IN ('Current', 'NonCurrent')),
    -- The calendar date the account was closed. NULL while it is open. See decision 4 in
    -- docs/reports.md.
    closed_on TEXT CHECK (date(closed_on) IS closed_on),
    -- Unique per user. SQLite treats NULLs as distinct, so any number of accounts can lack one.
    -- Also serves as the index for reading a user's accounts.
    UNIQUE (user_id, number)
);

-- The facts of what happened. A transaction's tag is its categorisation, kept apart.
CREATE TABLE transactions (
    -- Version 7, so ids sort by creation time.
    id          UUID    NOT NULL PRIMARY KEY,
    user_id     TEXT    NOT NULL,
    -- Cents: a debit is negative and a credit positive.
    amount      BIGINT  NOT NULL,
    description TEXT    NOT NULL,
    -- The calendar date the transaction occurred, as given by the bank statement or the user.
    date        TEXT    NOT NULL CHECK (date(date) IS date),
    -- NULL when the account is unknown or does not apply, e.g. cash.
    account_id  UUID,
    -- A hash of the identity fields of the statement row the transaction was imported from, unique
    -- per user, so a re-import skips it. NULL for transactions created by the user. See decision 6
    -- in docs/csv-import.md.
    import_hash TEXT,
    -- Deleting an account deletes its transactions, see decision 2 in docs/csv-import.md.
    FOREIGN KEY (account_id) REFERENCES accounts (id) ON UPDATE CASCADE ON DELETE CASCADE
);

-- Search reads a user's transactions newest first, then by id.
CREATE INDEX ix_transactions_user_id_date ON transactions (user_id, date, id);
-- SQLite treats NULLs as distinct, so transactions created by the user never collide.
CREATE UNIQUE INDEX ux_transactions_user_id_import_hash ON transactions (user_id, import_hash);
-- Lets deleting an account find its transactions without a table scan.
CREATE INDEX ix_transactions_account_id ON transactions (account_id);

-- How a transaction is categorised: a tag, a dismissal, or a transfer, and who decided it. One row
-- per tagged, dismissed, or transfer transaction; an untagged transaction has none. See
-- docs/auto-tagging.md, docs/quick-tagging.md and docs/transfer-rules.md.
CREATE TABLE categorisations (
    transaction_id UUID NOT NULL PRIMARY KEY,
    user_id        TEXT NOT NULL,
    -- Tagged: the transaction has the tag. Dismissed: the user decided it has no tag. Transfer: it
    -- moves money between the user's own accounts, so it is neither income nor expense.
    kind           TEXT NOT NULL CHECK (kind IN ('Tagged', 'Dismissed', 'Transfer')),
    -- Set only when tagged.
    tag_id         UUID,
    -- Who decided: the user without a suggestion (Manual) or by choosing one (Accepted), a rule
    -- (Rule), or import's account-number detection (Detected). A dismissal is always Manual. See
    -- decision 4 in docs/transfer-rules.md.
    source         TEXT NOT NULL CHECK (source IN ('Manual', 'Accepted', 'Rule', 'Detected')),
    CHECK ((kind = 'Tagged') = (tag_id IS NOT NULL)),
    CHECK (kind <> 'Dismissed' OR source = 'Manual'),
    -- Deleting the transaction or the tag removes the categorisation: the transaction is untagged.
    FOREIGN KEY (transaction_id) REFERENCES transactions (id) ON DELETE CASCADE,
    FOREIGN KEY (tag_id) REFERENCES tags (id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX ix_categorisations_user_id ON categorisations (user_id);
-- Lets deleting a tag find its categorisations without a table scan.
CREATE INDEX ix_categorisations_tag_id ON categorisations (tag_id);
