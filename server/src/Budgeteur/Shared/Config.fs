namespace Budgeteur.Shared.Config

open System
open System.ComponentModel.DataAnnotations
open Microsoft.Data.Sqlite
open Microsoft.Extensions.Configuration
open Microsoft.Extensions.DependencyInjection
open Microsoft.Extensions.Options

[<CLIMutable>]
type OidcConfig = {
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
type OAuth2Config = {
    [<Required>]
    ClientId : string

    [<Required>]
    AuthorizationUrl : string

    [<Required>]
    TokenUrl : string
}

[<CLIMutable>]
type LoginConfig = {
    [<Required>]
    ReturnUrl : string
}

[<CLIMutable>]
type LoggingConfig = { FilePath : string }

type AppConfig = {
    ConnectionString : string
    Oidc : OidcConfig
    Oauth2 : OAuth2Config option
    Login : LoginConfig
    Logging : LoggingConfig
}

module Config =
    [<Literal>]
    let private ConnectionName = "Default"

    [<Literal>]
    let private OidcSectionName = "Oidc"

    [<Literal>]
    let private Oauth2SectionName = "OAuth2"

    [<Literal>]
    let private LoginSectionName = "Login"

    [<Literal>]
    let private LoggingSectionName = "Logging"

    let private register<'T when 'T : not struct and 'T : (new : unit -> 'T)>
        (services : IServiceCollection)
        (config : IConfiguration)
        (sectionName : string)
        =
        services.AddOptions<'T>().Bind(config.GetSection sectionName).ValidateDataAnnotations().ValidateOnStart()
        |> ignore

    /// Raises `OptionsValidationException` for missing or invalid config entries.
    let private read<'T when 'T : not struct and 'T : (new : unit -> 'T)>
        (config : IConfiguration)
        (sectionName : string)
        : 'T =
        let section = config.GetSection sectionName

        // `Get` returns null for an absent section, which the validator rejects with an exception.
        if not (section.Exists ()) then
            raise (OptionsValidationException (sectionName, typeof<'T>, [ $"{sectionName} is required" ]))

        let value = section.Get<'T>()
        let validator = DataAnnotationValidateOptions<'T> Options.DefaultName
        let result = validator.Validate (Options.DefaultName, value)

        if result.Succeeded then
            value
        else
            raise (OptionsValidationException (sectionName, typeof<'T>, result.Failures))

    let private sectionExists (config : IConfiguration) (name : string) = (config.GetSection name).Exists()

    /// <summary>Enforce foreign keys on every connection opened with the connection string. SQLite
    /// enforces them per connection, so the setting belongs in the connection string rather than a
    /// one-off <c>PRAGMA</c>. The bundled e_sqlite3 build already defaults to on; this keeps the
    /// guarantee independent of the native library's build flags.</summary>
    let withForeignKeys (connectionString : string) =
        SqliteConnectionStringBuilder (connectionString, ForeignKeys = Nullable true)
        |> string

    /// Raises `OptionsValidationException` when the connection string is missing, rather than
    /// letting SQLite open a temporary database.
    let private readConnectionString (config : IConfiguration) =
        match config.GetConnectionString ConnectionName with
        | null
        | "" ->
            raise (
                OptionsValidationException (
                    "ConnectionStrings",
                    typeof<string>,
                    [ $"ConnectionStrings:{ConnectionName} is required" ]
                )
            )
        | connectionString -> withForeignKeys connectionString

    /// Raises `OptionsValidationException` for missing or invalid config entries.
    let load (services : IServiceCollection) (config : IConfiguration) : AppConfig =
        register<OidcConfig> services config OidcSectionName
        register<LoginConfig> services config LoginSectionName
        register<LoggingConfig> services config LoggingSectionName

        let oauthOptions =
            if sectionExists config Oauth2SectionName then
                register<OAuth2Config> services config Oauth2SectionName
                Some (read config Oauth2SectionName)
            else
                None

        {
            ConnectionString = readConnectionString config
            Oidc = read config OidcSectionName
            Oauth2 = oauthOptions
            Login = read config LoginSectionName
            Logging = read config LoggingSectionName
        }
