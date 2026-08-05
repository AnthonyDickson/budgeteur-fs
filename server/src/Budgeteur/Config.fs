namespace Budgeteur.Config

open System.ComponentModel.DataAnnotations
open Microsoft.Extensions.Configuration
open Microsoft.Extensions.DependencyInjection

[<CLIMutable>]
type OidcOptions = {
    [<Required>]
    Authority : string

    [<Required>]
    ClientId : string

    [<Required>]
    ClientSecret : string

    [<Required>]
    CallbackPath : string

    ValidAudiences : string array
}

[<CLIMutable>]
type OAuth2Options = {
    [<Required>]
    ClientId : string

    [<Required>]
    AuthorizationUrl : string

    [<Required>]
    TokenUrl : string
}

[<CLIMutable>]
type LoginOptions = { ReturnUrl : string }

[<CLIMutable>]
type LoggingOptions = { FilePath : string }

module Config =
    let readSection<'T when 'T : not struct and 'T : (new : unit -> 'T)>
        (services : IServiceCollection)
        (config : IConfiguration)
        (sectionName : string)
        =
        let section = config.GetSection sectionName
        let value = new 'T ()
        section.Bind value

        let results = ResizeArray<ValidationResult> ()

        if
            not (Validator.TryValidateObject (value, ValidationContext value, results, validateAllProperties = true))
        then
            let messages =
                results
                |> Seq.map (fun r ->
                    let names =
                        if r.MemberNames |> Seq.isEmpty then
                            sectionName
                        else
                            r.MemberNames |> String.concat ", "

                    $"  - {names}: {r.ErrorMessage}")
                |> String.concat "\n"

            failwith (
                String.concat "\n" [
                    $"Configuration validation failed for section '{sectionName}':"
                    messages
                    ""
                    "Ensure the required settings are present in appsettings or environment variables."
                ]
            )

        services.AddOptions<'T>().Bind(section).ValidateDataAnnotations().ValidateOnStart ()
        |> ignore

        value
