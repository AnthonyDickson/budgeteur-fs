namespace Budgeteur.Tests

open System
open Expecto
open Microsoft.Data.Sqlite

open Budgeteur.Domain.Transaction

/// Migrations applied to a database with data from an earlier release, so an
/// upgraded database keeps its behaviour.
module MigrationTests =
    let private migrate (connectionString : string) (filter : string -> bool) =
        let result =
            DbUp.DeployChanges.To
                .SqliteDatabase(connectionString)
                .WithScriptsEmbeddedInAssembly(
                    typeof<Transaction>.Assembly,
                    Func<string, bool> filter
                )
                .WithTransactionPerScript()
                .Build()
                .PerformUpgrade()

        if not result.Successful then
            failwithf "Migration failed: %O" result.Error

    let private execute (conn : SqliteConnection) (sql : string) =
        use cmd = conn.CreateCommand ()
        cmd.CommandText <- sql
        cmd.ExecuteNonQuery () |> ignore

    let private query (conn : SqliteConnection) (sql : string) =
        use cmd = conn.CreateCommand ()
        cmd.CommandText <- sql
        use reader = cmd.ExecuteReader ()

        [
            while reader.Read () do
                [
                    for i in 0 .. reader.FieldCount - 1 ->
                        if reader.IsDBNull i then
                            None
                        else
                            Some (reader.GetString i)
                ]
        ]

    /// Data as 1.0.0-rc3 wrote it, with migration 001 only. Ids are short
    /// text, which the schema accepts, so each row fits on a line.
    let private rc3Data =
        """
        INSERT INTO Tags (Id, UserId, Name, Color, Kind)
        VALUES ('groceries', 'u', 'Groceries', 'Green', 'Expense');

        INSERT INTO Transactions (Id, UserId, Amount, Description, Date)
        VALUES
            ('a', 'u', -1, 'Manual', '2026-10-01'),
            ('b', 'u', -1, 'Rule', '2026-10-01'),
            ('c', 'u', -1, 'Dismissed', '2026-10-01'),
            ('d', 'u', -1, 'Transfer', '2026-10-01');

        INSERT INTO Categorisations (TransactionId, UserId, Kind, TagId, Source)
        VALUES
            ('a', 'u', 'Tagged', 'groceries', 'Manual'),
            ('b', 'u', 'Tagged', 'groceries', 'Rule'),
            ('c', 'u', 'Dismissed', NULL, NULL),
            ('d', 'u', 'Transfer', NULL, NULL);

        INSERT INTO Rules (Id, UserId, Pattern, TagId)
        VALUES ('r', 'u', 'COUNTDOWN', 'groceries');
        """

    [<Tests>]
    let tests =
        testCase "an rc3 database keeps its data, with targets and sources"
        <| fun () ->
            let name = $"migration-{Guid.NewGuid ()}"

            let connectionString =
                Budgeteur.Shared.Config.Config.withForeignKeys
                    $"Data Source=file:{name}?mode=memory&cache=shared"

            use keeper = new SqliteConnection (connectionString)
            keeper.Open ()

            migrate connectionString (fun script -> script.Contains "001_")
            execute keeper rc3Data
            migrate connectionString (fun script -> script.EndsWith ".sql")

            Expect.equal
                (query
                    keeper
                    "SELECT Description, Kind, Source FROM Categorisations c \
                    JOIN Transactions t ON t.Id = c.TransactionId \
                    ORDER BY Description")
                [
                    [ Some "Dismissed"; Some "Dismissed"; Some "Manual" ]
                    [ Some "Manual"; Some "Tagged"; Some "Manual" ]
                    [ Some "Rule"; Some "Tagged"; Some "Rule" ]
                    [ Some "Transfer"; Some "Transfer"; Some "Manual" ]
                ]
                "tags keep their source; dismissals and transfers become manual"

            Expect.equal
                (query keeper "SELECT Pattern, Target, TagId FROM Rules")
                [ [ Some "COUNTDOWN"; Some "Tag"; Some "groceries" ] ]
                "existing rules should become tag rules"

            // The rebuilt tables keep their foreign keys: deleting the tag
            // untags its transactions and deletes its rules.
            execute keeper "DELETE FROM Tags"

            Expect.equal
                (query keeper "SELECT Kind FROM Categorisations ORDER BY Kind")
                [ [ Some "Dismissed" ]; [ Some "Transfer" ] ]
                "deleting the tag should remove its categorisations"

            Expect.isEmpty
                (query keeper "SELECT Id FROM Rules")
                "deleting the tag should delete its rules"
