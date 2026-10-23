# Smart tagging

Design brief for smart tagging: a model, trained on the user's own tagging
decisions, that suggests a tag or a transfer for queued transactions no rule
matches. It records what we decided, why, and what each decision is meant to
achieve. Change it when the reasoning changes.

It extends [auto-tagging](auto-tagging.md), [quick tagging](quick-tagging.md),
and [transfer rules](transfer-rules.md), whose decisions still hold unless this
brief replaces them. Transfer rules already describe where a model fits: a
second origin of proposals, suggested only, using the queue's suggestions,
counts, filter, and approval unchanged.

## Goal

- **Suggestions where rules are silent.** After rules, the queue holds
  transactions no pattern matches. The model suggests a tag for those, learned
  from how the user has tagged similar transactions.
- **Rules stay in charge.** A rule is the user's explicit intent. The model
  never overrides one, and never changes a categorisation without the user.
- **The shipped model is the one we measured.** Model choice is settled by
  experiments on real data, and production computes the same thing the
  experiments evaluated.
- **No new state to keep in sync.** The model is derived from categorisations
  and can always be recomputed from them.

## Ubiquitous language

| Term             | Meaning                                                                                       |
| ---------------- | --------------------------------------------------------------------------------------------- |
| Label            | A categorisation the model learns from: a tag or a transfer whose source decision 4 includes. |
| Residual row     | A transaction no rule matches: the only kind the model suggests for.                          |
| Training set     | The user's transactions that have a label, with each label's weight.                          |
| Class            | What the model can predict: one of the user's tags, or transfer.                              |
| Fit              | Training the model on the training set. Done on every queue read.                             |
| Model suggestion | A suggestion whose origin is the model rather than a rule.                                    |
| Confidence       | The model's probability for its top class.                                                    |
| Threshold        | The confidence below which the model abstains.                                                |
| Abstain          | The model makes no suggestion for a transaction.                                              |
| Seen merchant    | A transaction whose normalised description occurs in the training set. Unseen otherwise.      |

Categorisation, source, rule, and winning rule are defined in
[auto-tagging](auto-tagging.md#ubiquitous-language); queue and batch in
[quick tagging](quick-tagging.md#ubiquitous-language); proposal, policy,
suggestion, suggestion count, approve, and accept in
[transfer rules](transfer-rules.md#ubiquitous-language).

## Decisions

### 1. The model runs in the server, in F#

- **Decision**: feature extraction, training, and inference run inside the
  server process as F# code. There is no separate ML service. If the experiments
  (decision 8) choose sentence embeddings, they are computed with ONNX Runtime
  in the same process, and the Docker image moves from the musl Alpine base to a
  glibc one, because ONNX Runtime ships no musl native library.
- **Why**: the model is small (thousands of rows, tens of classes), so it needs
  no specialised runtime. In-process keeps one deploy, one health check, and one
  owner of user scoping. Suggestions stay part of the queue read rather than a
  network call that can fail or time out.
- **Rejected**:
  - A Python service beside the server. It ships the exact experiment code and
    gives direct access to scikit-learn and sentence-transformers, but fitting
    on every read (decision 5) would send each user's labelled transactions to
    it on every queue read, or give a second process read access to every user's
    data. It also adds a container, an API contract on both sides,
    authentication between services, and a degraded mode for when it is down.
    Revisit if the experiments favour a model F# cannot reasonably host, such as
    a fine-tuned transformer.
  - A service in another functional language (Elixir with Nx, OCaml). The same
    operational costs as Python, with thinner ML tooling and a third language.
- **Goal**: smart tagging adds code, not infrastructure.

### 2. The classifier is hand-rolled; embeddings are optional

- **Decision**: the vectoriser (character and word n-grams, TF-IDF) and a
  weighted multinomial logistic regression with L2 regularisation are pure
  functions in `Domain/`, using MathNet.Numerics' L-BFGS minimiser for the
  optimisation. Embeddings, if used, come from a pretrained sentence model run
  through ONNX Runtime, behind a function the domain receives, as other I/O is.
  A parity test checks the F# fit against scikit-learn's on a fixture dataset.
- **Why**: a linear model over sparse features is a few hundred lines, and
  owning it means every choice the experiments made (tokenisation, weighting,
  regularisation, per-row weights) is reproduced exactly. Pure functions are
  tested like the rule matcher, and contain no reflection, so trimming still
  works. The parity test turns "the shipped model is the one we measured" from
  intent into a check.
- **Cost**: numerical correctness is ours: a stable log-sum-exp, convergence,
  and edge cases such as a single class. Each further model type is more code.
- **Rejected**:
  - ML.NET. Its text featuriser and maximum entropy trainer would mean less of
    our own code, but its featuriser differs from scikit-learn's, so the
    experiments would only approximate production. It is built on a stateful
    context, data views, and reflection over mutable classes, and does not
    support trimming.
  - Exporting a scikit-learn pipeline to ONNX and running only inference. No
    parity gap, but training stays in Python, so the model cannot be fitted on
    read and would need a stored, versioned artefact per user.
- **Goal**: the model is ordinary domain code, and its parity with the
  experiments is tested.

### 3. Features come from the transaction's facts

- **Decision**: candidate features, each kept only if the experiments show it
  helps:
  - character n-grams of the description (3 to 5 characters), TF-IDF weighted;
  - word tokens of the description, with digit runs normalised, so store and
    reference numbers do not split one merchant into many;
  - the amount's sign and a logarithmic bucket of its size;
  - the account;
  - optionally, a sentence embedding of the description.

  The vocabulary and IDF weights come from the training set of each fit.
- **Why**: bank descriptions are codes rather than prose, with merchant names
  truncated, abbreviated, and prefixed by a transaction type (`POS W/D`, `PAY`).
  Character n-grams match these fuzzily, as substring rules do exactly. Sign
  separates income from expense tags; size and account separate tags that share
  a payee. N-grams cannot relate merchants with no text in common (`PAK N SAVE`
  and `COUNTDOWN`); embeddings can, which matters while labels are few and
  unseen merchants are common.
- **Rejected**: the other party, particulars, code, and reference fields. Import
  does not store them, and they cannot be recovered for old rows
  ([transfer rules](transfer-rules.md#deferred)).
- **Goal**: every feature is computable from what `Transactions` already holds.

### 4. Classes are the user's tags and transfer; labels come from categorisations

- **Decision**:
  - **Classes**: one per tag present in the training set, and one for transfer.
    Dismissed is not a class: it means the transaction has no tag, not that it
    belongs to a category, and no proposal ever dismisses
    ([transfer rules](transfer-rules.md) decision 9).
  - **Labels**: `Manual` categorisations at full weight; `Accepted` ones at a
    lower weight; `Detected` transfers at full weight. The `Accepted` weight is
    set by the experiments. Whether `Rule` categorisations are labels is open
    (below), and settled by the experiments with a criterion fixed beforehand
    (decision 8). Until then the default is to leave them out.
  - **Accepting a model suggestion** records `Accepted`, as accepting a rule's
    does. No new source value.
- **Why**: `Manual` labels are the user's own choice. `Accepted` ones are
  confirmations, sometimes given in bulk by approval, so weighting them lower
  limits the model reinforcing its own mistakes. `Detected` transfers are exact,
  since import matched account numbers. Deleting a tag deletes its
  categorisations, so its class disappears from the next fit without any
  cleanup.
- **Open: rule tags as labels**. Both sides make predictions the experiments can
  test, so neither is assumed.
  - **For**: rule tags are likely most of a user's tagged transactions, and they
    cover the most common tags. Without them the model has few or no examples of
    those tags, so it cannot suggest them for new merchants of the same kind
    (Groceries for `PAK N SAVE` when a `COUNTDOWN` rule covers the usual
    supermarket). They are an indirect user decision: the user wrote the pattern
    after seeing its match count and samples (auto-tagging decision 7). The
    model never writes `Rule` categorisations, so there is no feedback loop, and
    fitting on read (decision 5) means a fixed rule and a re-tag correct the
    labels on the next read. The benefit should be largest for embeddings, which
    relate merchants with no text in common.
  - **Against**:
    - Distribution shift: rule tags come from transactions rules matched, while
      the model predicts only for residual rows, which differ by construction. A
      tag common overall may be rare among residual rows because its rule
      already caught most of them, so the model would over-suggest it.
    - No per-transaction review: substring rules over-match (auto-tagging
      decision 1 allows patterns such as `Z`), the rule modal shows five
      samples, not every match, and a wrong rule tag is less visible than an
      untagged row. Training on it spreads the error beyond the rule's matches.
    - Staleness: editing or deleting a rule leaves its tags until the next
      re-tag (auto-tagging decision 5), so some labels reflect a rule the user
      has since changed.
    - Redundancy: a rule tag is a function of the description and the pattern,
      so hundreds of rows from one merchant are one fact, inflating the apparent
      size of the training set and the model's confidence.
    - Spurious tokens: rule-covered rows share incidental text (a city, a card
      prefix, a branch code) that the model may tie to the rule's tag.
  - **Variants compared**: no rule labels; rule labels with each normalised
    description's total weight capped; rule labels uncapped. The cap answers
    redundancy and spurious tokens, so it beating the uncapped variant is a
    check on those arguments. Distribution shift and unreviewed errors are not
    answered by a cap, and are measured directly (decision 8).
- **Goal**: the model learns from the user's decisions, direct or through rules,
  as far as the measurements support, and nothing about categorisations changes
  to support it.
- **Cost**: `Accepted` does not say whether a rule or the model made the
  suggestion, so both are weighted the same.
- **Rejected**:
  - A separate `Accepted` source for model suggestions. A migration and decoder
    change for a distinction the training does not need yet.
  - The `Model` source anticipated by [transfer rules](transfer-rules.md)
    decision 4. Model proposals are suggested only (decision 7), so nothing
    would write it. Add it with the policy change that applies them.

### 5. The model is fitted on every queue read

- **Decision**: when the quick tagging queue is read, the QuickTag slice loads
  the user's training set, fits the model, and predicts for each queued
  transaction no rule matches. No weights are stored. The fit is deterministic:
  the same training set always gives the same model.
- **Why**: with under a thousand labels the fit takes tens of milliseconds, so a
  stored model would only add a second record of what the categorisations
  already say. Fitting on read means a suggestion always reflects the latest
  labels, with no retrain action, staleness, or invalidation, the same reason
  rule suggestions are computed on read ([transfer rules](transfer-rules.md)
  decision 6). Determinism matters because the suggestion filter and the
  approval rely on a second read returning the same suggestions as the first.
- **Rejected**:
  - A stored model with a retrain button. Survives restarts and costs nothing
    per read, but goes stale and needs a staleness indicator and a store.
  - An in-memory cache per user, invalidated on categorisation writes. Saves the
    fit, but every writer of categorisations would have to invalidate it.
  - Online learning, updating the model per label. Always current, but the
    model's state has to be kept in step with categorisations, including edits
    and deletions.
- **Open**: if embeddings are chosen, computing one per description on every
  read is too slow (milliseconds each). Whether they are kept in a derived table
  rebuilt when the model file changes, as transfer rules decision 6 allows, or
  in a per-process cache, is decided after the experiments.
- **Goal**: the model has no state of its own.

### 6. A rule's suggestion beats the model's

- **Decision**: a queued transaction whose description a rule matches gets the
  winning rule's suggestion, as now. The model suggests only for transactions no
  rule matches. Each suggestion carries its origin: a rule, with its pattern, or
  the model.
- **Why**: the user wrote the rule for that description. Letting the model
  override it would make rules unpredictable, against auto-tagging's goal. The
  model is there for the gap rules leave.
- **Rejected**:
  - The higher-confidence suggestion wins. Rules lose their predictability, and
    a rule has no confidence to compare with.
  - Two suggestions per row. The suggestion's shape, the counts, and the
    approval identity would all change.
- **Goal**: adding the model changes nothing for transactions rules cover.

### 7. Model suggestions are suggestions only, and may abstain

- **Decision**:
  - **Policy**: the policy in `Domain/` gains a line: a model proposal is
    suggested, never applied. Tag untagged, re-tag, and import do not run the
    model.
  - **Abstaining**: the model makes no suggestion when:
    - its confidence is below the threshold;
    - the user has fewer labels than a minimum overall;
    - its top class has fewer labels than a minimum. Such classes stay in the
      fit, so their probability is not given to other classes, but are never
      suggested.

    The threshold and both minimums are set from the experiments.
- **Why**: a wrong suggestion costs one click; a wrong applied tag goes
  unnoticed. The policy exists so that applying confident proposals later is a
  change to one function ([transfer rules](transfer-rules.md) decision 3). A
  model trained on a handful of labels, or a class seen twice, is close to
  guessing, and a guess presented as a suggestion trains the user to ignore
  suggestions.
- **Goal**: every model suggestion shown is likely enough to be right to be
  worth a click.

### 8. Model choice is settled offline, in Python, on real data

- **Decision**:
  - **Where**: a Python project in `ml/`, with its tools provided by the Nix dev
    shell. A `just` target exports one user's transactions, categorisations,
    tags, and rules from a local copy of the database to a gitignored folder.
    Results are summarised in this brief; the data never leaves the machine.
  - **Data**: the user's real labelled transactions. The anonymiser's output is
    not used for model choice: it keeps token identity, so n-grams still work,
    but replaces meaning, so embeddings cannot be judged on it. Anonymised
    fixtures serve the automated tests (decision 10). Synthetic data is used
    only to build test shapes, not to choose a model, since its distribution
    would not match real bank text.
  - **Candidates**:
    - features and logistic regression (decision 3);
    - sentence embeddings (such as all-MiniLM-L6-v2 or bge-small) with logistic
      regression or nearest neighbours;
    - both feature sets in one linear model.

    Baselines: the most common class, and the most common label for an exact
    normalised description in the training set. A candidate has to beat the
    lookup to justify itself.
  - **Label variants**: each candidate is run with the rule label variants from
    decision 4.
  - **Split**: rolling origin. For each monthly cutoff, train on every label
    before it and test on the next month, then aggregate over cutoffs. Only
    residual rows with a label the user chose (`Manual` or `Accepted`) are
    scored, since those are the only rows the model suggests for. The scored
    rows are the same in every variant: rule labels only ever enter training.
  - **Metrics**: top-1 accuracy, reported separately for seen and unseen
    merchants; and precision against coverage across thresholds, which sets the
    threshold.
  - **Diagnostics**: the distribution of suggested classes against the true
    labels of residual rows, which measures distribution shift directly; and,
    for any rule known to over-match, precision on residual rows near it with
    and without rule labels.
  - **Choice**: fixed before the first run.
    - **Coverage**: each candidate and variant gets one threshold, set so that
      it suggests for 50% of the scored rows, pooled over all cutoffs.
    - **Measure**: precision at that threshold: correct suggestions over
      suggestions made.
    - **Noise**: a paired bootstrap over the scored rows, with 1,000 resamples
      and a fixed seed. Two options are within noise when the 95% interval of
      their precision difference includes zero.
    - **Winner**: the option with the best precision, unless a simpler option is
      within noise of it, in which case the simplest such option wins. Features
      alone are simpler than embeddings, and embeddings alone simpler than both
      concatenated. For labels, no rule labels is simplest, then uncapped rule
      labels, then capped ones.
    - **Baseline**: the lookup cannot reach 50% coverage, since it suggests only
      for seen merchants. The winner has to beat it on precision at the lookup's
      own coverage, by more than noise, or the lookup ships instead.

    The shipped threshold is chosen afterwards, from the winner's precision
    against coverage (decision 7), and may differ from the comparison's.
- **Why**: in production the model fits on every label up to now and suggests
  for the next import, so each rolling-origin step reproduces that. Every
  transaction is tested once, which matters with under a thousand rows. Random
  k-fold would put most of a merchant's transactions in training and one in
  test, so nearly every test merchant is seen; that overstates accuracy and
  hides the unseen merchants where embeddings would help, biasing the
  comparison. Scoring rule-matched rows would flatter the model with
  transactions it never sees, and would favour training on rule labels for the
  wrong reason. Fixing the criterion before the results are known keeps the
  measure from being chosen to fit them, which matters most for the rule label
  question, where there are plausible arguments on both sides. A fixed coverage
  compares options on the same number of suggestions, so a cautious option
  cannot win by suggesting less. At 50%, the scored rows include unseen
  merchants, where the candidates differ most, while every candidate still has
  confident rows to suggest for. The bootstrap is paired, because every option
  scores the same rows, and it scales with however many rows there are, where a
  fixed margin would not.
- **Cost**: current rules are used for every cutoff, though some were written
  later, so a few rows a rule would not then have matched are left out of
  scoring.
- **Rejected**:
  - Stratified k-fold, for the bias above.
  - Comparing coverage at a fixed precision. Closer to decision 7's goal, but
    with few rows the precision near a threshold is noisy, so the threshold
    found, and the coverage with it, would vary from run to run.
  - A bootstrap over whole test months. It respects correlation within a month,
    but with few months its interval is wide enough to tie most comparisons.
  - A single time split. One small, noisy test set.
  - Experiments in F#. No parity gap, but far fewer ready-made models and tools
    for trying candidates quickly; the parity test closes the gap instead.
- **Goal**: the model is chosen by measured accuracy on the transactions it will
  actually suggest for.

### 9. Model suggestions share the queue's suggestion mechanics

- **Decision**: a model suggestion is a suggestion as
  [transfer rules](transfer-rules.md) decisions 6 and 7 define it. Its identity
  is the suggested categorisation whatever its origin, so counts merge rule and
  model suggestions of the same tag, the filter returns both, and approval
  applies to every row shown. The row shows the "Suggested" label with no
  pattern; the confidence is not shown.
- **Why**: one identity keeps counts, filter, and approval unchanged, which was
  the purpose of making the categorisation the identity. Without a pattern, the
  label alone says the model made the suggestion. Showing a percentage would
  need calibrated probabilities, which the experiments do not optimise for.
- **Rejected**:
  - Counts split by origin, so bulk approval of model suggestions is a separate
    choice. Abstaining (decision 7) and the down-weighting of `Accepted`
    (decision 4) address the risk without a second identity.
  - The nearest labelled description as an explanation. Natural for nearest
    neighbours, not for logistic regression; revisit if that candidate wins.
- **Goal**: quick tagging gains suggestions without gaining concepts.

### 10. Tests

- **Decision**:
  - **Domain**: the vectoriser (n-grams, digit normalisation, TF-IDF); the
    logistic regression (a gradient check, separable data reaching high
    confidence, row weights changing the fit, a single class, determinism);
    abstaining for each of the three reasons; a rule's suggestion beating the
    model's; the policy never applying a model proposal.
  - **Parity**: the `ml/` project fits scikit-learn on an anonymised fixture and
    writes its predicted probabilities as a committed fixture; a server test
    fits the F# model on the same data and compares within a tolerance. CI does
    not run Python.
  - **QuickTag**: the queue suggests from the model only for rows no rule
    matches, trains only on the caller's labels, includes each source with the
    weight decision 4 settles, and counts rule and model suggestions together;
    accepting a model suggestion records `Accepted`.
  - **E2E**: tag enough transactions by hand to pass the minimums, add an
    untagged one like them, and quick tagging marks the expected tag as
    suggested.
- **Why**: the numerical code and the precedence are where confidence is low;
  the endpoint shapes are unchanged from transfer rules. The parity fixture
  keeps the comparison in CI without a Python toolchain there.
- **Goal**: the model's correctness and its agreement with the experiments are
  both checked on every change.

## Consequences

- **Schema**: none, unless embeddings are chosen and kept in a table (decision
  5).
- **Domain**: the vectoriser, the classifier, abstaining, and the policy line,
  beside the proposal and policy.
- **QuickTag slice**: the queue read loads the training set, fits, and adds
  model suggestions where no rule matches. The suggestion's origin gains the
  model case. Counts, filter, and approval are unchanged.
- **Client**: the suggestion decoder accepts the model origin, and the row shows
  "Suggested" without a pattern.
- **Docker**: a glibc base image and the model file, only if embeddings are
  chosen.
- **Dev shell**: Python and the `ml/` project's dependencies.
- **Docs updated with the implementation**:
  - [transfer rules](transfer-rules.md): decision 4's `Model` source (not added,
    decision 4 here) and the smart tagging consequence.
  - [quick tagging](quick-tagging.md): decision 8's suggestion label and the
    deferred suggestions from smart tagging.
  - [deployment](deployment.md): the base image, if it changes.
  - [testing strategy](testing-strategy.md): the parity fixture.

## Open questions

Settled by the experiments, then recorded in the decisions above:

- Which candidate, and which features, ship.
- Whether `Rule` categorisations are labels, and if so whether capped per
  normalised description and at what weight (decision 4).
- The `Accepted` weight, and whether `Detected` transfers help or only add easy
  rows.
- The threshold, and the overall and per-class label minimums.
- If embeddings ship: which model, and how they are kept.

## Deferred

- **Applying confident model proposals.** A policy change, with a `Model` source
  and re-tag recomputing it, once precision at a threshold is known in use.
- **Showing confidence.** Needs calibrated probabilities.
- **Ranking a row's tag buttons by the model.** Rejected by quick tagging
  decision 5 to keep positions stable; a model makes it possible, not desirable.
- **Model suggestions in the transaction form.** A suggested tag for a
  transaction being entered by hand.
- **Fine-tuned or larger models.** Revisit the Python service (decision 1) if
  linear models over frozen features are not good enough.
- **Other party fields.** Would improve the features once import stores them.

## Assumptions

- A user has at most a few thousand labels and tens of tags, so fitting on every
  queue read is fast.
- Descriptions carry most of the signal; amount and account refine it.
- One user's labelled data is representative enough of their future transactions
  that past accuracy predicts future accuracy.
