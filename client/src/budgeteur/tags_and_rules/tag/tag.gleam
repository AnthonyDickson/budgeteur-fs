import budgeteur/shared/uuid as uuid_codec
import gleam/dynamic/decode
import gleam/json
import youid/uuid.{type Uuid}

pub type Tag {
  Tag(
    // Unique identifier for the tag.
    id: Uuid,
    // Display name of the tag.
    name: String,
    // Hex color used for the tag's swatch, e.g. "#6366F1".
    color: String,
  )
}

pub fn tag_decoder() -> decode.Decoder(Tag) {
  use id <- decode.field("id", uuid_codec.decoder())
  use name <- decode.field("name", decode.string)
  use color <- decode.field("color", decode.string)
  decode.success(Tag(id:, name:, color:))
}

pub fn tag_to_json(tag: Tag) -> json.Json {
  let Tag(id:, name:, color:) = tag
  json.object([
    #("id", json.string(uuid.to_string(id))),
    #("name", json.string(name)),
    #("color", json.string(color)),
  ])
}
