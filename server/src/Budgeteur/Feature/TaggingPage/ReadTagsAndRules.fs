namespace Budgeteur.Feature.TaggingPage

open System

type TagDto = {
    Id : Guid
    Name : string
    Color : string
}

module TagDto =
    open Budgeteur.Domain.Tag

    let fromDomain (tag : Tag) : TagDto = {
        Id = tag.Id
        Name = TagName.value tag.Name
        Color = TagColor.value tag.Color
    }

type RuleDto = {
    Id : Guid
    Pattern : string
    TagId : Guid
}

module RuleDto =
    open Budgeteur.Domain.Rule

    let fromDomain (rule : Rule) : RuleDto = {
        Id = rule.Id
        Pattern = RulePattern.value rule.Pattern
        TagId = rule.TagId
    }

type TagsAndRulesResponse = {
    Tags : TagDto list
    Rules : RuleDto list
}

module ReadTagsAndRules =
    open System.Collections.Generic
    open System.Threading.Tasks

    open FsToolkit.ErrorHandling
    open Microsoft.OpenApi
    open Oxpecker
    open Oxpecker.OpenApi
    open SqlHydra.Query

    open Budgeteur.Data
    open Budgeteur.Data.Db
    open Budgeteur.Shared.ApiError
    open Budgeteur.Shared.Auth
    open Budgeteur.Shared.Endpoint
    open Budgeteur.Shared.Json
    open Budgeteur.Shared.RequestLogging

    [<Literal>]
    let Path = "/api/tags-and-rules"

    let private getTags (queryContext : QueryContextFactory) (userId : string) =
        task {
            let! rows =
                selectTask queryContext {
                    for t in main.Tags do
                        select t
                        where (t.UserId = userId)
                }

            let tags = rows |> List.ofSeq |> List.map TagCodec.fromRow

            return tags
        }

    let private getRules (queryContext : QueryContextFactory) (userId : string) =
        task {
            let! rows =
                selectTask queryContext {
                    for r in main.Rules do
                        select r
                        where (r.UserId = userId)
                }

            let rules = rows |> List.ofSeq |> List.map RuleCodec.fromRow

            return rules
        }

    let private handler (queryContext : QueryContextFactory) : EndpointHandler =
        Endpoint.handler (fun ctx ->
            taskResult {
                let! userId = Auth.getUserId ctx
                let! tags = getTags queryContext userId
                and! rules = getRules queryContext userId

                let log = RequestLog.fromContext ctx
                log.Info ($"Returned %i{List.length tags} tags", LogProp.prop "count" (List.length tags))
                log.Info ($"Returned %i{List.length rules} rules", LogProp.prop "count" (List.length rules))

                let response = {
                    Tags = List.map TagDto.fromDomain tags
                    Rules = List.map RuleDto.fromDomain rules
                }

                do! Json.write ctx response
            })

    let endpoint (queryContext : QueryContextFactory) =
        route Path (handler queryContext)
        |> addOpenApi (
            OpenApiConfig (
                responseBodies = [|
                    ResponseBody typeof<TagsAndRulesResponse>
                    ResponseBody (typeof<ApiError>, statusCode = 401)
                |],
                configureOperation =
                    fun op _ _ ->
                        op.Summary <- "List all tags and rules"
                        op.Description <- "Returns all of the user's tags and rules."
                        op.Tags <- HashSet [ OpenApiTagReference "Tagging Page" ]
                        Task.CompletedTask
            )
        )
