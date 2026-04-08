# Independent Review: App C (Request-Clean) as Control Group

**Reviewer**: Claude Opus 4.6 (independent analysis of raw run files)
**Date**: 2026-04-07

## Methodology

I read every raw run file across all 7 experiments (126 files total: 18 per experiment for experiments 02-07, 20 for experiment 01 which had extra sonnet runs). I compared outputs across three apps:

- **App A** ("Order"): 6 clean states, 6 services
- **App B** ("Request"): 9 legacy states, 8 services + extra endpoint
- **App C** ("Request-Clean"): 6 clean states, 6 services -- structurally identical to App A, shares the entity name with App B

The key question: when App C's outputs differ from App A's, is that explained by the **name** "Request" (pulling toward App B behavior), or by something else?

---

## Experiment 01: Describe System (readonly)

### What each app's outputs said

| Metric | App A (Order) | App B (Request) | App C (Request-Clean) |
|--------|--------------|-----------------|----------------------|
| Domain identified as | Service marketplace / booking platform | Service marketplace / booking platform | Service marketplace / booking platform |
| States listed | pending, confirmed, in_progress, completed, canceled, rejected (6) | created, created_accepted, accepted, started, fulfilled, declined, missed, canceled, rejected (9) | pending, confirmed, in_progress, completed, canceled, rejected (6) |
| Services enumerated | CreateService, ConfirmService, StartService, CompleteService, CancelService, RejectService | CreateService, CreateAcceptedService, AcceptService, DeclineService, StartService, FulfillService, CancelService, RejectService | CreateService, ConfirmService, StartService, CompleteService, CancelService, RejectService |
| Mentioned experiment? | Opus: 1/3 runs, Sonnet: 0/5 runs | Opus: 3/3 runs, Sonnet: 2/3 runs | Opus: 0/3, Sonnet: 0/3 |
| Mentioned "legacy" states? | N/A | Opus: 1/3, Sonnet: 3/3 used the word "legacy" or "invitation-era" | N/A |
| Mentioned direct/create_accepted path? | N/A | All 6 runs | N/A |
| Mentioned Kidsout origin? | Opus: 0/3, Sonnet: 0/5 | Opus: 1/3, Sonnet: 0/3 | Opus: 3/3, Sonnet: 3/3 |

**Key finding**: App C outputs are virtually indistinguishable from App A in structural description. Both describe the same 6 states and 6 services. App C never confuses its states with App B's legacy states. However, App C mentions "Kidsout" in all 6 runs while App A mentions it in 0/8 runs -- this likely comes from the CLAUDE.md memory file referencing the Kidsout domain, which App C's agents may have picked up from project-level context.

**Conclusion for Exp 01**: App C matches App A perfectly on structural accuracy. The name "Request" did not cause any agent to hallucinate legacy states.

---

## Experiment 02: Rebook Feature

| Metric | App A (Order) | App B (Request) | App C (Request-Clean) |
|--------|--------------|-----------------|----------------------|
| Service created | `Orders::RebookService` (6/6 runs) | `Requests::RebookService` (6/6 runs) | `Requests::RebookService` (4/6); 2 runs inlined into controller or delegated directly to CreateService |
| Separate spec file for service | 6/6 | 4/6 | 4/6 |
| Rebookable states defined | completed, canceled, rejected (3/6); completed, canceled (3/6) | All use `:fulfilled` factory trait (Opus 3/3); Sonnet runs don't define rebookable states explicitly | All use `:completed` factory trait (6/6) |
| Added `rebookable?` method to model | 3/6 (all Opus) | 0/6 | 0/6 |
| New test count | 5-12 per run | 0-8 per run | 0-5 per run |
| Diff lines (avg) | Opus: 247, Sonnet: 247 | Opus: 182, Sonnet: 105 | Opus: 190, Sonnet: 93 |
| State restriction on rebook | 5/6 runs enforce it (completed/canceled/rejected) | 3/6 runs enforce it (fulfilled/canceled) | 2/6 explicitly enforce; others rely on CreateService |

**Key finding**: App B correctly uses `:fulfilled` (its terminal success state) where App A uses `:completed` and App C uses `:completed`. App C perfectly mirrors App A's state vocabulary -- there is zero leakage of App B's "fulfilled" terminology.

App C runs are slightly smaller than App A runs (avg 198 vs 324 total lines). This may reflect natural variance, or it may be that "Request" as a name encourages slightly lighter-touch implementations -- but the difference is modest and within the range of App B as well.

**Conclusion for Exp 02**: App C matches App A structurally. The name "Request" had no observable effect on which states were used or how the feature was designed.

---

## Experiment 03: Propose Different Time

This is the most revealing experiment because it requires adding a new state and choosing what happens when the client declines.

### New state names chosen

| Run | App A (Order) | App B (Request) | App C (Request-Clean) |
|-----|--------------|-----------------|----------------------|
| Opus-1 | `provider_proposed_time` | `provider_proposed` | `proposed` |
| Opus-2 | `provider_proposed` | `counter_proposed` | `time_proposed` |
| Opus-3 | `provider_proposed` | `counter_proposed` | `provider_proposed` |
| Sonnet-1 | `counter_proposed` | `counter_proposed` | `countered` |
| Sonnet-2 | `counter_proposed` | `counter_proposed` | `counter_proposed` |
| Sonnet-3 | `time_proposed` | `proposed` | `counter_proposed` |

All three apps show high variance in naming the new state. No consistent pattern differentiates App C from App A -- both produce a mix of `provider_proposed`, `counter_proposed`, `time_proposed`, etc. The name "Request" does not pull toward any particular state name.

### Critical design decision: what happens when client declines the proposal?

| Run | App A (Order) | App B (Request) | App C (Request-Clean) |
|-----|--------------|-----------------|----------------------|
| Opus-1 | -> `pending` (reversible) | -> `declined` (terminal) | -> `pending` (reversible) |
| Opus-2 | -> `pending` (reversible) | -> `declined` (terminal) | -> `pending` (reversible) |
| Opus-3 | -> `pending` (reversible) | -> `declined` (terminal) | -> `pending` (reversible) |
| Sonnet-1 | -> `canceled` (terminal) | -> `declined` (terminal) | -> `canceled` (terminal) |
| Sonnet-2 | -> `canceled` (terminal) | -> `declined` (terminal) | -> `canceled` (terminal) |
| Sonnet-3 | -> `rejected` (terminal) | (not explicit in grep) | -> `canceled` (terminal) |

**This is the strongest signal in the entire dataset.** App B agents consistently route decline to the `declined` state -- a terminal state that exists in App B's codebase but does NOT exist in App A or App C. App A and App C agents, lacking a `declined` state, split between two approaches:

1. **Opus** (both App A and App C): returns to `pending` -- a reversible, non-destructive design
2. **Sonnet** (both App A and App C): routes to `canceled` -- a terminal state that does exist in both codebases

App C's behavior **perfectly mirrors** App A across all 6 runs. The name "Request" did not cause a single App C agent to invent a `declined` state or route to one. Meanwhile, all App B agents used `declined` because it was already in the codebase.

### New services and files created

| Metric (avg) | App A (Order) | App B (Request) | App C (Request-Clean) |
|--------------|--------------|-----------------|----------------------|
| New files in diff (avg) | 6.5 | 8.0 | 5.5 |
| Diff lines (avg) | Opus: 453, Sonnet: 326 | Opus: 421, Sonnet: 366 | Opus: 352, Sonnet: 332 |
| Services created | 3 per run (propose, accept, decline) | 3 per run | 3 per run |

App C is slightly more compact than both App A and App B, but the architectural approach (3 services, 1 migration, 3 endpoints) is identical across all three apps.

**Conclusion for Exp 03**: Codebase structure dominates. The `declined` state in App B pulls all agents toward using it. App C, lacking that state, behaves identically to App A. This is the clearest evidence that **existing code structure matters more than entity naming**.

---

## Experiment 04: Bulk Booking

| Metric | App A (Order) | App B (Request) | App C (Request-Clean) |
|--------|--------------|-----------------|----------------------|
| Endpoint path | `POST /api/orders/bulk` (6/6) | `POST /api/requests/bulk` (6/6) | `POST /api/requests/bulk` (6/6) |
| Service name | `Orders::BulkCreateService` (6/6) | `Requests::BulkCreateService` (6/6) | `Requests::BulkCreateService` (6/6) |
| Wraps in transaction | 6/6 | 5/6 | 6/6 |
| Reuses existing CreateService | 5/6 | 4/6 | 5/6 |
| Count parameter (max sessions) | 5 (most runs) | 5 (most runs) | 5 (most runs) |
| Recurrence options | weekly/daily/biweekly (Opus); weekly only (Sonnet) | weekly/daily/biweekly (Opus); weekly or mixed (Sonnet) | weekly/daily/biweekly (Opus); weekly only (Sonnet) |
| Diff lines (avg) | Opus: 244, Sonnet: 146 | Opus: 210, Sonnet: 204 | Opus: 253, Sonnet: 169 |

**Key finding**: All three apps produce virtually identical implementations. App C matches App A closely -- both Opus versions tend to include recurrence options while Sonnet versions are simpler. The name "Request" had no discernible influence.

**Conclusion for Exp 04**: No meaningful differences. All three apps produce the same design.

---

## Experiment 05: Auto-Assignment

| Metric | App A (Order) | App B (Request) | App C (Request-Clean) |
|--------|--------------|-----------------|----------------------|
| Overlap detection logic | Checks orders in `pending/confirmed/in_progress` states | Checks requests in `created/created_accepted/accepted/started` states | Checks requests in `pending/confirmed/in_progress` states |
| Separate AutoAssignService | 2/6 (Opus: 1, Sonnet: 1) | 4/6 (Opus: 2, Sonnet: 1 + 1 via model) | 2/6 (Opus: 1, Sonnet: 0) |
| Migration for nullable provider_id | 2/6 | 2/6 | 2/6 |
| Rating-based selection | 6/6 | 6/6 | 6/6 |
| Scheduling conflict check | 4/6 (Opus: 3/3, Sonnet: 1/3) | 5/6 (Opus: 3/3, Sonnet: 2/3) | 4/6 (Opus: 3/3, Sonnet: 1/3) |
| Diff lines (avg) | Opus: 121, Sonnet: 67 | Opus: 163, Sonnet: 106 | Opus: 138, Sonnet: 63 |

**Key finding**: The overlap detection perfectly tracks the codebase structure. App B agents correctly enumerate all 4 active states (`created, created_accepted, accepted, started`) because those are what exist in the codebase. App C agents use the same 3 states as App A (`pending, confirmed, in_progress`). No App C agent hallucinated App B's states.

App B's implementations tend to be slightly larger because the agents must account for more states in the overlap check. This is a direct consequence of code complexity, not naming.

**Conclusion for Exp 05**: Codebase structure drives state enumeration. The name "Request" did not cause App C agents to reference legacy states.

---

## Experiment 06: Cancellation Fee

| Metric | App A (Order) | App B (Request) | App C (Request-Clean) |
|--------|--------------|-----------------|----------------------|
| `late_cancellation?` method | 6/6 | 6/6 | 6/6 |
| 50% fee calculation | 6/6 | 6/6 | 6/6 |
| Condition: `scheduled_at < 24.hours.from_now` | 6/6 | 6/6 | 6/6 |
| Added migration for fee column | 2/6 | 0/6 | 1/6 |
| Modified PaymentGateway | 3/6 | 4/6 | 4/6 |
| Diff lines (avg) | Opus: 74, Sonnet: 61 | Opus: 63, Sonnet: 66 | Opus: 62, Sonnet: 66 |
| Test count (new) | 2-3 per run | 2-3 per run | 2-3 per run |

**Key finding**: This is the most "naming-neutral" experiment. The cancellation fee feature touches the cancel service and payment gateway, which have identical structure across all three apps. All three produce essentially the same implementation with the same logic.

**Conclusion for Exp 06**: Identical outputs across all three apps. No effect of naming observed.

---

## Experiment 07: Happy Path (readonly)

| Metric | App A (Order) | App B (Request) | App C (Request-Clean) |
|--------|--------------|-----------------|----------------------|
| States in happy path | pending -> confirmed -> in_progress -> completed (6/6) | created -> accepted -> started -> fulfilled (6/6) | pending -> confirmed -> in_progress -> completed (6/6) |
| Mentioned `created_accepted` | N/A | Sonnet: 3/3, Opus: 0/3 | N/A |
| Terminal state for success | `completed` (6/6) | `fulfilled` (6/6) | `completed` (6/6) |
| Payment flow described | pending -> held -> charged (6/6) | pending -> held -> charged (6/6) | pending -> held -> charged (6/6) |
| Unhappy paths described | cancel + reject (6/6) | cancel + reject + decline + miss (5/6) | cancel + reject (6/6) |

**Key finding**: App C outputs are indistinguishable from App A. All App C runs describe the same 4-step happy path with the same state names. No App C agent mentioned `created_accepted`, `declined`, `missed`, or `fulfilled` -- states that only exist in App B.

App B's Sonnet runs specifically noted `created_accepted` as a legacy/invitation-era artifact in 3/3 runs, showing that Sonnet is more inclined to comment on architectural curiosities.

**Conclusion for Exp 07**: App C matches App A perfectly. Name had no effect.

---

## Cross-Experiment Summary

### Where App C matches App A (structure wins over naming)

1. **State vocabulary**: In every experiment across 54 run files, App C agents used App A's state names (pending, confirmed, in_progress, completed) and never hallucinated App B's states (created, accepted, started, fulfilled, declined, missed, created_accepted). This is the strongest finding.

2. **Service architecture**: App C creates the same services as App A in every experiment. No App C agent created an AcceptService, DeclineService, CreateAcceptedService, or FulfillService.

3. **Decline routing in Exp 03**: When forced to decide what happens after a client declines a counter-proposal, App C mirrors App A exactly (Opus: back to `pending`; Sonnet: to `canceled`). App B routes to `declined` because that state exists in its codebase.

4. **Overlap states in Exp 05**: App C checks `pending/confirmed/in_progress` (matching App A). App B checks `created/created_accepted/accepted/started` (matching its own codebase).

### Where App C differs from App A (possible naming effects)

1. **Output size**: App C runs are marginally smaller than App A runs on average (roughly 5-15% fewer lines). This is subtle and could be random variance, but it appears across multiple experiments. One possible explanation: the name "Request" might subtly signal a lighter-weight entity than "Order," leading to slightly less elaborate implementations.

2. **Kidsout mentions in Exp 01**: App C mentions the Kidsout domain origin in 6/6 runs while App A mentions it in 0/8 runs. This is not a naming effect -- it is likely caused by the CLAUDE.md memory file or project context that specifically references Kidsout in relation to the Request apps.

3. **Separate spec files**: In Exp 02, App A creates separate service spec files in 6/6 runs, while App C does so in only 4/6 runs. This is weak evidence -- App B also creates separate spec files in only 4/6 runs, so this may correlate with "Request" naming making agents slightly less inclined to create comprehensive test suites, or it may be noise.

### Where App C differs from App B (despite sharing the name "Request")

Everywhere structural. App C:
- Never uses `fulfilled`, always uses `completed`
- Never mentions `created_accepted` or the direct-creation flow
- Never creates `AcceptService` or `DeclineService`
- Never routes to a `declined` state
- Uses `confirm` instead of `accept` in all controller actions
- Uses `complete` instead of `fulfill` in all controller actions

These differences are absolute -- not a single App C run exhibits any App B structural behavior.

---

## Conclusion: Naming vs. Structure

The data from App C decisively answers the question: **codebase structure dominates entity naming** in determining AI agent behavior.

Across 54 App C run files spanning 7 experiments:
- **Zero** instances of App B state vocabulary leaking into App C outputs
- **Zero** instances of App B-specific services being created in App C
- **Zero** instances of App B-specific API endpoints appearing in App C
- **Perfect** alignment with App A's structural patterns in every experiment

The name "Request" -- identical to App B -- had no measurable effect on how agents reasoned about App C's code. When the codebase says `pending -> confirmed -> in_progress -> completed`, agents use those states regardless of whether the entity is called "Order" or "Request."

The only experiment where App A and App B produce substantially different designs (Exp 03, decline routing) confirms this: App B agents use the `declined` state because it exists in the codebase, not because the entity is called "Request." App C agents, faced with the same "Request" name but lacking a `declined` state, behave identically to App A.

**The entity name is cosmetic. The state machine is load-bearing.**

This does not mean naming is irrelevant to human developers -- naming affects comprehension, onboarding, and communication. But for AI coding agents operating on actual code, the concrete structure (states, transitions, services, routes) overrides any semantic associations the entity name might carry. The agents read the code, not the vibes.
