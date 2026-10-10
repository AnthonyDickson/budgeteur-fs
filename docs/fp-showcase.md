# Functional Programming in Practice

<!--toc:start-->

- [Functional Programming in Practice](#functional-programming-in-practice)
  - [1. Make invalid states unrepresentable](#1-make-invalid-states-unrepresentable)
  - [2. Option instead of null](#2-option-instead-of-null)
  - [3. Errors as values](#3-errors-as-values)
  - [4. Effects as data](#4-effects-as-data)
  - [5. Cross-cutting concerns as functions](#5-cross-cutting-concerns-as-functions)
  - [6. Dependencies as arguments](#6-dependencies-as-arguments)
  - [F# and Gleam: two levels of strictness](#f-and-gleam-two-levels-of-strictness)
  - [General costs](#general-costs)
  - [Further reading](#further-reading)

<!--toc:end-->

This tour is for developers with little or no functional programming (FP)
experience. It covers the FP ideas in this codebase that have no common
equivalent in imperative or object-oriented (OOP) code. Each section has three
parts: the problem in a typical imperative/OOP design, the FP pattern this repo
uses instead, and what the pattern costs.

The server is F#, which is FP-first but allows objects, mutation, and
exceptions. The client is Gleam, which has no null, no classes, and no mutable
data. Snippets are short and some are simplified; the file named next to each
one has the real code.

## 1. Make invalid states unrepresentable

**Problem.** State is usually modelled as a record of flags and nullable fields.
A delete-confirmation dialog might look like this:

```gleam
DeleteModalState(is_open: Bool, is_deleting: Bool, transaction: Option(Transaction))
```

That gives eight combinations, but only three are meaningful. `is_deleting:
True` with no transaction compiles, so code that reads the state needs guards
against values that should never exist. The rule "deleting requires a target"
lives in the developer's head, not in the type, and there is nowhere to put the
error message from a failed delete.

**Pattern.** A **sum type**, also called a discriminated union or tagged union,
is a fixed list of named cases. Each case can carry its own data
(`shared/delete_modal.gleam`):

```gleam
pub type State(target, context) {
  Hidden
  Confirming(target: target, context: context)
  Deleting(target: target, context: context)
  Errored(target: target, context: context, error: String)
}
```

Only the cases that are in progress carry a target, and only `Errored` carries
an error, so the nonsense combinations cannot be built. Code reads the state
with **pattern matching** (`case` in Gleam, `match` in F#), which works like a
`switch` with one difference: the compiler rejects a match that leaves out a
case. If you add a case, the compiler lists every match that has to handle it.
The same technique models the client's routes (`shared/route.gleam`), where an
unknown URL becomes the `NotFound` case, and the server's errors (section 3).

**Trade-offs.** Sum types and class hierarchies make opposite things easy. This
is the _expression problem_ (Wadler).

- OOP: adding a new kind is cheap (a new subclass). Adding a new operation is
  expensive, because every class needs a new method.
- Sum types: adding a new operation is cheap (one new function with a `match`).
  Adding a new case is expensive, because every `match` has to change. The
  compiler finds them all, but you still edit them all.

Sum types suit sets that the app owns and that rarely change, such as dialog
states, routes, and error kinds. They suit plugin-style extension poorly, where
third parties add cases. A catch-all branch (`_ ->`) turns off the completeness
check for that match, so new cases go through it without any warning.

## 2. Option instead of null

**Problem.** In most languages any reference can be `null`, and the type does
not tell you which ones are. Whether `transaction.Tag.Name` can crash is
something you find out at runtime.

**Pattern.** Gleam has no null. A value that may be missing has the type
`Option(a)`, a two-case sum type: `Some(value)` or `None`. To get the value out
you have to match on it, so the compiler makes you handle `None`. F# idiom is
the same (`Domain/Transaction.fs`):

```fsharp
type Transaction = {
    // ...
    AccountId : Guid option // linked to a bank account, or not
    TagId : Guid option // tagged, or not
}
```

A missing value is visible in the type wherever the field is used. Section 1
goes a step further and gets rid of the `Option` altogether: the `Deleting` case
always holds its target.

**Trade-offs.** Every read of an optional value needs a match, `Option.map`, or
a default. That is more code than an unchecked dereference. F# still has `null`,
because any .NET API can return one, so code that calls .NET has to convert
those results to `Option` itself.

## 3. Errors as values

**Problem.** Exceptions are invisible in function signatures. You can't tell
from a call whether it can fail or how. An empty `catch` hides the failure, and
an uncaught one shows up as a 500 in production. Thrower and catcher also have
to agree on what each exception type means, and nothing checks that they do.

**Pattern.** A fallible function returns `Result<'T, DomainError>`, which is
either `Ok value` or `Error err`. The error is an ordinary return value that is
written in the signature. Validated values use a type whose constructor is
private, so the only way to get one is through a `create` function that returns
a `Result` (`Domain/Transaction.fs`):

```fsharp
let create (description : string) =
    description.Trim ()
    |> nonEmpty
    |> Result.bind acceptableLength
    |> Result.map TransactionDescription
```

`x |> f` means `f x`, so the steps read top to bottom. `nonEmpty` and
`acceptableLength` each return a `Result`. `Result.bind` runs the next step only
if the previous one returned `Ok`, so the first `Error` skips the rest. The
signature `string -> Result<TransactionDescription, DomainError>` is the whole
contract. Code that holds a `TransactionDescription` knows it has already been
checked, which Alexis King calls "parse, don't validate".

Handlers chain steps with a **computation expression**, F#'s block syntax for
sequencing that works like `async`/`await`. Inside `taskResult { ... }`, `let!`
unwraps an `Ok`, and an `Error` stops the block and becomes its result
(`Feature/Transaction/ReadTransaction.fs`, simplified):

```fsharp
taskResult {
    let! userId = Auth.getUserId ctx
    let! transaction = get queryContext userId id
    match transaction with
    | Some t -> do! Json.write ctx (TransactionResponse.fromDomain t)
    | None -> return! Error (NotFound $"Transaction %O{id} not found")
}
```

`DomainError` is a sum type (`Shared/DomainError.fs`). One exhaustive `match` in
`Shared/Endpoint.fs` turns each case into a status code and a uniform error
body. If you add a case, the compiler requires a response for it. The same file
is the one place that catches exceptions. It turns SQLite and other platform
exceptions into `Conflict`, `DatabaseError`, or `UnhandledException`, so feature
code never uses `try`.

**Trade-offs.**

- `Result` spreads through signatures the way `async` does. A function that
  calls a fallible function has to return a `Result` itself or handle the error.
  Mixing `Task` and `Result` needs a library computation expression (FsToolkit's
  `taskResult`).
- A `Result` error has no stack trace. Domain errors carry a message instead,
  and platform errors keep the original exception.
- There are two error mechanisms. Exceptions still come from .NET, so the
  boundary that turns them into values has to be maintained, and a `try` that
  wraps too little lets exceptions through to the framework.

## 4. Effects as data

**Problem.** In a typical web client, event handlers call the outside world
directly: `await api.post(...)`, `localStorage.setItem(...)`,
`history.pushState(...)`. To test that logic you have to mock `fetch`, storage,
and the history API. Side effects can happen in any function, so you can't tell
from a signature which functions touch the network.

**Pattern.** The client follows the Elm architecture. A page's `update` is a
pure function. It takes the current model and a message, and returns the new
model, an `Effect`, and an optional request to the app shell. An `Effect` is a
sum type that _describes_ work (`HttpRequest`, `SaveToStore`, `PushUrl`,
`Batch`, ...). It does not run anything
(`transaction_page/transaction_page.gleam`):

```gleam
form_modal.Post(payload) ->
  effect.post(
    api_route.CreateTransaction |> api_route.to_string,
    create_transaction_request.create_transaction_request_to_json(payload)
      |> json.to_string,
    handle_save_response,
  )
  |> effect.with_timeout(form_modal.submit_timeout_ms)
  |> effect.map(TransactionModalMsg)
```

`effect.run` in `shared/effect.gleam` is the one interpreter that runs these
descriptions. It and a small JS file (`shared/effect_ffi.mjs`) are the only code
that touches the browser. Gary Bernhardt calls this "functional core, imperative
shell". Tests call `update` and inspect the effect it returns, with no browser
or HTTP involved (`client/test/`):

```gleam
let assert effect.HttpRequest(method: method, url: url, ..) = effect
method |> should.equal(http_effect.Post)
url |> should.equal("/api/transactions")
```

**Trade-offs.**

- More indirection. A click becomes a message, the message produces an effect,
  the interpreter runs it, and the result arrives as another message. To follow
  one action you read several functions.
- The `Effect` type and its interpreter are in-house infrastructure with 14
  cases. In a mainstream client that code would come from a library.
- Unit tests show that a request was _described_ correctly, not that it works.
  Only the E2E tests exercise the client against the server.
- Effects hold callbacks, and functions can't be compared for equality. Tests
  therefore match on fields, as above, or call the callback and check the
  message it returns.

## 5. Cross-cutting concerns as functions

**Problem.** Concerns such as auth checks and session expiry usually need
framework machinery: decorators, attributes, aspect-oriented programming, or
global HTTP interceptors. That machinery is configured in one place and takes
effect somewhere else, so you have to know it exists to understand a call.

**Pattern.** Effects and endpoint lists are plain values, so a cross-cutting
concern can be a function that takes a value and returns a changed one. The
client rewrites every HTTP effect so that a 401 response dispatches
`SessionExpired` instead of reaching the page (`app.gleam`):

```gleam
pub fn wrap_http_requests(effect: Effect(Msg)) -> Effect(Msg) {
  case effect {
    effect.HttpRequest(callback: original_callback, ..) as request ->
      effect.HttpRequest(..request, callback: fn(result) {
        case result {
          Error(http_effect.HttpError(status: 401, ..)) -> SessionExpired
          _ -> original_callback(result)
        }
      })
    effect.Batch(effects) -> effect.Batch(list.map(effects, wrap_http_requests))
    _ -> effect
  }
}
```

The shell applies it to the result of `update` and `init`. Pages know nothing
about it. The server does the same with its endpoint lists: `withAuth` in
`Program.fs` maps an auth filter over every feature endpoint. Testing the rule
means calling the function on a value (`client/test/app_test.gleam`).

**Trade-offs.** The rewrite has to know every case that can contain other
effects. Here that is only `Batch`. A new case that wraps effects would match `_
-> effect` and skip the 401 handling with no compiler warning, which is the
catch-all problem from section 1. The function also has to be applied at every
entry point, and forgetting one is a silent bug.

## 6. Dependencies as arguments

**Problem.** OOP codebases often use a dependency-injection container:
interfaces that exist so they can be mocked, constructor injection, and a
registration list. The registration list is a second description of the
dependency graph. When it does not match the code, the error shows up at
runtime, the first time the container resolves that dependency.

**Pattern.** Functions take their dependencies as arguments. `Program.fs`
creates the database `QueryContextFactory` once and passes it to each slice's
endpoint list. Each slice passes it on to its handlers
(`Feature/Transaction/TransactionEndpoints.fs`):

```fsharp
let all (queryContext : QueryContextFactory) = [
    POST [ CreateTransaction.endpoint queryContext ]
    GET [ ReadTransaction.endpoint queryContext; ReadAllTransactions.endpoint queryContext ]
    ...
]
```

`CreateTransaction.endpoint queryContext` is **partial application**: you pass
the first argument and get back a function that waits for the rest. The function
keeps the dependency it was given, which is the work an object constructor does
in OOP. Nothing is registered or looked up, and a missing argument is a compile
error. The test host calls the same `all` functions with an in-memory database
(`server/tests/Budgeteur.Tests/TestApp.fs`). The client's `update` functions are
pure, so they need no dependencies.

**Trade-offs.** Each new dependency is a new parameter on every function between
where it is created and where it is used. There is no lifetime management (per
request, singleton). That is acceptable here because the server has one
dependency. An app with many would group them in a record and end up rebuilding
part of a container by hand. The server tests also avoid mocks because they use
a real SQLite database, which is a testing decision, not an FP one.

## F# and Gleam: two levels of strictness

F# lets you leave FP when the platform requires it, and the server does so at
its edges:

- `Shared/Endpoint.fs` catches exceptions.
- Config records in `Shared/Config.fs` are `[<CLIMutable>]` so the ASP.NET
  binder can fill them.
- The per-request log buffer in `Shared/RequestLogging.fs` is a mutable list.

Domain code and handlers use the patterns above.

Gleam has no null, classes, or mutation, and its errors are `Result` values. It
is not a pure language, though. Any function can call JavaScript through FFI,
and `panic` and `let assert` crash. `update` is pure because the `Effect` design
makes that the easy path, not because the language enforces it.

## General costs

These costs apply to the whole codebase rather than to one pattern:

- **Learning curve.** Sum types, `Result`, `|>`, computation expressions, and
  partial application are unfamiliar to most developers. Code that is idiomatic
  here looks foreign at first.
- **Gleam's small ecosystem.** Routing, the effect system, HTTP, and toasts are
  hand-written (`shared/route.gleam`, `shared/effect.gleam`,
  `shared/http_effect.gleam`, `shared/toast.gleam`), plus JS FFI where Gleam has
  no binding. In a mainstream stack these would be `npm` packages.
- **Hiring.** Few developers know Gleam, and F# is a minority choice even in
  .NET teams.
- **Performance.** Immutable data allocates a new value for each change. That
  doesn't matter in an I/O-bound app like this one, but it does in tight numeric
  loops or real-time rendering.

## Further reading

- Yaron Minsky, _Effective ML_ (2010), and Scott Wlaschin, _Designing with
  types_: making illegal states unrepresentable (sections 1 and 2).
- Philip Wadler, _The Expression Problem_ (1998): the trade-off in section 1.
- Tony Hoare, _Null References: The Billion Dollar Mistake_ (2009): section 2.
- Joel Spolsky, _Exceptions_ (2003); Rob Pike, _Errors are values_ (2015); Joe
  Duffy, _The Error Model_ (2016): section 3.
- Alexis King, _Parse, don't validate_ (2019): refined types in section 3.
- Gary Bernhardt, _Boundaries_ (2012): functional core, imperative shell
  (section 4).
- Mark Seemann, _From dependency injection to dependency rejection_ (2017):
  section 6.
- Scott Wlaschin, _Domain Modeling Made Functional_ (2018): most of the above,
  in F#.

To read the code, start with `Feature/Transaction/` on the server and
`transaction_page/` on the client, the reference implementations described in
[architecture.md](architecture.md).
