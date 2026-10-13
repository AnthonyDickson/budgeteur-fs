namespace Budgeteur.Tests.IncomeStatement

module ValidatePeriodTests =
    open System
    open Expecto

    open Budgeteur.Domain.IncomeStatement
    open Budgeteur.Feature.IncomeStatement
    open Budgeteur.Shared.DomainError

    /// The validation message, failing the test if the period was accepted or
    /// failed otherwise.
    let private failure (fromValue : string option) (toValue : string option) =
        match ReadIncomeStatement.validatePeriod fromValue toValue with
        | Error (ValidationFailed message) -> message
        | other -> failtest $"expected a validation failure, got %A{other}"

    [<Tests>]
    let tests =
        testList "ReadIncomeStatement.validatePeriod" [
            test "ISO-8601 dates make a period" {
                match
                    ReadIncomeStatement.validatePeriod
                        (Some "2026-10-01")
                        (Some "2026-10-31")
                with
                | Ok period ->
                    Expect.equal
                        (Period.fromDate period)
                        (DateOnly (2026, 10, 1))
                        "from"

                    Expect.equal
                        (Period.toDate period)
                        (DateOnly (2026, 10, 31))
                        "to"
                | Error error -> failtest $"expected a period, got %A{error}"
            }

            test "every missing parameter is reported" {
                let message = failure None None

                Expect.stringContains
                    message
                    "'from'"
                    "the message should name 'from'"

                Expect.stringContains
                    message
                    "'to'"
                    "the message should name 'to'"
            }

            test "a date that is not ISO-8601 is reported by name" {
                let message = failure (Some "2026-10-01") (Some "31/10/2026")

                Expect.stringContains
                    message
                    "'to'"
                    "the message should name 'to'"

                Expect.isFalse
                    (message.Contains "'from'")
                    "the valid 'from' should not be reported"
            }

            test "an invalid period is a validation failure" {
                let message = failure (Some "2026-10-31") (Some "2026-10-01")

                Expect.stringContains
                    message
                    "must not be after"
                    "the period's rule should be reported"
            }
        ]
