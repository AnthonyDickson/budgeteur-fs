namespace Budgeteur.Tests.Auth

module SchemeTests =
    open System.Net
    open System.Net.Http
    open System.Net.Http.Headers
    open System.Security.Claims
    open Expecto
    open Microsoft.AspNetCore.Authentication.JwtBearer
    open Microsoft.AspNetCore.Builder
    open Microsoft.AspNetCore.Hosting
    open Microsoft.AspNetCore.TestHost
    open Microsoft.Extensions.DependencyInjection
    open Microsoft.Extensions.Hosting
    open Microsoft.IdentityModel.JsonWebTokens
    open Microsoft.IdentityModel.Protocols.OpenIdConnect
    open Microsoft.IdentityModel.Tokens
    open Oxpecker

    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Config

    let private issuer = "https://auth.test"

    let private oidc : OidcConfig = {
        Authority = issuer
        ClientId = "budgeteur-fs"
        ClientSecret = "secret"
        CallbackPath = "/signin-oidc"
        ValidAudiences = null
        LogoutUrl = null
    }

    let private signingKey =
        SymmetricSecurityKey (Array.init 32 byte, KeyId = "test-key")

    /// A token the provider signed, as one issued to any of its applications
    /// would be.
    let private token =
        JsonWebTokenHandler()
            .CreateToken(
                SecurityTokenDescriptor (
                    Issuer = issuer,
                    Subject = ClaimsIdentity [ Claim ("sub", "some-user") ],
                    SigningCredentials =
                        SigningCredentials (
                            signingKey,
                            SecurityAlgorithms.HmacSha256
                        )
                )
            )

    /// A host with the production auth services and middleware in front of
    /// one protected endpoint. The bearer scheme, where registered, gets the
    /// provider's signing key directly, so it validates tokens without
    /// fetching the provider's metadata.
    let private createHost (isDevelopment : bool) =
        let providerConfig = OpenIdConnectConfiguration (Issuer = issuer)
        providerConfig.SigningKeys.Add signingKey

        let host =
            HostBuilder()
                .ConfigureWebHost(fun webHostBuilder ->
                    webHostBuilder
                        .UseTestServer()
                        .ConfigureServices(fun services ->
                            services.AddRouting().AddOxpecker() |> ignore

                            Auth.configureServices services isDevelopment oidc

                            services.Configure<JwtBearerOptions>(
                                Auth.bearerScheme,
                                fun (options : JwtBearerOptions) ->
                                    options.Configuration <- providerConfig
                            )
                            |> ignore)
                        .Configure(fun app ->
                            app
                                .UseRouting()
                                .UseAuthentication()
                                .UseAuthorization()
                                .UseOxpecker(
                                    [
                                        GET [ route "/protected" (text "ok") ]
                                        |> Auth.authenticated
                                    ]
                                )
                            |> ignore)
                    |> ignore)
                .Build()

        host.StartAsync().GetAwaiter().GetResult()
        host

    let private getWithBearer (host : IHost) =
        use client = host.GetTestClient ()
        use request = new HttpRequestMessage (HttpMethod.Get, "/protected")

        request.Headers.Authorization <-
            AuthenticationHeaderValue ("Bearer", token)

        client.SendAsync(request).GetAwaiter().GetResult().StatusCode

    [<Tests>]
    let tests =
        testList "Auth schemes" [
            testCase "outside Development a bearer token is not accepted"
            <| fun () ->
                use host = createHost false

                Expect.equal
                    (getWithBearer host)
                    HttpStatusCode.Unauthorized
                    "a valid token without a session cookie"

            testCase "in Development a bearer token is accepted"
            <| fun () ->
                use host = createHost true

                Expect.equal
                    (getWithBearer host)
                    HttpStatusCode.OK
                    "the Scalar docs authenticate with a token"
        ]
