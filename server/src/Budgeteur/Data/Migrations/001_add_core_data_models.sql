-- Note that while `GUID`, `BOOLEAN` and `DATETIME` are not real SQLite data types,
-- they act as hints to SqlHydra for codegen, see
-- https://github.com/JordanMarr/SqlHydra/blob/main/src/SqlHydra.Cli/Sqlite/SqliteDataTypes.fs
-- for the full list of supported types.
--
-- # Column Type Assumptions
-- GUIDs are assumed to be v7 UUIDs
-- DATETIME columns are assumed to be UTC and DATE columns hold calendar dates, see docs/dates.md
-- for how to read and write them.

-- Accounts

-- Somewhere the user's transactions happen: chequing, savings, credit card. See docs/csv-import.md.
CREATE TABLE Accounts (
    -- v7 UUID
    Id     GUID NOT NULL PRIMARY KEY,
    UserId TEXT NOT NULL,
    -- The number statements identify the account by, in canonical form: an NZ bank account
    -- number or a masked card number. NULL for an account without one.
    Number TEXT,
    -- The user's alias for the account. Defaults to the account number.
    Name   TEXT NOT NULL,
    Term   TEXT NOT NULL CHECK (Term IN ('Current', 'NonCurrent')),
    -- Unique per user. SQLite treats NULLs as distinct, so any number of accounts can lack one.
    -- Also serves as the index for reading a user's accounts.
    UNIQUE(UserId, Number)
);

-- Account balance observations

-- A balance an account had as of a date, from a statement or entered by hand. One per account
-- and date; the latest is the account's current balance. See decision 3 in docs/csv-import.md.
CREATE TABLE BalanceObservations (
    AccountId GUID     NOT NULL,
    UserId    TEXT     NOT NULL,
    -- The calendar date the balance is accurate as of.
    AsOf      DATE     NOT NULL,
    -- Signed: positive is an asset (owned), negative a liability (owed).
    Balance   CURRENCY NOT NULL,
    PRIMARY KEY (AccountId, AsOf),
    -- Deleting the account deletes its balance history.
    FOREIGN KEY(AccountId) REFERENCES Accounts(Id) ON DELETE CASCADE
);

CREATE INDEX IX_BalanceObservations_UserId ON BalanceObservations(UserId);

-- Each account's current balance: the observation with the latest as-of date,
-- so an old statement never replaces a newer balance. An account without
-- observations has no row: its balance is unknown. A read model; see decision
-- 3 in docs/csv-import.md.
CREATE VIEW CurrentBalances AS
SELECT o.AccountId, o.UserId, o.AsOf, o.Balance
FROM BalanceObservations o
WHERE o.AsOf = (
    SELECT MAX(latest.AsOf)
    FROM BalanceObservations latest
    WHERE latest.AccountId = o.AccountId
);

-- Balance Sheet Items

CREATE TABLE BalanceSheetItems (
    -- v7 UUID
    Id      GUID     NOT NULL PRIMARY KEY,
    UserId  TEXT     NOT NULL,
    Name    TEXT     NOT NULL,
    Kind    TEXT     NOT NULL CHECK (Kind IN ('Asset', 'Liability')),
    Term    TEXT     NOT NULL CHECK (Term IN ('Current', 'NonCurrent')),
    Balance CURRENCY NOT NULL CHECK (Balance >= 0),
    -- The calendar date the balance is accurate as of, chosen by the user.
    AsOf    DATE     NOT NULL,
    UNIQUE(UserId, Name, Kind, Term)
);

-- Tags

CREATE TABLE Tags (
    -- v7 UUID
    Id     GUID NOT NULL PRIMARY KEY,
    UserId TEXT NOT NULL,
    Name   TEXT NOT NULL,
    Color  Text NOT NULL,
    -- Which side of the income statement the tag's transactions are on, see docs/dashboard.md.
    Kind   TEXT NOT NULL CHECK (Kind IN ('Income', 'Expense')),
    UNIQUE(UserId, Name)
);

CREATE INDEX IX_Tags_UserId on Tags(UserId);

-- Transactions

CREATE TABLE Transactions (
    -- Expected to be v7 UUIDs for better sorting and performance
    Id          GUID     NOT NULL PRIMARY KEY,
    -- User IDs are likely GUIDs, but we play it safe by not making any assumptions
    -- since the identity provider chooses the format.
    UserId      TEXT     NOT NULL,
    -- The currency amount of income or expenses
    Amount      CURRENCY NOT NULL,
    -- A text description of the transaction either manually entered by the user or derived from a CSV row.
    Description TEXT     NOT NULL,
    -- The calendar date the transaction occurred, as given by the bank statement or the user (not an instant).
    Date        DATE     NOT NULL,
    -- The account associated with the transaction.
    -- NULL indicates the account info is not available or not applicable (e.g., cash).
    AccountId   GUID,
    -- A hash of the identity fields of the statement row the transaction was imported from, unique
    -- per user, so a re-import skips it. NULL for transactions created by the user. See decision 6
    -- in docs/csv-import.md.
    ImportHash  TEXT,
    -- Deleting an account deletes its transactions, see decision 2 in docs/csv-import.md.
    FOREIGN KEY(AccountId) REFERENCES Accounts(Id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX IX_Transactions_UserId_Date ON Transactions(UserId, Date);
-- SQLite treats NULLs as distinct, so transactions created by the user never collide.
CREATE UNIQUE INDEX UX_Transactions_UserId_ImportHash ON Transactions(UserId, ImportHash);
-- Lets deleting an account find its transactions without a table scan.
CREATE INDEX IX_Transactions_AccountId ON Transactions(AccountId);

-- Auto-tagging rules

CREATE TABLE Rules (
    -- v7 UUID
    Id         GUID NOT NULL PRIMARY KEY,
    UserId     TEXT NOT NULL,
    -- The string pattern to match in transaction descriptions
    Pattern    TEXT NOT NULL,
    -- The tag to apply when the pattern matches the transaction description
    TagId      GUID NOT NULL,
    FOREIGN KEY(TagId) REFERENCES Tags(Id) ON UPDATE CASCADE ON DELETE CASCADE,
    -- Unique per user, ignoring case, whatever the tag. NOCASE folds ASCII only; the server
    -- checks uniqueness first with ordinal case-insensitive comparison, see docs/auto-tagging.md.
    -- Also serves as the index for reading a user's rules.
    UNIQUE(UserId, Pattern COLLATE NOCASE)
);

-- Categorisations

-- How a transaction is categorised: its tag and where it came from, a dismissal, or a transfer.
-- Kept apart from the transaction so categorising changes without touching its facts. One row per
-- tagged, dismissed, or transfer transaction; an untagged transaction has none. See
-- docs/auto-tagging.md and docs/quick-tagging.md.
CREATE TABLE Categorisations (
    TransactionId GUID NOT NULL PRIMARY KEY,
    UserId        TEXT NOT NULL,
    -- Tagged: the transaction has the tag. Dismissed: the user decided it has no tag. Transfer: it
    -- moves money between the user's own accounts, so it has no tag and is neither income nor
    -- expense; it is shown in the transactions table but counts towards no statistics.
    Kind          TEXT NOT NULL CHECK (Kind IN ('Tagged', 'Dismissed', 'Transfer')),
    -- Set only when tagged.
    TagId         GUID,
    -- Whether the user set the tag or a rule did. Rules never change a manual tag. Set only when
    -- tagged.
    Source        TEXT CHECK (Source IN ('Manual', 'Rule')),
    CHECK ((Kind = 'Tagged') = (TagId IS NOT NULL)),
    CHECK ((Kind = 'Tagged') = (Source IS NOT NULL)),
    -- Deleting the transaction or the tag removes the categorisation: the transaction is untagged.
    FOREIGN KEY(TransactionId) REFERENCES Transactions(Id) ON DELETE CASCADE,
    FOREIGN KEY(TagId) REFERENCES Tags(Id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX IX_Categorisations_UserId ON Categorisations(UserId);
-- Lets deleting a tag find its categorisations without a table scan.
CREATE INDEX IX_Categorisations_TagId ON Categorisations(TagId);
