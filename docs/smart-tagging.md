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
  server process as F# code. There is no separate ML service. The experiments
  (decision 8) chose a model without sentence embeddings, so there is no ONNX
  Runtime, model file, or change of Docker base image.
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

### 2. The classifier is hand-rolled

- **Decision**: the vectoriser (decision 3) and a weighted multinomial logistic
  regression with L2 regularisation are pure functions in `Domain/`, using
  MathNet.Numerics' L-BFGS minimiser for the optimisation. They reproduce
  scikit-learn's `TfidfVectorizer`, `OneHotEncoder`, and `LogisticRegression` as
  the experiments configured them:
  - **Vectoriser**: smoothed IDF from unweighted row counts; each text block
    normalised to unit length on its own; terms and categories not in the
    training set ignored at prediction.
  - **Fit**: inverse regularisation strength 1; unpenalised intercepts; a
    softmax over every class with a stable log-sum-exp; classes ordered by id,
    with ties going to the first; starting from zero weights, with a fixed
    memory and iteration cap, so the fit is deterministic.
  - **One class**: a training set with a single class predicts it with full
    confidence, since a softmax cannot be fitted to it.

  A parity test checks the F# fit against scikit-learn's on a fixture dataset.
  Both sides fit it to a tight tolerance, so they are compared at the unique
  optimum rather than where two optimisers happen to stop.
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

- **Decision**: the features, all computed from the normalised description (case
  folded as rules fold it, digit runs replaced, whitespace collapsed) or the
  transaction's other facts:
  - character n-grams of 3 to 5 characters within each word padded by a space on
    either side, TF-IDF weighted;
  - word tokens, TF-IDF weighted, so store and reference numbers, already
    normalised away, do not split one merchant into many;
  - the amount's sign, and the sign with the base 2 logarithm of its size
    rounded down, as categories;
  - the account, as a category.

  The vocabulary, IDF weights, and categories come from the training set of each
  fit.
- **Why**: bank descriptions are codes rather than prose, with merchant names
  truncated, abbreviated, and prefixed by a transaction type (`POS W/D`, `PAY`).
  Character n-grams match these fuzzily, as substring rules do exactly. Sign
  separates income from expense tags; size and account separate tags that share
  a payee. In the experiments each addition to character n-grams raised top-1
  accuracy (0.806 for n-grams alone to 0.840 with all four, without class
  balance), mostly on unseen merchants (0.520 to 0.566).
- **Rejected**:
  - The other party, particulars, code, and reference fields. Import does not
    store them, and they cannot be recovered for old rows
    ([transfer rules](transfer-rules.md#deferred)).
  - Sentence embeddings (all-MiniLM-L6-v2, bge-small), alone or with these
    features. They relate merchants with no text in common (`PAK N SAVE` and
    `COUNTDOWN`), and with these features they were the most accurate option:
    with MiniLM and the same class balance, 1 point more precision at the
    lookup's coverage and 2 at 90% coverage, both beyond noise, and 0.649 top-1
    accuracy on unseen merchants against 0.594. That gain costs ONNX Runtime, a
    model file, a glibc base image, and an embedding store (decision 1), for a
    model whose suggestions are already right about 98% of the time at the
    shipped threshold. Revisit if unseen merchants come to dominate the queue.
  - Dropping the account. Without it the model was 0.8 points more precise at
    the lookup's coverage, at the edge of noise, and level at 90% coverage. Kept
    because the account is cheap and separates tags that share a payee, which
    this user's data may not exercise.
- **Goal**: every feature is computable from what `Transactions` already holds.

### 4. Classes are the user's tags and transfer; labels come from categorisations

- **Decision**:
  - **Classes**: one per tag present in the training set, and one for transfer.
    Dismissed is not a class: it means the transaction has no tag, not that it
    belongs to a category, and no proposal ever dismisses
    ([transfer rules](transfer-rules.md) decision 9).
  - **Labels**: `Manual` categorisations at full weight; `Accepted` ones at half
    weight; `Detected` transfers at full weight. `Rule` categorisations are not
    labels.
  - **Class balance**: each label's weight is multiplied by the square root of
    its class's balancing factor: the total label weight over the number of
    classes times the class's own total. The weights are then scaled back to
    their original total, so the regularisation strength means the same.
  - **Accepting a model suggestion** records `Accepted`, as accepting a rule's
    does. No new source value.
- **Why**: `Manual` labels are the user's own choice. `Accepted` ones are
  confirmations, sometimes given in bulk by approval, so weighting them lower
  limits the model reinforcing its own mistakes. `Detected` transfers are exact,
  since import matched account numbers. Deleting a tag deletes its
  categorisations, so its class disappears from the next fit without any
  cleanup.
  - **Weights unmeasured**: the export had no `Accepted` or `Detected` labels,
    so the sweep of `Accepted` weights (a quarter, half, full) and of `Detected`
    in or out changed nothing. Half and full stay as the reasoning above sets
    them; rerun the sweep once quick tagging has produced `Accepted` labels.
  - **Class balance**: unbalanced, the model favours the large classes on
    ambiguous rows, and some small tags were almost never suggested (Donations
    and Gifts at 13% recall, at the lookup's coverage). Full balancing raised
    small-class recall to the lookup's level but overcorrected, suggesting a
    small tag for rows of a large one: wrong suggestions rose, mostly
    Entertainment for Home Expenses. The square root sits between: the best
    top-1 accuracy (0.855 against 0.840 unbalanced, and 0.594 against 0.566 on
    unseen merchants), the fewest wrong suggestions at the lookup's coverage (19
    against 23 unbalanced and 25 fully balanced), and small-class recall about
    halfway. It also limits the boost for a tag with one or two labels, which
    full balancing gives a large share of the fit; the per-class minimum
    (decision 7) keeps such a tag from being suggested.
- **Rejected for class balance**:
  - Full balancing, for the overcorrection above.
  - Full balancing with the factor capped at 5. It only changes classes with
    under a fifth of the mean class weight, so on this data it matched full
    balancing.
- **Rule tags as labels**: left out. Both sides made predictions the experiments
  could test, so neither was assumed beforehand.
  - **Result**: uncapped rule labels made the shipped model worse (0.551 top-1
    accuracy on unseen merchants against 0.594, and 25 wrong suggestions at the
    lookup's coverage against 19), and taught it Utilities, a tag only rules
    assign, which it then suggested for residual rows. Rule labels capped at a
    total weight of 1 per normalised description were within noise of none, so
    none wins as the simpler option. The cap beating the uncapped variant
    supports the redundancy argument below.
  - **For**: rule tags are likely most of a user's tagged transactions, and they
    cover the most common tags. Without them the model has few or no examples of
    those tags, so it cannot suggest them for new merchants of the same kind
    (Groceries for `PAK N SAVE` when a `COUNTDOWN` rule covers the usual
    supermarket). They are an indirect user decision: the user wrote the pattern
    after seeing its match count and samples (auto-tagging decision 7). The
    model never writes `Rule` categorisations, so there is no feedback loop, and
    fitting on read (decision 5) means a fixed rule and a re-tag correct the
    labels on the next read.
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
    answered by a cap, and were measured directly (decision 8).
- **Goal**: the model learns from the user's decisions as far as the
  measurements support, every tag gets a fair share of suggestions, and nothing
  about categorisations changes to support it.
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
- **Why**: the fit is cheap, so a stored model would only add a second record of
  what the categorisations already say. In the experiments a fit on about 1,100
  labels took 0.2 seconds in scikit-learn and under 20 MB at its peak, and the
  hand-rolled fit is expected to take 50 to 100 milliseconds. Fit time and
  memory grow with the labels, about linearly; the weights grow with the
  vocabulary, about as the square root of the labels, times the classes. At ten
  years of labels at the current rate (about 5,000), a fit is expected to take a
  few hundred milliseconds, with a model of about a megabyte. Fitting on read
  means a suggestion always reflects the latest labels, with no retrain action,
  staleness, or invalidation, the same reason rule suggestions are computed on
  read ([transfer rules](transfer-rules.md) decision 6). Determinism matters
  because the suggestion filter and the approval rely on a second read returning
  the same suggestions as the first.
- **Rejected**:
  - A stored model with a retrain button. Survives restarts and costs nothing
    per read, but goes stale and needs a staleness indicator and a store.
  - An in-memory cache per user, invalidated on categorisation writes. Saves the
    fit, but every writer of categorisations would have to invalidate it.
  - An in-memory model per user, refitted at startup and then on a timer, such
    as daily. Costs nothing per read, but labels from a tagging session inform
    suggestions only after the next refit, when the model learns most during the
    session itself. A refit between a filtered read and its approval would also
    change the suggestions under it, against the determinism above.
  - Online learning, updating the model per label. Always current, but the
    model's state has to be kept in step with categorisations, including edits
    and deletions.
- **Revisit**: the queue read logs each fit's duration with its label, class,
  and feature counts. If fits regularly take more than 200 milliseconds, the
  delay becomes noticeable on the queue read, expected somewhere between 3,000
  and 5,000 labels. Then cache the fitted model per user, keyed by a hash of the
  training set: a read still loads the training set, but fits only when the hash
  differs from the cached one. The key comes from the data, so no writer has to
  invalidate it, edits and deletions change it, and suggestions are never stale.
  The cache saves the fit on repeated reads and filter changes but not on the
  read after a batch is saved, since that batch changed the labels.
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
    - its confidence is below the threshold, 0.7;
    - the user has fewer than 25 labels;
    - its top class has fewer than 2 labels. Such classes stay in the fit, so
      their probability is not given to other classes, but are never suggested.
- **Why**: a wrong suggestion costs one click; a wrong applied tag goes
  unnoticed. The policy exists so that applying confident proposals later is a
  change to one function ([transfer rules](transfer-rules.md) decision 3). A
  model trained on a handful of labels, or a class seen once, is close to
  guessing, and a guess presented as a suggestion trains the user to ignore
  suggestions.
  - **Threshold**: in the experiments, 0.7 suggested for 65% of the scored rows
    at 98.4% precision (99.5% for seen merchants, 90.1% for unseen). 0.6
    suggested for 74% at 95.7%, but the extra rows it adds are right only about
    78% of the time, and approval accepts every suggestion shown at once
    (decision 9), so a wrong one is easy to accept unread. 0.8 gave up a fifth
    of the suggestions for under a point of precision.
  - **Minimums**: the data did not constrain them: at 0.7 every bucket with
    suggestions was at least 93.5% precise, however few labels the fit or the
    predicted class had. Below 25 labels, the first month, the model reached the
    threshold for no row. Classes with 2 labels were suggested 6 times, all
    correctly; classes with 1 label were never suggested. The minimums are set
    at those edges, as guards beyond what the data tested: a new tag's first
    label carries the largest class balance factor (decision 4).
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

    Each logistic regression also ran with each class balance of decision 4.
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
    labels of residual rows, which measures distribution shift directly; recall
    by class, and wrong suggestions by suggested class, which show tags the
    model neglects or over-suggests; and, for any rule known to over-match,
    precision on residual rows near it with and without rule labels.
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
  - **Result**: one user's export: 2,118 transactions and 1,068 scored rows (743
    seen merchants, 325 unseen) over 25 monthly cutoffs. At 50% coverage every
    candidate was 97.9% to 100% precise, so the comparison could not separate
    them, and the criterion chose the simplest: character n-grams alone, without
    rule labels or class balance. The lookup reached 70% coverage at 95.7%
    precision, and the chosen option was within noise of it there (+0.4 points),
    so by the criterion the lookup ships.
  - **Override**: the shipped model is instead decision 3's features with the
    square root class balance of decision 4, without rule labels. The criterion
    assumed the lookup would fall well short of 50% coverage and that candidates
    would differ there; on this data neither held, so the fixed measure compared
    options where none of them fail. The shipped model is better where they
    differ:
    - at the lookup's coverage, 97.4% precise against the lookup's 95.7% (+1.7
      points, interval +0.1 to +3.4);
    - beyond it, where the lookup makes no suggestion, 89.7% precise at 90%
      coverage, against 86.8% for character n-grams alone;
    - top-1 accuracy of 0.855, and 0.594 on unseen merchants, against 0.806 and
      0.520 for the criterion's choice;
    - 19 wrong suggestions at the lookup's coverage, against 32 for the lookup
      and 29 for the criterion's choice.

    Among simple models it is the most accurate; models with embeddings were
    more accurate still, and are rejected in decision 3 for their cost.
- **Cost of the override**: the criterion was fixed beforehand so that results
  could not choose the measure, and the override is chosen after seeing them.
  Many variants were tried, so a margin as narrow as the one over the lookup is
  weak evidence on its own. The override rests on suggestions for unseen
  merchants, which the lookup cannot make and which no variant disputes.
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
    neighbours, which did not ship, not for logistic regression.
- **Goal**: quick tagging gains suggestions without gaining concepts.

### 10. Tests

- **Decision**:
  - **Domain**: the vectoriser (n-grams, digit normalisation, TF-IDF, the amount
    and account categories); the class balance (the square root factor, the
    total weight kept); the logistic regression (a gradient check, separable
    data reaching high confidence, row weights changing the fit, a single class,
    determinism); abstaining for each of the three reasons; a rule's suggestion
    beating the model's; the policy never applying a model proposal.
  - **Parity**: the `ml/` project vectorises and fits scikit-learn on an
    anonymised fixture, and writes its features and predicted probabilities as
    committed fixtures; server tests vectorise and fit the F# model on the same
    data and compare within a tolerance. Comparing the features separately shows
    which half a failure is in. CI does not run Python.
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

- **Schema**: none.
- **Domain**: the vectoriser, the classifier, abstaining, and the policy line,
  beside the proposal and policy.
- **QuickTag slice**: the queue read loads the training set, fits, and adds
  model suggestions where no rule matches. The suggestion's origin gains the
  model case. Counts, filter, and approval are unchanged.
- **Client**: the suggestion decoder accepts the model origin, and the row shows
  "Suggested" without a pattern.
- **Docker**: none.
- **Dev shell**: Python and the `ml/` project's dependencies.
- **Docs updated with the implementation**:
  - [transfer rules](transfer-rules.md): decision 4's `Model` source (not added,
    decision 4 here) and the smart tagging consequence.
  - [quick tagging](quick-tagging.md): decision 8's suggestion label and the
    deferred suggestions from smart tagging.
  - [testing strategy](testing-strategy.md): the parity fixture.

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
- **Sentence embeddings.** More accurate on unseen merchants (decision 3), at
  the cost of ONNX Runtime, a model file, and a glibc base image.
- **Rerunning the experiments.** Once quick tagging has produced `Accepted`
  labels, to set their weight from data, and to check the threshold as the
  classes even out.

## Assumptions

- A user has at most a few thousand labels and tens of tags, so fitting on every
  queue read is fast.
- Descriptions carry most of the signal; amount and account refine it.
- One user's labelled data is representative enough of their future transactions
  that past accuracy predicts future accuracy.
