-- Transfer rules and categorisation sources. See decision 11 in docs/transfer-rules.md.
--
-- SQLite cannot change a column's nullability or a table's checks in place, so each table is
-- rebuilt: create the new table, copy the rows, drop the old one, rename, and recreate its
-- indexes. No table references either table, so dropping them cascades nowhere. The migration
-- runner applies this script in one database transaction.

-- Categorisations

CREATE TABLE Categorisations_new (
    TransactionId GUID NOT NULL PRIMARY KEY,
    UserId        TEXT NOT NULL,
    -- Tagged: the transaction has the tag. Dismissed: the user decided it has no tag. Transfer: it
    -- moves money between the user's own accounts, so it has no tag and is neither income nor
    -- expense; it is shown in the transactions table but counts towards no statistics.
    Kind          TEXT NOT NULL CHECK (Kind IN ('Tagged', 'Dismissed', 'Transfer')),
    -- Set only when tagged.
    TagId         GUID,
    -- Who decided the categorisation, whatever its kind: the user without a suggestion (Manual)
    -- or by choosing one (Accepted), a rule (Rule), or import's account-number detection
    -- (Detected). Re-tag recomputes only Rule rows. A dismissal is always the user's decision.
    -- See decision 4 in docs/transfer-rules.md.
    Source        TEXT NOT NULL CHECK (Source IN ('Manual', 'Accepted', 'Rule', 'Detected')),
    CHECK ((Kind = 'Tagged') = (TagId IS NOT NULL)),
    CHECK (Kind <> 'Dismissed' OR Source = 'Manual'),
    -- Deleting the transaction or the tag removes the categorisation: the transaction is untagged.
    FOREIGN KEY(TransactionId) REFERENCES Transactions(Id) ON DELETE CASCADE,
    FOREIGN KEY(TagId) REFERENCES Tags(Id) ON UPDATE CASCADE ON DELETE CASCADE
);

-- Transfers and dismissals had no source. Whether a transfer was detected was not recorded.
INSERT INTO Categorisations_new (TransactionId, UserId, Kind, TagId, Source)
SELECT TransactionId, UserId, Kind, TagId, COALESCE(Source, 'Manual')
FROM Categorisations;

DROP TABLE Categorisations;

ALTER TABLE Categorisations_new RENAME TO Categorisations;

CREATE INDEX IX_Categorisations_UserId ON Categorisations(UserId);
-- Lets deleting a tag find its categorisations without a table scan.
CREATE INDEX IX_Categorisations_TagId ON Categorisations(TagId);
