namespace Budgeteur.Feature.BalanceSheet

open System

module BalanceSheetStore =
    open System.Threading.Tasks

    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db

    /// <summary> Update the statement date on the user's balance sheet if it
    /// exists, otherwise create it. The instant is stored in UTC, as the
    /// <c>DATETIME</c> column convention requires.</summary>
    let updateOrCreate
        (queryContext : QueryContext)
        (now : DateTimeOffset)
        (userId : string)
        : Task<unit> =
        task {
            // The column carries no offset, so it has to be written as UTC.
            let statementDate = UtcDateTime.toColumn now

            let! sheetCount =
                selectTask queryContext {
                    for b in main.BalanceSheets do
                        where (b.UserId = userId)
                        count
                }

            let exists = sheetCount > 0

            if exists then
                let! _ =
                    updateTask queryContext {
                        for b in main.BalanceSheets do
                            set b.StatementDate statementDate
                            where (b.UserId = userId)
                    }

                return ()
            else
                let! _ =
                    insertTask queryContext {
                        for b in main.BalanceSheets do
                            entity {
                                UserId = userId
                                StatementDate = statementDate
                            }
                    }

                return ()
        }
