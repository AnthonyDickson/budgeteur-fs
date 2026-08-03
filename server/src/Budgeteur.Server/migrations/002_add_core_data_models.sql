-- Note that while `GUID`, `BOOLEAN` and `DATETIME` are not real SQLite data types,
-- they act as hints to SqlHydra for codegen, see
-- https://github.com/JordanMarr/SqlHydra/blob/main/src/SqlHydra.Cli/Sqlite/SqliteDataTypes.fs
-- for the full list of supported types.

-- Accounts

CREATE TABLE Accounts (
    -- v7 UUID
    Id        GUID     NOT NULL PRIMARY KEY,
    UserId    TEXT     NOT NULL,
    -- The account number from a bank statement
    Number    TEXT     NOT NULL,
    -- The account name, defaults to the account number. May be set by the user to a custom name.
    Name      TEXT     NOT NULL,
    -- The amount of money held in the account. Positive values indicate credit whereas negative values indicate debit.
    Balance   CURRENCY NOT NULL,
    -- When the balance snapshot was taken (the date the balance is accurate as of) as a Unix timestamp in seconds
    CurrentAsOf INTEGER  NOT NULL
);

CREATE INDEX IX_Accounts_UserId on Accounts(UserId);

-- Categories

CREATE TABLE Categories (
    -- v7 UUID
    Id     GUID NOT NULL PRIMARY KEY,
    UserId TEXT NOT NULL,
    Name   TEXT NOT NULL
);

CREATE INDEX IX_Categories_UserId on Categories(UserId);

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
    -- When the transaction occurred as a Unix timestamp in seconds
    Date        INTEGER  NOT NULL,
    -- The account associated with the transaction.
    -- NULL indicates the account info is not available or not applicable (e.g., cash).
    AccountId   GUID,
    -- The hash of the CSV row that uniquely identifies a transaction imported from a CSV file.
    -- NULL for transactions directly created by the user.
    ImportHash  TEXT,
    CategoryId  GUID,
    FOREIGN KEY(AccountId)  REFERENCES Accounts(Id)   ON UPDATE CASCADE ON DELETE SET NULL,
    FOREIGN KEY(CategoryId) REFERENCES Categories(Id) ON UPDATE CASCADE ON DELETE SET NULL
);

CREATE INDEX IX_Transactions_UserId ON Transactions(UserId);
CREATE INDEX IX_Transactions_UserId_CategoryId ON Transactions(UserId, CategoryId);

-- Auto-tagging rules

CREATE TABLE Rules (
    -- v7 UUID
    Id         GUID NOT NULL PRIMARY KEY,
    UserId     TEXT NOT NULL,
    -- The string pattern to match in transaction descriptions
    Pattern    TEXT NOT NULL,
    -- The category (tag) to apply when the pattern matches the transaction description
    CategoryId GUID NOT NULL,
    FOREIGN KEY(CategoryId) REFERENCES Categories(Id) ON UPDATE CASCADE ON DELETE CASCADE,
    UNIQUE(UserId, Pattern, CategoryId)
);

CREATE INDEX IX_Rules_UserId ON Rules(UserId);

-- Tagging Queue

CREATE TABLE TaggingQueue (
    TransactionId GUID    NOT NULL PRIMARY KEY,
    UserId        TEXT    NOT NULL,
    -- When the transaction was added to the queue as Unix timestamp in seconds, used for sorting the queue.
    CreatedAt     INTEGER NOT NULL,
    FOREIGN KEY(TransactionId) REFERENCES Transactions(Id) ON DELETE CASCADE
);

CREATE INDEX IX_TaggingQueue_UserId ON TaggingQueue(UserId);

CREATE TRIGGER RemoveTransactionFromTaggingQueueWhenTagSet
AFTER UPDATE OF CategoryId ON Transactions
WHEN OLD.CategoryId IS NULL AND NEW.CategoryId IS NOT NULL
BEGIN
    DELETE FROM TaggingQueue WHERE TransactionId = NEW.Id;
END;


-- User Preferences

-- Categories that should be excluded from summary statistics, e.g. internal transfers
CREATE TABLE HiddenCategories (
    CategoryId GUID NOT NULL PRIMARY KEY,
    UserId     TEXT NOT NULL,
    FOREIGN KEY(CategoryId) REFERENCES Categories(Id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX IX_HiddenCategories_UserId ON HiddenCategories(UserId);
