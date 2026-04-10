# Do AI Coding Assistants Understand Your Architecture — Or Just Copy It?

An experiment in two parts, testing how code structure shapes AI agent behavior.

**Part 1** asked: does entity naming ("Order" vs "Request") affect how AI reasons about code?
Answer: no — AI reads structure, not semantics.

**Part 2** asked: at what point does accumulated technical debt break AI-assisted development?
Answer: it doesn't break it — it *shapes* it, silently and permanently.

---

## The Headline Results

### The AI will never tell you your code has a problem

We asked Claude Opus to describe 5 different codebases, 3 times each. One codebase has a
model called `Request` that simultaneously serves as an invitation, a booking, a fulfillment
tracker, and an announcement response. The AI described this god object as "the core
transactional entity" with the same confident, professional tone it used for a cleanly
separated four-model architecture. Across 30 descriptive runs, **zero mentioned any design
problem.** ([analysis](experiments/02-debt-threshold/e01-describe-system/analysis.md))

### Clean architecture produced more bugs than messy code

The clean-architecture apps delegate to sub-services inside transactions. This delegation
pattern contains a subtle bug (`return` after `raise ActiveRecord::Rollback` — the return
never executes, and the method silently continues to the success path). The AI copied this
bug into **all 6 clean-app runs**. The messy apps create payments inline — a simpler pattern
with no such bug. **All 6 debt-app runs were bug-free.** Most Rails developers would not
catch this in review. ([analysis](experiments/02-debt-threshold/e03-counter-proposal/analysis.md))

```ruby
# This bug appeared in 7 AI-generated runs. It already existed in the source code.
Request.transaction do
  order_result = Orders::CreateService.call(request: @request)
  unless order_result[:success]
    raise ActiveRecord::Rollback    # rolls back the transaction
    return error("Failed to create order")  # UNREACHABLE — never executes
  end
end
# execution falls through here — sends success notification with rolled-back data
```

### God objects have gravitational pull

When asked to build recurring bookings, clean-architecture apps created a proper
`RecurringBooking` model in 6/6 runs. Debt apps avoided the new model in 2/6 runs, choosing
instead to add a `recurring_group_id` column to the existing god object — the kind of
shortcut that deepens existing debt. Each AI-generated feature that piles onto the god object
makes the *next* AI-generated feature more likely to do the same.
([analysis](experiments/02-debt-threshold/e05-recurring-bookings/analysis.md))

### Same prompt, same codebase, 3 different architectures = a problem

Run the same prompt 3 times on a clean codebase: you get the same diff. Run it on a messy
codebase: you get different approaches each time. A clean app produced near-identical code
across 3 runs (same service, same tests, zero migrations). The debt app diverged on column
choices, validation, and routing. **Cross-run variance is a measurable signal of
architectural ambiguity** — and a practical diagnostic you can use today.
([analysis](experiments/02-debt-threshold/e06-withdraw-response/analysis.md))

---

## Part 1: Does Naming Matter?

**3 Rails apps, 7 experiments, 128 runs (Opus + Sonnet), 6 independent judges**

### The Question

A real production codebase (a babysitting marketplace) has a model called `Request` that
evolved from an invitation system into a full booking/order pipeline, but was never renamed.
Does calling it "Request" instead of "Order" cause AI agents to reason differently?

### The Apps

| | **affordance_order** | **affordance_request** | **affordance_request_clean** |
|---|---|---|---|
| Entity name | Order | Request | Request |
| States | 6 clean | 9 legacy (invitation-era) | 6 clean (same as Order) |
| Services | 6 | 8 | 6 (same as Order) |
| Purpose | Baseline | Legacy codebase | **Control: isolates naming from structure** |

The control app (`affordance_request_clean`) is the decisive test. It shares
`affordance_request`'s entity name but `affordance_order`'s clean structure.

### The Experiments

| # | Experiment | Type | Prompt |
|---|-----------|------|--------|
| 01 | Describe System | descriptive | "Describe what this system does" |
| 02 | Rebook Feature | code | "Add re-booking with the same provider" |
| 03 | Counter-Proposal | code | "Provider can propose a different time" |
| 04 | Bulk Booking | code | "Book 5 sessions at once" |
| 05 | Auto-Assignment | code | "Auto-assign highest-rated provider" |
| 06 | Cancellation Fee | code | "Charge 50% if canceled <24h before" |
| 07 | Happy Path | descriptive | "Walk through the happy path step by step" |

### The Findings

**Structure, not naming, drives AI behavior.** The control app behaved like Order in every
experiment — never like legacy Request. Three independent judges confirmed unanimously.

- **AI reads code, not connotations.** The word "Request" does not activate "invitation" or
  "negotiation" mental models. A clean 6-state Request app behaves identically to a clean
  6-state Order app.
- **Existing code is the strongest design constraint.** When the codebase has a `decline`
  event, the AI reuses it. When it has 8 services, the AI creates more. Your codebase is a
  style guide that agents follow with high fidelity.
- **Specific prompts neutralize structural differences.** Well-scoped prompts like "book 5
  sessions at once" produced equivalent results across all three apps.
- **Model choice (Opus vs Sonnet) matters more than any codebase characteristic.**

Full report: **[experiments/01-naming/REPORT.md](experiments/01-naming/REPORT.md)**

---

## Part 2: At What Point Does Debt Break Things?

**5 Rails apps, 6 experiments, 72 Opus-only runs, 3 independent judges**

### The Question

Part 1 showed that AI reads structure. Part 2 asks: what happens when that structure
accumulates technical debt? At what point does a god object start corrupting AI output?

### The Domain

All 5 apps model a babysitting marketplace evolving through stages. Two parallel tracks — one
that refactors properly, one that accumulates debt:

**Stage 0 — The Invitation (app_alpha).** A parent sends a Request to a specific sitter. The
sitter accepts or declines. The name "Request" fits perfectly.

**Stage 1 — The Booking Platform.** The product evolves from invitations to scheduled
bookings with payment and reviews.
- *Clean track (app_bravo):* Someone extracts an **Order** model. Request stays as matching.
  Each model has a small, focused state machine.
- *Debt track (app_charlie):* Nobody refactors. Request absorbs the booking lifecycle.
  `AcceptService` now captures payment — the name "accept a request" lies about what it does.

**Stage 2 — The Marketplace.** Providers can post Announcements ("I'm available Saturday"),
and clients respond.
- *Clean track (app_delta):* A **Response** model is added. When selected, it becomes an
  Order. Four models, each with one job.
- *Debt track (app_echo):* No Response model. Responding creates a Request with
  `announcement_id` set. `AcceptService` now branches on context and serves three different
  purposes. Request has 8 states and 4 simultaneous roles.

### The Apps

| App | Stage | Track | Models | Request is... |
|-----|-------|-------|--------|--------------|
| app_alpha | 0: MVP | — | 4 | An invitation (fits perfectly) |
| app_bravo | 1 | Clean | 7 | A matching mechanism (+ Order for fulfillment) |
| app_charlie | 1 | Debt | 5 | The entire booking lifecycle |
| app_delta | 2 | Clean | 9 | A matching mechanism (+ Order + Announcement + Response) |
| app_echo | 2 | Debt | 6 | Everything: invitation, booking, fulfillment, announcement response |

### The Experiments

Each prompt runs 3 times per eligible app, blind (no CLAUDE.md, no project memory), with
fresh databases.

| # | Experiment | Type | Apps | Prompt | What it tests |
|---|-----------|------|------|--------|--------------|
| E01 | Describe System | descriptive | all 5 | "Describe what this system does" | Does the AI notice or flag debt? |
| E02 | Happy Path | descriptive | all 5 | "What is the happy path?" | Does debt surface in walkthrough? |
| E03 | Counter-Proposal | code | B,C,D,E | "Add counter-proposals for bookings" | Where do bugs appear in existing patterns? |
| E04 | Cancellation Fee | code | B,C,D,E | "Charge 50% if canceled <24h" | Where does AI place new business data? |
| E05 | Recurring Bookings | code | B,C,D,E | "Add recurring weekly bookings (5 sessions)" | Does AI create a new model or pile onto existing? |
| E06 | Withdraw Response | code | D,E | "Provider withdraws announcement response" | Same feature, one has a model for it, one doesn't |

### The Findings

| # | Finding | Strength | Surprise |
|---|---------|----------|---------|
| 1 | AI describes debt as intentional design, never flags problems | Strong | Expected |
| 2 | Clean codebases produce consistent AI output; debt produces variance | Strong | Moderate |
| 3 | AI copies patterns including bugs — 7/7 instances in clean apps only | Strong | High |
| 4 | Debt codebases pull AI toward piling onto existing models | Moderate | Expected |
| 5 | Clean architecture's indirection creates more surface for subtle bugs | Moderate | High |
| 6 | Naming mismatches propagate into error messages, tests, comments | Moderate | Expected |
| 7 | The threshold is model separation, not debt volume | Moderate | Moderate |

Full report: **[experiments/02-debt-threshold/REPORT.md](experiments/02-debt-threshold/REPORT.md)**

---

## Practical Takeaways

### From Part 1
1. **Renaming entities won't change AI behavior.** Don't invest in renaming for AI's sake.
2. **Clean up state machines and service patterns instead.** Structural complexity shapes AI
   output; names don't.
3. **Write specific prompts for critical features.** Prompt specificity neutralizes structural
   differences.

### From Part 2
4. **Don't rely on AI to find refactoring targets.** It will never tell you a model is
   overloaded.
5. **Review AI PRs for architecture, not just correctness.** Tests passing doesn't mean the
   right model was chosen.
6. **Use the 3-run convergence test.** Run the same prompt 3 times. Divergent architectures
   mean the codebase is ambiguous.
7. **Document your error-handling patterns.** The AI copies whatever transaction pattern it
   finds — make sure what it finds is correct.
8. **Refactor before structural features, not before simple ones.** Adding a state to a god
   object works fine. Building a new domain concept on one doesn't.

---

## What Is an Affordance?

An [**affordance**](https://en.wikipedia.org/wiki/Affordance) is a property of an object that
suggests how to interact with it. A door handle invites pulling; a flat plate invites pushing.
A "Norman Door" — a pull handle on a push door — is the classic example of bad affordance.

This experiment tests whether the same concept applies to code: does naming an entity
"Request" (invitation vocabulary) afford different AI decisions than "Order" (transactional
vocabulary)? Part 1 says no. Part 2 asks the deeper question: what structural signals *do*
AI agents read, and at what point does accumulated debt corrupt those signals?

### Further Reading

* [Affordance](https://en.wikipedia.org/wiki/Affordance) — Wikipedia overview
* [What Does OO Afford?](https://sandimetz.com/blog/2018/21/what-does-oo-afford) — Sandi Metz
* [Some Quick Thoughts on Input Validation](https://avdi.codes/some-quick-thoughts-on-input-validation/) — Avdi Grimm on code affordances
* [Affordances in Programming Languages](https://www.youtube.com/watch?v=fjH1DCa56Co) — Randy Coulman, RubyConf 2014
* [Affordances in Code Design](https://mozaicworks.com/blog/affordances-in-code-design) — Alex Bolboaca
* [The Role of Affordance in Software Design](https://hackernoon.com/affordance-in-software-design-12cc0d9d2721) — Perceived affordance in APIs

---

## Methodology & Skepticism

This is an exploratory study, not a controlled experiment. See the adversarial judge review
([judge-2-skeptic.md](experiments/02-debt-threshold/judges/judge-2-skeptic.md)) for a thorough critique:

- **n=3 per condition** is too small for statistical significance
- **Opus judges Opus** — shared biases are possible
- **Debt is confounded with complexity** — clean apps have more code and more models
- **Single model, single domain** — may not generalize
- **No human baseline** — we don't know if humans show the same effects

The strongest findings (pattern replication, convergence, zero architectural critique) are
robust to these concerns. The subtler findings (god-object gravity, binary threshold) are
directional hypotheses needing larger samples.

---

## Repository Structure

```
experiments/
  01-naming/                         # Part 1: Does Naming Matter?
    DESIGN.md                        #   Experiment design and hypotheses
    REPORT.md                        #   Cross-experiment synthesis (start here)
    run.sh                           #   Experiment runner (3 apps x 7 experiments x 2 models x 3 runs)
    analyze.sh                       #   Blind analysis generator
    judges/                          #   Independent judge reviews
      judge-{1,2,3}.md              #     Phase 1 judges (2-app comparison)
      judge-{a,b,c}.md              #     Phase 2 judges (3-app, confirmed structure)
    apps/                            #   Rails apps for this experiment
      order/                         #     "Order" with clean states (baseline)
      request/                       #     "Request" with legacy states
      request_clean/                 #     "Request" name + clean structure (control)
    01-describe-system/              #   Each experiment directory contains:
      prompt.md                      #     The exact prompt given to the AI
      config.sh                      #     Experiment type (readonly/code)
      runs/                          #     Raw AI outputs (18 per experiment)
      analysis.md                    #     Blind cross-app comparison
      summary.md                     #     Unblinded summary with conclusions
    02-rebook-feature/
    03-propose-different-time/
    04-bulk-booking/
    05-auto-assignment/
    06-cancellation-fee/
    07-happy-path/

  02-debt-threshold/                 # Part 2: At What Point Does Debt Break Things?
    DESIGN.md                        #   Experiment design, hypotheses, and predictions
    REPORT.md                        #   Main report (start here)
    run.sh                           #   Experiment runner (5 apps x 6 experiments x 3 runs)
    analyze.sh                       #   Blind analysis generator
    judges/                          #   Independent judge reviews
      judge-1-fair.md               #     Balanced review
      judge-2-skeptic.md            #     Adversarial review
      judge-3-practitioner.md       #     Engineering-manager review
    results-round2-contaminated.md   #   Preserved earlier round with analysis
    apps/                            #   Rails apps for this experiment
      alpha/                         #     Stage 0: MVP — Request = invitation
      bravo/                         #     Stage 1 Clean — Request + Order
      charlie/                       #     Stage 1 Debt — Request absorbs Order
      delta/                         #     Stage 2 Clean — + Announcement + Response
      echo/                          #     Stage 2 Debt — Request is god object
    e01-describe-system/             #   Each experiment directory contains:
      prompt.md                      #     The exact prompt
      config.sh                      #     Experiment type (readonly/code)
      runs/                          #     Raw AI outputs (6-15 per experiment)
      analysis.md                    #     Blind cross-app comparison
    e02-happy-path/
    e03-counter-proposal/
    e04-cancellation-fee/
    e05-recurring-bookings/
    e06-withdraw-response/

docs/superpowers/specs/              # Original design specifications
```

## Tech Stack

- Ruby 3.3.5, Rails 8.1.3
- SQLite, AASM (state machines), RSpec + FactoryBot
- Claude Opus 4.6 and Sonnet 4.6 via `claude -p` (automated, single-shot)
- API mode (JSON) + admin HTML section (ERB, basic auth)

## Running

```bash
# Any app
cd experiments/<experiment>/apps/<app> && bundle install && bin/rails db:create db:migrate && bundle exec rspec

# Re-run experiments
./experiments/01-naming/run.sh           # Part 1
./experiments/02-debt-threshold/run.sh   # Part 2

# Generate blind analyses
./experiments/01-naming/analyze.sh       # Part 1
./experiments/02-debt-threshold/analyze.sh # Part 2
```
