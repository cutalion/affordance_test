# Do AI Coding Assistants Understand Your Architecture — Or Just Copy It?

An experiment in two parts, testing how code structure shapes AI agent behavior.

**Part 1** found that entity naming ("Order" vs "Request") doesn't matter — AI reads structure,
not semantics. **Part 2** found something more troubling: AI faithfully replicates whatever
architectural patterns it finds, including bugs, god objects, and semantic mismatches — and
it will never tell you anything is wrong.

---

## The Headline Results

### The AI will never tell you your code has a problem

We asked Claude Opus to describe 5 different codebases, 3 times each. One codebase has a
model called `Request` that simultaneously serves as an invitation, a booking, a fulfillment
tracker, and an announcement response. The AI described this god object as "the core
transactional entity" with the same confident, professional tone it used for a cleanly
separated four-model architecture. Across 30 descriptive runs, **zero mentioned any design
problem.** ([E01 analysis](experiments_phase3b/e01-describe-system/analysis.md))

### Clean architecture produced more bugs than messy code

In our counter-proposal experiment, the clean-architecture apps delegate to sub-services
inside transactions. This delegation pattern contains a subtle bug (`return` after
`raise ActiveRecord::Rollback` — the return never executes, and the method silently continues
to the success path). The AI copied this bug into **all 6 clean-app runs**. The messy apps
create payments inline — a simpler pattern with no such bug. **All 6 debt-app runs were
bug-free.** Most Rails developers would not catch this in review.
([E03 analysis](experiments_phase3b/e03-counter-proposal/analysis.md))

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
([E05 analysis](experiments_phase3b/e05-recurring-bookings/analysis.md))

### Same prompt, same codebase, 3 different architectures = a problem

Run the same prompt 3 times on a clean codebase: you get the same diff. Run it on a messy
codebase: you get different approaches each time. In E06, a clean app produced near-identical
code across 3 runs (same service, same tests, zero migrations). The debt app diverged on
column choices, validation, and routing. **Cross-run variance is a measurable signal of
architectural ambiguity** — and a practical diagnostic you can use today.
([E06 analysis](experiments_phase3b/e06-withdraw-response/analysis.md))

---

## How It Works

### Part 1: Does Naming Matter? (3 apps, 128 runs)

We built two identical Rails booking apps — one with the central entity named "Order" (clean
states) and one named "Request" (legacy invitation-era states from a real production
codebase). Initial results suggested naming matters. Then we built a third app: "Request"
name with Order's clean structure.

**Result:** The control app always behaved like Order, never like legacy Request. **Structure
drives AI behavior, not naming.** Three independent judges confirmed unanimously.

Full report: **[experiments/REPORT.md](experiments/REPORT.md)**

### Part 2: At What Point Does Debt Break Things? (5 apps, 72 runs)

We built 5 apps simulating a babysitting marketplace evolving through stages of complexity,
with two tracks — one that refactors properly and one that accumulates technical debt:

| App | Stage | What happened |
|-----|-------|--------------|
| **app_alpha** | MVP | Request = invitation. The name fits perfectly. |
| **app_bravo** | Stage 1 Clean | Someone extracted an Order model. Clean separation. |
| **app_charlie** | Stage 1 Debt | Nobody refactored. Request absorbs the booking lifecycle. |
| **app_delta** | Stage 2 Clean | Announcements added. Response gets its own model. |
| **app_echo** | Stage 2 Debt | Announcements added. Responses ARE Requests. God object. |

We ran 6 experiments — 2 descriptive ("describe this system," "walk the happy path") and
4 code-generation ("add counter-proposals," "add cancellation fees," "add recurring bookings,"
"withdraw an announcement response"). Each prompt ran 3 times per app, blind, with fresh
databases.

Full report: **[experiments_phase3b/report-round3.md](experiments_phase3b/report-round3.md)**

---

## Key Findings (Part 2)

| # | Finding | Strength | Surprise level |
|---|---------|----------|---------------|
| 1 | AI describes debt as intentional design, never flags problems | Strong | Expected |
| 2 | Clean codebases produce identical AI output across runs; debt produces variance | Strong | Moderate |
| 3 | AI copies existing patterns including bugs — 7/7 bug instances in clean apps | Strong | High |
| 4 | Debt codebases pull AI toward piling onto existing models | Moderate | Expected |
| 5 | Clean architecture's indirection creates *more* surface for subtle bugs | Moderate | High |
| 6 | Naming mismatches propagate into error messages, tests, comments | Moderate | Expected |
| 7 | The threshold is model separation, not debt volume | Moderate | Moderate |

### The Practical Takeaways

1. **Don't rely on AI to find refactoring targets.** It will never tell you a model is
   overloaded.
2. **Review AI PRs for architecture, not just correctness.** Tests passing doesn't mean the
   right model was chosen.
3. **Use the 3-run convergence test.** Run the same prompt 3 times. Divergent architectures
   mean the codebase is ambiguous.
4. **Document your error-handling patterns.** The AI copies whatever transaction pattern it
   finds — make sure what it finds is correct.
5. **Refactor before structural features, not before simple ones.** Adding a state to a god
   object works fine. Creating a new domain concept on one doesn't.

---

## What Is an Affordance?

An [**affordance**](https://en.wikipedia.org/wiki/Affordance) is a property of an object that
suggests how to interact with it. A door handle invites pulling; a flat plate invites pushing.
Good design relies on clear affordances. A "Norman Door" — a pull handle on a push door — is
the classic example of bad affordance.

This experiment tests whether the same concept applies to code: does naming an entity
"Request" (with invitation-era vocabulary) afford different AI design decisions than naming it
"Order" (with transactional vocabulary)? Part 1 says no — AI reads structure, not
connotations. Part 2 asks the deeper question: what structural signals *do* AI agents read,
and at what point does accumulated debt corrupt those signals?

### Further Reading

* [Affordance](https://en.wikipedia.org/wiki/Affordance) — Wikipedia overview
* [What Does OO Afford?](https://sandimetz.com/blog/2018/21/what-does-oo-afford) — Sandi Metz
* [Affordances in Programming Languages](https://www.youtube.com/watch?v=fjH1DCa56Co) — Randy Coulman, RubyConf 2014

---

## Methodology & Skepticism

This is an exploratory study, not a controlled experiment. The adversarial judge review
([judge-2-skeptic.md](experiments_phase3b/judge-2-skeptic.md)) identifies real limitations:

- **n=3 per condition** is too small for statistical significance
- **Opus judges Opus** — shared biases are possible
- **Debt is confounded with complexity** — clean apps have more code and more models
- **Single model, single domain** — may not generalize
- **No human baseline** — we don't know if humans would show the same effects

The strongest findings (pattern replication, convergence signal, zero architectural critique)
are robust to these concerns. The subtler findings (god-object gravity, binary threshold) are
directional hypotheses that would benefit from larger sample sizes.

We ran the experiment twice. Round 2 had schema contamination (prior experiment branches left
artifacts in the databases). Round 3 fixed this with fresh databases per run. All findings
reproduced, confirming they are not artifacts.

---

## Repository Structure

```
affordance_order/                # Part 1: Rails app — "Order" with clean states
affordance_request/              # Part 1: Rails app — "Request" with legacy states
affordance_request_clean/        # Part 1: Rails app — "Request" name + clean structure (control)
experiments/                     # Part 1: 7 experiments, 128 runs, 6 judges
  REPORT.md                      #   Cross-experiment synthesis
app_alpha/                       # Part 2: Stage 0 MVP (invitation)
app_bravo/                       # Part 2: Stage 1 Clean (Request + Order)
app_charlie/                     # Part 2: Stage 1 Debt (Request absorbs Order)
app_delta/                       # Part 2: Stage 2 Clean (+ Announcement + Response)
app_echo/                        # Part 2: Stage 2 Debt (Request is god object)
experiments_phase3b/             # Part 2: 6 experiments, 72 runs, 3 judges
  report-round3.md               #   Main report (start here)
  judge-{1,2,3}-*.md             #   Independent judge reviews
  e01-describe-system/           #   Each experiment has prompt.md, analysis.md, runs/
  e02-happy-path/
  e03-counter-proposal/
  e04-cancellation-fee/
  e05-recurring-bookings/
  e06-withdraw-response/
docs/superpowers/specs/          # Design specifications
```

## Tech Stack

- Ruby 3.3.5, Rails 8.1.3
- SQLite, AASM (state machines), RSpec + FactoryBot
- Claude Opus 4.6 via `claude -p` (automated, single-shot)

## Running

```bash
# Part 1 apps
cd affordance_order && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd affordance_request && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd affordance_request_clean && bundle install && bin/rails db:create db:migrate && bundle exec rspec

# Part 2 apps
cd app_alpha && bundle install && bin/rails db:create db:migrate && bundle exec rspec
# ... same for app_bravo, app_charlie, app_delta, app_echo

# Re-run experiments
./experiments/run.sh                    # Part 1
./experiments_phase3b/run.sh            # Part 2
./experiments_phase3b/analyze.sh        # Generate blind analyses
```
