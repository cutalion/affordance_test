# Phase 3b: How Technical Debt Shapes AI Coding Assistant Behavior

> 72 Claude Opus runs. 5 Rails apps. 6 experiments. 3 independent judges.
> Clean data — fresh databases per run, no schema artifacts, no domain leaks.

---

## Executive Summary

We built 5 Rails apps representing a babysitting marketplace at different stages of domain
evolution — from a clean invitation model to a god object where one model serves four
purposes — and asked Claude Opus to describe, extend, and build features on each, 3 times per
prompt, blind (no CLAUDE.md, no project memory).

**The core finding:** AI coding assistants are pattern amplifiers, not architectural reasoners.
They replicate whatever they find — structure, conventions, and bugs — without questioning
fitness. This makes clean architecture self-reinforcing and technical debt equally
self-reinforcing, creating a feedback loop where each AI-generated feature makes the next one
more likely to follow the same pattern.

**The surprise:** The most dangerous bug in the entire experiment appeared exclusively in
clean-architecture apps, not in debt apps. The AI faithfully copied a subtle transaction-
handling pattern that looks correct, passes all tests, and would survive most code reviews —
but silently swallows errors.

---

## The Domain: A Babysitting Marketplace

All 5 apps model the same business: clients book providers for childcare services. The domain
evolves through stages, with two parallel tracks — one that refactors properly at each stage,
and one that accumulates debt.

### Stage 0: The Invitation (alpha)

A parent sends a **Request** to a specific sitter. The sitter accepts or declines. If they
don't respond, it expires. The name "Request" fits perfectly — it literally is a request.

*States: pending, accepted, declined, expired*

### Stage 1: The Booking Platform

The product evolves from "invite a specific sitter" to "book a time slot and get matched."
Now there's payment, reviews, and a fulfillment lifecycle.

**Clean path (bravo):** Someone extracts a new **Order** model for the fulfillment phase.
Request stays as the matching/invitation mechanism. Each model has a small, focused state
machine. Payment belongs to Order.

*Request: pending, accepted, declined, expired*
*Order: pending, confirmed, in_progress, completed, canceled, rejected*

**Debt path (charlie):** Nobody refactors. Request absorbs the booking lifecycle. The
`AcceptService` now captures payment — the name "accept a request" now lies about what it
does. Request has 8 states spanning matching, fulfillment, and payment.

*Request: pending, accepted, in_progress, completed, declined, expired, canceled, rejected*

### Stage 2: The Marketplace

Providers can now post **Announcements** ("I'm available Saturday"), and clients respond.
This creates a third path to a booking, alongside direct requests.

**Clean path (delta):** A **Response** model is added for announcement replies. When a
response is selected, it becomes an Order through the existing flow. Four models, each with
one job.

**Debt path (echo):** No Response model. Instead, responding to an announcement creates
a Request with `announcement_id` set. The `AcceptService` now branches on
`announcement.present?` and serves three different purposes depending on context: accepting
an invitation, confirming a booking, and selecting an announcement response. The Request model
has 8 states and serves as invitation, booking, fulfillment tracker, and announcement response
simultaneously.

### The Experimental Matrix

| App | Stage | Track | Models | Request is... |
|-----|-------|-------|--------|--------------|
| alpha | 0: MVP | — | 4 | An invitation (fits perfectly) |
| bravo | 1 | Clean | 7 | A matching mechanism (Request + Order) |
| charlie | 1 | Debt | 5 | The entire booking lifecycle (god object begins) |
| delta | 2 | Clean | 9 | A matching mechanism (Request + Order + Announcement + Response) |
| echo | 2 | Debt | 6 | Everything (god object: 4 roles, 1 model) |

---

## The Experiments

Each experiment asks a specific question about how debt affects AI behavior. Experiments run
blind: CLAUDE.md is hidden, project memory is hidden, and app names are neutral (alpha through
echo). Each prompt runs 3 times on each eligible app.

### E01: "Describe what this system does" (15 runs)

**Question:** Does the AI accurately describe each architecture? Does it notice or flag
technical debt?

**Prompt:** *"Describe what this system does. What is the domain, what are the main entities,
and what is the typical workflow?"*

**What we learned:** The AI is a perfect mirror. It accurately describes every app's
architecture — entities, states, relationships — without inventing or omitting anything. But
it never flags design problems. App E's Request model serves four simultaneous purposes, and
the AI describes this as "the core transactional entity" with the same neutral confidence it
uses for App B's clean two-model design.

The AI also adjusts its narrative framing: in App A, Request is "a booking inquiry." In
App E, it's "the core transaction." This reframing is technically accurate but it
**naturalizes debt as intentional design** — a reader of the AI's description would have no
idea anything is wrong.

**The one crack:** App E (highest debt) produced the only factual error across all 15 runs —
an actor-role inversion in Run 2 where the AI got confused about who accepts what in the
announcement flow. More debt = more descriptive variance.

---

### E02: "Walk through the happy path" (15 runs)

**Question:** Does debt become visible when the AI traces the main workflow?

**Prompt:** *"What is the happy path for the main entity in this system? Walk through it
step by step."*

**What we learned:** The happy path is the one angle from which debt looks exactly like clean
design. Apps C and E (debt) produce happy-path descriptions that read as clean and simple as
Apps B and D (clean) — pending, accepted, in_progress, completed. The god object's complexity
is invisible because the happy path only touches one path through the branching logic.

App E's `AcceptService` serves three purposes depending on context, but the happy-path
walkthrough only ever exercises one of them. The AI describes it as a straightforward accept
flow. The other two purposes are invisible.

**Interesting signal:** App D (clean, Stage 2) never mentioned Announcements or Responses in
any happy-path run — clean separation made secondary entities invisible to the main-entity
question. App E Run 3 *did* mention Announcements — the god object's coupling leaked into the
explanation.

---

### E03: "Add counter-proposals" (12 runs, skip alpha)

**Question:** When the AI builds a feature following existing patterns, where do bugs appear?

**Prompt:** *"Add the ability for providers to propose a different time for a booking. The
client can accept or decline the counter-proposal."*

**What we learned:**

**The bug that only exists in clean apps.** All 6 clean-app runs (bravo + delta) contain an
identical unreachable-code bug:

```ruby
Request.transaction do
  # ...
  unless order_result[:success]
    raise ActiveRecord::Rollback    # raises, rolls back the transaction
    return error("Failed to create order")  # UNREACHABLE — never executes
  end
end
# execution continues here — sends success notification with rolled-back data
```

This bug exists in the clean apps' *existing* `AcceptService` — the AI copied it into the new
`AcceptCounterProposalService`. The debt apps' `AcceptService` creates Payment directly
(no delegation, no sub-service return check), so the AI copies a structurally simpler pattern
that has no such bug. **All 6 debt-app runs are bug-free.**

This is the experiment's most striking result. The AI doesn't reason about error-handling
contracts — it copies the delegation structure it sees. Clean architecture's additional
indirection created a surface for a subtle bug that the AI faithfully propagated.

**Other findings:**
- Decline semantics split: debt apps unanimously chose non-terminal decline (back to pending);
  clean apps split (some terminal, killing the request entirely)
- Debt apps more consistently extended `cancel` to work from the new `counter_proposed` state
- Scope creep: echo Run 1 generated a 768-line implementation plan document

---

### E04: "Add a cancellation fee" (12 runs, skip alpha)

**Question:** Where does the AI place new business data — on the booking entity or elsewhere?

**Prompt:** *"Add a cancellation fee: if a booking is canceled within 24 hours of the
scheduled time, charge the client 50% of the booking amount."*

**What we learned:**

**The AI routes data away from god objects.** In clean apps, the AI places
`cancellation_fee_cents` on Order (the booking entity) in 7 of 9 column placements. In debt
apps, it places the fee on Payment in 5 of 6 runs — systematically avoiding the overloaded
Request model.

The AI never says "Request has too many columns" or "I'll put this on Payment to avoid
bloating Request." It just does it. This implicit avoidance behavior suggests the AI can
sense model overload even though it never articulates the problem.

**The worst correctness bug:** Echo Run 2 skips the migration entirely by reusing the existing
`fee_cents` column (which stores platform/processing fees) for cancellation fees — conflating
two different business concepts. The test passes because it checks the wrong thing.

**Convergence signal:** Delta (clean) placed fee on Order in 3/3 runs. Echo (debt) varied
across all 3 runs (Payment, reuse fee_cents, Payment). More architectural clarity = more
consistent AI output.

---

### E05: "Add recurring weekly bookings" (12 runs, skip alpha)

**Question:** When the AI needs a new domain concept, does it create a new model or pile onto
an existing one?

**Prompt:** *"Add the ability to create recurring weekly bookings — 5 sessions with the same
provider at the same time."*

**What we learned:**

**God-object gravity is real.** Clean apps created a dedicated `RecurringBooking` model in
all 6 code-producing runs. Debt apps diverged: charlie Run 1 and echo Run 1 both
independently chose a UUID-column approach — adding `recurring_group_id` to the Request table
instead of creating a new model. Runs 2-3 for both debt apps did create models.

This is clean evidence (no schema artifacts in round 3). The debt codebase's existing pattern
of "put everything on Request" pulled the AI toward the same approach in 2 of 6 runs. The
UUID-column hack works, but it's the kind of shortcut that deepens existing debt.

**App D found the right abstraction level.** Delta is the only app where the AI created
Orders (not Requests) as children of the recurring booking, and also created Payment records.
The clean model hierarchy communicated the correct domain semantics — recurring bookings
produce orders which have payments.

**The composition bug again.** Delta Run 1 reused `Orders::CreateService` inside a
transaction and hit the same `raise ActiveRecord::Rollback` silent failure as E03. The
service-delegation pattern is consistently problematic for AI.

---

### E06: "Withdraw response to announcement" (6 runs, delta + echo only)

**Question:** When a feature maps to a dedicated model in one app but not in another, how
does implementation differ?

**Prompt:** *"Add the ability for a provider to withdraw their response to an announcement
before the client makes a decision."*

**What we learned:**

**This is the cleanest paired comparison in the experiment.** Same prompt, same feature, two
apps. One has a Response model, one doesn't.

**App D (3 runs):** Near-identical diffs. `withdrawn` state on Response model.
`Responses::WithdrawService`. "Not your response." Zero migrations (state is a string column).
One obvious implementation path, found consistently.

**App E (3 runs):** `withdrawn` state on Request model (the god object).
`Requests::WithdrawService`. "Not your request" — semantically wrong, since the user is
withdrawing a *response*. 1-2 migrations (adding `withdrawn_at`, optionally
`withdraw_reason`). Divergence: 2/3 runs require a reason, 1/3 doesn't.

The semantic mismatch is systematic: all 3 echo runs write error messages like "Not your
request" and "Cannot withdraw request" when the domain concept is withdrawing a response to
an announcement. The code works, but every AI-generated artifact — error messages,
notifications, tests, comments — carries the naming mismatch forward.

**Pattern pressure:** Echo's existing model has `decline_reason`, `cancel_reason`,
`reject_reason`, `accepted_at`, `expired_at`, etc. The AI follows this convention and adds
`withdraw_reason` and `withdrawn_at` — more columns on the god object, driven by pattern
consistency rather than necessity. Delta's Response model has no such pressure, so the
implementation stays minimal.

---

## Cross-Experiment Findings

### 1. AI is a Pattern Amplifier (Strong — all judges agree)

Across all 72 runs, the AI replicated whatever patterns it found: entity structure, service
conventions, column naming patterns (`_reason`, `_at` suffixes), delegation patterns, and
bugs. It never exercised independent architectural judgment. It never questioned naming
choices. It never suggested refactoring.

This is pattern completion — exactly what large language models are optimized for. It makes
clean architecture self-reinforcing (the AI creates new models when existing code uses many
models) and debt self-reinforcing (the AI piles onto god objects when existing code does that).

### 2. Convergence Correlates with Architectural Clarity (Strong — all judges agree)

| Codebase | E05 convergence | E06 convergence | E04 convergence |
|----------|----------------|----------------|----------------|
| Clean | 6/6 same architecture | 3/3 near-identical | 3/3 fee on Order |
| Debt | 4/6 same, 2/6 UUID hack | 2/3 with reason, 1/3 without | 3 different approaches |

When a domain concept has its own model, the AI finds one implementation path and follows it
consistently. When it doesn't, the AI must make judgment calls, and different runs reach
different conclusions. This variance is measurable and could serve as a diagnostic: if 3 runs
produce 3 architectures, the codebase is architecturally ambiguous.

### 3. Clean Architecture Introduces Composition Risks (Moderate — counterintuitive)

The `raise ActiveRecord::Rollback` / unreachable `return` bug appeared in:
- E03: 6/6 clean-app runs, 0/6 debt-app runs
- E05: 1/6 clean-app runs (delta Run 1)

Total: 7 instances, all in clean apps, zero in debt apps.

The mechanism: clean apps use service delegation (`AcceptService` calls
`Orders::CreateService`), which requires checking return values inside transactions. This
pattern already contains the bug in the source code. Debt apps use direct creation (inline
Payment creation), which has no sub-service to check.

This does NOT mean debt is better. It means the AI copies patterns without reasoning about
their error-handling contracts. More indirection = more surface for subtle bugs.

### 4. God-Object Gravity (Moderate — Judge 2 offers alternative explanation)

Debt codebases pull the AI toward adding to existing structures:
- E05: 2/6 debt runs chose UUID columns on Request instead of a new model
- E04: 5/6 debt runs placed fee on Payment (avoiding Request); clean apps placed on Order
- E06: All echo runs added columns to Request following existing `_reason`/`_at` conventions

Judge 2's counterpoint: the UUID approach may reflect pragmatism, not confusion. The fee
placement may reflect that Payment is where fee data "naturally belongs." These are valid
alternative readings, but the pattern is consistent across experiments.

### 5. Semantic Confusion in Debt Apps (Moderate — all judges agree)

When the model name doesn't match the domain concept, the mismatch propagates into every
AI-generated artifact. E06 is the clearest example: delta writes "Not your response" (correct
domain language), echo writes "Not your request" (code language that contradicts the domain).

### 6. Debt Threshold is About Model Separation (Moderate — Judge 2 cites confounds)

The clean/debt split is more predictive than the complexity level. Charlie (Stage 1 debt) and
echo (Stage 2 debt) produce "nearly identical behavior" across experiments. The decisive
factor is whether each domain concept has its own model, not how many concepts are collapsed.

Judge 2 notes this may conflate debt with structural complexity: clean apps have more code,
more models, and more patterns to follow. Disentangling these would require a different
experimental design.

---

## Methodology

### Experimental Design

- **Runner:** `run.sh` — automated, creates git branches for code experiments, captures diffs
- **Isolation:** CLAUDE.md hidden, project memory hidden, fresh database per run
  (`rm -f storage/*.sqlite3 && bin/rails db:create db:migrate` before each code experiment)
- **Model:** Claude Opus, single-shot (`claude -p --dangerously-skip-permissions`)
- **Analysis:** `analyze.sh` — blind (apps labeled A-E, header lines stripped), run through
  separate Opus instance
- **Judges:** 3 independent Opus reviews with different perspectives (fair, skeptical,
  practitioner), no access to each other's output

### Known Limitations (per Judge 2)

- **n=3 per condition is too small** for statistical significance. All patterns are
  directional hypotheses, not confirmed results. No p-values, no confidence intervals.
- **Opus judges Opus.** The same model family generates and evaluates the data. Shared
  biases are possible.
- **Blinding is cosmetic.** The analyzer can infer architecture from code structure in diffs.
- **Debt is confounded with complexity.** Clean apps have 20-30% more code and more models.
  We cannot separate "debt causes X" from "structural complexity causes X."
- **Single model, single domain.** May not generalize to other AI models or other codebases.
- **No human baseline.** We don't know if these effects are AI-specific or would appear with
  human developers too.

### Round 2 vs Round 3

Round 2 was contaminated: prior experiment branches had modified SQLite databases, and
`rails db:migrate` regenerated schema.rb with artifacts (e.g., `recurring_bookings` table
already present, `withdraw_reason` columns already present). This meant E05 and E06 findings
were partly artifacts of schema hints rather than genuine AI decisions.

Round 3 fixed this with fresh databases per run. Judge 2 verified that round 3 schemas are
"structurally honest" with no contamination. All major findings from round 2 reproduced,
confirming they were not schema artifacts.

---

## Practical Recommendations

### For teams using AI coding assistants

1. **The AI will not warn you about debt.** 30 descriptive runs, zero mentions of design
   problems. Don't rely on AI to identify refactoring targets.

2. **Review AI PRs for architecture, not just correctness.** The most dangerous output is
   code that passes tests but entrenches the wrong model.

3. **Use the 3-run convergence test.** Before a complex feature, run the prompt 3 times. If
   you get 3 different architectures, clarify the codebase patterns first.

4. **Prioritize refactoring by feature type.** Simple additive features: leave god objects
   alone. New domain concepts requiring new models: refactor first.

5. **Document error-handling patterns.** The AI copies whatever transaction pattern it finds.
   The common `raise ActiveRecord::Rollback` + `return` pattern is subtly wrong. Fix it once
   in your codebase and the AI will copy the fix instead.

6. **Don't trust AI-generated tests for error paths.** The AI writes tests that validate its
   own implementation, not tests that challenge it. The raise/return bug passes all tests.

### Refactoring ROI

| Feature type | Debt impact | Refactor first? |
|-------------|------------|----------------|
| Simple (new state + endpoint) | Nuisance, not hazard | No |
| Medium (business logic + payment) | Different bugs, not more bugs | Maybe — document patterns instead |
| Structural (new model, new entity) | Architectural indecision, divergent designs | Yes |

---

## Evidence Summary

| Finding | Evidence strength | Judges | Key data |
|---------|------------------|--------|----------|
| AI mirrors, never critiques | Strong | 3/3 agree | 0/30 descriptive runs flag any design issue |
| Clean = convergent output | Strong | 3/3 agree | 6/6 vs 4/6 model creation (E05); identical diffs in E06 delta |
| AI copies patterns + bugs | Strong | 3/3 agree | 7/7 raise/return bugs in clean apps, 0 in debt |
| God-object gravity | Moderate | 2/3 agree | 2/6 UUID hack in debt (E05); 5/6 fee on Payment in debt (E04) |
| Composition bugs in clean | Moderate | 3/3 agree | Counterintuitive but mechanistically explained |
| Semantic confusion in debt | Moderate | 3/3 agree | "Not your request" vs "Not your response" (E06) |
| Binary threshold | Moderate | 2/3 agree | C~E within debt; B~D within clean |

---

## Files

```
experiments/02-debt-threshold/
  DESIGN.md                           # Experiment design, hypotheses, predictions
  REPORT.md                           # This file
  run.sh                              # Experiment runner
  analyze.sh                          # Blind analysis generator
  results-round2-contaminated.md      # Preserved earlier round with analysis
  judges/
    judge-1-fair.md                   # Independent balanced review
    judge-2-skeptic.md                # Independent adversarial review
    judge-3-practitioner.md           # Independent engineering-manager review
  apps/
    alpha/                            # Stage 0: MVP (Rails app)
    bravo/                            # Stage 1 Clean (Rails app)
    charlie/                          # Stage 1 Debt (Rails app)
    delta/                            # Stage 2 Clean (Rails app)
    echo/                             # Stage 2 Debt (Rails app)
  e01-describe-system/
    prompt.md                         # "Describe what this system does"
    config.sh                         # TYPE=readonly
    analysis.md                       # Blind cross-app analysis
    runs/                             # 15 raw outputs (5 apps x 3 runs)
  e02-happy-path/                     # Same structure, 15 runs
  e03-counter-proposal/               # 12 runs (skip alpha)
  e04-cancellation-fee/               # 12 runs (skip alpha)
  e05-recurring-bookings/             # 12 runs (skip alpha)
  e06-withdraw-response/              # 6 runs (delta + echo only)
```
