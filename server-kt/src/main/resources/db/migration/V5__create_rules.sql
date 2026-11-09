-- A pattern that proposes a categorisation for the transactions whose descriptions contain it. See
-- docs/auto-tagging.md and docs/transfer-rules.md.
CREATE TABLE rules (
    -- Version 7, so ids sort by creation time.
    id      UUID NOT NULL PRIMARY KEY,
    user_id TEXT NOT NULL,
    -- The text to find in transaction descriptions.
    pattern TEXT NOT NULL,
    -- What the rule proposes when it wins: a tag, or a transfer. See decision 1 in
    -- docs/transfer-rules.md.
    target  TEXT NOT NULL CHECK (target IN ('Tag', 'Transfer')),
    -- The tag a tag rule proposes. NULL for a transfer rule, so deleting a tag never deletes one.
    tag_id  UUID,
    CHECK ((target = 'Tag') = (tag_id IS NOT NULL)),
    FOREIGN KEY (tag_id) REFERENCES tags (id) ON DELETE CASCADE,
    -- Unique per user, ignoring case, whatever the target. NOCASE folds ASCII only, so the server
    -- checks uniqueness first with its own comparison; see docs/auto-tagging.md. Also serves as the
    -- index for reading a user's rules.
    UNIQUE (user_id, pattern COLLATE NOCASE)
);

CREATE INDEX ix_rules_tag_id ON rules (tag_id);
