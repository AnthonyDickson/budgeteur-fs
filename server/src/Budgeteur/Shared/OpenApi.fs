namespace Budgeteur.Shared.OpenApi

module OpenApi =
    open Microsoft.AspNetCore.OpenApi
    open Microsoft.FSharp.Reflection
    open Microsoft.OpenApi
    open System.Collections.Concurrent
    open System.Collections.Generic
    open System.IO
    open System.Reflection
    open System.Text.Json
    open System.Threading
    open System.Threading.Tasks
    open System.Xml.Linq

    let private isOptionType (t : System.Type) : bool =
        if t.IsGenericType then
            let definition = t.GetGenericTypeDefinition ()
            definition = typedefof<option<_>> || definition = typedefof<voption<_>>
        else
            false

    /// <summary>
    /// Marks non-option record fields as required and fixes string property type inference in OpenAPI schemas.
    /// </summary>
    type FSharpRecordSchemaTransformer () =
        interface IOpenApiSchemaTransformer with
            member _.TransformAsync (schema, context, _cancellationToken : CancellationToken) =
                let jsonType = context.JsonTypeInfo.Type

                if FSharpType.IsRecord jsonType then
                    let required =
                        jsonType
                        |> FSharpType.GetRecordFields
                        |> Seq.filter (fun field -> not (isOptionType field.PropertyType))
                        |> Seq.map (fun field -> field.Name)
                        |> HashSet<string>

                    if required.Count > 0 then
                        schema.Required <- required

                if
                    not (isNull context.JsonPropertyInfo)
                    && context.JsonPropertyInfo.PropertyType = typeof<string>
                then
                    schema.Type <- JsonSchemaType.String

                    if not (isNull schema.OneOf) then
                        schema.OneOf.Clear ()

                    if not (isNull schema.AnyOf) then
                        schema.AnyOf.Clear ()

                    if not (isNull schema.AllOf) then
                        schema.AllOf.Clear ()

                Task.CompletedTask


    /// <summary>
    /// Populates schema and property descriptions from F# XML doc comments (`summary` tags on types and record fields).
    /// </summary>
    type XmlDocSchemaTransformer () =
        let loadedDocs = ConcurrentDictionary<string, Map<string, string>> ()

        let tryLoadDoc (asm : Assembly) : Map<string, string> =
            let xmlPath = Path.ChangeExtension (asm.Location, ".xml")

            if File.Exists xmlPath then
                let doc = XDocument.Load xmlPath

                doc.Descendants (XName.Get "member")
                |> Seq.choose (fun el ->
                    let name = el.Attribute (XName.Get "name") |> Option.ofObj

                    let summary =
                        el.Element (XName.Get "summary")
                        |> Option.ofObj
                        |> Option.map (fun e -> e.Value.Trim ())

                    match name, summary with
                    | Some n, Some s -> Some (n.Value, s)
                    | _ -> None)
                |> Map.ofSeq
            else
                Map.empty

        let getSummaries (asm : Assembly) : Map<string, string> =
            loadedDocs.GetOrAdd (asm.Location, fun _ -> tryLoadDoc asm)

        interface IOpenApiSchemaTransformer with
            member _.TransformAsync (schema, context, _cancellationToken : CancellationToken) =
                let jsonType = context.JsonTypeInfo.Type
                // .NET reflection uses '+' for nested types but XML doc uses '.'
                let xmlTypeName = jsonType.FullName.Replace ('+', '.')

                let summaries = getSummaries jsonType.Assembly

                // Set type-level description from <summary> on the type itself
                let typeKey = $"T:%s{xmlTypeName}"

                match summaries.TryFind typeKey with
                | Some summary -> schema.Description <- summary
                | None -> ()

                // Set field-level descriptions from <summary> on record fields
                if FSharpType.IsRecord jsonType then
                    for field in FSharpType.GetRecordFields jsonType do
                        let fieldKey = $"P:%s{xmlTypeName}.%s{field.Name}"
                        let jsonName = JsonNamingPolicy.CamelCase.ConvertName field.Name

                        match summaries.TryFind fieldKey with
                        | Some summary ->
                            if not (isNull schema.Properties) && schema.Properties.ContainsKey jsonName then
                                schema.Properties[jsonName].Description <- summary
                        | None -> ()

                Task.CompletedTask
