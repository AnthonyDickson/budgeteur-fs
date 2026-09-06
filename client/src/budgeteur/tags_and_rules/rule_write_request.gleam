import budgeteur/shared/uuid as uuid_codec
import gleam/dynamic/decode
import gleam/json
import youid/uuid.{type Uuid}

/// Full-replacement (PUT) payload for a rule: pattern + tag id, shared by
/// create and update. The server generates the id and derives the user id
/// from auth.
pub type RuleWriteRequest {
  RuleWriteRequest(pattern: String, tag_id: Uuid)
}

pub fn to_json(rule_write_request: RuleWriteRequest) -> json.Json {
  let RuleWriteRequest(pattern:, tag_id:) = rule_write_request
  json.object([
    #("pattern", json.string(pattern)),
    #("tagId", json.string(uuid.to_string(tag_id))),
  ])
}

pub fn decoder() -> decode.Decoder(RuleWriteRequest) {
  use pattern <- decode.field("pattern", decode.string)
  use tag_id <- decode.field("tagId", uuid_codec.decoder())
  decode.success(RuleWriteRequest(pattern:, tag_id:))
}
