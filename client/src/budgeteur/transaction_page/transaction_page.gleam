import budgeteur/shared/api_error.{type ApiError}
import budgeteur/shared/api_route
import budgeteur/shared/date
import budgeteur/shared/delete_modal
import budgeteur/shared/effect.{type Effect}
import budgeteur/shared/form_modal
import budgeteur/shared/money
import budgeteur/shared/out_msg.{type OutMsg}
import budgeteur/shared/remote.{type Remote, Failed, Loaded, Loading}
import budgeteur/shared/response
import budgeteur/shared/route
import budgeteur/shared/tag.{type Tag}
import budgeteur/shared/ui/button
import budgeteur/shared/ui/card
import budgeteur/shared/ui/input
import budgeteur/shared/ui/row
import budgeteur/shared/ui/swatch
import budgeteur/transaction_page/account.{type Account}
import budgeteur/transaction_page/import_modal
import budgeteur/transaction_page/transaction.{type Transaction}
import budgeteur/transaction_page/transaction_delete_modal.{
  type DeleteModalState,
}
import budgeteur/transaction_page/transaction_modal
import budgeteur/transaction_page/transaction_search.{
  type AccountFilter, type Criteria, type DatePreset, type Direction, type Page,
  type Search, type TagFilter,
}
import budgeteur/transaction_page/transaction_write_request
import gleam/dict
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import gleam/time/calendar.{type Date}
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import youid/uuid.{type Uuid}

pub type Model {
  Model(
    /// The client's date, which the server resolves date presets from. None
    /// until the browser reports it; no search runs before then.
    today: Option(Date),
    /// The criteria the page shows.
    search: Search,
    /// The last search's matches, with the user's changes applied.
    results: Remote(Results),
    /// Whether a search for the current criteria is in flight. The results
    /// shown stay until it returns.
    searching: Bool,
    /// Whether a "Load more" request is in flight.
    loading_more: Bool,
    /// Whether the filters panel is open.
    filters_open: Bool,
    /// Names the transactions' tags and fills the modal's tag select. Empty
    /// until loaded; if the fetch fails, transactions show without tag names.
    tags: List(Tag),
    /// Fills the modal's account select. Empty until loaded; if the fetch
    /// fails, the select offers no accounts.
    accounts: List(Account),
    modal: transaction_modal.Modal,
    delete_modal: DeleteModalState,
    import_modal: import_modal.State,
  )
}

/// The rows the page shows. See decisions 6 and 10 in
/// docs/transaction-search.md.
pub type Results {
  Results(
    /// The search the matches came from. "Load more" continues it.
    search: Search,
    /// The matches in the server's order, with the user's changes applied: a
    /// created transaction is added at the top, an updated one keeps its
    /// place even if it no longer matches, and a deleted one is removed.
    transactions: List(Transaction),
    /// Where the search's next page starts, or None on the last page.
    next: Option(String),
    /// The dates criterion's first day, with a preset resolved.
    from: Option(Date),
    /// The dates criterion's last day, with a preset resolved.
    to: Option(Date),
  )
}

pub type Msg {
  ClientGotToday(Date)
  UserChangedText(String)
  /// The search box went `search_delay_ms` without input.
  UserPausedTyping(String)
  UserClearedSearch
  UserToggledFilters
  UserChangedDatePreset(DatePreset)
  UserChangedFromDate(String)
  UserChangedToDate(String)
  UserChangedAccount(AccountFilter)
  UserChangedTag(TagFilter)
  UserChangedDirection(Direction)
  /// The minimum's input changed; the search runs when it is committed.
  UserChangedMinimum(String)
  UserChangedMaximum(String)
  /// The minimum or maximum was committed: the field lost focus or the user
  /// pressed Enter.
  UserCommittedSize
  /// The first page of a search's matches.
  ClientSearched(search: Search, result: Result(Page, ApiError))
  UserRequestedMore
  /// The page of a search's matches starting at the cursor.
  ClientFetchedMore(
    search: Search,
    cursor: String,
    result: Result(Page, ApiError),
  )
  ClientFetchedTags(Result(List(Tag), ApiError))
  ClientFetchedAccounts(Result(List(Account), ApiError))
  // Retry after a failed first load.
  UserRequestedReload
  // Modal messages
  UserRequestedCreationForm
  UserRequestedEditForm(Uuid)
  TransactionModalMsg(transaction_modal.Msg)
  // Delete modal messages. The transaction modal's `DeleteRequested` opens it.
  UserConfirmedDelete
  ServerDeletedTransaction(Transaction, Result(Nil, ApiError))
  UserCancelledDeleteModal
  // Import modal messages
  ImportModalMsg(import_modal.Msg)
}

fn fetch_tags() -> Effect(Msg) {
  effect.get(api_route.GetAllTags |> api_route.to_string, fn(result) {
    case result {
      Ok(body) ->
        ClientFetchedTags(response.decode_success(
          body,
          decode.list(tag.tag_decoder()),
        ))
      Error(http_error) ->
        ClientFetchedTags(Error(response.http_error_to_api_error(http_error)))
    }
  })
}

fn fetch_accounts() -> Effect(Msg) {
  effect.get(api_route.GetAllAccounts |> api_route.to_string, fn(result) {
    case result {
      Ok(body) ->
        ClientFetchedAccounts(response.decode_success(
          body,
          decode.list(account.decoder()),
        ))
      Error(http_error) ->
        ClientFetchedAccounts(
          Error(response.http_error_to_api_error(http_error)),
        )
    }
  })
}

/// Fetch the page of the criteria's matches starting at the cursor, or the
/// first page.
fn fetch_page(
  criteria: Criteria,
  today: Date,
  cursor: Option(String),
  to_msg: fn(Result(Page, ApiError)) -> Msg,
) -> Effect(Msg) {
  effect.post(
    api_route.SearchTransactions |> api_route.to_string,
    transaction_search.request_json(criteria, today, cursor) |> json.to_string,
    fn(result) {
      to_msg(case result {
        Ok(body) ->
          response.decode_success(body, transaction_search.page_decoder())
        Error(http_error) -> Error(response.http_error_to_api_error(http_error))
      })
    },
  )
}

/// How long typing pauses before the search box runs a search: the rule
/// modal's delay for counting a pattern's matches.
const search_delay_ms = 300

/// Run the page's search from the first page, once today is known. Invalid
/// input runs no search; its field shows the error.
fn run_search(model: Model) -> #(Model, Effect(Msg)) {
  case model.today, transaction_search.validate(model.search) {
    Some(today), Ok(criteria) -> #(
      Model(..model, searching: True),
      fetch_page(criteria, today, None, ClientSearched(model.search, _)),
    )
    _, _ -> #(Model(..model, searching: False), effect.none())
  }
}

/// Change the criteria and run the search.
fn change_search(
  model: Model,
  search: Search,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(model, effect) = run_search(Model(..model, search:))
  #(model, effect, None)
}

/// Searching waits for today, so the page asks for it first.
fn load() -> Effect(Msg) {
  effect.batch([
    effect.GetLocalDate(ClientGotToday),
    fetch_tags(),
    fetch_accounts(),
  ])
}

fn delete_transaction(transaction: Transaction) -> Effect(Msg) {
  effect.delete(
    api_route.DeleteTransaction(transaction.id) |> api_route.to_string,
    fn(result) {
      case result {
        // A successful delete returns 204 with no body, so there is nothing
        // to decode.
        Ok(_) -> ServerDeletedTransaction(transaction, Ok(Nil))
        Error(http_error) ->
          ServerDeletedTransaction(
            transaction,
            Error(response.http_error_to_api_error(http_error)),
          )
      }
    },
  )
  |> effect.with_timeout(delete_modal.delete_timeout_ms)
}

fn sort_tags(tags: List(Tag)) -> List(Tag) {
  list.sort(tags, by: fn(a, b) { string.compare(a.name, b.name) })
}

/// The transactions the page shows, or none until a search has loaded.
fn shown(model: Model) -> List(Transaction) {
  case model.results {
    Loaded(results) -> results.transactions
    Loading | Failed -> []
  }
}

/// Apply a change to the transactions the page shows.
fn map_shown(
  model: Model,
  f: fn(List(Transaction)) -> List(Transaction),
) -> Model {
  Model(
    ..model,
    results: remote.map(model.results, fn(results) {
      Results(..results, transactions: f(results.transactions))
    }),
  )
}

/// Append a later page, skipping transactions already shown: a created or
/// updated transaction can also be on a later page.
fn append_unshown(
  shown: List(Transaction),
  more: List(Transaction),
) -> List(Transaction) {
  let shown_ids = shown |> list.map(fn(t) { t.id }) |> set.from_list
  list.append(
    shown,
    list.filter(more, fn(t) { !set.contains(shown_ids, t.id) }),
  )
}

pub fn init() -> #(Model, Effect(Msg)) {
  #(
    Model(
      today: None,
      search: transaction_search.new(),
      results: Loading,
      searching: False,
      loading_more: False,
      filters_open: False,
      tags: [],
      accounts: [],
      modal: transaction_modal.hidden(),
      delete_modal: transaction_delete_modal.empty(),
      import_modal: import_modal.Hidden,
    ),
    load(),
  )
}

pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg), Option(OutMsg)) {
  case msg {
    // Returning to the page asks for today again, which runs the page's
    // search again.
    ClientGotToday(today) -> {
      let #(model, effect) = run_search(Model(..model, today: Some(today)))
      #(model, effect, None)
    }

    // The text is kept as typed; the search runs once typing pauses.
    UserChangedText(text) -> #(
      Model(..model, search: transaction_search.Search(..model.search, text:)),
      effect.none(),
      None,
    )

    UserPausedTyping(text) if text == model.search.text -> {
      let #(model, effect) = run_search(model)
      #(model, effect, None)
    }

    // A pause from before the box was cleared.
    UserPausedTyping(_) -> #(model, effect.none(), None)

    UserClearedSearch -> change_search(model, transaction_search.new())

    UserToggledFilters -> #(
      Model(..model, filters_open: !model.filters_open),
      effect.none(),
      None,
    )

    UserChangedDatePreset(preset) ->
      change_search(model, transaction_search.Search(..model.search, preset:))

    UserChangedFromDate(from) ->
      change_search(model, transaction_search.Search(..model.search, from:))

    UserChangedToDate(to) ->
      change_search(model, transaction_search.Search(..model.search, to:))

    UserChangedAccount(account) ->
      change_search(model, transaction_search.Search(..model.search, account:))

    UserChangedTag(tag) ->
      change_search(model, transaction_search.Search(..model.search, tag:))

    UserChangedDirection(direction) ->
      change_search(
        model,
        transaction_search.Search(..model.search, direction:),
      )

    UserChangedMinimum(minimum) -> #(
      Model(
        ..model,
        search: transaction_search.Search(
          ..model.search,
          minimum: money.clip_to_two_dp(minimum),
        ),
      ),
      effect.none(),
      None,
    )

    UserChangedMaximum(maximum) -> #(
      Model(
        ..model,
        search: transaction_search.Search(
          ..model.search,
          maximum: money.clip_to_two_dp(maximum),
        ),
      ),
      effect.none(),
      None,
    )

    UserCommittedSize -> change_search(model, model.search)

    // A response for criteria other than the current ones is ignored, so a
    // slow response never replaces a newer one.
    ClientSearched(search:, result: _) if search != model.search -> #(
      model,
      effect.none(),
      None,
    )

    ClientSearched(search:, result: Ok(page)) -> #(
      Model(
        ..model,
        results: Loaded(Results(
          search:,
          transactions: page.transactions,
          next: page.next,
          from: page.from,
          to: page.to,
        )),
        searching: False,
        // A "Load more" in flight continues the replaced results.
        loading_more: False,
      ),
      effect.none(),
      None,
    )

    ClientSearched(search: _, result: Error(error)) ->
      case model.results {
        // The results shown are still the latest the page has.
        Loaded(_) -> #(
          Model(..model, searching: False),
          effect.LogError(api_error.describe(error)),
          Some(out_msg.error_toast(
            "Could not search transactions",
            "Showing the transactions loaded earlier",
          )),
        )
        Loading | Failed -> #(
          Model(..model, results: Failed, searching: False),
          effect.LogError(api_error.describe(error)),
          None,
        )
      }

    UserRequestedMore ->
      case model.results, model.today, model.loading_more {
        Loaded(Results(search:, next: Some(cursor), ..)), Some(today), False ->
          // The results' search was valid when it was sent.
          case transaction_search.validate(search) {
            Ok(criteria) -> #(
              Model(..model, loading_more: True),
              fetch_page(criteria, today, Some(cursor), ClientFetchedMore(
                search,
                cursor,
                _,
              )),
              None,
            )
            Error(_) -> #(model, effect.none(), None)
          }
        _, _, _ -> #(model, effect.none(), None)
      }

    ClientFetchedMore(search:, cursor:, result:) ->
      case model.results {
        // Only the page after the results shown is appended; a search since
        // replaced them.
        Loaded(results)
          if results.search == search && results.next == Some(cursor)
        ->
          case result {
            Ok(page) -> #(
              Model(
                ..model,
                results: Loaded(
                  Results(
                    ..results,
                    transactions: append_unshown(
                      results.transactions,
                      page.transactions,
                    ),
                    next: page.next,
                  ),
                ),
                loading_more: False,
              ),
              effect.none(),
              None,
            )
            Error(error) -> #(
              Model(..model, loading_more: False),
              effect.LogError(api_error.describe(error)),
              Some(out_msg.error_toast(
                "Could not load more transactions",
                "Showing the transactions loaded so far",
              )),
            )
          }
        _ -> #(model, effect.none(), None)
      }

    ClientFetchedTags(Ok(tags)) -> #(
      Model(..model, tags: sort_tags(tags)),
      effect.none(),
      None,
    )

    ClientFetchedTags(Error(error)) -> #(
      model,
      effect.LogError(api_error.describe(error)),
      Some(out_msg.error_toast(
        "Could not load tags",
        "Transactions are shown without tag names",
      )),
    )

    ClientFetchedAccounts(Ok(accounts)) -> #(
      Model(..model, accounts:),
      effect.none(),
      None,
    )

    ClientFetchedAccounts(Error(error)) -> #(
      model,
      effect.LogError(api_error.describe(error)),
      Some(out_msg.error_toast(
        "Could not load accounts",
        "The transaction form offers no accounts",
      )),
    )

    UserRequestedReload -> #(Model(..model, results: Loading), load(), None)

    UserRequestedCreationForm ->
      run_transaction_modal(model, transaction_modal.CreateRequested)

    UserRequestedEditForm(id) -> {
      case list.find(shown(model), fn(t) { t.id == id }) {
        Ok(transaction) ->
          run_transaction_modal(
            model,
            transaction_modal.EditRequested(transaction),
          )
        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    TransactionModalMsg(transaction_modal.DeleteRequested as msg) ->
      open_delete(model) |> run_transaction_modal(msg)

    TransactionModalMsg(msg) -> run_transaction_modal(model, msg)

    UserConfirmedDelete -> {
      case delete_modal.confirm(model.delete_modal) {
        Ok(#(state, transaction)) -> #(
          Model(..model, delete_modal: state),
          delete_transaction(transaction),
          None,
        )
        Error(Nil) -> #(model, effect.none(), None)
      }
    }

    ServerDeletedTransaction(transaction, Ok(_)) ->
      on_delete_succeeded(model, transaction)

    ServerDeletedTransaction(transaction, Error(error)) -> {
      case api_error.is_not_found(error) {
        True -> on_delete_succeeded(model, transaction)
        False -> on_delete_failed(model, error)
      }
    }

    UserCancelledDeleteModal -> #(
      Model(..model, delete_modal: transaction_delete_modal.empty()),
      effect.none(),
      None,
    )

    ImportModalMsg(msg) -> run_import_modal(model, msg)
  }
}

/// Open the delete confirmation for the transaction being edited. The
/// transaction modal closes itself on the same message.
fn open_delete(model: Model) -> Model {
  let transaction = case form_modal.mode(model.modal) {
    Some(form_modal.Edit(id:)) ->
      shown(model) |> list.find(fn(t) { t.id == id })
    Some(form_modal.Create) | None -> Error(Nil)
  }
  case transaction {
    Ok(transaction) ->
      Model(..model, delete_modal: transaction_delete_modal.open(transaction))
    Error(Nil) -> model
  }
}

fn run_import_modal(
  model: Model,
  msg: import_modal.Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(import_modal, command, outcome) =
    import_modal.update(model.import_modal, msg)
  let model = Model(..model, import_modal:)
  // The import added transactions the user has not seen and maybe accounts,
  // so the search runs again and the accounts are fetched again.
  let #(model, imported) = case outcome {
    import_modal.NoChange -> #(model, [])
    import_modal.Imported(_) -> {
      let #(model, search_effect) = run_search(model)
      #(model, [search_effect, fetch_accounts()])
    }
  }
  let effects = case command {
    Some(import_modal.ReadFiles) -> [
      effect.ReadFiles(import_modal.file_input_id, fn(result) {
        ImportModalMsg(import_modal.FilesRead(result))
      }),
    ]
    Some(import_modal.Upload(files)) -> [
      effect.post(
        api_route.ImportStatements |> api_route.to_string,
        import_modal.request_json(files) |> json.to_string,
        fn(result) {
          ImportModalMsg(
            import_modal.ImportCompleted(case result {
              Ok(body) ->
                response.decode_success(body, import_modal.result_decoder())
              Error(http_error) ->
                Error(response.http_error_to_api_error(http_error))
            }),
          )
        },
      )
      |> effect.with_timeout(import_modal.import_timeout_ms),
    ]
    None -> []
  }
  let effects = case msg {
    import_modal.ImportCompleted(Error(error)) -> [
      effect.LogError(api_error.describe(error)),
      ..effects
    ]
    _ -> effects
  }
  let #(effects, out_msg) = case outcome {
    import_modal.NoChange -> #(effects, None)
    import_modal.Imported(result) -> #(
      list.append(effects, imported),
      // The counts and created accounts take a while to read, so the toast
      // stays until dismissed.
      Some(
        out_msg.PageRequestedToast(
          ..out_msg.success_toast(import_modal.describe(result)),
          dismiss_after_ms: None,
        ),
      ),
    )
  }
  let effect = case effects {
    [] -> effect.none()
    [effect] -> effect
    _ -> effect.batch(effects)
  }
  #(model, effect, out_msg)
}

fn run_transaction_modal(
  model: Model,
  msg: transaction_modal.Msg,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(modal, request, outcome) = transaction_modal.update(model.modal, msg)
  let model = Model(..model, modal:)
  let error_effect = case msg {
    transaction_modal.SaveCompleted(result: Error(error)) ->
      Some(effect.LogError(api_error.describe(error)))
    _ -> None
  }
  fold_form(
    model,
    request,
    outcome,
    error_effect,
    apply_outcome,
    interpret_transaction_request,
  )
}

fn apply_outcome(
  model: Model,
  outcome: transaction_modal.Outcome,
) -> #(Model, Option(OutMsg)) {
  case outcome {
    form_modal.NoChange -> #(model, None)
    // Changes apply to the rows shown and never run the search again, so the
    // user sees the result of every change. See decision 10 in
    // docs/transaction-search.md.
    form_modal.Created(entity: transaction) -> #(
      map_shown(model, fn(transactions) { [transaction, ..transactions] }),
      Some(out_msg.success_toast("Transaction created")),
    )
    form_modal.Updated(entity: updated) -> #(
      map_shown(
        model,
        list.map(_, fn(t) {
          case t.id == updated.id {
            True -> updated
            False -> t
          }
        }),
      ),
      Some(out_msg.success_toast("Transaction updated")),
    )
  }
}

fn interpret_transaction_request(
  request: transaction_modal.Request,
) -> Effect(Msg) {
  case request {
    form_modal.Post(payload) ->
      effect.post(
        api_route.CreateTransaction |> api_route.to_string,
        transaction_write_request.to_json(payload)
          |> json.to_string,
        handle_save_response,
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(TransactionModalMsg)
    form_modal.Put(id:, payload:) ->
      effect.put(
        api_route.UpdateTransaction(id) |> api_route.to_string,
        transaction_write_request.to_json(payload)
          |> json.to_string,
        handle_save_response,
      )
      |> effect.with_timeout(form_modal.submit_timeout_ms)
      |> effect.map(TransactionModalMsg)
  }
}

fn handle_save_response(result) {
  case result {
    Ok(body) ->
      response.decode_success(body, transaction.transaction_decoder())
      |> transaction_modal.SaveCompleted
    Error(http_error) ->
      transaction_modal.SaveCompleted(
        Error(response.http_error_to_api_error(http_error)),
      )
  }
}

/// Fold a form's `#(modal, request, outcome)` triple into page state: store
/// the modal, apply the outcome to the transactions list (with a toast), turn
/// the request into an effect, and log the API error when the triggering
/// message was a save failure.
fn fold_form(
  model: Model,
  request: Option(request),
  outcome: outcome,
  error_effect: Option(Effect(Msg)),
  apply_outcome: fn(Model, outcome) -> #(Model, Option(OutMsg)),
  interpret: fn(request) -> Effect(Msg),
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let #(model, out_msg) = apply_outcome(model, outcome)
  let effects = case request {
    Some(request) -> [interpret(request)]
    None -> []
  }
  let effects = case error_effect {
    Some(error_effect) -> [error_effect, ..effects]
    None -> effects
  }
  // A single effect stays unwrapped rather than becoming a one-element batch;
  // several effects are batched.
  let effect = case effects {
    [] -> effect.none()
    [effect] -> effect
    _ -> effect.batch(effects)
  }
  #(model, effect, out_msg)
}

fn on_delete_succeeded(
  model: Model,
  transaction: Transaction,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  #(
    Model(
      ..map_shown(model, list.filter(_, fn(t) { t.id != transaction.id })),
      delete_modal: transaction_delete_modal.empty(),
    ),
    effect.none(),
    Some(out_msg.success_toast(
      "Deleted transaction " <> transaction.description,
    )),
  )
}

fn on_delete_failed(
  model: Model,
  error: ApiError,
) -> #(Model, Effect(Msg), Option(OutMsg)) {
  let updated = delete_modal.fail(model.delete_modal, error)
  case updated == model.delete_modal {
    True -> #(model, effect.none(), None)
    False -> #(
      Model(..model, delete_modal: updated),
      effect.LogError(api_error.describe(error)),
      None,
    )
  }
}

pub fn view(model: Model) -> Element(Msg) {
  let tags_by_id =
    model.tags |> list.map(fn(tag) { #(tag.id, tag) }) |> dict.from_list

  html.div([attribute.class("mx-auto max-w-6xl px-4 py-8 sm:px-6")], [
    // Wraps so the buttons go below the title on a narrow screen.
    html.div(
      [
        attribute.class(
          "flex flex-wrap items-center justify-between gap-4 mb-6",
        ),
      ],
      [
        html.h1([attribute.class("text-2xl font-semibold text-fg")], [
          html.text("Transactions"),
        ]),
        // Offered only once the list has loaded, so a new transaction always
        // has a list to join.
        case model.results {
          Loaded(_) ->
            html.div([attribute.class("flex items-center gap-2")], [
              button.link(
                button.Secondary,
                button.Regular,
                [
                  attribute.href(route.to_string(route.QuickTagging)),
                  attribute.attribute("data-testid", "quick-tag-link"),
                ],
                [html.text("Quick tag")],
              ),
              button.view(
                button.Secondary,
                button.Regular,
                [
                  attribute.attribute("data-testid", "import-button"),
                  event.on_click(ImportModalMsg(import_modal.OpenRequested)),
                ],
                [html.text("Import")],
              ),
              button.view(
                button.Primary,
                button.Regular,
                [
                  attribute.attribute(
                    "data-testid",
                    "record-transaction-button",
                  ),
                  event.on_click(UserRequestedCreationForm),
                ],
                [html.text("Record Transaction")],
              ),
            ])
          Loading | Failed -> element.none()
        },
      ],
    ),
    case model.results {
      Loading -> loading_state()
      Failed -> failed_state()
      Loaded(results) ->
        html.div([], [
          search_bar(model.search, model.filters_open),
          case model.filters_open {
            True -> filters_panel(model, results)
            False -> element.none()
          },
          searching_note(model.searching),
          case results.transactions, transaction_search.is_set(results.search) {
            [], False -> no_transactions_empty_state()
            [], True -> no_matches_empty_state()
            transactions, _ -> transactions_table(transactions, tags_by_id)
          },
          load_more(results, model.loading_more),
        ])
    },
    transaction_modal.view(model.modal, model.tags, model.accounts)
      |> element.map(TransactionModalMsg),
    transaction_delete_modal.view(
      model.delete_modal,
      on_cancel: UserCancelledDeleteModal,
      on_confirm: UserConfirmedDelete,
    ),
    import_modal.view(model.import_modal) |> element.map(ImportModalMsg),
  ])
}

fn transaction_tag(
  transaction: Transaction,
  tags_by_id: dict.Dict(Uuid, Tag),
) -> Option(Tag) {
  transaction.tag
  |> option.to_result(Nil)
  |> result.try(fn(tag) { dict.get(tags_by_id, tag.id) })
  |> option.from_result
}

/// The search box, the "Filters" button, and "Clear" while any criterion is
/// set.
fn search_bar(search: Search, filters_open: Bool) -> Element(Msg) {
  html.div([attribute.class("mb-4 flex flex-wrap items-center gap-2")], [
    html.label(
      [
        attribute.class("min-w-48 flex-1"),
        // The input's own handler keeps the text as typed. Input events bubble
        // to this label, which runs the search once typing pauses.
        event.debounce(event.on_input(UserPausedTyping), search_delay_ms),
      ],
      [
        html.span([attribute.class("sr-only")], [
          html.text("Search descriptions"),
        ]),
        input.text([
          attribute.type_("search"),
          attribute.attribute("data-testid", "search-input"),
          attribute.placeholder("Search descriptions"),
          attribute.maxlength(transaction_search.max_text_length),
          attribute.value(search.text),
          event.on_input(UserChangedText),
        ]),
      ],
    ),
    button.view(
      button.Secondary,
      button.Regular,
      [
        attribute.attribute("data-testid", "filters-button"),
        attribute.aria_expanded(filters_open),
        attribute.aria_controls(filters_panel_id),
        event.on_click(UserToggledFilters),
      ],
      [
        html.text(case transaction_search.filter_count(search) {
          0 -> "Filters"
          count -> "Filters (" <> int.to_string(count) <> ")"
        }),
      ],
    ),
    case transaction_search.is_set(search) {
      True ->
        button.view(
          button.Secondary,
          button.Regular,
          [
            attribute.attribute("data-testid", "clear-search-button"),
            event.on_click(UserClearedSearch),
          ],
          [html.text("Clear")],
        )
      False -> element.none()
    },
  ])
}

const filters_panel_id = "transaction-filters"

/// The criteria other than text. The fields stack on narrow screens.
fn filters_panel(model: Model, results: Results) -> Element(Msg) {
  let invalid = case transaction_search.validate(model.search) {
    Ok(_) ->
      transaction_search.Invalid(dates: None, minimum: None, maximum: None)
    Error(invalid) -> invalid
  }
  card.panel(
    [
      attribute.id(filters_panel_id),
      attribute.class("mb-4 grid gap-4 p-4 sm:grid-cols-2"),
      attribute.attribute("data-testid", "filters-panel"),
    ],
    [
      dates_filter(model.search, invalid.dates, results),
      account_filter(model.search.account, model.accounts),
      tag_filter(model.search.tag, model.tags),
      amount_filter(model.search, invalid),
    ],
  )
}

fn account_filter(
  selected: AccountFilter,
  accounts: List(Account),
) -> Element(Msg) {
  let option = fn(filter, label) {
    html.option(
      [
        attribute.value(transaction_search.account_to_value(filter)),
        attribute.selected(filter == selected),
      ],
      label,
    )
  }
  html.label([attribute.class("block")], [
    input.label("Account"),
    input.select(
      [
        attribute.attribute("data-testid", "account-select"),
        event.on_change(fn(value) {
          UserChangedAccount(transaction_search.parse_account(value))
        }),
      ],
      [
        option(transaction_search.AnyAccount, "Any account"),
        option(transaction_search.NoAccount, "No account"),
        ..accounts
        |> list.sort(fn(a, b) { string.compare(a.name, b.name) })
        |> list.map(fn(account) {
          option(transaction_search.OneAccount(account.id), account.name)
        })
      ],
    ),
  ])
}

/// The categorisation states, then the tags grouped into expense and income
/// tags, each by name.
fn tag_filter(selected: TagFilter, tags: List(Tag)) -> Element(Msg) {
  let option = fn(filter, label) {
    html.option(
      [
        attribute.value(transaction_search.tag_to_value(filter)),
        attribute.selected(filter == selected),
      ],
      label,
    )
  }
  let group = fn(label, kind) {
    html.optgroup(
      [attribute.attribute("label", label)],
      tags
        |> list.filter(fn(tag) { tag.kind == kind })
        |> list.map(fn(tag) {
          option(transaction_search.OneTag(tag.id), tag.name)
        }),
    )
  }
  html.label([attribute.class("block")], [
    input.label("Tag"),
    input.select(
      [
        attribute.attribute("data-testid", "tag-select"),
        event.on_change(fn(value) {
          UserChangedTag(transaction_search.parse_tag(value))
        }),
      ],
      [
        option(transaction_search.AnyTag, "Any tag"),
        option(transaction_search.WithoutTag, "Without a tag"),
        option(transaction_search.Untagged, "Untagged"),
        option(transaction_search.Dismissed, "Dismissed"),
        option(transaction_search.Transfer, "Transfer"),
        group("Expense tags", tag.Expense),
        group("Income tags", tag.Income),
      ],
    ),
  ])
}

/// The dates select, with the first and last day inputs for custom dates and
/// the resolved days for a preset.
fn dates_filter(
  search: Search,
  error: Option(String),
  results: Results,
) -> Element(Msg) {
  html.div([attribute.class("space-y-2")], [
    html.label([attribute.class("block")], [
      input.label("Dates"),
      input.select(
        [
          attribute.attribute("data-testid", "dates-select"),
          event.on_change(fn(value) {
            transaction_search.parse_preset(value)
            |> result.unwrap(transaction_search.AnyTime)
            |> UserChangedDatePreset
          }),
        ],
        list.map(transaction_search.date_presets, fn(preset) {
          html.option(
            [
              attribute.value(transaction_search.preset_to_string(preset)),
              attribute.selected(preset == search.preset),
            ],
            transaction_search.preset_label(preset),
          )
        }),
      ),
    ]),
    case search.preset {
      transaction_search.Custom ->
        html.div([attribute.class("grid grid-cols-2 gap-2")], [
          date_input(
            "First day",
            "from-date-input",
            search.from,
            UserChangedFromDate,
          ),
          date_input("Last day", "to-date-input", search.to, UserChangedToDate),
        ])
      transaction_search.AnyTime -> element.none()
      preset -> resolved_days(preset, results)
    },
    field_error("dates-error", error),
  ])
}

fn field_error(testid: String, error: Option(String)) -> Element(Msg) {
  case error {
    Some(error) ->
      html.p(
        [
          attribute.class("text-sm text-danger"),
          attribute.attribute("data-testid", testid),
        ],
        [html.text(error)],
      )
    None -> element.none()
  }
}

/// The direction select and the range of sizes: absolute amounts, so "a
/// debit of 50 to 200" reads as typed.
fn amount_filter(
  search: Search,
  invalid: transaction_search.Invalid,
) -> Element(Msg) {
  html.div([attribute.class("space-y-2")], [
    html.label([attribute.class("block")], [
      input.label("Direction"),
      input.select(
        [
          attribute.attribute("data-testid", "direction-select"),
          event.on_change(fn(value) {
            UserChangedDirection(transaction_search.parse_direction(value))
          }),
        ],
        list.map(transaction_search.directions, fn(direction) {
          html.option(
            [
              attribute.value(transaction_search.direction_to_string(direction)),
              attribute.selected(direction == search.direction),
            ],
            case direction {
              transaction_search.AnyDirection -> "Credits and debits"
              transaction_search.Credit -> "Credits"
              transaction_search.Debit -> "Debits"
            },
          )
        }),
      ),
    ]),
    html.div([attribute.class("grid grid-cols-2 gap-2")], [
      size_input(
        "Minimum",
        "minimum-input",
        search.minimum,
        invalid.minimum,
        UserChangedMinimum,
      ),
      size_input(
        "Maximum",
        "maximum-input",
        search.maximum,
        invalid.maximum,
        UserChangedMaximum,
      ),
    ]),
  ])
}

fn size_input(
  label: String,
  testid: String,
  value: String,
  error: Option(String),
  on_input: fn(String) -> Msg,
) -> Element(Msg) {
  html.div([], [
    html.label([attribute.class("block")], [
      input.label(label),
      input.text([
        attribute.type_("text"),
        attribute.attribute("data-testid", testid),
        attribute.inputmode("decimal"),
        attribute.placeholder("0.00"),
        attribute.value(value),
        event.on_input(on_input),
        event.on_change(fn(_) { UserCommittedSize }),
        input.invalid(option.is_some(error)),
      ]),
    ]),
    field_error(testid <> "-error", error),
  ])
}

fn date_input(
  label: String,
  testid: String,
  value: String,
  on_input: fn(String) -> Msg,
) -> Element(Msg) {
  html.label([attribute.class("block")], [
    input.label(label),
    input.text([
      attribute.type_("date"),
      attribute.attribute("data-testid", testid),
      attribute.value(value),
      event.on_input(on_input),
    ]),
  ])
}

/// The days the server resolved the preset to, once results for it have
/// loaded.
fn resolved_days(preset: DatePreset, results: Results) -> Element(Msg) {
  case results.search.preset == preset, results.from, results.to {
    True, Some(from), Some(to) ->
      html.p(
        [
          attribute.class("text-sm text-fg-muted"),
          attribute.attribute("data-testid", "dates-range"),
        ],
        [html.text(date.format(from) <> " to " <> date.format(to))],
      )
    _, _, _ -> element.none()
  }
}

/// Shown above the results while a search is in flight; the previous results
/// stay, so the table does not flash on every pause in typing.
fn searching_note(searching: Bool) -> Element(Msg) {
  html.p(
    [
      attribute.class("mb-2 h-5 text-sm text-fg-muted"),
      attribute.attribute("data-testid", "searching-note"),
      attribute.aria_live("polite"),
    ],
    case searching {
      True -> [html.text("Searching…")]
      False -> []
    },
  )
}

fn transactions_table(
  transactions: List(Transaction),
  tags_by_id: dict.Dict(Uuid, Tag),
) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "overflow-hidden rounded-lg border border-border shadow-sm",
      ),
    ],
    [
      html.table([attribute.class("min-w-full divide-y divide-border")], [
        html.caption([attribute.class("sr-only")], [
          html.text("All transactions"),
        ]),
        // Below md the columns do not fit, so a row shows only its description
        // cell, which repeats the other columns' figures under the description.
        html.thead(
          [
            attribute.class(
              "hidden bg-surface-hover text-left text-xs font-medium uppercase tracking-wide text-fg-muted md:table-header-group",
            ),
          ],
          [
            html.tr([], [
              html.th([attribute.class("px-4 py-3 font-medium")], [
                html.text("Date"),
              ]),
              html.th([attribute.class("px-4 py-3 font-medium text-right")], [
                html.text("Amount"),
              ]),
              html.th([attribute.class("px-4 py-3 font-medium")], [
                html.text("Description"),
              ]),
              html.th([attribute.class("px-4 py-3 font-medium")], [
                html.text("Account"),
              ]),
              html.th([attribute.class("px-4 py-3 font-medium")], [
                html.text("Tag"),
              ]),
              // The chevron column.
              html.td([], []),
            ]),
          ],
        ),
        html.tbody(
          [attribute.class("divide-y divide-border bg-surface")],
          list.map(transactions, fn(transaction) {
            html.tr(
              [
                // Below md the row is a flex box, not a table row: iOS Safari
                // does not make a positioned table row the containing block
                // of `open_button`'s overlay, so every row's overlay would
                // cover the viewport and a tap would open the last row.
                attribute.class(
                  "group relative hover:bg-surface-hover max-md:flex",
                ),
                attribute.attribute("data-testid", "transaction-row"),
              ],
              [
                html.td(
                  [
                    attribute.class(
                      "hidden whitespace-nowrap px-4 py-3 text-sm text-fg-muted md:table-cell",
                    ),
                  ],
                  [html.text(transaction.date |> date.format)],
                ),
                html.td(
                  [
                    attribute.class(
                      "hidden whitespace-nowrap px-4 py-3 text-sm tabular-nums text-fg text-right md:table-cell",
                    ),
                    attribute.attribute(
                      "data-amount",
                      float.to_string(transaction.amount),
                    ),
                  ],
                  [amount_text(transaction.amount)],
                ),
                html.td([attribute.class("min-w-0 flex-1 px-4 py-3")], [
                  html.div([attribute.class("flex items-start gap-3")], [
                    row.open_button(
                      testid: "edit-transaction-"
                        <> uuid.to_string(transaction.id),
                      on_click: UserRequestedEditForm(transaction.id),
                      class: "min-w-0 flex-1 wrap-anywhere",
                      children: [html.text(transaction.description)],
                    ),
                    html.span(
                      [
                        attribute.class(
                          "whitespace-nowrap text-sm tabular-nums text-fg md:hidden",
                        ),
                      ],
                      [amount_text(transaction.amount)],
                    ),
                  ]),
                  html.p(
                    [
                      attribute.class(
                        "mt-1 flex flex-wrap items-center gap-x-2 text-sm text-fg-muted md:hidden",
                      ),
                    ],
                    [
                      // Each part is an element: adjacent text would join
                      // into one flex item, with no gap around the dots.
                      html.span([], [html.text(transaction.date |> date.format)]),
                      ..list.flat_map(
                        option.values([
                          transaction.account_name
                            |> option.map(fn(name) {
                              html.span([], [html.text(name)])
                            }),
                          tag_label(transaction, tags_by_id),
                        ]),
                        fn(part) {
                          [
                            html.span([attribute.aria_hidden(True)], [
                              html.text("·"),
                            ]),
                            part,
                          ]
                        },
                      )
                    ],
                  ),
                ]),
                html.td(
                  [
                    attribute.class(
                      "hidden whitespace-nowrap px-4 py-3 text-sm text-fg-muted md:table-cell",
                    ),
                  ],
                  [html.text(transaction.account_name |> option.unwrap("-"))],
                ),
                html.td(
                  [
                    attribute.class(
                      "hidden whitespace-nowrap px-4 py-3 text-sm text-fg-muted md:table-cell",
                    ),
                  ],
                  [
                    tag_label(transaction, tags_by_id)
                    |> option.unwrap(html.text("-")),
                  ],
                ),
                html.td([attribute.class("py-3 pr-4")], [
                  row.chevron(class: "block"),
                ]),
              ],
            )
          }),
        ),
      ]),
    ],
  )
}

/// A transaction's tag with its colour, "Transfer" for a transfer, or nothing
/// when it is untagged.
fn tag_label(
  transaction: Transaction,
  tags_by_id: dict.Dict(Uuid, Tag),
) -> Option(Element(Msg)) {
  case transaction.is_transfer, transaction_tag(transaction, tags_by_id) {
    // A transfer has no tag: it is neither income nor an expense.
    True, _ -> Some(html.text("Transfer"))
    False, Some(tag) ->
      Some(
        html.span([attribute.class("inline-flex items-center gap-2 text-fg")], [
          swatch.view(tag.color),
          html.text(tag.name),
        ]),
      )
    False, None -> None
  }
}

/// Shown below the table while the search has another page.
fn load_more(results: Results, loading_more: Bool) -> Element(Msg) {
  case results.next {
    None -> element.none()
    Some(_) ->
      html.div([attribute.class("mt-4 flex justify-center")], [
        button.view(
          button.Secondary,
          button.Regular,
          [
            attribute.attribute("data-testid", "load-more-button"),
            attribute.disabled(loading_more),
            event.on_click(UserRequestedMore),
          ],
          [
            html.text(case loading_more {
              True -> "Loading…"
              False -> "Load more"
            }),
          ],
        ),
      ])
  }
}

/// Shown in place of the table when there are no transactions yet. The
/// "Record Transaction" button in the page header stays visible, so no extra
/// call to action is needed here.
fn no_transactions_empty_state() -> Element(Msg) {
  card.empty_state(
    [
      attribute.attribute("data-testid", "no-transactions-empty-state"),
    ],
    [
      html.h2([attribute.class("text-base font-semibold text-fg")], [
        html.text("No transactions yet"),
      ]),
      html.p([attribute.class("mt-1 text-sm text-fg-muted")], [
        html.text("Use \"Record Transaction\" to add your first one."),
      ]),
    ],
  )
}

/// Shown in place of the table when the search matches nothing.
fn no_matches_empty_state() -> Element(Msg) {
  card.empty_state(
    [
      attribute.attribute("data-testid", "no-matches-empty-state"),
    ],
    [
      html.h2([attribute.class("text-base font-semibold text-fg")], [
        html.text("No transactions match your search"),
      ]),
      button.view(
        button.Secondary,
        button.Regular,
        [
          attribute.class("mt-4"),
          attribute.attribute("data-testid", "clear-search-empty-button"),
          event.on_click(UserClearedSearch),
        ],
        [html.text("Clear search")],
      ),
    ],
  )
}

fn loading_state() -> Element(Msg) {
  card.empty_state(
    [
      attribute.attribute("data-testid", "transactions-loading-state"),
    ],
    [
      html.p([attribute.class("text-sm text-fg-muted")], [
        html.text("Loading transactions..."),
      ]),
    ],
  )
}

/// The first load failed; the page offers a retry rather than an indefinite
/// loading state.
fn failed_state() -> Element(Msg) {
  card.empty_state(
    [
      attribute.attribute("data-testid", "transactions-load-error"),
    ],
    [
      html.h2([attribute.class("text-base font-semibold text-fg")], [
        html.text("Could not load transactions"),
      ]),
      html.p([attribute.class("mt-1 text-sm text-fg-muted")], [
        html.text("Check your connection and try again."),
      ]),
      button.view(
        button.Primary,
        button.Regular,
        [
          attribute.class("mt-4"),
          attribute.attribute("data-testid", "transactions-retry"),
          event.on_click(UserRequestedReload),
        ],
        [html.text("Retry")],
      ),
    ],
  )
}

/// Credits sit on the success tint so money coming in stands out from the
/// debits around it. Success is never a text colour (decision 6 in
/// docs/styling.md), and the minus sign on debits still carries the direction.
/// The tint's negative margin cancels its padding so the figures line up.
fn amount_text(amount: Float) -> Element(Msg) {
  case amount >. 0.0 {
    True ->
      html.span([attribute.class("-mx-1 rounded bg-success-tint px-1")], [
        html.text(money.format(amount)),
      ])
    False -> html.text(money.format(amount))
  }
}
