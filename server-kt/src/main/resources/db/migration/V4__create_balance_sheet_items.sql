-- A balance sheet line that is not an account: one asset or one liability. Its values are
-- observations. See docs/balance-sheet.md.
CREATE TABLE balance_sheet_items (
    -- Version 7, so ids sort by creation time.
    id        UUID NOT NULL PRIMARY KEY,
    user_id   TEXT NOT NULL,
    name      TEXT NOT NULL,
    -- Fixed at creation.
    side      TEXT NOT NULL CHECK (side IN ('Asset', 'Liability')),
    term      TEXT NOT NULL CHECK (term IN ('Current', 'NonCurrent')),
    -- The calendar date the item was sold or repaid. NULL while it is held. A balance sheet drawn
    -- on or after it leaves the item out. See decision 4 in docs/reports.md.
    closed_on TEXT CHECK (date(closed_on) IS closed_on),
    -- Also serves as the index for reading a user's items.
    UNIQUE (user_id, name, side, term)
);

-- A value an item had as of a date, entered by hand. One per item and date; the latest is the
-- item's current value. Every item has at least one: it is created with its first, and its last
-- cannot be deleted. See decision 2 in docs/reports.md.
CREATE TABLE item_observations (
    item_id UUID   NOT NULL,
    user_id TEXT   NOT NULL,
    -- The calendar date the value is accurate as of.
    as_of   TEXT   NOT NULL CHECK (date(as_of) IS as_of),
    -- Cents, a positive magnitude: the direction comes from the item's side. BIGINT, as for
    -- transactions.amount.
    value   BIGINT NOT NULL CHECK (value >= 0),
    PRIMARY KEY (item_id, as_of),
    -- Deleting the item deletes its value history.
    FOREIGN KEY (item_id) REFERENCES balance_sheet_items (id) ON DELETE CASCADE
);

CREATE INDEX ix_item_observations_user_id ON item_observations (user_id);

-- Each item's current value: the observation with the latest as-of date. A read model, as for
-- current_balances.
CREATE VIEW current_item_values AS
SELECT o.item_id, o.user_id, o.as_of, o.value
FROM item_observations o
WHERE o.as_of = (
    SELECT MAX(latest.as_of)
    FROM item_observations latest
    WHERE latest.item_id = o.item_id
);
