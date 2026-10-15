namespace Budgeteur.Domain.Tag

open System

open Budgeteur.Shared.DomainError

type TagName = private TagName of string

module TagName =
    [<Literal>]
    let private MaxNameLength = 64

    let private nonEmpty name =
        if String.IsNullOrWhiteSpace name then
            Error (ValidationFailed "Tag name cannot be null or whitespace")
        else
            Ok name

    let private acceptableLength (name : string) =
        if name.Length > MaxNameLength then
            Error (
                ValidationFailed
                    $"Name is too long. Names must be at most \
                    %i{MaxNameLength} characters, but got %i{name.Length}"
            )
        else
            Ok name

    let create (name : string) =
        name.Trim ()
        |> nonEmpty
        |> Result.bind acceptableLength
        |> Result.map TagName

    let value (TagName name) = name

    /// An escape hatch for the smart constructor for reading trusted values
    /// from the database.
    let internal unsafeFromString name = TagName name

/// <summary>A tag's colour: one of Catppuccin's accent colours, by name. The
/// client draws it in the active flavour's value, so a tag keeps its colour in
/// light and dark mode. See decision 9 in docs/styling.md.</summary>
type TagColor =
    | Rosewater
    | Flamingo
    | Pink
    | Mauve
    | Red
    | Maroon
    | Peach
    | Yellow
    | Green
    | Teal
    | Sky
    | Sapphire
    | Blue
    | Lavender

module TagColor =
    let toString color =
        match color with
        | Rosewater -> "Rosewater"
        | Flamingo -> "Flamingo"
        | Pink -> "Pink"
        | Mauve -> "Mauve"
        | Red -> "Red"
        | Maroon -> "Maroon"
        | Peach -> "Peach"
        | Yellow -> "Yellow"
        | Green -> "Green"
        | Teal -> "Teal"
        | Sky -> "Sky"
        | Sapphire -> "Sapphire"
        | Blue -> "Blue"
        | Lavender -> "Lavender"

    /// <summary>Every colour, in Catppuccin's order.</summary>
    let all = [
        Rosewater
        Flamingo
        Pink
        Mauve
        Red
        Maroon
        Peach
        Yellow
        Green
        Teal
        Sky
        Sapphire
        Blue
        Lavender
    ]

    let parse string =
        match all |> List.tryFind (fun color -> toString color = string) with
        | Some color -> Ok color
        | None ->
            let expected = all |> List.map toString |> String.concat ", "

            Error
                $"\"{string}\" is not a valid value for TagColor, expecting \
                one of {expected}."

/// <summary>Which side of the income statement a tag's transactions are on. The
/// user states it, so a tag stays on the same side in every period, whatever
/// the sign of its amounts.</summary>
type TagKind =
    | Income
    | Expense

module TagKind =
    let toString kind =
        match kind with
        | Income -> "Income"
        | Expense -> "Expense"

    let parse string =
        match string with
        | "Income" -> Ok Income
        | "Expense" -> Ok Expense
        | other ->
            Error
                $"\"{other}\" is not a valid value for TagKind, expecting \
                one of \"Income\" or \"Expense\"."

type Tag = {
    Id : Guid
    Name : TagName
    Color : TagColor
    Kind : TagKind
}
