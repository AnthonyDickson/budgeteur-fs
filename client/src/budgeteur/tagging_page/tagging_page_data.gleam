import budgeteur/tag.{type Tag}
import budgeteur/tagging_page/rule.{type Rule}
import gleam/dynamic/decode

/// The tagging page's tags and rules, as `GET /api/tagging` returns them.
pub type TaggingPageData {
  TaggingPageData(tags: List(Tag), rules: List(Rule))
}

pub fn data_decoder() -> decode.Decoder(TaggingPageData) {
  use tags <- decode.field("tags", decode.list(tag.tag_decoder()))
  use rules <- decode.field("rules", decode.list(rule.rule_decoder()))
  decode.success(TaggingPageData(tags:, rules:))
}
