namespace Budgeteur.Data

module ItemValueCodec =
    open Budgeteur.Data.Db
    open Budgeteur.Domain.BalanceSheetItem

    /// <summary>An item row joined to its row in the current values view. A
    /// view's columns are nullable to SqlHydra, but every item has an
    /// observation and the view's columns come from a table that requires
    /// them.</summary>
    let fromRow
        (item : main.BalanceSheetItems, current : main.CurrentItemValues)
        : ItemValue = {
        Item = BalanceSheetItemCodec.fromRow item
        Current =
            match current.AsOf, current.Value with
            | Some asOf, Some value -> {
                AsOf = asOf
                Value = Value.unsafeFromDecimal value
              }
            // Unreachable: see above
            | _ -> failwith $"Item %O{item.Id} has no current value"
    }
