"""Export one user's transactions, categorisations, tags, and rules from a local copy of the
database to CSV files in ml/data/. See decision 8 in docs/smart-tagging.md.

Usage: python export.py <database> <user id>
"""

import sqlite3
import sys
from pathlib import Path

import pandas as pd

DATA_DIR = Path(__file__).parent / "data"

# Each transaction with its categorisation, if it has one. Amounts are stored as REAL, so they
# are formatted to cents rather than exported as floats.
TRANSACTIONS = """
SELECT t.Id AS id,
       date(t.Date) AS date,
       printf('%.2f', t.Amount) AS amount,
       t.Description AS description,
       t.AccountId AS account_id,
       c.Kind AS kind,
       c.TagId AS tag_id,
       c.Source AS source
FROM Transactions t
LEFT JOIN Categorisations c ON c.TransactionId = t.Id
WHERE t.UserId = ?
ORDER BY t.Date, t.Id
"""

TAGS = """
SELECT Id AS id, Name AS name, Kind AS kind
FROM Tags
WHERE UserId = ?
ORDER BY Name
"""

RULES = """
SELECT Id AS id, Pattern AS pattern, Target AS target, TagId AS tag_id
FROM Rules
WHERE UserId = ?
ORDER BY Pattern
"""


def main(database: str, user_id: str) -> None:
    # Read-only, so the export cannot change the database it reads.
    with sqlite3.connect(f"file:{database}?mode=ro", uri=True) as connection:
        tables = {
            name: pd.read_sql_query(query, connection, params=(user_id,))
            for name, query in [
                ("transactions", TRANSACTIONS),
                ("tags", TAGS),
                ("rules", RULES),
            ]
        }
        if tables["transactions"].empty:
            users = connection.execute(
                "SELECT UserId, COUNT(*) FROM Transactions GROUP BY UserId ORDER BY 2 DESC"
            ).fetchall()
            listing = "\n".join(f"  {user} ({count} transactions)" for user, count in users)
            sys.exit(f"User {user_id} has no transactions. Users in {database}:\n{listing}")

    DATA_DIR.mkdir(exist_ok=True)
    for name, table in tables.items():
        path = DATA_DIR / f"{name}.csv"
        table.to_csv(path, index=False)
        print(f"{path}: {len(table)} rows")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
