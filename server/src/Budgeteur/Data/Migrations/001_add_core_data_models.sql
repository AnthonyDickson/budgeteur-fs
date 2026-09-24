-- Note that while `GUID`, `BOOLEAN` and `DATETIME` are not real SQLite data types,
-- they act as hints to SqlHydra for codegen, see
-- https://github.com/JordanMarr/SqlHydra/blob/main/src/SqlHydra.Cli/Sqlite/SqliteDataTypes.fs
-- for the full list of supported types.
--
-- # Column Type Assumptions
-- GUIDs are assumed to be v7 UUIDs
--
-- # DATETIME Special Handling
-- 
-- DATETIME columns are stored without offset info and by default will be loaded
-- with the `Unspecified` offset. In general, DATETIME values are assumed to be
-- UTC and any deviation from this should be clearly documented.
-- When writing to this column ensure the value is in UTC.
-- When reading this column, set the offset to UTC via DateTime.SpecifyKind.

-- Accounts

CREATE TABLE Accounts (
    -- v7 UUID
    Id          GUID     NOT NULL PRIMARY KEY,
    UserId      TEXT     NOT NULL,
    -- The account number from a bank statement
    Number      TEXT     NOT NULL,
    -- The account name, defaults to the account number. May be set by the user to a custom name.
    Name        TEXT     NOT NULL,
    -- The amount of money held in the account. Positive values indicate credit whereas negative values indicate debit.
    Balance     CURRENCY NOT NULL,
    -- When the balance snapshot was taken (the date the balance is accurate as of).
    -- TODO: Change this column to UTC DATETIME to ensure the local date can be reconstructed from it
    CurrentAsOf DATE     NOT NULL
);

CREATE INDEX IX_Accounts_UserId on Accounts(UserId);

-- Balance Sheet + Items

CREATE TABLE BalanceSheets (
    -- One balance sheet per user
    UserId        TEXT     NOT NULL PRIMARY KEY,
    -- When the balance snapshot was taken (the date the balance is accurate as of).
    StatementDate DATETIME NOT NULL
);

CREATE TABLE BalanceSheetItems (
    -- v7 UUID
    Id      GUID     NOT NULL PRIMARY KEY,
    UserId  TEXT     NOT NULL,
    Name    TEXT     NOT NULL,
    Kind    TEXT     NOT NULL CHECK (Kind IN ('Asset', 'Liability')),
    Term    TEXT     NOT NULL CHECK (Term IN ('Current', 'NonCurrent')),
    Balance CURRENCY NOT NULL CHECK (Balance >= 0),
    UNIQUE(UserId, Name, Kind, Term)
);

-- Tags

CREATE TABLE Tags (
    -- v7 UUID
    Id     GUID NOT NULL PRIMARY KEY,
    UserId TEXT NOT NULL,
    Name   TEXT NOT NULL,
    Color  Text NOT NULL,
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
    -- When the transaction occurred.
    -- TODO: Change this column to UTC DATETIME to ensure the local date can be reconstructed from it
    Date        DATE     NOT NULL,
    -- Whether the transaction represents an internal transfer between a user's own accounts.
    -- If true, the transaction should only be shown in the transactions table, but not anywhere else.
    -- It should not contribute to any statistics or charts.
    IsTransfer  BOOL     NOT NULL,
    -- The account associated with the transaction.
    -- NULL indicates the account info is not available or not applicable (e.g., cash).
    AccountId   GUID,
    -- The hash of the CSV row that uniquely identifies a transaction imported from a CSV file.
    -- NULL for transactions directly created by the user.
    ImportHash  TEXT,
    TagId  GUID,
    FOREIGN KEY(AccountId) REFERENCES Accounts(Id) ON UPDATE CASCADE ON DELETE SET NULL,
    FOREIGN KEY(TagId) REFERENCES Tags(Id) ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE INDEX IX_Transactions_UserId ON Transactions(UserId);
CREATE INDEX IX_Transactions_UserId_TagId ON Transactions(UserId, TagId);

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
    UNIQUE(UserId, Pattern, TagId)
);

CREATE INDEX IX_Rules_UserId ON Rules(UserId);

-- Tagging Queue

CREATE TABLE TaggingQueue (
    TransactionId GUID     NOT NULL PRIMARY KEY,
    UserId        TEXT     NOT NULL,
    -- When the transaction was added to the queue, used for sorting the queue.
    CreatedAt     DATETIME NOT NULL,
    FOREIGN KEY(TransactionId) REFERENCES Transactions(Id) ON DELETE CASCADE
);

CREATE INDEX IX_TaggingQueue_UserId ON TaggingQueue(UserId);

CREATE TRIGGER RemoveTransactionFromTaggingQueueWhenTagSet
AFTER UPDATE OF TagId ON Transactions
WHEN OLD.TagId IS NULL AND NEW.TagId IS NOT NULL
BEGIN
    DELETE FROM TaggingQueue WHERE TransactionId = NEW.Id;
END;
