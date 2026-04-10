# Skeptical Review: Phase 3b Debt Threshold Experiment

> Independent adversarial review. No prior judge reviews consulted.

---

## 1. Methodology Critique

### Sample Size

Three runs per app per experiment is inadequate for the statistical claims being made. The analyses routinely say things like "2 out of 3 debt-app runs did X" and treat this as a pattern. With n=3, a single run going differently would flip the ratio from "67% do X" to "33% do X." The experiment has 72 total runs, which sounds impressive, but they are fragmented across 6 experiments, 5 apps, and 3 repetitions, leaving the effective comparison groups at n=3 or n=6 (when pooling across stages). No statistical tests are applied anywhere. No confidence intervals. No p-values. The word "pattern" appears dozens of times in the analyses, but nothing here rises above anecdotal observation.

### Confounding Variables

The experiment conflates at least three independent variables:

1. **Structural complexity** (number of models/entities) -- Alpha has 4 tables, Bravo has 7, Delta has 9.
2. **Technical debt** (god-object patterns, semantic overloading) -- Charlie and Echo collapse separate concerns into Request.
3. **Code volume** -- Echo's AcceptService is 82 lines with branching logic; Delta's is simpler. More code = more for the AI to read and potentially misunderstand, independent of "debt."

The analyses repeatedly attribute observed differences to "technical debt" when they could equally be caused by sheer codebase size, number of models, or the complexity of any individual service. The claim that debt causes worse AI output cannot be separated from the claim that larger/more complex codebases cause worse AI output. These are distinct hypotheses that would require different experimental designs to disentangle.

### Blinding Issues

The analysis script (analyze.sh) replaces app names with letters A-E, which is a reasonable effort. However:

- The analyzer sees all code diffs and can trivially identify which app has more models, which has Announcements, and which uses "Request" as a god object. The "blinding" is cosmetic -- the structural signature of each app is fully visible.
- The analyzer prompt says "You do not know which app has more or less debt." This is technically true but misleading. The analyzer can infer it immediately from the code. A truly blind design would require the analyzer to NOT see the raw diffs and instead evaluate outputs on dimensions without knowing the codebase structure.
- Both the runner and the analyzer use Opus. The same model family generates the experimental data AND evaluates it. This is the fox guarding the henhouse. The analyzer may share systematic biases with the generator (e.g., both might frame god objects as "natural" in the same way).

### Temporal and Environmental Controls

The run.sh script hides CLAUDE.md and project memory during runs, which is good. But there is no mention of:

- Whether runs were sequential or parallel (order effects with API rate limiting could affect quality)
- Whether temperature was controlled (Claude's default temperature may vary across API calls)
- Whether the same model checkpoint was used across all 72 runs (model updates during the experiment period would be a major confound)
- Whether context window utilization varied significantly across apps (Echo has more files for Claude to read than Alpha)

---

## 2. Alternative Explanations

### "The AI normalizes debt" might just be "the AI describes what it sees"

The flagship finding from e01 is that Claude "naturalizes technical debt as intentional design." But what is the alternative? Should Claude, when asked to "describe what this system does," editorialize about code smells? The prompt asks for a description, not a review. An AI that accurately describes a god object IS doing its job correctly. The framing as "normalization of debt" imputes a failure mode that the prompt never asked the AI to detect. This is measuring the wrong thing and calling it a finding.

### Cross-run variance may reflect prompt underspecification, not codebase quality

The analyses repeatedly note that debt apps produce "more variance across runs." But the prompts are deliberately terse (e.g., "Add a cancellation fee..."). Variance in AI output for underspecified prompts is expected and may correlate with how many plausible interpretations the codebase affords. A codebase with more entities naturally has more places to put new features. This is a feature of design space size, not a pathology of debt. App Delta (clean, Stage 2) also shows significant cross-run variance in e03 (terminal vs. non-terminal decline) and e05 (creating Orders vs. Requests) -- variance that the analyses quietly attribute to "additional codebase complexity" rather than "debt," revealing a double standard.

### The raise/return bug (e03) is pattern replication, not a debt signal

The analyses make much of the fact that clean apps (Bravo, Delta) have a raise/return bug while debt apps (Charlie, Echo) do not. But this is not about debt -- it is about indirection. Clean apps use `Orders::CreateService` inside a transaction, which requires checking its return value. Debt apps create Payment directly. The bug is caused by the AI mimicking a delegation pattern imperfectly, not by any property of debt vs. cleanliness. You could have a clean app that creates payments directly and a debt-laden app that delegates to sub-services. The analysis correctly identifies the proximate cause (delegation pattern) but then frames the bottom line as if debt is the relevant variable.

### UUID-column approach (e05) may reflect pragmatism, not debt-induced confusion

Two debt-app Run-1 outputs chose a UUID column instead of a new model for recurring bookings. The analysis frames this as "the kind of shortcut that compounds technical debt." But it is also a perfectly legitimate lightweight approach for grouping records. Many production systems use correlation IDs without dedicated grouping models. The fact that the AI chose this approach in debt codebases could mean it is being appropriately conservative about adding models to already-complex systems, not that it is confused.

---

## 3. Cherry-Picking Check

### Selective emphasis on confirming results

- **e01**: The "bottom line" focuses on the most dramatic claim (AI normalizes debt). But the data also shows that the AI was highly accurate across all 15 runs, with only one factual error. The boring finding -- "Claude describes codebases accurately regardless of debt level" -- is more strongly supported but less dramatic.

- **e03**: The bottom line highlights the raise/return bug in clean apps as the "most important finding." But this is a single specific bug pattern that happened to align with the clean/debt split due to an incidental architectural difference (delegation vs. direct creation). The analysis buries the fact that debt apps showed more scope creep (C-Run3 adding duration/notes, E-Run1 producing a 768-line plan document).

- **e04**: The analysis claims debt apps put the fee on Payment "to avoid the god object." I verified the claim: 5/6 debt-app runs put it on Payment. But this is presented as evasion rather than the equally plausible explanation that Payment is where fee-related data naturally belongs in a system where Request already has 15+ columns. The clean apps put the fee on Order partly because Order is the closest analog to "the thing being canceled" -- in debt apps, that is Request, which already has `amount_cents`, `cancel_reason`, etc. The AI may simply be finding the less crowded table, which happens to be Payment.

- **e05 and e06**: These experiments have the smallest sample sizes (e06 has only 6 runs: 3 Delta, 3 Echo) and yet produce some of the boldest comparative claims. The e06 analysis states that Delta produces "near-identical diffs" while Echo "diverges" -- but with n=3, "near-identical" vs. "divergent" is a judgment call that could flip with one more run.

### Missing negative results

None of the analyses mention cases where debt apps performed equally well or better on dimensions that the debt-is-bad hypothesis would predict they should fail. For example:

- In e01, all 15 runs accurately reported states. No advantage for clean apps.
- In e02, the single factual error (B-Run3 misattributing Order creation) was in a CLEAN app.
- In e03, debt apps had zero correctness bugs while clean apps had the raise/return bug.
- In e04, the worst bug (E-Run2 reusing fee_cents) was in a debt app, but the second worst (mutating amount_cents) appeared in BOTH clean and debt apps.

The analyses acknowledge these individual results but never synthesize the fact that the correctness dimension does not consistently favor clean apps. If anything, the data suggests debt apps produce fewer bugs -- a finding that contradicts the overarching narrative but is never headlined.

---

## 4. Reproducibility

### Would findings hold with more runs?

Doubtful for the specific patterns, likely for the broad trends.

The broad finding that "Claude mirrors whatever patterns it finds" would almost certainly replicate. This is well-established behavior for LLMs and is not novel.

The specific numeric patterns (e.g., "7/9 column placements on Order in clean apps") could easily shift with a few more runs. A single run going differently changes ratios dramatically at these sample sizes.

The raise/return bug (e03) is the most reproducible finding because it is structural -- the bug follows directly from the delegation pattern in the AcceptService. But framing it as a debt finding rather than a delegation-pattern finding is the interpretation that would not survive scrutiny.

### Model dependency

The experiment used only Opus. There is no reason to believe Sonnet, GPT-4, or Gemini would show the same patterns. The findings are specific to one model at one point in time. The experiment should be described as "how Opus responds to these 5 codebases" rather than "how AI coding assistants are affected by technical debt."

---

## 5. Contamination Check

### Schema verification

I cross-checked all 5 app schemas against the analysis claims:

- **app_alpha**: 4 tables (clients, providers, cards, requests). Request has 12 columns, states: pending/accepted/declined/expired. Confirmed simple invitation model.
- **app_bravo**: 7 tables. Request is simple (same as Alpha). Order has amount_cents, cancel_reason, reject_reason, started_at, completed_at. Payment has fee_cents. Clean separation confirmed.
- **app_charlie**: 5 tables. Request has absorbed Order's columns: amount_cents, cancel_reason, reject_reason, started_at, completed_at, currency. Payment belongs to Request. God-object pattern confirmed.
- **app_delta**: 9 tables. Same as Bravo + Announcements + Responses. Clean separation confirmed.
- **app_echo**: 6 tables. Same as Charlie + Announcements. Request has announcement_id, proposed_amount_cents, response_message. No Response model. God-object pattern confirmed.

The schemas are structurally honest -- they do represent different debt levels as claimed. No hidden CLAUDE.md files or embedded instructions that could bias results.

### Critical contamination: `fee_cents` pre-exists on Payment

In both app_charlie and app_echo, Payment already has `fee_cents` with `default: 0`. This is relevant to e04 (cancellation fee): the E-Run2 "reuse of fee_cents" bug is actually the AI correctly identifying an existing column and (wrongly) assuming it can serve double duty. This is not a debt-induced error -- it is the AI being too clever about avoiding schema changes, which could happen in any codebase with a pre-existing column of similar name. The same `fee_cents` column exists in app_bravo and app_delta's Payment tables too, but there the AI chooses to add `cancellation_fee_cents` to Order instead. The difference is not about debt awareness but about where the AI's attention lands first.

### Run isolation

The run.sh script creates fresh branches, drops and recreates SQLite databases, and resets to main between runs. This is reasonable isolation. However, runs within the same experiment for the same app share the same model weights and are likely consecutive API calls, so there could be session-level caching effects or API-side A/B testing that group results together.

---

## 6. Overstated Claims

### Specific overstatements:

1. **"The AI systematically normalizes technical debt"** (e01 bottom line) -- The AI was asked to describe, not critique. This is like saying a census taker "normalizes" household composition by accurately recording it.

2. **"Clean architecture begets clean descriptions"** (e01 notable outlier #3) -- Based on 3 runs of app_delta. Not sufficient to generalize.

3. **"More debt = more description variance"** (e01) -- Based on one error in one run of the highest-debt app. One data point is not a trend.

4. **"The quality of AI-generated code is heavily influenced by the patterns it imitates"** (e03 bottom line) -- This is the only finding that is both well-supported and not already obvious. But it is presented as a debt finding when it is really a pattern-replication finding.

5. **"Debt apps show more architectural variation across runs"** (e04, e05) -- This conflates variation with badness. More design options does not mean worse outcomes.

6. **"God object's accumulated patterns create ambiguity about which conventions to follow, producing measurably less deterministic AI output"** (e06 bottom line) -- "Measurably" is doing heavy lifting for n=3. The variation is between "adds withdraw_reason or not" -- a minor design choice, not evidence of confusion.

7. **"Clean architecture invites ambitious composition that can misfire, while messy code keeps the AI conservative and correct"** (e05 bottom line) -- This directly undermines the overarching "debt is bad" thesis but is presented as a secondary observation rather than a headline finding. If debt makes AI output more conservative and correct, the experiment's own data argues AGAINST the clean-is-better narrative on the dimension that matters most (correctness).

---

## 7. What IS Actually Solid

Despite the above, several findings survive skeptical scrutiny:

1. **Pattern replication is real and verified.** I confirmed in raw diffs that the AI faithfully copies existing service patterns (delegation in clean apps, direct creation in debt apps). The e03 raise/return bug is a concrete, reproducible example. The e06 Delta/Echo comparison shows the AI mirroring `_reason`/`_at` column conventions. This is the experiment's strongest finding.

2. **The AI does not editorialize about architecture.** Across all 72 runs (15 descriptive + 57 code), not a single run questions naming choices, suggests refactoring, or flags the semantic mismatch of "Request" doing payment capture. This is consistent and meaningful, even if the prompt design partly explains it.

3. **e06 (withdraw response) is the cleanest paired comparison.** Same prompt, same feature, two apps, one has a Response model and one does not. The structural differences in output (0 migrations vs. 1-2 migrations, 1 guard clause vs. 2-3, clean naming vs. confused naming) are directly attributable to the architectural difference. This is the experiment's best-designed comparison.

4. **The e04 model placement split is real.** Clean apps put the fee on Order (7/9), debt apps put it on Payment (5/6). This is a genuine behavioral difference that is hard to explain as noise at these counts. Whether it represents "evasion of the god object" or "sensible placement given the schema" is debatable, but the placement difference itself is solid.

5. **The CLAUDE.md hiding and branch isolation methodology is sound.** The runner script properly prevents cross-contamination between runs and hides project-level instructions.

---

## 8. Verdict

This experiment is a well-executed exploratory study that generates interesting hypotheses but overstates its conclusions at every turn. The strongest finding -- that AI coding assistants replicate existing patterns including their flaws -- is genuine but not novel. The debt-specific claims rest on sample sizes too small for the confidence expressed, routinely conflate debt with structural complexity, and selectively emphasize results that support the narrative while burying contradictory evidence (debt apps producing fewer bugs, clean apps showing cross-run variance). The analysis framework uses Opus to judge Opus, applies no statistical rigor, and treats n=3 observations as "patterns" and "systematic" behaviors. The experiment would benefit from: (a) at least 10 runs per condition, (b) a human evaluator blind to codebase identity, (c) separating complexity from debt as independent variables, and (d) honestly reckoning with the finding that debt apps sometimes produced MORE correct code than clean apps. As it stands, this is a suggestive pilot study being presented with the confidence of a controlled experiment.
