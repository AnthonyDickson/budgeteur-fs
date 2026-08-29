namespace Budgeteur.Domain.Tag

open System

open Budgeteur.Shared.DomainError

type TagName = private TagName of string

module TagName =
    [<Literal>]
    let private MaxNameLength = 256

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
        name.Trim () |> nonEmpty |> Result.bind acceptableLength |> Result.map TagName

    let value (TagName name) = name

    /// An escape hatch for the smart constructor for reading trusted values from the database.
    let internal unsafeFromString name = TagName name

type TagColor = private TagColor of string

module TagColor =
    open System.Text.RegularExpressions

    let private regexPattern = "^#[A-Fa-f0-9]{6}$"

    let create (color : string) : Result<TagColor, DomainError> =
        if Regex.IsMatch (color, regexPattern) then
            Ok (TagColor color)
        else
            Error (ValidationFailed $"Tag color should be hex color string matching '{regexPattern}', e.g. #00AAFF")

    let value (TagColor color) = color

    /// An escape hatch for the smart constructor for reading trusted values from the database.
    let internal unsafeFromString color = TagColor color

type Tag = {
    Id : Guid
    Name : TagName
    Color : TagColor
}
