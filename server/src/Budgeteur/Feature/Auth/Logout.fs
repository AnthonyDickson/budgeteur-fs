namespace Budgeteur.Feature.Auth

module Logout =
    open Microsoft.AspNetCore.Authentication
    open Oxpecker

    open Budgeteur.Shared.Auth

    let private handler (redirectUri : string) : EndpointHandler =
        fun ctx ->
            task {
                // Currently Authelia does not support RP-Initiated Logout
                // (see https://github.com/authelia/authelia/pull/11660). Once released,
                // replace with: ctx.SignOutAsync cookieScheme then
                // ctx.SignOutAsync (oidcScheme, AuthenticationProperties (RedirectUri = returnUrl))
                return! ctx.SignOutAsync (Auth.cookieScheme, AuthenticationProperties (RedirectUri = redirectUri))
            }

    let endpoint (redirectUri : string) : Endpoint =
        route Auth.LogoutPath (handler redirectUri)
