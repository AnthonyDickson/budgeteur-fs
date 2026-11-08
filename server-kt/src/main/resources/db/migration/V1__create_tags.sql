-- Tags group transactions on the income statement, see docs/dashboard.md.
CREATE TABLE tags (
    -- Version 7, so ids sort by creation time.
    id      UUID NOT NULL PRIMARY KEY,
    user_id TEXT NOT NULL,
    name    TEXT NOT NULL,
    -- A Catppuccin accent colour, by name, see docs/styling.md.
    color   TEXT NOT NULL,
    -- Which side of the income statement the tag's transactions are on.
    kind    TEXT NOT NULL CHECK (kind IN ('Income', 'Expense')),
    UNIQUE (user_id, name)
);

CREATE INDEX ix_tags_user_id ON tags (user_id);
