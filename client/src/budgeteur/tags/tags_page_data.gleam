import budgeteur/tags/rule/rule.{type Rule}
import budgeteur/tags/tag/tag.{type Tag}
import gleam/dynamic/decode
import gleam/json

/// The payload persisted to localStorage and the future `GET /api/tags`
/// response. Mirroring the endpoint's shape now means the backend can drop in
/// later without reshaping the page.
pub type TagsPageData {
  TagsPageData(tags: List(Tag), rules: List(Rule))
}

/// localStorage key for the whole tags-and-rules payload.
pub const storage_key = "budgeteur.tags"

pub fn data_decoder() -> decode.Decoder(TagsPageData) {
  use tags <- decode.field("tags", decode.list(tag.tag_decoder()))
  use rules <- decode.field("rules", decode.list(rule.rule_decoder()))
  decode.success(TagsPageData(tags:, rules:))
}

pub fn data_to_json(data: TagsPageData) -> json.Json {
  json.object([
    #("tags", json.array(data.tags, tag.tag_to_json)),
    #("rules", json.array(data.rules, rule.rule_to_json)),
  ])
}

pub fn data_to_string(data: TagsPageData) -> String {
  data_to_json(data) |> json.to_string
}
