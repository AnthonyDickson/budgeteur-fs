# Functional Programming in Practice

<!--toc:start-->

- [Functional Programming in Practice](#functional-programming-in-practice)
  - [Part I — The server (F#)](#part-i-the-server-f)
    - [1. Make invalid states unrepresentable](#1-make-invalid-states-unrepresentable)
    - [2. Errors as values](#2-errors-as-values)
    - [3. Pipelines](#3-pipelines)
    - [4. Compiler as a pair programmer](#4-compiler-as-a-pair-programmer)
    - [5. Pragmatic FP](#5-pragmatic-fp)
    - [6. Logs as data](#6-logs-as-data)
  - [Part II — The client (Gleam)](#part-ii-the-client-gleam)
    - [7. Effects as data](#7-effects-as-data)
    - [8. Programs as data](#8-programs-as-data)
    - [9. App state as data](#9-app-state-as-data)
    - [10. Routes and codecs as values](#10-routes-and-codecs-as-values)
  - [Part III — Shared patterns](#part-iii-shared-patterns)
    - [11. No DI container](#11-no-di-container)
    - [12. Testing without mocks](#12-testing-without-mocks)
    - [13. Small patterns](#13-small-patterns)
  - [Part IV — The FP spectrum](#part-iv-the-fp-spectrum)
  - [What FP costs you](#what-fp-costs-you)
  - [Where to look next](#where-to-look-next)
    - [Further reading](#further-reading)

<!--toc:end-->

A tour of this codebase for developers who are **curious about functional
programming (FP)** but don't necessarily know it. You don't need to read F# or
Gleam fluently — every idea is explained in plain terms, with short annotated
snippets and file pointers. If you're an FP veteran, most of this is familiar
territory; the value here is in seeing it applied to a real product.

The stack has two halves: an F#/Oxpecker backend and a Gleam/Lustre
SPA frontend. F# is _pragmatic_ FP — you can dip in and out, objects interop,
and computation expressions keep things looking familiar (stop 5). Gleam is
_strict_ FP — no null, no exceptions, no inheritance, nothing. The contrast
gets its own section at the end.

FP is easy to write off as a niche that industry doesn't really use, but the
record says otherwise. Jane Street runs its trading platform on OCaml; WhatsApp
and Discord serve hundreds of millions of real-time users on Erlang and Elixir;
RabbitMQ, one of the most widely deployed message brokers in existence, is
Erlang; and Ericsson's AXD301 telephone switch was reported to achieve "nine
nines" of availability. F# has its own production record on .NET, particularly
in finance. This tour covers the ideas behind those systems in the context of
this codebase.

Every stop follows the same shape: the problem it solves in typical
OOP/imperative codebases, how this repo does it instead, and why you should
care. Skip around freely. If a claim makes you want the full argument, the
original sources are collected in "Further reading" at the end.

## Part I — The server (F#)

### 1. Make invalid states unrepresentable

The classic OOP instinct is to model failure with a class hierarchy:
`NotFoundException`, `ValidationException`, `DatabaseException`, all extending a
base. The hierarchy is open-ended: any library can add a subclass you have
never seen, and "handle failure" means knowing about classes that may not exist
yet. Here, "what can go wrong" is one closed data type with named cases
(`DomainError.fs`):

```fsharp
type DomainError =
    | ValidationFailed of string
    | NotFound of string
    | Conflict of string
    | UserNotFound
    | DatabaseError of string * exn option
    | UnhandledException of string * exn option
```

And the API response shape is one record (`ApiError.fs`):

```fsharp
type ApiError = { Error: string; Details: string; StatusCode: int option; RequestId: string }
```

No inheritance, no polymorphism, no base class to remember. Two consequences
that don't exist in the class-hierarchy world:

- **The full set of failures is discoverable** — read one type and you know
  everything a handler can do.
- **The compiler enforces completeness** — any code that handles a
  `DomainError` must cover every case (see stop 4).

The phrase for this is _"make invalid states unrepresentable"_ — coined by Yaron
Minsky of Jane Street and popularized in the F# world by Scott Wlaschin: if a
value of this type exists, it is a valid, meaningful error — there is no way to
construct a nonsense one.

### 2. Errors as values

In most codebases, failure is an exception: something throws, something catches,
and the two often disagree about what failure means. A method signature doesn't
say what it can throw, so the coupling between "can fail here" and "handled
there" is invisible until runtime. Here, failure is part of the type. Handlers
never throw; they return a `Result` — a value that is _either_ a success (`Ok`)
_or_ a failure (`Error`). Here is an entire endpoint
(`Transaction/Endpoints/Read.fs`):

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

Note the shapes: the handler reads a user id, fetches a transaction, and
pattern-matches it. **There is no try/catch, no null check, and no code path
for "the database exploded".** What happens if the database is unreachable? The
`get` function returns an `Error (DatabaseError ...)`, and the `!` in `let!`
short-circuits the rest of the handler automatically.

Errors flow _through_ the program as values, and one central place decides what
they become on the wire — `Endpoint.handler` (`Endpoint.fs`):

```fsharp
match! body with
| Ok () -> ()
| Error (ValidationFailed err) -> ctx.Response.StatusCode <- 400
| Error (NotFound err)         -> ctx.Response.StatusCode <- 404
| Error (Conflict err)         -> ctx.Response.StatusCode <- 409
| ...all other cases...
```

So every endpoint in the app returns a consistent, machine-readable JSON error
(`{ Error, Details, StatusCode, RequestId }`) without each handler re-implementing
error handling. Compare this with try/catch blocks sprinkled through controllers, each formatting its own error shape.

Why it matters: failure is _data_. It can be returned, transformed, logged,
tested, and passed around — the same tools that work on any other value.

### 3. Pipelines

In imperative code, a multi-step transformation becomes a trail of temporary
variables — `let t1 = ...; let t2 = ...` — and reading it means tracing each
assignment. This repo does the opposite. The pipe operator `|>` threads a value
through functions top-to-bottom, and both languages in this stack have it. The
clearest example is description validation (`Transaction/Validation.fs`) — three
steps, one line, read as a sentence:

```fsharp
let validateAndTrimDescription (description : string) =
    description.Trim () |> nonEmpty |> Result.bind acceptableLength
```

"Trim it, then require it to be non-empty, then check the length." Each step is
a plain function, and `Result.bind` makes a failed step stop the chain — an
`Error` skips the rest, so there are no early returns or nested `if`s. Written
imperatively, the same logic is a `Trim()` call plus two `if` checks, with the
values threaded through by hand.

The same style appears throughout the client. Parsing a URL into a route
(`route.gleam`):

```gleam
path
|> string.lowercase
|> uri.path_segments
|> from_path_segments
```

Reading a database row into the API type (`Transaction/Endpoints/Read.fs`):

```fsharp
let transaction = result |> Option.map Transaction.fromRow
```

The tell-tale sign of the style: no temporary variables, and the reading order
is the execution order. Each step is a named, independently testable function —
"take X, then do Y, then Z" instead of `let t1 = ...; let t2 = ...; if ...`.

Why it matters: data flows forward, the order is the reading order, and every
intermediate step is a reusable, testable function — you follow one value
through named steps instead of juggling hidden intermediate state.

### 4. Compiler as a pair programmer

In most codebases, "handle every case" is a discipline. An enum or error code
gains a new value, and every `switch` that should have handled it is found by
searching — or by a bug report. In this repo, the compiler does the searching.
Two concrete results of strong typing + exhaustive matching:

**Miss a case, and it won't compile.** In `Endpoint.fs`, every `DomainError`
case is handled explicitly. Add a new case to the type tomorrow and the
compiler will point at every place that must handle it. In OOP terms: the
compiler enforces the "update all subclasses" step of the Visitor pattern.

**The schema and the code cannot drift.** Tables are defined in migration SQL
(`migrations/001_add_core_data_models.sql`) using special type hints:

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

### 5. Pragmatic FP

FP is usually pitched as all-or-nothing: to get the benefits you adopt a pure
language, a different runtime, and re-implement the ecosystem. This repo is the
counter-argument — a real ASP.NET Core app where "pragmatic" means FP where it
pays, and the platform where it doesn't. Here is a whole endpoint, verbatim
(`Transaction/Endpoints/Create.fs`):

```fsharp
let private handler (queryContext : QueryContextFactory) : EndpointHandler =
    Endpoint.handler (fun ctx ->
        taskResult {
            let log = RequestLog.fromContext ctx
            let! userId = Auth.getUserId ctx
            let! (req : CreateTransactionRequest) = Json.read ctx
            let! description = Validation.validateAndTrimDescription req.Description

            let transaction = {
                Id = Guid.CreateVersion7 ()
                Amount = Money.roundToCents req.Amount
                Description = description
                Date = req.Date
                IsTransfer = req.IsTransfer
                AccountId = None
                CategoryId = None
            }

            let! () = insert queryContext transaction userId

            log.Info (
                $"Created transaction %O{transaction.Id}",
                LogProp.prop "transactionId" (transaction.Id.ToString ())
            )

            ctx.SetStatusCode 201
            do! Json.write ctx transaction
        })
```

Read it as a script: bind the user id, decode the request, validate the
description, build the transaction, insert it, log it, respond. Every `let!`
step can fail, and any failure short-circuits the rest — no nesting, no
try/catch, no null checks — yet it reads like the sequential imperative code
you already know. That's the payoff of the `taskResult` computation expression
(FsToolkit's sugar over `Task<Result<...>>`): the safety of typed errors with
the reading experience of plain code.

The pragmatism isn't just syntax. Notice what the same file does at the edge of
the platform (`Create.fs`):

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
fine here — FP is about where errors live, not about avoiding the platform.

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
binder populate the record. Deliberate compromises at the boundary — FP shows
up where it pays off, not as ceremony.

Why it matters: the entry cost is low. F# gives you FP benefits on top of the
platform you already know — no different runtime, no pure-functional stack, no
reimplementing the ecosystem.

### 6. Logs as data

Logging usually means a global: a singleton `Logger` injected into every class,
writing lines to a sink as they happen. This backend does the opposite. A
request-scoped `RequestLog` lives in the HTTP context (`RequestLogging.fs`):

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

Handlers append structured facts to it — `let log = RequestLog.fromContext ctx`
then `log.Info (...)` — and never touch a logger or a sink. When the request
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
  central side effect — the same "side effects at the edges" idea as the
  client's effect interpreter (stop 7).
- **No injected logger.** Like the `QueryContextFactory` (stop 11), the log is
  part of the request context rather than a dependency to inject and mock.
  Handlers ask for it when they need it.
- **Pragmatic mutation.** The buffer is a mutable `ResizeArray`, deliberately.
  If an exception unwinds the stack mid-request, a purely immutable
  accumulation would be lost with the discarded references — the mutable buffer
  preserves every message logged up to the point of failure. Same philosophy as
  stop 5: FP where it pays, the platform where it doesn't.

The result: one line per request with its logs bundled together, so you never
go fishing for related lines among hundreds of framework log lines.

## Part II — The client (Gleam)

### 7. Effects as data

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
descriptions against the real world. This is the Elm architecture's core move
(Gary Bernhardt's "functional core, imperative shell" is the same idea):

- **No mocking.** A unit test calls `update` with a model and a message, then
  inspects the returned effect — "did it request POST /api/transactions?" — and
  asserts on the model. The test suite in `client/test/` does exactly this, in
  plain function calls.
- **All the messy reality lives in one place.** The interpreter and a small
  JS shim (`effect_ffi.mjs`) are the _only_ code that talks to the browser.
- **Effects compose.** `Batch` runs several; `map` renames the messages an
  effect produces so children can be embedded in parents.

The idea in one line: _side effects as data you can inspect, transform, and
test._

### 8. Programs as data

Cross-cutting concerns — auth, persistence, session expiry — are the classic
middleware problem, and the typical fix bolts on a framework: decorators,
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

Three different concerns (auth, persistence, session expiry), three one-liners,
zero framework involvement. This is "the program is data" in practice, and
it's why neither half of this stack needs a DI container or a middleware
framework.

### 9. App state as data

In a typical app, "the state" is scattered across components, stores, and
globals, so persisting it across a reload means saving pieces and hoping you got
them all. Here the model is plain data — no methods, no hidden state — so
persisting the _entire application state_ is a few lines: serialize it to JSON,
save it to localStorage after every update, parse it back on startup. "Save the
whole app and restore it" — famously hard in OOP, needing serialization
annotations and a snapshotting strategy — is a few lines here, because state is
data and saving it is just serialization. Rich Hickey draws the same line in
"The Value of Values": values are immutable and self-contained, so they can be
compared, cached, serialized, and passed between threads freely, while objects
carry identity and mutable state.

### 10. Routes and codecs as values

In typical web apps, the URL is a string: parsed with regexes, compared with
string literals scattered through components, and a typo silently renders a
blank page. Here, routes are a type with a bidirectional mapping (`route.gleam`):

```gleam
pub type Route { Transactions | NotFound }

pub fn to_string(route: Route) -> String { ... }
```

The URL is parsed into this type once; the compiler guarantees every
`case` on a route handles every route. Unknown paths aren't a string-comparison
footgun — they're the `NotFound` case you're forced to handle.

The same idea applies to JSON: decoders are composed values, not reflection.
`model_decoder()` is built from small `decode.field(...)` pieces — the
serialization logic is explicit, readable, and type-checked, instead of
"annotate the class and hope the serializer agrees." This is what Alexis King
calls "parse, don't validate": the boundary checks the input once and hands the
rest of the program a value that has already been checked, rather than a raw
string every consumer must re-verify.

## Part III — Shared patterns

### 11. No DI container

In typical codebases, dependencies get a container: interfaces so they can be
mocked, constructor injection, and registration wiring to maintain. The FP
answer is simpler — _pass what you need_. The server creates its
`QueryContextFactory` once in `Program.fs` and threads it into each slice's
`endpoints` function:

```fsharp
let transactionEndpoints = Transaction.Api.endpoints queryContext |> withAuth
```

Nothing is hidden behind an interface for mockability, because nothing is
mockable that matters — the test suite builds the _same_ endpoints and runs
them against an in-memory database (`server-tests.md`):

```fsharp
TestApp.create (TestAppConfig.empty |> TestAppConfig.withTransactions)
```

Testability is a property of the design, not of a mocking framework. Both
halves of the stack follow this: dependencies flow in at the edges, logic stays
pure in the middle.

### 12. Testing without mocks

- **Server:** Expecto tests hit the real endpoints (minus auth) over a real
  in-memory SQLite database. No fakes, no stubs — `server/tests/`.
- **Client:** gleeunit tests call `update` and assert on the returned model and
  effect. No browser, no DOM, no HTTP server — `client/test/`.

The tests aren't a parallel universe that re-implements the app's behavior —
they exercise the same functions production uses. This works because the middle
of the program is pure data transformation; in OOP, state hides behind methods,
so tests fall back to mocking the calls between objects — and mocks, as Martin
Fowler argued in "Mocks Aren't Stubs", couple tests to implementation details
you'd otherwise be free to change.

### 13. Small patterns

- **The timeout race** (`Status.fs`): the status endpoint races a database
  probe against a timer with `Task.WhenAny`, so an unresponsive database can't
  hang a healthcheck. A five-line idiom for "do this, but never longer than
  that".
- **Business rules in the schema** (`migrations/001_add_core_data_models.sql`):
  a SQL trigger deletes a transaction from the tagging queue the moment its
  category is set. Some invariants are cheapest to declare in the database
  itself.
- **Child-to-parent messages** (`out_msg.gleam`): pages can ask the shell for
  shell-level behavior (currently: show a toast) via a typed `OutMsg` value,
  keeping the message flow explicit — no global event bus, no pub/sub.

## Part IV — The FP spectrum

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
abandon your platform to get most of the benefits — you need types, values over
exceptions, and data over classes.

## What FP costs you

FP isn't a strict upgrade — it trades one set of problems for another, and the
costs show up in this repo too. F# and Gleam sit at different points in the FP
spectrum, so they pay different bills.

**The learning curve is real.** Everything on display here — `Result`/`Option`,
computation expressions, `|>`, pattern matching — is foreign to most working
developers, and type signatures can look like algebra. It's not that the
concepts are hard; it's that almost nothing transfers from OOP: loops become
folds and recursion, "mutate the object" becomes "build a new value", and the
habits that served you for years are the ones the compiler now punishes. This
doc exists because reading the codebase unaided is hard for newcomers. The repo
mitigates with `///` doc comments on nearly every type and function, but the
tax is paid on every new pair of eyes — including your future self.

**Gleam's bill is a young ecosystem.** Gleam is a small language with a small
package registry, and only a fraction of its packages even target the browser.
This repo doesn't use React Router, axios, Redux, or a toast library — it has
`route.gleam`, `http_effect.gleam`, `effect.gleam`, and `toast.gleam` instead
(stops 7 and 10), each hand-rolled, plus hand-written JS glue
(`effect_ffi.mjs`) where the language ends. In the mainstream ecosystem you'd
`npm install` your way out; here, infrastructure is a feature you maintain. The
upside is full control and a tiny dependency tree; the cost is your own time —
and any mainstream library you need, you write yourself.

**F#'s bill is platform friction.** The .NET interop is one-directional: F#
calling C# is seamless, but C# consuming F# types is awkward — discriminated
unions need helper properties and `when` guards, modules need attributes, and
options and tuples don't map cleanly. That's invisible here, because the whole
server is F#; it starts to hurt when C# teams must consume F# code, or when a
mixed codebase forces you to maintain a "functional core, imperative shell"
boundary by hand.

**The compiler's help is also a bill.** Exhaustive matching means every
consumer of a type must be updated when it changes (stop 4). That's safety —
and it's also more files touched per change. A solo dev adding a field to
`Transaction` pays for the guarantee every time, whether or not they needed it.

**Performance is a consideration, not a given.** Immutability and pure data
structures bring allocation and GC pressure, and structural equality on records
is easy to trigger in hot paths. The repo shows both sides: the logging buffer
is a mutable `ResizeArray` (stop 6) precisely because immutable accumulation
was the wrong tool, and amounts are `decimal` serialised as strings — correct,
but not the cheapest wire format. For a database-backed, network-bound app like
this one, the costs rarely matter; they're the whole story in real-time
graphics, tight numeric loops, or anything with hard latency limits.

**Cleverness is a hazard.** FP rewards abstraction — monads, type-level
gymnastics, generic pipelines — and it's easy to make simple things clever
instead of clear. This repo deliberately keeps its F# pragmatic (stop 5) and
its Gleam simple: the `Effect` type is a hand-written, 16-variant value type,
not a category-theory lecture.

**Hiring and onboarding are harder.** The pool of developers who know Gleam is
tiny, and even F# developers are a minority in .NET shops. An experienced OOP
engineer doesn't ramp in a week — the concepts in this doc are roughly the
first month of the job. Fine for a solo project; a real cost for a team.

These costs explain why the repo applies FP selectively: types, pure logic, and
data transformations in the domain; mutable buffers, .NET interop, and
framework tooling at the boundaries (stops 5 and 6). They're also why FP
genuinely doesn't pay everywhere: one-off scripts, real-time rendering, and
tight numeric loops buy little from the discipline and pay the allocation
costs.

## Where to look next

- `docs/architecture.md` — the mechanical how-it-works counterpart to this tour.
- `docs/database.md`, `docs/server-tests.md`, `docs/e2e-tests.md` — the details.
- Start reading `Transaction/Endpoints/Read.fs` (server) and
  `transactions/transactions_page.gleam` (client): the two reference
  implementations of everything above.

### Further reading

This tour compresses arguments others have made at length. If a stop made you
want the full version:

- Rich Hickey, _Simple Made Easy_ (2011) — why state couples a value to a point
  in time; the foundational argument for immutability.
- Rich Hickey, _The Value of Values_ (2012) — values vs. objects (stops 1 and 9).
- Yaron Minsky, _Effective ML_ (Jane Street, 2010) — "make illegal states
  unrepresentable"; Scott Wlaschin's _Designing with types_ brings it to F#.
- Tony Hoare, _Null References: The Billion Dollar Mistake_ (2009) — the origin
  of the problem `Option` solves.
- Ben Moseley and Peter Marks, _Out of the Tar Pit_ (2006) — most complexity in
  software is accidental, and state and control are its biggest generators.
- Gary Bernhardt, _Boundaries_ (2012) — "functional core, imperative shell"
  (stop 7).
- Alexis King, _Parse, don't validate_ (2019) — the decoder philosophy of stop 10.
- Mark Seemann, _From dependency injection to dependency rejection_ (2017) — the
  testing argument behind stops 11 and 12.
- Martin Fowler, _Mocks Aren't Stubs_ (2007) — why interaction-based tests
  couple to implementation details (stop 12).
