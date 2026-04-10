# Experiment 01: Does Entity Naming Shape AI Agent Reasoning?

## Goal

Determine whether the *name* of a central domain entity affects how AI coding agents reason about and modify a codebase. Specifically: does calling something "Request" (invitation vocabulary) vs "Order" (transactional vocabulary) cause AI agents to make different architectural decisions?

## Hypothesis

Entity naming creates "affordances" — cognitive shortcuts that shape how agents (human or AI) interact with code. A model called "Request" should trigger invitation/negotiation mental models, while "Order" should trigger transactional/fulfillment mental models. This would manifest as different state machines, different service boundaries, and different feature implementations.

## The Domain

A babysitting marketplace where clients book providers. The core workflow: client creates a booking, provider accepts, service happens, payment is captured, review is left.

In a real production system, this entity was originally called "Request" (from when it was an invitation system) but evolved into a full booking/order pipeline without being renamed.

## The Three Apps

| | **Order** | **Request** | **Request Clean** |
|---|---|---|---|
| Entity name | Order | Request | Request |
| States | 6 clean: pending, confirmed, in_progress, completed, canceled, rejected | 9 legacy: created, created_accepted, accepted, started, fulfilled, declined, missed, canceled, rejected | 6 clean (same as Order) |
| Services | 6 | 8 (+ CreateAcceptedService, DeclineService) | 6 (same as Order) |
| Extra endpoint | No | Yes (POST /api/requests/direct) | No |
| Purpose | Baseline | Legacy codebase | **Control: isolates naming from structure** |

The Request Clean app is the decisive test. It shares Request's entity name but Order's clean structure. If naming matters, it should behave like Request. If structure matters, it should behave like Order.

## Experiments

| # | Experiment | Type | Prompt | What it tests |
|---|-----------|------|--------|--------------|
| 01 | Describe System | descriptive | "Describe what this system does" | Framing and vocabulary choices |
| 02 | Rebook Feature | code | "Add re-booking with the same provider" | State machine extension patterns |
| 03 | Counter-Proposal | code | "Provider can propose a different time" | Model placement and state reuse |
| 04 | Bulk Booking | code | "Book 5 sessions at once" | Batch creation patterns |
| 05 | Auto-Assignment | code | "Auto-assign highest-rated provider" | Service architecture decisions |
| 06 | Cancellation Fee | code | "Charge 50% if canceled <24h before" | Financial logic placement |
| 07 | Happy Path | descriptive | "Walk through the happy path step by step" | Domain understanding and scope |

### Run Matrix

- 3 apps x 7 experiments x 2 models (Opus + Sonnet) x 3 runs = **126 runs**
- Plus 2 additional validation runs = **128 total**

## Key Questions

1. Does the word "Request" activate invitation/negotiation mental models in AI agents?
2. Does the word "Order" activate transactional/fulfillment mental models?
3. When naming and structure conflict (Request Clean), which wins?
4. Does model choice (Opus vs Sonnet) interact with naming effects?
5. Do specific prompts neutralize any naming effects?

## Analysis Approach

### Blind comparison
Apps labeled A, B, C without revealing names. Analyzer compares implementations looking for structural differences, design quality, and correctness.

### Unblinded summary
After blind analysis, reveal identities and connect findings to naming vs structure.

### Independent judges
Two rounds of 3 independent judges each (6 total). First round: 2-app comparison. Second round: 3-app comparison with control.

### Pairwise comparisons
- A vs B: Order vs Request (naming + structure differ)
- A vs C: Order vs Request Clean (naming differs, structure same)
- B vs C: Request vs Request Clean (naming same, structure differs)

The A-vs-C comparison is decisive. If A and C produce identical AI behavior despite different names, naming has no effect.

## Methodology

- **Blind analysis**: Apps labeled A, B, C without revealing which is which
- **Memory isolation**: CLAUDE.md hidden during runs to prevent experiment contamination
- **Both models**: Opus and Sonnet to test model interaction effects
- Code experiments append: "Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation."
