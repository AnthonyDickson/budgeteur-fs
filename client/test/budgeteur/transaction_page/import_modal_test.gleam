import budgeteur/shared/api_error.{ApiError}
import budgeteur/transaction_page/import_modal.{
  Choosing, Hidden, ImportFile, Importing, NoChange, ReadFiles, Reading, Upload,
}
import gleam/option.{None, Some}
import gleeunit/should

fn opened() -> import_modal.State {
  let #(state, _, _) =
    import_modal.update(import_modal.Hidden, import_modal.OpenRequested)
  state
}

fn importing() -> import_modal.State {
  let #(state, _, _) =
    import_modal.update(opened(), import_modal.FilesChosen(1))
  let #(state, _, _) = import_modal.update(state, import_modal.SubmitRequested)
  let #(state, _, _) =
    import_modal.update(state, import_modal.FilesRead(Ok([#("a.csv", "x")])))
  state
}

pub fn submitting_needs_a_file_test() {
  import_modal.update(opened(), import_modal.SubmitRequested)
  |> should.equal(#(Choosing(file_count: 0, errors: []), None, NoChange))
}

pub fn the_files_are_read_then_uploaded_test() {
  let #(state, _, _) =
    import_modal.update(opened(), import_modal.FilesChosen(2))

  let #(state, command, _) =
    import_modal.update(state, import_modal.SubmitRequested)
  state |> should.equal(Reading(file_count: 2))
  command |> should.equal(Some(ReadFiles))

  let #(state, command, _) =
    import_modal.update(
      state,
      import_modal.FilesRead(Ok([#("a.csv", "x"), #("b.csv", "y")])),
    )
  state |> should.equal(Importing(file_count: 2))
  command
  |> should.equal(
    Some(Upload([ImportFile("a.csv", "x"), ImportFile("b.csv", "y")])),
  )
}

pub fn every_listed_problem_is_shown_for_a_retry_test() {
  let error =
    ApiError(
      error: "Validation Error",
      details: "a.csv line 3: Amount \"ten\" is not an amount\n"
        <> "b.csv: matches no known format.\n"
        <> "  The file starts with:\n"
        <> "    hello",
      status_code: Some(400),
      request_id: None,
    )

  let #(state, command, outcome) =
    import_modal.update(importing(), import_modal.ImportCompleted(Error(error)))

  // A continuation line stays with the problem it belongs to.
  state
  |> should.equal(
    Choosing(file_count: 1, errors: [
      "a.csv line 3: Amount \"ten\" is not an amount",
      "b.csv: matches no known format.\n  The file starts with:\n    hello",
    ]),
  )
  command |> should.equal(None)
  outcome |> should.equal(NoChange)

  // The files are still chosen, so the user can fix them and retry.
  let #(_, retry, _) = import_modal.update(state, import_modal.SubmitRequested)
  retry |> should.equal(Some(ReadFiles))
}

pub fn a_stale_response_does_not_reopen_the_dialog_test() {
  let #(state, _, _) =
    import_modal.update(opened(), import_modal.CancelRequested)
  state |> should.equal(Hidden)

  import_modal.update(state, import_modal.FilesRead(Ok([#("a.csv", "x")])))
  |> should.equal(#(Hidden, None, NoChange))
}
