# Does Entity Naming Shape AI Agent Reasoning?

An experiment exploring how naming conventions in code affect the way AI agents (Claude Opus and Sonnet) understand, describe, and modify a codebase.

## The Setup

Two structurally related Rails 8.1 booking apps manage the same domain — clients booking providers for services. They differ in one key way:

| | **Order App** | **Request App** |
|---|---|---|
| Central entity | `Order` | `Request` |
| States | 6 clean: pending, confirmed, in_progress, completed, canceled, rejected | 9 legacy: created, created_accepted, accepted, started, fulfilled, declined, missed, canceled, rejected |
| Services | 6 | 8 (extra: CreateAcceptedService, DeclineService) |
| Origin | Clean design | Evolved from an invitation system; never refactored |

The Request app is inspired by a real production codebase (a babysitting/childcare marketplace). The original flow was: a parent sends a **request** to a specific sitter, essentially inviting them — the sitter can *accept* or *decline*, and if they don't respond, the request is *missed*. Over time the product evolved into a straightforward booking system (pick a time, get matched with a provider, pay), but the entity stayed `Request` and the invitation-era states (`created_accepted`, `declined`, `missed`) were never cleaned up. The state `created_accepted` is a relic of a two-phase flow where the sitter could be pre-assigned before formally accepting — it no longer serves a distinct purpose but remains in the schema.

The Order app represents what the Request app *would look like* if someone had refactored the naming to match the current business reality: a clean booking/order pipeline with states that read as a straightforward lifecycle.

## The Experiments

7 experiments, each run 3 times per model (Opus, Sonnet) per app = 12 runs per experiment, 86 total.

| # | Experiment | Type | Prompt (abbreviated) |
|---|---|---|---|
| 01 | Describe System | readonly | "Describe what this system does" |
| 02 | Rebook Feature | code | "Add re-booking with the same provider" |
| 03 | Counter-Proposal | code | "Provider can propose a different time" |
| 04 | Bulk Booking | code | "Book 5 sessions at once" |
| 05 | Auto-Assignment | code | "Auto-assign highest-rated provider" |
| 06 | Cancellation Fee | code | "Charge 50% if canceled <24h before" |
| 07 | Happy Path | readonly | "Walk through the happy path step by step" |

Each experiment was run via `claude -p` with the app directory as working context. CLAUDE.md was hidden during runs to prevent contamination. Code experiments created git branches with the resulting diffs.

## Key Findings

**AI agents produced measurably different outputs depending on which app they worked with.** The differences were not in comprehension — no agent misunderstood either app — but in design judgment.

### The strongest results

- **Clean states invite lifecycle reasoning.** When asked to add a rebook feature, 4/6 Order runs added a `rebookable?` state check. 0/6 Request runs did — the complex state machine discouraged the AI from even attempting eligibility logic. (Experiment 02)

- **Existing vocabulary constrains new designs.** The Request app's `decline` event caused all 6 runs to treat "client declines counter-proposal" as terminal. 2/6 Order runs instead returned to `pending`, creating a negotiation loop — an arguably better design that no Request run even considered. (Experiment 03)

- **Specific prompts neutralize the effect.** When asked to "book 5 sessions at once," both apps produced structurally identical solutions. No room for interpretation = no naming effect. (Experiment 04)

- **Model choice matters more than naming.** Opus vs Sonnet consistently produced larger differences than Order vs Request across every experiment.

### The central caveat

Three independent judge reviews (see `experiments/judge-{1,2,3}.md`) identified a key limitation: **naming and structural complexity are confounded.** The Request app isn't just named differently — it has more states, more services, and more endpoints. The experiment can't prove whether differences are caused by the *name* "Request" or by the *structural complexity* that name implies. A follow-up with a third app ("Request naming + clean states") would isolate the variable.

## Repository Structure

```
affordance_order/          # Rails app — "Order" with clean states
affordance_request/        # Rails app — "Request" with legacy states
experiments/
  run.sh                   # Automated experiment runner
  analyze.sh               # Blind analysis + summary generator
  REPORT.md                # Cross-experiment report with judge synthesis
  judge-{1,2,3}.md         # Independent reviewer reports
  01-describe-system/      # Each experiment has:
    prompt.md              #   The prompt given to the AI
    config.sh              #   Type (readonly/code)
    runs/                  #   Raw AI outputs (12 per experiment)
    analysis.md            #   Blind comparison (App A vs App B)
    summary.md             #   Unblinded summary with conclusions
  02-rebook-feature/
  ...
  07-happy-path/
docs/superpowers/
  specs/                   # Design specifications
  plans/                   # Implementation plans
```

## Running the Apps

```bash
cd affordance_order && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd affordance_request && bundle install && bin/rails db:create db:migrate && bundle exec rspec
```

## Re-running Experiments

```bash
# Run all experiments (skips existing outputs)
./experiments/run.sh

# Run a single experiment
./experiments/run.sh 04-bulk-booking

# Run specific experiment/model/app/count
./experiments/run.sh 04-bulk-booking sonnet order 1

# Generate analyses and summaries
./experiments/analyze.sh
```

## Tech Stack

- Ruby 3.3.5, Rails 8.1.3
- SQLite, AASM (state machines), RSpec + FactoryBot
- Claude Opus 4.6 and Sonnet 4.6 (via `claude -p`)

## Read the Full Report

Start with **[experiments/REPORT.md](experiments/REPORT.md)** for the cross-experiment synthesis, or browse individual experiment summaries in each experiment directory.
