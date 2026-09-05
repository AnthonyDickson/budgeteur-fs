import gleam/dynamic/decode
import gleam/json

/// Full-replacement (PUT) payload for a tag: name + color, shared by create
/// and update. The server generates the id and derives the user id from auth.
pub type TagWriteRequest {
  TagWriteRequest(name: String, color: String)
}

pub fn tag_write_request_to_json(
  tag_write_request: TagWriteRequest,
) -> json.Json {
  let TagWriteRequest(name:, color:) = tag_write_request
  json.object([
    #("name", json.string(name)),
    #("color", json.string(color)),
  ])
}

pub fn tag_write_request_decoder() -> decode.Decoder(TagWriteRequest) {
  use name <- decode.field("name", decode.string)
  use color <- decode.field("color", decode.string)
  decode.success(TagWriteRequest(name:, color:))
}
