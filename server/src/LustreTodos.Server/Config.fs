namespace LustreTodos.Server.Config

open System.ComponentModel.DataAnnotations

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
