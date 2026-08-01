# JSON Serialization

## Timestamp encoding

`DateTime` fields are encoded as UNIX epoch seconds in JSON. Several
approaches were evaluated:

| Approach                     | JSON output             | Issue                     |
| ---------------------------- | ----------------------- | ------------------------- |
| `int64 \|> Encode.int64`     | `"1784706894"` (string) | Not a JSON number         |
| `decimal \|> Encode.decimal` | `"1784706894"` (string) | Thoth preserves precision |
| `int \|> Encode.int`         | `1784706894`            | Y2038 overflow (32-bit)   |
| **`float \|> Encode.float`** | **`1784706894.0`**      | **Chosen**                |

### Final choice: `float` encoder, tolerant decoder

The encoder (`Coders.fs:Extra.epoch`) writes `float` — the `.0` suffix is
cosmetic. JavaScript and every JSON parser treat `1784706894.0` identically to
`1784706894`. Float precision (53 bits) is safe until ~285,000 AD.

The decoder tries `int64` first, then falls back to `float` → `int64`. This
means historical data with either format deserializes correctly.
