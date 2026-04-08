# Does Entity Naming Shape AI Agent Reasoning?

An experiment testing whether naming conventions in code act as affordances for AI agents — shaping how they understand, describe, and modify a codebase.

## Key Findings

**Structure, not naming, drives AI behavior.**

We initially thought the entity name ("Order" vs "Request") was shaping AI design decisions. A third control app proved us wrong. When we gave the "Request" name to a codebase with Order's clean structure, the AI treated it identically to the Order app — never like the legacy Request app.

- **AI agents read structure, not semantic associations.** The word "Request" does not activate "invitation" or "negotiation" mental models. A clean 6-state Request app behaves identically to a clean 6-state Order app. The AI reads actual code — state definitions, event names, service patterns — not the connotations of the entity name. (All 7 experiments, 42 control runs, 0 exceptions)

- **Existing code is the strongest design constraint.** When the codebase has a `decline` event, the AI reuses it. When it has 8 services, the AI creates more. When it has unusual state names, the AI comments on them. Your codebase is a style guide that agents follow with high fidelity. (Experiments 03, 05, 07)

- **Specific prompts neutralize structural differences.** When asked to "book 5 sessions at once," all three apps produced structurally identical solutions. Well-scoped prompts override both naming and structural effects. (Experiments 04, 06)

- **Model choice remains the strongest variable.** Opus vs Sonnet consistently produced larger differences than any codebase characteristic across every experiment.

### How we got here

Our initial 2-app experiment (Order vs Request, 86 runs) suggested naming matters. Three independent judges identified the confound: naming and structural complexity were entangled. We built a third app — "Request" naming with Order's clean structure — and ran 42 more experiments. Three new judges, reviewing all 128 runs blind, unanimously concluded: structure drives the effects, not naming.

Start with **[experiments/REPORT.md](experiments/REPORT.md)** for the full cross-experiment synthesis, or browse individual experiment summaries in each experiment directory.

## The Setup

Three Rails 8.1 booking apps manage the same domain — clients booking providers for services:

| | **App A: Order** | **App B: Request** | **App C: Request Clean** |
|---|---|---|---|
| Central entity | `Order` | `Request` | `Request` |
| States | 6 clean: pending, confirmed, in_progress, completed, canceled, rejected | 9 legacy: created, created_accepted, accepted, started, fulfilled, declined, missed, canceled, rejected | 6 clean (same as Order) |
| Services | 6 | 8 (extra: CreateAcceptedService, DeclineService) | 6 (same as Order) |
| Extra endpoint | No | Yes (`POST /api/requests/direct`) | No |
| Purpose | Baseline | Legacy codebase | **Control: isolates naming from structure** |

App C is the decisive test. It shares App B's entity name ("Request") but App A's clean structure. If naming matters, C should behave like B. If structure matters, C should behave like A. **Result: C always behaves like A.**

The Request app is inspired by a real production codebase (a babysitting/childcare marketplace). The original flow was: a parent sends a **request** to a specific sitter, essentially inviting them — the sitter can *accept* or *decline*, and if they don't respond, the request is *missed*. Over time the product evolved into a straightforward booking system (pick a time, get matched with a provider, pay), but the entity stayed `Request` and the invitation-era states (`created_accepted`, `declined`, `missed`) were never cleaned up. The state `created_accepted` is a relic of a two-phase flow where the sitter could be pre-assigned before formally accepting — it no longer serves a distinct purpose but remains in the schema.

The Order app represents what the Request app *would look like* if someone had refactored the naming to match the current business reality: a clean booking/order pipeline with states that read as a straightforward lifecycle. The Request Clean app proves this refactoring would not change AI behavior — the clean structure alone is what matters.

## The Experiments

7 experiments, each run 3 times per model (Opus, Sonnet) per app = 18 runs per experiment, 128 total across two phases.

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

## What Is an Affordance?

An [**affordance**](https://en.wikipedia.org/wiki/Affordance) is a property of an object or environment that suggests to a person exactly how they can interact with it. Simply put, it's an intuitive "cue" about a thing's purpose, embedded in its shape or design.

The term is most commonly used in cognitive psychology, industrial design, and user interface (UI/UX) design. This experiment tests whether the same concept applies to code: does naming an entity "Request" (with invitation-era vocabulary) afford different design decisions than naming it "Order" (with clean transactional vocabulary) — even when the underlying system is functionally identical?

### Physical World Examples
* **A light switch button:** Its raised shape suggests that it is meant to be pressed.
* **A chair:** Its flat, horizontal surface at knee level "invites" you to sit on it.
* **A doorknob:** A round knob suggests it needs to be grasped and turned, while a flat vertical handle indicates it should be pulled.

### Digital Environment Examples (UI/UX)
* **Blue underlined text:** A historically established affordance indicating a clickable link.
* **A 3D button on a website:** A gradient or drop shadow creates an illusion of depth, inviting the user to click.
* **An empty field with a blinking cursor:** Gives a clear signal that text can be typed into it.

### Where the Term Originated
1. **James Gibson (Psychologist):** First coined the term in the late 1970s. For him, an affordance meant *all* physical action possibilities an environment offers a human (or animal), regardless of whether the individual actually perceives them. For example, a rock has the affordance of "being thrown" or "serving as a hammer."
2. **Don Norman (Designer):** In his 1988 book *The Design of Everyday Things*, Norman adapted the term for the design world. He shifted the focus to **perceived affordance** — meaning the action possibilities that are *readily apparent* to the user at first glance.

### Why It Matters
Good design relies on clear affordances. If a person needs an explanatory sign to figure out how to open a door (push vs. pull) or how to submit data in an application, it means the affordances are poorly designed.

A classic example of bad affordance is the so-called "Norman Door." These are doors equipped with vertical pull handles (which naturally invite you to pull them), but they actually open by pushing. Because of the conflict between the appearance (the affordance) and the actual physical mechanism, people constantly push when they should pull, or vice versa.

## Further Reading on Affordances in Code

* [Affordance](https://en.wikipedia.org/wiki/Affordance) -- Wikipedia overview of the concept from Gibson through Norman
* [What Does OO Afford?](https://sandimetz.com/blog/2018/21/what-does-oo-afford) -- Sandi Metz on how object-oriented programming affords anthropomorphic, polymorphic, loosely-coupled designs
* [Some Quick Thoughts on Input Validation](https://avdi.codes/some-quick-thoughts-on-input-validation/) -- Avdi Grimm on how code has affordances and validation DSLs can break them
* [Affordances in Programming Languages](https://www.youtube.com/watch?v=fjH1DCa56Co) -- Randy Coulman's RubyConf 2014 talk, directly on the topic
* [Affordances in Code Design](https://mozaicworks.com/blog/affordances-in-code-design) -- Alex Bolboaca applying Don Norman's affordance concept to code structure
* [The Role of Affordance in Software Design](https://hackernoon.com/affordance-in-software-design-12cc0d9d2721) -- Perceived affordance as a criterion for API and code effectiveness

## Development

### Repository Structure

```
affordance_order/          # Rails app — "Order" with clean states
affordance_request/        # Rails app — "Request" with legacy states
affordance_request_clean/  # Rails app — "Request" name + Order's clean structure (control)
experiments/
  run.sh                   # Automated experiment runner
  analyze.sh               # Blind analysis + summary generator
  REPORT.md                # Cross-experiment report with judge synthesis
  judge-{1,2,3}.md         # Phase 1 judge reports (2-app, debated naming vs structure)
  judge-{a,b,c}.md         # Phase 2 judge reports (3-app, unanimously confirmed structure)
  01-describe-system/      # Each experiment has:
    prompt.md              #   The prompt given to the AI
    config.sh              #   Type (readonly/code)
    runs/                  #   Raw AI outputs (18 per experiment)
    analysis.md            #   Blind comparison (App A vs App B vs App C)
    summary.md             #   Unblinded summary with conclusions
  02-rebook-feature/
  ...
  07-happy-path/
docs/superpowers/
  specs/                   # Design specifications
  plans/                   # Implementation plans
```

### Tech Stack

- Ruby 3.3.5, Rails 8.1.3
- SQLite, AASM (state machines), RSpec + FactoryBot
- Claude Opus 4.6 and Sonnet 4.6 (via `claude -p`)

### Running the Apps

```bash
cd affordance_order && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd affordance_request && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd affordance_request_clean && bundle install && bin/rails db:create db:migrate && bundle exec rspec
```

### Re-running Experiments

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
