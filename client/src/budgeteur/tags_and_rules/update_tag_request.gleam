import gleam/dynamic/decode
import gleam/json

pub type UpdateTagRequest {
  UpdateTagRequest(name: String, color: String)
}

pub fn update_tag_request_to_json(
  update_tag_request: UpdateTagRequest,
) -> json.Json {
  let UpdateTagRequest(name:, color:) = update_tag_request
  json.object([
    #("name", json.string(name)),
    #("color", json.string(color)),
  ])
}

pub fn update_tag_request_decoder() -> decode.Decoder(UpdateTagRequest) {
  use name <- decode.field("name", decode.string)
  use color <- decode.field("color", decode.string)
  decode.success(UpdateTagRequest(name:, color:))
}
