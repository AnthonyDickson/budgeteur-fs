//// The statement import dialog: choose CSV files, read them, send them. A
//// state machine held in the page model; the page turns its commands into
//// effects. See decisions 10 and 13 in docs/csv-import.md.

import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/ui/dialog
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

/// The id of the dialog's file input, which the file-reading effect reads.
pub const file_input_id = "import-files"

/// An import may carry a year of statements, so it gets longer than a form
/// save.
pub const import_timeout_ms = 60_000

pub type State {
  Hidden
  /// The dialog is open. `errors` are the problems the last attempt
  /// reported, so the user can fix the files and retry.
  Choosing(file_count: Int, errors: List(String))
  /// The browser is reading the chosen files.
  Reading(file_count: Int)
  /// The import request is in flight; the dialog is locked.
  Importing(file_count: Int)
}

/// A file's name and UTF-8 text, as the import request carries it.
pub type ImportFile {
  ImportFile(name: String, content: String)
}

/// What the server did with the statements.
pub type ImportResult {
  ImportResult(
    imported: Int,
    skipped_duplicates: Int,
    transfers: Int,
    tagged_by_rules: Int,
    accounts_created: List(String),
  )
}

/// What the page must do for the dialog.
pub type Command {
  /// Read the files chosen in the file input.
  ReadFiles
  /// Send the files' text to the import endpoint.
  Upload(files: List(ImportFile))
}

pub type Outcome {
  NoChange
  Imported(ImportResult)
}

pub type Msg {
  OpenRequested
  // The file input changed; only the count is kept, since the files stay in
  // the input until they are read.
  FilesChosen(count: Int)
  SubmitRequested
  FilesRead(Result(List(#(String, String)), String))
  ImportCompleted(Result(ImportResult, ApiError))
  // Cancel button, or the browser dismissed the dialog (Esc / outside click)
  CancelRequested
}

pub fn update(state: State, msg: Msg) -> #(State, Option(Command), Outcome) {
  case msg, state {
    OpenRequested, Hidden | OpenRequested, Choosing(..) -> #(
      Choosing(file_count: 0, errors: []),
      None,
      NoChange,
    )
    FilesChosen(count:), Choosing(..) -> #(
      Choosing(file_count: count, errors: []),
      None,
      NoChange,
    )
    SubmitRequested, Choosing(file_count:, ..) if file_count > 0 -> #(
      Reading(file_count:),
      Some(ReadFiles),
      NoChange,
    )
    FilesRead(Ok(files)), Reading(file_count:) -> #(
      Importing(file_count:),
      Some(
        Upload(
          list.map(files, fn(file) {
            let #(name, content) = file
            ImportFile(name:, content:)
          }),
        ),
      ),
      NoChange,
    )
    FilesRead(Error(reason)), Reading(file_count:) -> #(
      Choosing(file_count:, errors: [reason]),
      None,
      NoChange,
    )
    ImportCompleted(Ok(result)), Importing(..) -> #(
      Hidden,
      None,
      Imported(result),
    )
    ImportCompleted(Error(error)), Importing(file_count:) -> #(
      Choosing(file_count:, errors: errors(error)),
      None,
      NoChange,
    )
    CancelRequested, Choosing(..) -> #(Hidden, None, NoChange)
    // Anything else is stale: a response for a dialog that has moved on, or a
    // message that does not apply in this state.
    _, _ -> #(state, None, NoChange)
  }
}

/// A validation failure lists one problem per line, each naming its file and
/// line; anything else is one problem.
fn errors(error: ApiError) -> List(String) {
  case error.status_code {
    Some(400) ->
      error.details
      |> string.split("\n")
      |> list.fold([], fn(problems, line) {
        // A line that starts with a space continues the problem above it,
        // e.g. the headers listed for a file in no known format.
        case problems, string.starts_with(line, " ") {
          [previous, ..rest], True -> [previous <> "\n" <> line, ..rest]
          _, _ -> [line, ..problems]
        }
      })
      |> list.reverse
    _ -> [api_error.describe(error)]
  }
}

pub fn request_json(files: List(ImportFile)) -> json.Json {
  json.object([
    #(
      "files",
      json.array(files, fn(file) {
        json.object([
          #("name", json.string(file.name)),
          #("content", json.string(file.content)),
        ])
      }),
    ),
  ])
}

pub fn result_decoder() -> decode.Decoder(ImportResult) {
  use imported <- decode.field("imported", decode.int)
  use skipped_duplicates <- decode.field("skippedDuplicates", decode.int)
  use transfers <- decode.field("transfers", decode.int)
  use tagged_by_rules <- decode.field("taggedByRules", decode.int)
  use accounts_created <- decode.field(
    "accountsCreated",
    decode.list(decode.at(["name"], decode.string)),
  )
  decode.success(ImportResult(
    imported:,
    skipped_duplicates:,
    transfers:,
    tagged_by_rules:,
    accounts_created:,
  ))
}

/// The toast body for a finished import: the counts, and the accounts it
/// created so a holding entered twice can be spotted.
pub fn describe(result: ImportResult) -> String {
  let plural = fn(count, noun) {
    int.to_string(count)
    <> " "
    <> noun
    <> case count {
      1 -> ""
      _ -> "s"
    }
  }

  let counts =
    "Imported "
    <> plural(result.imported, "transaction")
    <> " ("
    <> plural(result.transfers, "transfer")
    <> ", "
    <> int.to_string(result.tagged_by_rules)
    <> " tagged by rules). Skipped "
    <> int.to_string(result.skipped_duplicates)
    <> " already imported."

  case result.accounts_created {
    [] -> counts
    names -> counts <> " Created accounts: " <> string.join(names, ", ") <> "."
  }
}

// View

pub fn view(state: State) -> Element(Msg) {
  case state {
    Hidden -> element.none()
    Choosing(file_count:, errors:) -> dialog(file_count:, errors:, busy: False)
    Reading(file_count:) | Importing(file_count:) ->
      dialog(file_count:, errors: [], busy: True)
  }
}

fn dialog(
  file_count file_count: Int,
  errors errors: List(String),
  busy busy: Bool,
) -> Element(Msg) {
  dialog.dialog(
    testid: "import-modal",
    busy:,
    on_dismiss: CancelRequested,
    children: [
      html.h2([attribute.class("mb-2 text-lg font-semibold text-gray-900")], [
        html.text("Import statements"),
      ]),
      html.p([attribute.class("mb-4 text-sm text-gray-500")], [
        html.text(
          "Choose CSV exports from Kiwibank or ASB credit cards. Transactions already imported are skipped, and accounts are created for new account numbers.",
        ),
      ]),
      html.form(
        [
          event.on_submit(fn(_) { SubmitRequested }),
          attribute.class("space-y-4"),
        ],
        [
          case errors {
            [] -> element.none()
            _ ->
              html.div(
                [
                  attribute.class(
                    "max-h-64 overflow-y-auto rounded-md border border-red-200 bg-red-50 px-3 py-2",
                  ),
                  attribute.attribute("data-testid", "import-errors"),
                ],
                [
                  html.p([attribute.class("text-sm font-medium text-red-800")], [
                    html.text("Nothing was imported. Fix these and try again:"),
                  ]),
                  html.ul(
                    [
                      attribute.class(
                        "mt-1 list-disc space-y-1 pl-5 text-sm text-red-700",
                      ),
                    ],
                    list.map(errors, fn(error) {
                      html.li([attribute.class("whitespace-pre-wrap")], [
                        html.text(error),
                      ])
                    }),
                  ),
                ],
              )
          },
          html.input([
            attribute.type_("file"),
            attribute.id(file_input_id),
            attribute.attribute("data-testid", "import-file-input"),
            attribute.accept([".csv", "text/csv"]),
            attribute.multiple(True),
            attribute.disabled(busy),
            attribute.class(
              "block w-full text-sm text-gray-700 file:mr-3 file:rounded-md file:border-0 "
              <> "file:bg-indigo-50 file:px-3 file:py-2 file:text-sm file:font-medium file:text-indigo-700 "
              <> "hover:file:bg-indigo-100",
            ),
            event.on(
              "change",
              decode.at(["target", "files", "length"], decode.int)
                |> decode.map(FilesChosen),
            ),
          ]),
          html.div([attribute.class("flex justify-end gap-3 pt-2")], [
            dialog.cancel_button(
              testid: "import-cancel-button",
              disabled: busy,
              on_click: CancelRequested,
            ),
            dialog.submit_button(
              testid: "import-submit-button",
              idle_label: "Import",
              busy_label: "Importing...",
              busy:,
              disabled: file_count == 0,
            ),
          ]),
        ],
      ),
    ],
  )
}
