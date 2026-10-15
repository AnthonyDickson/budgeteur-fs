namespace Budgeteur.Feature.Transaction

/// <summary>The slice's read shape: a transaction with its tag, if any, and its
/// account's name, if any. Writes respond with it too, read back inside their
/// database transaction, so every response carries the same fields.</summary>
module TransactionQuery =
    open System

    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Domain.Money
    open Budgeteur.Domain.Rule
    open Budgeteur.Feature.Transaction

    let private fromJoinedRow
        (
            row : main.Transactions,
            categorisation : main.LeftJoined.Categorisations,
            accountName : string option
        ) =
        TransactionCodec.fromRow row,
        categorisation.ToOption () |> Option.map CategorisationCodec.fromRow,
        accountName

    /// <summary>Every transaction of the user.</summary>
    let readAll (ctx : QueryContext) (userId : string) =
        task {
            let! rows =
                selectTask ctx {
                    for t in main.Transactions do
                        leftJoin a in main.LeftJoined.Categorisations
                                          on
                                          (t.Id = a.TransactionId)

                        leftJoin' account in main.LeftJoined.Accounts
                        on' (t.AccountId = account.Id)

                        where (t.UserId = userId)
                        select (t, a, account.Name)
                }

            return rows |> Seq.map fromJoinedRow |> List.ofSeq
        }

    /// <summary>A page of the user's transactions matching the search, newest
    /// first, then by id, starting after the cursor, and the cursor for the
    /// next page. Each criterion applies only when its flag is set: SqlHydra
    /// leaves out a term <c>flag &amp;&amp; condition</c> when the flag is
    /// false. See docs/transaction-search.md.</summary>
    let search
        (ctx : QueryContext)
        (userId : string)
        (search : Search)
        (after : Cursor option)
        =
        task {
            PatternMatch.register ctx

            let hasText = search.Text.IsSome

            let text =
                search.Text
                |> Option.map RulePattern.value
                |> Option.defaultValue ""

            let hasFrom = search.From.IsSome
            let from = Option.defaultValue DateOnly.MinValue search.From
            let hasTo = search.To.IsSome
            let ``to`` = Option.defaultValue DateOnly.MaxValue search.To

            let isNoAccount = search.Account = AccountCriterion.NoAccount

            let isAccount, accountId =
                match search.Account with
                | AccountCriterion.Account id -> true, Some id
                | _ -> false, None

            let isWithoutTag = search.Tag = TagCriterion.WithoutTag
            let isUntagged = search.Tag = TagCriterion.Untagged
            let isDismissed = search.Tag = TagCriterion.Dismissed
            let isTransfer = search.Tag = TagCriterion.Transfer

            let isTag, tagId =
                match search.Tag with
                | TagCriterion.Tag id -> true, Some id
                | _ -> false, None

            let dismissed = Some CategorisationCodec.DismissedKind
            let transfer = Some CategorisationCodec.TransferKind

            let isCredit = search.Direction = Direction.Credit
            let isDebit = search.Direction = Direction.Debit

            // A size bounds the absolute amount, so each bound is a pair of
            // signed comparisons on the column. Its NUMERIC affinity converts
            // the decimal parameters, which are bound as text, to numbers.
            let hasMinimum = search.Minimum.IsSome

            let minimum =
                search.Minimum
                |> Option.map Money.value
                |> Option.defaultValue 0m

            let negativeMinimum = -minimum
            let hasMaximum = search.Maximum.IsSome

            let maximum =
                search.Maximum
                |> Option.map Money.value
                |> Option.defaultValue 0m

            let negativeMaximum = -maximum

            let hasCursor = after.IsSome

            let cursorDate =
                after
                |> Option.map _.Date
                |> Option.defaultValue DateOnly.MaxValue

            let cursorId =
                after |> Option.map _.Id |> Option.defaultValue Guid.Empty

            let limit = TransactionSearch.PageSize + 1

            let! rows =
                selectTask ctx {
                    for t in main.Transactions do
                        leftJoin c in main.LeftJoined.Categorisations
                                          on
                                          (t.Id = c.TransactionId)

                        leftJoin' account in main.LeftJoined.Accounts
                        on' (t.AccountId = account.Id)

                        where (
                            t.UserId = userId
                            && (hasText
                                && PatternMatch.position (t.Description, text) >
                                    0)
                            && (hasFrom && t.Date >= from)
                            && (hasTo && t.Date <= ``to``)
                            && (isNoAccount && t.AccountId = None)
                            && (isAccount && t.AccountId = accountId)
                            && (isWithoutTag
                                && (isNullValue c.TransactionId
                                    || c.Kind = dismissed))
                            && (isUntagged && isNullValue c.TransactionId)
                            && (isDismissed && c.Kind = dismissed)
                            && (isTransfer && c.Kind = transfer)
                            && (isTag && c.TagId = tagId)
                            && (isCredit && t.Amount > 0m)
                            && (isDebit && t.Amount < 0m)
                            && (hasMinimum
                                && (t.Amount >= minimum
                                    || t.Amount <= negativeMinimum))
                            && (hasMaximum
                                && (t.Amount <= maximum
                                    && t.Amount >= negativeMaximum))
                            && (hasCursor
                                && (t.Date < cursorDate
                                    || t.Date = cursorDate && t.Id < cursorId))
                        )

                        orderByDescending t.Date
                        thenByDescending t.Id
                        take limit
                        select (t, c, account.Name)
                }

            return
                rows
                |> Seq.map fromJoinedRow
                |> List.ofSeq
                |> TransactionSearch.page (fun (transaction, _, _) -> {
                    Date = transaction.Date
                    Id = transaction.Id
                })
        }

    /// <summary>The user's transaction with the id, if any.</summary>
    let tryRead (ctx : QueryContext) (userId : string) (id : Guid) =
        task {
            let! row =
                selectTask ctx {
                    for t in main.Transactions do
                        leftJoin a in main.LeftJoined.Categorisations
                                          on
                                          (t.Id = a.TransactionId)

                        leftJoin' account in main.LeftJoined.Accounts
                        on' (t.AccountId = account.Id)

                        where (t.Id = id && t.UserId = userId)
                        select (t, a, account.Name)
                        tryHead
                }

            return Option.map fromJoinedRow row
        }
