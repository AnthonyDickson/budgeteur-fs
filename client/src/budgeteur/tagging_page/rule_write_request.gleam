import budgeteur/tagging_page/rule.{type Target}
import gleam/dynamic/decode
import gleam/json

/// Full-replacement (PUT) payload for a rule: pattern + target, shared by
/// create and update. The server generates the id and derives the user id
/// from auth.
pub type RuleWriteRequest {
  RuleWriteRequest(pattern: String, target: Target)
}

pub fn to_json(rule_write_request: RuleWriteRequest) -> json.Json {
  let RuleWriteRequest(pattern:, target:) = rule_write_request
  json.object([#("pattern", json.string(pattern)), ..rule.target_fields(target)])
}

pub fn decoder() -> decode.Decoder(RuleWriteRequest) {
  use pattern <- decode.field("pattern", decode.string)
  use target <- decode.then(rule.target_decoder())
  decode.success(RuleWriteRequest(pattern:, target:))
}
