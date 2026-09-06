import budgeteur/tagging_page/rule/rule.{type Rule}
import budgeteur/tagging_page/tag/tag.{type Tag}
import gleam/dynamic/decode
import gleam/json

/// localStorage key for the whole tagging payload.
pub const storage_key = "budgeteur.tags"

pub type TaggingPageData {
  TaggingPageData(tags: List(Tag), rules: List(Rule))
}

pub fn data_decoder() -> decode.Decoder(TaggingPageData) {
  use tags <- decode.field("tags", decode.list(tag.tag_decoder()))
  use rules <- decode.field("rules", decode.list(rule.rule_decoder()))
  decode.success(TaggingPageData(tags:, rules:))
}

pub fn data_to_json(data: TaggingPageData) -> json.Json {
  json.object([
    #("tags", json.array(data.tags, tag.tag_to_json)),
    #("rules", json.array(data.rules, rule.rule_to_json)),
  ])
}

pub fn data_to_string(data: TaggingPageData) -> String {
  data_to_json(data) |> json.to_string
}
