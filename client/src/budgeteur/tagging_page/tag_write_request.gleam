import budgeteur/tag.{type TagKind}
import gleam/dynamic/decode
import gleam/json

/// Full-replacement (PUT) payload for a tag: name, color, and kind, shared by
/// create and update. The server generates the id and derives the user id from
/// auth.
pub type TagWriteRequest {
  TagWriteRequest(name: String, color: String, kind: TagKind)
}

pub fn to_json(tag_write_request: TagWriteRequest) -> json.Json {
  let TagWriteRequest(name:, color:, kind:) = tag_write_request
  json.object([
    #("name", json.string(name)),
    #("color", json.string(color)),
    #("kind", tag.kind_to_json(kind)),
  ])
}

pub fn decoder() -> decode.Decoder(TagWriteRequest) {
  use name <- decode.field("name", decode.string)
  use color <- decode.field("color", decode.string)
  use kind <- decode.field("kind", tag.kind_decoder())
  decode.success(TagWriteRequest(name:, color:, kind:))
}
