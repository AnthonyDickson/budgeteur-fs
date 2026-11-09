-- A balance an account had as of a date, from a statement or entered by hand. One per account and
-- date; the latest is the account's current balance. See decision 3 in docs/csv-import.md.
CREATE TABLE balance_observations (
    account_id UUID   NOT NULL,
    user_id    TEXT   NOT NULL,
    -- The calendar date the balance is accurate as of.
    as_of      TEXT   NOT NULL CHECK (date(as_of) IS as_of),
    -- Cents, signed: positive is an asset (owned), negative a liability (owed). BIGINT, as for
    -- transactions.amount.
    balance    BIGINT NOT NULL,
    PRIMARY KEY (account_id, as_of),
    -- Deleting the account deletes its balance history.
    FOREIGN KEY (account_id) REFERENCES accounts (id) ON DELETE CASCADE
);

CREATE INDEX ix_balance_observations_user_id ON balance_observations (user_id);

-- Each account's current balance: the observation with the latest as-of date, so an old statement
-- never replaces a newer balance. An account without observations has no row: its balance is
-- unknown. A read model; see decision 3 in docs/csv-import.md.
CREATE VIEW current_balances AS
SELECT o.account_id, o.user_id, o.as_of, o.balance
FROM balance_observations o
WHERE o.as_of = (
    SELECT MAX(latest.as_of)
    FROM balance_observations latest
    WHERE latest.account_id = o.account_id
);
