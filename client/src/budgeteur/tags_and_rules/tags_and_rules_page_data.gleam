import budgeteur/tags_and_rules/rule/rule.{type Rule}
import budgeteur/tags_and_rules/tag/tag.{type Tag}
import gleam/dynamic/decode
import gleam/json

/// localStorage key for the whole tags-and-rules payload.
pub const storage_key = "budgeteur.tags"

pub type TagsAndRulesPageData {
  TagsAndRulesPageData(tags: List(Tag), rules: List(Rule))
}

pub fn data_decoder() -> decode.Decoder(TagsAndRulesPageData) {
  use tags <- decode.field("tags", decode.list(tag.tag_decoder()))
  use rules <- decode.field("rules", decode.list(rule.rule_decoder()))
  decode.success(TagsAndRulesPageData(tags:, rules:))
}

pub fn data_to_json(data: TagsAndRulesPageData) -> json.Json {
  json.object([
    #("tags", json.array(data.tags, tag.tag_to_json)),
    #("rules", json.array(data.rules, rule.rule_to_json)),
  ])
}

pub fn data_to_string(data: TagsAndRulesPageData) -> String {
  data_to_json(data) |> json.to_string
}
