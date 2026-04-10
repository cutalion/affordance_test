# Experiment 02: At What Point Does Debt Break AI-Assisted Development?

## Goal

Determine at what level of accumulated technical debt AI agents start making poor design decisions. Instead of surgical lab variants, simulate realistic domain evolution where a codebase outgrows its original model without refactoring.

## Hypothesis

As technical debt accumulates (domain model diverges from business reality), AI agents make increasingly poor design decisions because they follow the misleading structure and vocabulary of existing code. The threshold is expected between stage 1 (single model overload) and stage 2 (god object with three business meanings).

## Prior Findings (Experiment 01)

The naming experiment (128 runs, 3 apps, 7 experiments) established:
- Entity naming alone has no detectable effect on AI behavior
- Codebase structure (states, services, patterns) is the strongest design constraint
- Existing states act as attractors — the AI reuses what it finds
- Model choice (Opus vs Sonnet) matters more than any codebase characteristic

This experiment extends the question: **if structure matters, how much structural debt is required before AI behavior degrades?**

## Domain Evolution

The apps simulate a babysitting marketplace evolving through three stages:

### Stage 0: MVP — Invitation Model

A client invites a specific provider. Provider accepts or declines. The entity name "Request" fits perfectly — it IS a request/invitation.

### Stage 1: Growth — Order Lifecycle

Business needs payments, cancellation, reviews, stats. The "accepted invitation" must become a trackable booking with lifecycle management.

- **Clean path**: The team refactors. Accepted Request creates an Order. Two models, clear responsibilities.
- **Debt path**: Nobody refactors. Request absorbs payment, cancellation, and review features. `accepted` now means "paid and confirmed" instead of "provider said yes." `AcceptService` captures payment — nothing to do with accepting an invitation.

### Stage 2: Marketplace — Announcements

Clients can post job announcements, providers respond, client picks one.

- **Clean path**: Announcement + Response models. Selected Response creates an Order. Three entry paths to Order, each with its own model.
- **Debt path**: Announcement responses ARE Requests. `Announcement has_many :requests`. Selecting a response reuses `AcceptService`. Request now means three different things: invitation, booking, and announcement response.

## The Five Apps

| App | Stage | Track | Models | Request is... |
|-----|-------|-------|--------|--------------|
| alpha | 0: MVP | — | 4 | An invitation (fits perfectly) |
| bravo | 1 | Clean | 7 | A matching mechanism (+ Order for fulfillment) |
| charlie | 1 | Debt | 5 | The entire booking lifecycle |
| delta | 2 | Clean | 9 | A matching mechanism (+ Order + Announcement + Response) |
| echo | 2 | Debt | 6 | Everything: invitation, booking, fulfillment, announcement response |

## Experiments

| # | Experiment | Type | Apps | Prompt | What it tests |
|---|-----------|------|------|--------|--------------|
| E01 | Describe System | descriptive | all 5 | "Describe what this system does" | Does the AI notice or flag debt? |
| E02 | Happy Path | descriptive | all 5 | "What is the happy path?" | Does debt surface in walkthrough? |
| E03 | Counter-Proposal | code | B,C,D,E | "Add counter-proposals for bookings" | Where do bugs appear in existing patterns? |
| E04 | Cancellation Fee | code | B,C,D,E | "Charge 50% if canceled <24h" | Where does AI place new business data? |
| E05 | Recurring Bookings | code | B,C,D,E | "Add recurring weekly bookings (5 sessions)" | Does AI create a new model or pile onto existing? |
| E06 | Withdraw Response | code | D,E | "Provider withdraws announcement response" | Same feature, one has a model for it, one doesn't |

### Run Matrix

| Experiment | MVP | Stage 1 Clean | Stage 1 Debt | Stage 2 Clean | Stage 2 Debt | Runs |
|---|---|---|---|---|---|---|
| E01 Describe System | 3 | 3 | 3 | 3 | 3 | 15 |
| E02 Happy Path | 3 | 3 | 3 | 3 | 3 | 15 |
| E03 Counter-Proposal | | 3 | 3 | 3 | 3 | 12 |
| E04 Cancellation Fee | | 3 | 3 | 3 | 3 | 12 |
| E05 Recurring Bookings | | 3 | 3 | 3 | 3 | 12 |
| E06 Withdraw Response | | | | 3 | 3 | 6 |
| **Total** | **6** | **15** | **15** | **18** | **18** | **72** |

All runs use Claude Opus only. 3 runs per cell.

## Behavioral Markers

### Per-experiment

**E01 — Describe System:** Does the AI notice `AcceptService` handles payment? Does it describe states by their name or their actual function?

**E02 — Happy Path:** In stage 2 debt, which of 3 Request flows is "happy"? Does the AI get tangled explaining Request's multiple meanings?

**E03 — Counter-Proposal:** Model placement (Order vs Request). Decline path reuse. Files touched due to mixed responsibilities.

**E04 — Cancellation Fee:** Does the AI apply the fee correctly despite `accepted` meaning "paid"? State transition correctness.

**E05 — Recurring Bookings:** What initial state do recurring bookings start in? Does the AI create Orders (clean) or Requests (debt)?

**E06 — Withdraw Response:** In clean app, new `withdrawn` state on Response. In debt app, what state/event? Can the AI distinguish announcement-response-Requests from invitation-Requests?

### Cross-experiment aggregate

1. **Files touched per implementation** — debt apps should spread changes across more files
2. **States invented vs reused** — debt apps should show more reuse of semantically-wrong existing states
3. **Correct model placement** — rate at which AI puts features on the appropriate model
4. **Implementation coherence** — does vocabulary overload cause logical errors?
5. **Scope creep** — does the AI add more than requested because mixed responsibilities pull in adjacent concerns?

## Predictions (written before running)

| Prediction | Rationale |
|---|---|
| Stage 1 debt shows measurable but small divergence from stage 1 clean | Single model overload — `declined` will attract counter-proposal decline, but cancellation fee will be implemented correctly |
| Stage 2 debt shows large divergence from stage 2 clean | God object with 3 business meanings — AI cannot distinguish which "kind" of Request it's working with |
| E06 (withdraw response) shows the largest clean/debt gap | The task directly requires distinguishing Request types, which is impossible without model boundaries |
| E05 (recurring bookings) reveals initial-state confusion in debt apps | The AI must choose between invitation semantics and booking semantics for new Requests |
| E01/E02 (readonly) show debt apps get less accurate system descriptions | Mixed responsibilities are harder to describe coherently |
| The threshold is between stage 1 and stage 2 | One overloaded model is manageable; a god object serving three flows is where AI behavior breaks down |

## Methodology

- **Blind analysis**: Apps labeled A through E without revealing which is clean vs debt
- **Memory isolation**: CLAUDE.md and project memory hidden during runs
- **Fresh databases**: `db:create db:migrate` before each code experiment
- **Independent judges**: 3 judges review raw runs blind
- Code experiments append: "Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation."
