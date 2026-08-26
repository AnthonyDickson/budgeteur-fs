# Functional Programming in Practice

<!--toc:start-->

- [Functional Programming in Practice](#functional-programming-in-practice)
  - [Part I: The server (F#)](#part-i-the-server-f)
    - [1. Make invalid states unrepresentable](#1-make-invalid-states-unrepresentable)
    - [2. Option instead of null](#2-option-instead-of-null)
    - [3. Closed types vs open hierarchies](#3-closed-types-vs-open-hierarchies)
    - [4. Errors as values](#4-errors-as-values)
    - [5. Pipelines](#5-pipelines)
    - [6. Compiler as a pair programmer](#6-compiler-as-a-pair-programmer)
    - [7. Pragmatic FP](#7-pragmatic-fp)
    - [8. Logs as data](#8-logs-as-data)
  - [Part II: The client (Gleam)](#part-ii-the-client-gleam)
    - [9. Effects as data](#9-effects-as-data)
    - [10. Programs as data](#10-programs-as-data)
    - [11. App state as data](#11-app-state-as-data)
    - [12. Routes and codecs as values](#12-routes-and-codecs-as-values)
  - [Part III: Shared patterns](#part-iii-shared-patterns)
    - [13. No DI container](#13-no-di-container)
    - [14. Testing without mocks](#14-testing-without-mocks)
  - [Part IV: The FP spectrum](#part-iv-the-fp-spectrum)
  - [What FP costs you](#what-fp-costs-you)
  - [Where to look next](#where-to-look-next)
    - [Further reading](#further-reading)

<!--toc:end-->

A tour of this codebase for developers who are **curious about functional
programming (FP)** but don't necessarily know it. You don't need to read F# or
Gleam fluently: every idea is explained in plain terms, with short annotated
snippets and file pointers. If you're an FP veteran, most of this is familiar
territory; the value here is in seeing it applied to a real product.

The stack has two halves: an F#/Oxpecker backend and a Gleam/Lustre
SPA frontend. F# is _pragmatic_ FP: you can dip in and out, objects
interoperate, and computation expressions keep things looking familiar (stop
7). Gleam is _strict_ FP: no null, no exceptions, no inheritance, nothing. The
contrast gets its own section at the end.

FP is easy to write off as a niche that industry doesn't really use, but the
record says otherwise. Jane Street runs its trading platform on OCaml; WhatsApp
and Discord serve hundreds of millions of real-time users on Erlang and Elixir;
RabbitMQ, one of the most widely deployed message brokers in existence, is
Erlang; and Ericsson's AXD301 telephone switch is widely reported to have
reached "nine nines" of availability. F# has its own production record on .NET,
particularly in finance. This tour covers the ideas behind those systems in the
context of this codebase.

Every stop follows the same shape: the problem it solves in typical
OOP/imperative codebases, how this repo does it instead, and why you should
care. Most stops stand on their own; where one leans on an earlier idea, it
says so with a `(stop N)` pointer, so you can jump there and back. If a claim
makes you want the full argument, the original sources are collected in
"Further reading" at the end.

## Part I: The server (F#)

### 1. Make invalid states unrepresentable

_"Make invalid states unrepresentable"_, a phrase coined by Yaron Minsky of
Jane Street and popularized in the F# world by Scott Wlaschin, means: design
your types so the values that can exist are exactly the valid states, and
constructing anything else is impossible.

The delete dialog's state could easily have been the OOP/imperative shape, a
flat record of flags:

```gleam
pub type DeleteModalState {
  DeleteModalState(
    is_open: Bool,
    is_deleting: Bool,
    transaction: Option(Transaction),
  )
}
```

Every combination of flags is a legal value: `is_deleting: True` with
`transaction: None`, a dialog that is deleting nothing, compiles fine. Of the
eight combinations, three are meaningful and five are nonsense, and the
nonsense ones are filtered by `if` guards scattered through the view. The
invariant "deleting requires a target" exists only as discipline; the compiler
can't see it.

The actual type encodes the lifecycle instead (`transaction_delete_modal.gleam`):

```gleam
pub type DeleteModalState {
  Hidden
  Confirming(transaction: Transaction)
  Deleting(transaction: Transaction)
}
```

"Deleting" carries the transaction it is deleting, so the nonsense state has no
variant: it cannot be written, let alone reached.

This kind of type, a fixed, named set of shapes a value can take with each
optionally carrying its own data, is called a **discriminated union**, also
known as a sum type or tagged union. It's the single most-reused tool in this
tour; watch for it again at stops 3, 4, 9, and 12. Every `case`/`match` on a
type like this, the pattern-matching syntax you'll see throughout and a
stricter cousin of a `switch` statement, has to name every variant, and the
compiler checks the list is complete (stop 6). The type's own doc comment makes the same claim: the
lifecycle is encoded in the variants so illegal states are unrepresentable.

`transaction: Option(Transaction)` in the flag-shaped version above is worth a
second look, too: that field is itself a small discriminated union; stop 2
covers it.

### 2. Option instead of null

In most languages, a reference can either point to a value or be `null`, and
nothing in the type tells you which. Reading `transaction.Amount` on a value
that might be `null` compiles fine and costs nothing to write; whether it
actually crashes is a fact you learn at runtime, at whichever call site forgot
to check. Tony Hoare, who invented the null reference, called it his
"billion-dollar mistake" for exactly this reason: it's a decision that looks
free where you write it and gets billed to whoever calls the code later.

Gleam doesn't have `null` at all. An unset value has to say so in its type.
That's the same discriminated-union shape from stop 1, applied to "value or
nothing": `Option(a)` has exactly two variants, `Some(value)` and `None`, and
the compiler treats them like any other pair of cases. There's no way to read
the value out of an `Option` without first handling both. Stop 1's
`DeleteModalState` already shows this at work: the flag-shaped version carried
`transaction: Option(Transaction)` as a field that could quietly be `None`
while other flags claimed a transaction was being deleted. The fixed version
doesn't need `Option` at all: `Confirming(transaction: Transaction)` and
`Deleting(transaction: Transaction)` only exist when a transaction is actually
attached, so there's nothing left that could be missing.

Both halves of this repo lean on `Option` everywhere. A transaction may or may
not be linked to an account or a tag, and the type says so explicitly
(`Domain/Transaction.fs`):

```fsharp
type Transaction = {
  // .. other fields ..
  AccountId : Guid option  // linked to a bank account, or not
  TagId : Guid option      // tagged, or not
}
```

A new transaction starts with `AccountId = None` and `TagId = None` (see
the `CreateTransaction.fs` handler in stop 7), and anything that reads a transaction must
decide what "no account" means at every use. The client's `transaction.gleam`
mirrors the same two fields as `account_id: Option(Uuid)` and
`tag_id: Option(Uuid)`. Even the server's error type uses the pattern:
`DomainError` (stop 3) carries an `exn option`, so a database error can
include the underlying .NET exception when one exists.

F# keeps `null` around for .NET interop, because any library on the platform
can hand one back. Idiomatic F# routes around it with the same `Option` type,
and nullable-reference-type checking, where enabled, flags the seam where a
.NET call might still return one.

Why it matters: with `null`, "does this need a check?" is a question about
memory, documentation, and hope. With `Option`, it's a question the compiler
answers for you, at every call site, every time, the same shift stop 4 makes
for errors, one level earlier.

### 3. Closed types vs open hierarchies

Handling failure with an error interface or exception hierarchy is the OOP
norm. Adding a new failure kind is trivial: new subclass, done. But handling
failure is unverifiable: the set of implementations is open, so "handle every
error" degrades into catching the base class and hoping. This repo's server
inverts that. The same discriminated union from stops 1 and 2 now describes
"what can go wrong" instead of "what state is this in", as one closed type
with named cases (`DomainError.fs`):

```fsharp
type DomainError =
    | ValidationFailed of string
    | NotFound of string
    | Conflict of string
    | UserNotFound
    | DatabaseError of string * exn option
    | UnhandledException of string * exn option
```

A closed type flips the trade. This is the expression problem (Wadler 1998):
you can make it easy to add new _data_ variants, or easy to add new
_operations_ over existing data, but not both at once. Adding a new failure
kind here means editing the type, and the compiler walks you through every
consumer. Adding a new operation over failures, a status-code mapping, a test,
or a log line, is one `match`, exhaustive by construction. An API's error
taxonomy is a small, stable set that everything downstream grows against,
which is exactly the case where closed wins. It works because the app owns the
taxonomy: unknown platform failures don't break the closure, they're folded
into `DatabaseError` and `UnhandledException` explicitly.

Two consequences that don't exist in the interface world:

- **The full set of failures is discoverable**: read one type and you know
  everything a handler can do.
- **The compiler enforces completeness**: any code that handles a
  `DomainError` must cover every case (see stop 6).

### 4. Errors as values

Three problems with exceptions, in increasing order of cost:

- **The contract is invisible.** No signature says what a function can throw,
  so "can this fail, and how?" is answered by reading the implementation, or
  by a crash. Joel Spolsky called exceptions "invisible in the source code";
  they're gotos between functions that the code doesn't show.
- **Thrower and catcher can disagree about what failure means.** One layer's
  "not found" is another layer's expected outcome, and nothing forces the two
  to share a vocabulary.
- **Handling is unverifiable.** Anything in the call tree can throw, empty
  `catch` blocks swallow failures silently, and the unhandled case surfaces as
  a 500 in production, found by a bug report, not by the compiler.

This repo answers all three by making failure part of the type. Handlers never
throw; they return a `Result`, a value that is _either_ a success (`Ok`) _or_
a failure (`Error`). Here is an entire endpoint
(`Feature/Transaction/ReadTransaction.fs`):

```fsharp
let handler (queryContext : QueryContextFactory) (id : Guid) : EndpointHandler =
    Endpoint.handler (fun ctx ->
        taskResult {
            let! userId = Auth.getUserId ctx
            let! transaction = get queryContext id userId
            match transaction with
            | Some t -> do! Json.write ctx t
            | None -> return! Error (NotFound $"Transaction %O{id} not found")
        })
```

`taskResult { ... }` is a **computation expression**, F#'s block syntax for
sequencing steps that don't behave like plain, linear code. If you know C#'s
`async`/`await`, it's the same idea: sugar that lets you write code that reads
top to bottom while something else, here "this step might fail or might still
be running", happens underneath. Inside the block, `let!` unwraps a
step's result and hands it to the next line; if that step is `Error`,
everything after it is skipped and the `Error` becomes the whole block's
result.

Three failure sources funnel into one `DomainError` type: auth, the database,
serialization. The contract is now readable: every step's type names what it
can fail with. Because every layer shares that one type, `NotFound`
means the same thing in the handler and in the response mapping. `let!` does
the short-circuiting for you, so the handler above reads top to bottom with no
try/catch and no hand-written propagation, yet the compiler still knows
exactly what each step can fail with, something a try/catch version never
tells you without reading its body.

One central place, `Endpoint.handler` (`Shared/Endpoint.fs`), decides what errors
become on the wire:

```fsharp
match! body with
| Ok () -> ()
| Error (ValidationFailed err) -> ctx.Response.StatusCode <- 400
| Error (NotFound err)         -> ctx.Response.StatusCode <- 404
| Error (Conflict err)         -> ctx.Response.StatusCode <- 409
| ...all other cases...
```

A global exception handler maps errors to responses just as centrally, so the
mapping is not the difference. What differs is what arrives at the boundary:
with exceptions, the failure set is whatever the code happened to throw, and
the unhandled case is a 500. Here the set is the closed `DomainError` type
(stop 3), and the compiler checks the mapping covers every case (stop 6). An
unhandled failure is a compile error, not a 500. The mapping also fixes the
wire shape once: every endpoint emits the same machine-readable
`{ Error, Details, StatusCode, RequestId }`.

Because the error is a _value_, it behaves like one. The `match` in the first
snippet translates `None` into `NotFound` in plain code, and the tests in
`server/tests/` drive error paths with real inputs: nothing is mocked into
throwing. Rob Pike's name for this is "errors are values": failure is data,
with the normal tools: return it, match it, transform it, log it.

### 5. Pipelines

In imperative code, a multi-step transformation becomes a trail of temporary
variables, `let t1 = ...; let t2 = ...`, and reading it means tracing each
assignment. This repo threads a value through named functions instead, using
the pipe operator `|>`, top-to-bottom; both languages in this stack have it.
If you've chained LINQ methods in C# or `.map()`/`.filter()` in JavaScript, the
reading experience is the same; the difference is that `|>` works with any
function, not just methods defined on the object you're chaining from. The
description validation in `Domain/Transaction.fs` is a pipeline,
read as a sentence:

```fsharp
let create (description : string) =
    description.Trim ()
    |> nonEmpty
    |> Result.bind acceptableLength
    |> Result.map TransactionDescription
```

"Trim it, then require it to be non-empty, then check the length, then wrap
the result in the `TransactionDescription` type." `nonEmpty`
and `acceptableLength` are plain functions returning `Ok`/`Error`. `Result.bind`
is what chains them: given a `Result` and a function, it runs the function on
the value inside if the `Result` is `Ok`, or skips the function and passes the
`Error` straight through if it isn't, the same short-circuit as `let!` (stop
4), just written as a function instead of block syntax. The wrapping step
(`Result.map`) is what turns the validated string into a value that cannot be
constructed unvalidated anywhere else. The same logic written
imperatively is an `if` chain with the rules baked into the control flow:

```fsharp
let create (description : string) =
    let trimmed = description.Trim ()
    if System.String.IsNullOrWhiteSpace trimmed then
        Error (ValidationFailed "Description cannot be null or just whitespace")
    elif trimmed.Length > MaxTransactionDescriptionLength then
        Error (ValidationFailed "Description must be at most 256 characters")
    else
        Ok (TransactionDescription trimmed)
```

The contrast shows when a rule is added. The imperative version needs a new
`elif` in the middle of the function, and the whole chain must be re-read to
confirm it still holds. The pipeline appends one step; the existing steps are
untouched, and the property tests in `TransactionDescriptionPropertyTests.fs` keep driving
the composed chain with generated inputs.

### 6. Compiler as a pair programmer

In most codebases, "handle every case" is a discipline. An enum or error code
gains a new value, and every `switch` that should have handled it is found by
searching, or by a bug report. In this repo, the compiler does the searching.
Two concrete results of strong typing + exhaustive matching:

**Miss a case, and it won't compile.** In `Shared/Endpoint.fs`, every `DomainError`
case is handled explicitly. Add a new case to the type tomorrow and the
compiler will point at every place that must handle it. In OOP terms: the
compiler enforces the "update all subclasses" step of the Visitor pattern.

**The schema and the code cannot drift.** Tables are defined in migration SQL
(`Data/Migrations/001_add_core_data_models.sql`) using special type hints:

```sql
Id     GUID     NOT NULL PRIMARY KEY,
Amount CURRENCY NOT NULL,
```

and SqlHydra generates the F# record types straight from the schema. The
`CURRENCY` column becomes a `decimal` in F#, `GUID` becomes `Guid`. The mapping
between database and code is _generated_, so schema drift is a compile error,
not a runtime surprise. This is the "type the schema, not the mapping" school
of thought: the type system is the source of truth, and tooling derives
everything else from it.

### 7. Pragmatic FP

FP is usually pitched as all-or-nothing: to get the benefits you adopt a pure
language, a different runtime, and re-implement the ecosystem. This repo is the
counter-argument: a real ASP.NET Core app where "pragmatic" means FP where it
pays, and the platform where it doesn't. Here is a whole endpoint, verbatim
(`Feature/Transaction/CreateTransaction.fs`):

```fsharp
let private handler (queryContext : QueryContextFactory) : EndpointHandler =
    Endpoint.handler (fun ctx ->
        taskResult {
            let log = RequestLog.fromContext ctx
            let! userId = Auth.getUserId ctx
            let! (req : CreateTransactionRequest) = Json.read ctx
            let! description = TransactionDescription.create req.Description

            let transaction : Transaction = {
                Id = Guid.CreateVersion7 ()
                Amount = Money.roundToCents req.Amount
                Description = description
                Date = req.Date
                IsTransfer = req.IsTransfer
                AccountId = None
                TagId = None
            }

            let! () = insert queryContext transaction userId

            log.Info (
                $"Created transaction %O{transaction.Id}",
                LogProp.prop "transactionId" (transaction.Id.ToString ())
            )

            ctx.SetStatusCode 201
            do! Json.write ctx (TransactionResponse.fromDomain transaction)
        })
```

Read it as a script: bind the user id, decode the request, validate the
description, build the transaction, insert it, log it, respond. Every `let!`
step can fail, and any failure short-circuits the rest: no nesting, no
try/catch, no null checks. Yet it reads like the sequential imperative code
you already know. That's the payoff of the `taskResult` computation expression,
stop 4's `let!` sugar again, here from FsToolkit over `Task<Result<...>>`: the
safety of typed errors with the reading experience of plain code.

The pragmatism isn't just syntax. Notice what the same file does at the edge of
the platform (`CreateTransaction.fs`):

```fsharp
try
    let! _ =
        insertTask queryContext {
            for t in main.Transactions do
                entity row
        }
    return Ok ()
with
| :? SqliteException as ex when ex.SqliteErrorCode = 19 ->
    return Error (Conflict $"A transaction with ID %O{transaction.Id} already exists")
| ex -> return Error (DatabaseError (ex.Message, Some ex))
```

SQLite's constraint violation arrives as a .NET exception and is folded into
the domain error type at the boundary. `try/with` and type-test patterns are
fine here; FP is about where errors live, not about avoiding the platform.

And configuration is the plain .NET way (`Config.fs`):

```fsharp
[<CLIMutable>]
type OidcConfig = {
    [<Required>]
    Authority : string

    [<Required>]
    ClientId : string
    ...
}
```

`[<Required>]` is stock .NET DataAnnotations (ASP.NET validates it at startup
and refuses to boot on failure); `[<CLIMutable>]` lets the framework's config
binder populate the record. Deliberate compromises at the boundary. FP shows
up where it pays off, not as ceremony.

Why it matters: the entry cost is low. F# gives you FP benefits on top of the
platform you already know: no different runtime, no pure-functional stack, no
reimplementing the ecosystem.

### 8. Logs as data

In typical code, logging is a side effect in the middle of your logic: a
singleton `Logger` injected into classes, writing to a sink at the moment each
call runs. To find out what a function would log, you must run it with a real
logger attached, and the log's timing and destination are decided at every call
site. This backend treats the log as data instead. Handlers record what
happened into a request-scoped `RequestLog` (`RequestLogging.fs`), and nothing
is written anywhere until the request ends:

```fsharp
type RequestLog () =
    let entries = ResizeArray<LogEntry> ()

    member _.Info (msg : string, [<ParamArray>] props : LogProperty[]) =
        entries.Add {
            Level = LogLevel.Info
            Message = msg
            Properties = List.ofArray props
            Timestamp = DateTimeOffset.UtcNow
        }
```

Handlers append structured facts to it, like `let log = RequestLog.fromContext ctx`
followed by `log.Info (...)`, and never touch a logger or a sink. When the request
finishes, the middleware emits the whole collection as **one** JSON log line per
request, with the entries as an array:

```fsharp
logger.Write (
    serilogLevel,
    "{Method} {RequestPath} {StatusCode} {ElapsedMs} {RequestId} {UserId} {@Log}",
    ...)
```

Three ideas:

- **Logs are data.** A log entry is a record (`Level`, `Message`, `Properties`,
  `Timestamp`); appending is a pure data operation. Emission is a single,
  central side effect, the same "side effects at the edges" idea as the
  client's effect interpreter (stop 9).
- **Nothing to inject.** Like the `QueryContextFactory` (stop 13), the log
  arrives as part of the request context instead of a dependency you
  construct, register, and mock. Handlers ask for it when they need it.
- **Pragmatic mutation.** The buffer is a mutable `ResizeArray`, deliberately.
  If an exception unwinds the stack mid-request, a purely immutable
  accumulation would be lost with the discarded references, so the mutable buffer
  preserves every message logged up to the point of failure. Same philosophy as
  stop 7: FP where it pays, the platform where it doesn't.

The result: a request's core produces data, its response and log entries, and
the middleware turns them into one JSON line per request at the edge. No
handler knows a sink exists, and you never go fishing for related lines among
hundreds of framework log lines.

## Part II: The client (Gleam)

### 9. Effects as data

In a typical web app, components call services directly: `await api.createTransaction(...)`,
`window.localStorage.setItem(...)`, `history.pushState(...)`. That code is
entangled with the outside world, so testing it means mocking.

This app does the opposite. Every page's `update` function returns **pure
data**: the new model, plus a _description_ of what side effects should happen
(`transactions/transactions_page.gleam`):

```gleam
pub fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserSubmittedForm -> #(
      model,
      effect.post("/api/transactions", body, fn(result) {
        case result { Ok(_) -> ... | Error(err) -> ... }
      }),
    )
    ...
  }
}
```

No HTTP happens here, and no browser is touched. The function _describes_ the
request as data; one interpreter (`effect.run` in `effect.gleam`) executes those
descriptions against the real world. This is the Elm architecture's core move,
and Gary Bernhardt's "functional core, imperative shell" is the same idea:

- **No mocking.** A unit test calls `update` with a model and a message, then
  inspects the returned effect to ask "did it request POST /api/transactions?",
  then asserts on the model. The test suite in `client/test/` does exactly this, in
  plain function calls.
- **All the messy reality lives in one place.** The interpreter and a small
  JS shim (`effect_ffi.mjs`) are the _only_ code that talks to the browser.
- **Effects compose.** `Batch` runs several; `map` renames the messages an
  effect produces so children can be embedded in parents.

The idea in one line: _side effects as data you can inspect, transform, and
test._

### 10. Programs as data

Cross-cutting concerns such as auth, persistence, and session expiry are the
classic middleware problem. The typical fix bolts on a framework: decorators,
attributes, AOP, or hooks, each adding indirection to learn and debug. In this
repo, endpoints, effects, and models are all _values_, so these concerns become
plain functions that transform those values.

The server applies auth by mapping over the endpoint list (`Program.fs`):

```fsharp
let withAuth endpoints =
    Seq.map (addFilter Auth.requireAuth) endpoints
```

The client rewrites the effect tree so a 401 becomes a redirect to login
(`app.gleam`), recursing through `Batch`:

```gleam
effect.HttpRequest(callback: original, ..) as request ->
  effect.HttpRequest(..request, callback: fn(result) {
    case result {
      Error(http_effect.HttpError(status: 401, ..)) -> SessionExpired
      _ -> original(result)
    }
  })
```

And the `update` function itself is wrapped in decorators that post-process its
result:

```gleam
let #(new_model, custom_effect) =
  update(model, msg)
  |> with_local_storage   // persist the whole model after every update
  |> with_auth_redirect   // turn 401s into login redirects
```

Three different concerns, auth, persistence, and session expiry, become three
one-liners, and none of them needed a framework. This is "the program is data"
in practice, and it's why neither half of this stack needs a DI container or a
middleware framework.

### 11. App state as data

In a typical app, "the state" is scattered across components, stores, and
globals, so persisting it across a reload means saving pieces and hoping you
got them all. The OOP version of "save the whole app and restore it" needs
serialization annotations and a snapshotting strategy just to approximate
what's really in memory. Here the model is plain data, with no methods and no
hidden state, so persisting the entire application state is a few lines:
serialize it to JSON, save it to localStorage after every update, parse it back
on startup. Rich Hickey draws the same line in "The Value of Values": values
are immutable and self-contained, so they can be compared, cached, serialized,
and passed between threads freely, while objects carry identity and mutable
state.

### 12. Routes and codecs as values

In typical web apps, the URL is a string: parsed with regexes, compared with
string literals scattered through components, and a typo silently renders a
blank page. Here, routes are a type with a bidirectional mapping (`route.gleam`):

```gleam
pub type Route { Transactions | NotFound }

pub fn to_string(route: Route) -> String { ... }
```

The URL is parsed into this type once; the compiler guarantees every
`case` on a route handles every route. Unknown paths aren't a string-comparison
footgun; they're the `NotFound` case you're forced to handle.

The same idea applies to JSON: decoders are composed values, not reflection.
`model_decoder()` is built from small `decode.field(...)` pieces, so the
serialization logic is explicit, readable, and type-checked, instead of
"annotate the class and hope the serializer agrees." This is what Alexis King
calls "parse, don't validate": the boundary checks the input once and hands the
rest of the program a value that has already been checked, rather than a raw
string every consumer must re-verify.

## Part III: Shared patterns

### 13. No DI container

In typical codebases, dependencies get a container: interfaces so they can be
mocked, constructor injection, and registration wiring to maintain. That wiring
is a second description of the dependency graph. When it disagrees with
reality, the failure shows up at runtime, at the moment the chain is first
resolved. The FP answer is simpler: _pass what you need_. The server creates
its `QueryContextFactory` once in `Program.fs` and threads it into each
operation's `endpoint` function, grouping them by HTTP method:

```fsharp
let transactionEndpoints =
    [
        GET [ ReadTransaction.endpoint queryContext; ReadAllTransactions.endpoint queryContext ]
        POST [ CreateTransaction.endpoint queryContext ]
        PUT [ UpdateTransaction.endpoint queryContext ]
        DELETE [ DeleteTransaction.endpoint queryContext ]
    ]
    |> withAuth
```

Nothing is hidden behind an interface for mockability, because nothing is
mockable that matters. The test suite builds the _same_ endpoints and runs
them against an in-memory database (`server-tests.md`):

```fsharp
TestApp.create (TestAppConfig.empty |> TestAppConfig.withTransactions)
```

Testability is a property of the design, not of a mocking framework. Both
halves of the stack follow this: dependencies flow in at the edges, logic stays
pure in the middle.

### 14. Testing without mocks

- **Server:** Expecto tests hit the real endpoints (minus auth) over a real
  in-memory SQLite database. No fakes, no stubs. See `server/tests/`.
- **Client:** gleeunit tests call `update` directly and assert on the returned
  model and effect, with no browser, DOM, or HTTP server anywhere in the loop.
  See `client/test/`.

The tests aren't a parallel universe that re-implements the app's behavior;
they exercise the same functions production uses. This works because the middle
of the program is pure data transformation; in OOP, state hides behind methods,
so tests fall back to mocking the calls between objects, and mocks, as Martin
Fowler argued in "Mocks Aren't Stubs", couple tests to implementation details
you'd otherwise be free to change.

## Part IV: The FP spectrum

Two languages, one philosophy, two strictness levels:

|               | F# (server)                                    | Gleam (client)                                 |
| ------------- | ---------------------------------------------- | ---------------------------------------------- |
| Null          | You avoid it (`Option`)                        | Doesn't exist                                  |
| Exceptions    | Avoided (`Result`), interop with .NET          | Don't exist                                    |
| Objects       | Available, used sparingly                      | Don't exist                                    |
| Purity        | Encouraged, enforced by convention             | Enforced by the language                       |
| Concurrency   | Opt-in: pure functions are easy to parallelize | No shared mutable state, nothing to race on    |
| Reading style | Computation expressions feel imperative        | `use` sugar makes callbacks read straight-line |

The Gleam half shows that a language can simply _remove_ null, exceptions, and
inheritance, and the app gets simpler: a whole class of bugs
(NullPointerException, uncaught exceptions, `instanceof` checks) is
unrepresentable. The F# half shows the pragmatic path: you don't need to
abandon your platform to get most of the benefits. You need types, values over
exceptions, and data over classes.

## What FP costs you

FP isn't a strict upgrade. It trades one set of problems for another, and the
costs show up in this repo too. F# and Gleam sit at different points in the FP
spectrum, so they pay different bills.

**The learning curve is real.** Everything on display here, `Result`/`Option`,
computation expressions, `|>`, and pattern matching, is foreign to most working
developers, and type signatures can look like algebra. It's not that the
concepts are hard; it's that almost nothing transfers from OOP: loops become
folds and recursion, "mutate the object" becomes "build a new value." This doc
exists because reading the codebase unaided is hard for newcomers. The repo
mitigates with `///` doc comments on nearly every type and function, but the
tax is paid on every new pair of eyes, including your future self.

**Gleam's bill is a young ecosystem.** Gleam is a small language with a small
package registry, and only a fraction of its packages even target the browser.
This repo doesn't use React Router, axios, Redux, or a toast library. It has
`route.gleam`, `http_effect.gleam`, `effect.gleam`, and `toast.gleam` instead
(stops 9 and 12), each hand-rolled, plus hand-written JS glue
(`effect_ffi.mjs`) where the language ends. In the mainstream ecosystem you'd
`npm install` your way out; here, infrastructure is a feature you maintain. The
upside is full control and a tiny dependency tree; the cost is that any
mainstream library you need, you write yourself.

**F#'s bill is platform friction.** The .NET interop is one-directional: F#
calling C# is seamless, but C# consuming F# types is awkward: discriminated
unions need helper properties and `when` guards, modules need attributes, and
options and tuples don't map cleanly. That's invisible here, because the whole
server is F#; it starts to hurt when C# teams must consume F# code, or when a
mixed codebase forces you to maintain a "functional core, imperative shell"
boundary by hand.

**The compiler's help is also a bill.** Exhaustive matching means every
consumer of a type must be updated when it changes (stop 6). That's safety,
but it's also more files touched per change. A solo dev adding a field to
`Transaction` pays for the guarantee every time, whether or not they needed it.

**Debugging feels different, not easier.** A debugger built around breakpoints
and mutable locals assumes there's a "current" value sitting at each line; a
pipeline or a pattern match doesn't pause at intermediate variables the same
way, so stepping through `description.Trim () |> nonEmpty |> Result.bind
acceptableLength` (stop 5) means stepping into each function instead of
watching one variable change across an `if` chain. Structured logs (stop 8)
and property tests (stop 5) cover a lot of this repo's cases, but the "set a
breakpoint, watch the variable" reflex from imperative code doesn't transfer
directly.

**Performance is a consideration, not a given.** Immutability and pure data
structures bring allocation and GC pressure, and structural equality on records
is easy to trigger in hot paths. The repo shows both sides: the logging buffer
is a mutable `ResizeArray` (stop 8) precisely because immutable accumulation
was the wrong tool, and amounts are `decimal` serialised as strings: correct,
but not the cheapest wire format. For a database-backed, network-bound app like
this one, the costs rarely matter; they're the whole story in real-time
graphics, tight numeric loops, or anything with hard latency limits.

**Cleverness is a hazard.** FP rewards abstraction, from monads and type-level
gymnastics to generic pipelines, and it's easy to make simple things clever
instead of clear. This repo deliberately keeps its F# pragmatic (stop 7) and
its Gleam simple: the `Effect` type is a hand-written, 16-variant value type,
not a category-theory lecture.

**Hiring and onboarding are harder.** The pool of developers who know Gleam is
tiny, and even F# developers are a minority in .NET shops. An experienced OOP
engineer doesn't ramp in a week; the concepts in this doc are roughly the
first month of the job. Fine for a solo project; a real cost for a team.

These costs explain why the repo applies FP selectively: types, pure logic, and
data transformations in the domain; mutable buffers, .NET interop, and
framework tooling at the boundaries (stops 7 and 8). They're also why FP
genuinely doesn't pay everywhere: one-off scripts, real-time rendering, and
tight numeric loops buy little from the discipline and pay the allocation
costs.

## Where to look next

- `docs/architecture.md`: the mechanical how-it-works counterpart to this tour.
- `docs/database.md`, `docs/server-tests.md`, `docs/e2e-tests.md`: the details.
- Start reading `Feature/Transaction/ReadTransaction.fs` (server) and
  `transactions/transactions_page.gleam` (client): the two reference
  implementations of everything above.

### Further reading

This tour compresses arguments others have made at length. If a stop made you
want the full version:

- Rich Hickey, _Simple Made Easy_ (2011): why state couples a value to a point
  in time; the foundational argument for immutability.
- Rich Hickey, _The Value of Values_ (2012): values vs. objects (stops 1 and 11).
- Yaron Minsky, _Effective ML_ (Jane Street, 2010): "make illegal states
  unrepresentable"; Scott Wlaschin's _Designing with types_ brings it to F#
  (stops 1 and 2).
- Philip Wadler, _The Expression Problem_ (1998): why data and operations
  can't both be open; the trade behind stop 3.
- Joel Spolsky, _Exceptions_ (2003): exceptions as invisible control flow
  (stop 4).
- Rob Pike, _Errors are values_ (2015): "errors can be programmed" like any
  other value (stop 4).
- Joe Duffy, _The Error Model_ (2016): "an exception ... is just a different
  kind of return value"; failure modes as part of the signature (stop 4).
- Tony Hoare, _Null References: The Billion Dollar Mistake_ (2009): the origin
  of the problem `Option` solves (stop 2).
- Ben Moseley and Peter Marks, _Out of the Tar Pit_ (2006): most complexity in
  software is accidental, and state and control are its biggest generators.
- Gary Bernhardt, _Boundaries_ (2012): "functional core, imperative shell"
  (stop 9).
- Alexis King, _Parse, don't validate_ (2019): the decoder philosophy of stop 12.
- Mark Seemann, _From dependency injection to dependency rejection_ (2017): the
  testing argument behind stops 13 and 14.
- Martin Fowler, _Mocks Aren't Stubs_ (2007): why interaction-based tests
  couple to implementation details (stop 14).
