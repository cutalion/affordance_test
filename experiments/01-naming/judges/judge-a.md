# Independent Judge Report: Affordance Experiment

Reviewer: Claude Opus 4.6 (judge-a)
Date: 2026-04-07

## Methodology

I read every raw run file across all 7 experiments (18 runs per experiment for 01, 18 for 02-07), focusing on concrete behavioral markers: state names used, design decisions made, terminology adopted, and structural choices. I did not read the existing analysis.md or summary.md files.

The core question for each experiment: does App C (request_clean -- named "Request" but with the same 6 clean states as Order) behave more like App A (Order) or App B (Request)?

---

## Experiment 01: Describe System

**Task:** Describe the system after exploring the codebase.

### App A (Order) -- all runs
All runs describe the system using "Order" terminology with states `pending -> confirmed -> in_progress -> completed`. Workflow descriptions are clean and linear. Domain framed as "service marketplace," "booking platform."

### App B (Request) -- all runs
All runs use Request terminology with the full legacy state set: `created -> accepted -> started -> fulfilled`. Every run mentions `declined`, `missed`, and `created_accepted`. Every run explains the direct-booking flow (`POST /api/requests/direct`). Multiple runs (request-sonnet-1, request-sonnet-2, request-sonnet-3) draw elaborate state diagrams showing the branching complexity. request-sonnet-2 explicitly labels these "legacy invitation-era states."

### App C (request_clean) -- all runs
All 6 runs describe the system using `pending -> confirmed -> in_progress -> completed` states. None mention `declined`, `missed`, `fulfilled`, or `created_accepted`. The workflow descriptions are functionally identical to App A runs, with "Request" substituted for "Order."

- request_clean-opus-1: "pending -> confirmed" flow, no legacy states
- request_clean-opus-2: "pending -> confirmed -> in_progress -> completed", no legacy states
- request_clean-opus-3: identical pattern
- request_clean-sonnet-1: draws the exact same state diagram as Order runs (`pending -> confirmed -> in_progress -> completed` with cancel/rejected branches)
- request_clean-sonnet-2: explicitly lists "pending -> confirmed -> in_progress -> completed"
- request_clean-sonnet-3: same pattern, mentions service objects `ConfirmService`, `CompleteService`

**Verdict: C behaves like A.** The descriptions are structurally identical to Order runs, differing only in entity name. No run hallucinates legacy states or extra complexity. This is expected -- the agent is reading code, and C's code has clean states.

---

## Experiment 02: Rebook Feature

**Task:** Implement a "rebook" feature allowing clients to rebook a previous booking.

### Key behavioral markers

**Which states are "rebookable"?**

- **App A (Order):** Consistently `completed`, `canceled`, `rejected` across all runs. order-opus-1 adds a `rebookable` scope. order-opus-2 limits to `completed` or `canceled` only (misses `rejected`).
- **App B (Request):** Tests use `:fulfilled` factory trait (request-opus-1, request-opus-2, request-opus-3). The rebookable concept maps to the app's terminal states. No run mentions `declined` or `missed` as rebookable, which is interesting -- agents correctly identified `fulfilled` as the completion state.
- **App C (request_clean):** Tests use `:completed` factory trait (request_clean-opus-1, request_clean-opus-2, request_clean-opus-3, request_clean-sonnet-1, request_clean-sonnet-3). This matches App A's `completed` state, not App B's `fulfilled`.

**Initial state of new rebooked entity?**

- **App A:** All new orders start in `pending`
- **App B:** New requests start in `created` (the app's initial state)
- **App C:** New requests start in `pending` (matching App A's initial state name)

**Implementation approach:** All three apps follow the same structural pattern: RebookService that delegates to CreateService, copying provider/location/duration/amount. No meaningful structural divergence across apps.

**Verdict: C behaves like A.** The state names used (`completed`, `pending`) directly mirror Order app patterns. The structural implementation is identical across all three apps.

---

## Experiment 03: Propose Different Time

**Task:** Implement a feature where a provider can propose a different time.

### Key behavioral markers

**New state name invented:**

- **App A (Order):** `provider_proposed_time` (opus-1), `provider_proposed` (opus-2, opus-3), `counter_proposed` (sonnet-1, sonnet-2), `time_proposed` (sonnet-3)
- **App B (Request):** `provider_proposed` (opus-1), `counter_proposed` (opus-2, opus-3, sonnet-1, sonnet-2), `proposed` (sonnet-3)
- **App C (request_clean):** `proposed` (opus-1), `time_proposed` (opus-2), `provider_proposed` (opus-3), `countered` (sonnet-1), `counter_proposed` (sonnet-2, sonnet-3)

No systematic naming difference between apps. State naming varies more across model/run combinations than across apps.

**Transition origin and target states (the critical behavioral test):**

- **App A:** Proposal originates from `pending`, acceptance leads to `confirmed`, decline leads to `pending` (opus-1, opus-3, sonnet-3 with caveat) or `canceled` (opus-2, sonnet-1, sonnet-2). The "clean" pattern is pending->proposed->confirmed or pending->proposed->pending.
- **App B:** Proposal originates from `created`, acceptance leads to `accepted`, decline leads to `declined` (all 6 runs consistently). This is the key B-specific behavior: agents use the existing `declined` terminal state for the decline path.
- **App C:** Proposal originates from `pending`, acceptance leads to `confirmed`. Decline leads to `pending` (opus-1, opus-2, opus-3) or `canceled` (sonnet-1, sonnet-2, sonnet-3).

**This is a strong finding.** App B agents uniformly route decline-of-proposal to the `declined` state, because that state exists in the Request app and semantically fits. App C agents never do this -- they route to `pending` (return to original) or `canceled`, which mirrors the App A pattern. App C has no `declined` state to attract the agent.

**Verdict: C behaves like A.** The transition topology follows App A patterns (pending-based origin/targets), not App B patterns (created/declined-based). The presence of `declined` as an available state in App B systematically pulls agent decisions in a direction that C never follows.

---

## Experiment 04: Bulk Booking

**Task:** Implement bulk booking (create 5 weekly sessions at once).

### Key behavioral markers

**Initial state of created entities:**

- **App A (Order):** All orders created in `pending` state
- **App B (Request):** All requests created in `created` state (request-sonnet-1: `eq("created")`, request-sonnet-3: `all(eq("created"))`)
- **App C (request_clean):** All requests created in `pending` state (request_clean-sonnet-2: `all(eq("pending"))`)

**Implementation pattern:** All three apps follow the same basic pattern: BulkCreateService that loops through dates and delegates to the existing CreateService, wrapped in a transaction. Endpoint is `POST /api/{entity}/bulk` or `bulk_create`.

**Verdict: C behaves like A.** Initial state follows the code (pending for A and C, created for B). Implementation is structurally identical across all three.

---

## Experiment 05: Auto-Assignment

**Task:** Make provider_id optional; auto-assign the highest-rated available provider.

### Key behavioral markers

**Which states count as "active/busy" for conflict detection?**

This is the most diagnostic marker across all experiments.

- **App A (Order):** `pending`, `confirmed`, `in_progress` (order-opus-1: `Order.where(state: [:pending, :confirmed, :in_progress])`)
- **App B (Request):** `created`, `created_accepted`, `accepted`, `started` (request-opus-1: `%w[created created_accepted accepted started]`, request-opus-2: `[:created, :created_accepted, :accepted, :started]`, request-sonnet-2: `ACTIVE_STATES = %w[created created_accepted accepted started]`). The inclusion of `created_accepted` is B-specific -- agents correctly identified this as an active state that could cause scheduling conflicts.
- **App C (request_clean):** `pending`, `confirmed`, `in_progress` (request_clean-opus-1: `%w[pending confirmed in_progress]`, request_clean-opus-2: `[:pending, :confirmed, :in_progress]`). This exactly mirrors App A's state set.

**This is a very clean signal.** App B agents consistently include the `created_accepted` state (which doesn't exist in A or C) in their conflict detection logic. App C agents use the exact same three-state set as App A.

**Verdict: C behaves like A.** The active-state set is identical to App A. No C run invents or references `created_accepted`.

---

## Experiment 06: Cancellation Fee

**Task:** Add a 50% cancellation fee for late cancellations (within 24 hours).

### Key behavioral markers

**Implementation approach:** All three apps modify their existing CancelService to check `scheduled_at < 24.hours.from_now` and apply a 50% fee. The structural implementation is nearly identical across all apps.

**State references:**

- **App A:** Tests use `confirmed` orders for cancellation scenarios
- **App B:** Tests use `accepted` requests
- **App C:** Tests use `confirmed` requests

**Fee mechanism:** All three apps use the same approach: check timing, calculate 50% of amount_cents, store as fee_cents on the payment, then proceed with refund (full or partial depending on run).

**Verdict: C behaves like A.** No meaningful structural difference. State names follow the code as expected.

---

## Experiment 07: Happy Path

**Task:** Describe the happy path step by step.

### Key behavioral markers

**State sequence described:**

- **App A (Order):** `pending -> confirmed -> in_progress -> completed` (all 6 runs, perfectly consistent)
- **App B (Request):** `created -> accepted -> started -> fulfilled` (all 6 runs, perfectly consistent). Every run also mentions `declined`, `missed`, and/or `created_accepted` as side paths. request-sonnet-1 explicitly calls out `created_accepted` as "a legacy artifact." request-sonnet-2 calls it "an orphaned state" that "was never cleaned up."
- **App C (request_clean):** `pending -> confirmed -> in_progress -> completed` (all 6 runs, perfectly consistent). No run mentions `declined`, `missed`, `fulfilled`, or `created_accepted`. The descriptions are structurally indistinguishable from App A runs.

**Terminology used for completion:**

- **App A:** "completed" (universal)
- **App B:** "fulfilled" (universal). request-opus-1: "The Provider marks the request as complete... Transition: started -> fulfilled." The natural language says "complete" but the state is `fulfilled`.
- **App C:** "completed" (universal), matching App A exactly

**Extra paths mentioned:**

- **App A:** Cancel and reject only
- **App B:** Cancel, reject, decline, missed, and created_accepted (direct booking flow)
- **App C:** Cancel and reject only -- identical to App A

**Verdict: C behaves like A.** Perfectly clean match. The descriptions are functionally identical modulo entity name.

---

## Cross-Experiment Patterns

### What holds consistently

1. **App C always behaves like App A on state-dependent decisions.** Across all 7 experiments, every run of App C uses the same states as App A (pending, confirmed, in_progress, completed) and never references App B's legacy states (created, accepted, started, fulfilled, declined, missed, created_accepted). This is a 100% consistent finding across 42 runs of App C.

2. **App C never hallucinates extra states or complexity.** In no run does an agent working on App C invent declined/missed states, suggest a created_accepted flow, or add the extra services/endpoints that App B has. The agents faithfully work with what the code contains.

3. **App B agents consistently engage with full state complexity.** Every App B run references states like `created_accepted`, `declined`, and `missed` when relevant to the task. In experiment 05, agents correctly include `created_accepted` in active-state detection. In experiment 03, agents route proposal-decline to the existing `declined` state.

4. **The entity name ("Request" vs "Order") does not cause behavioral divergence between A and C.** This is the experiment's central finding. When the underlying code structure is identical, calling the entity "Request" instead of "Order" produces no measurable difference in agent behavior.

### What breaks or is ambiguous

1. **Experiment 03 (propose time) shows intra-app variance.** The naming of the new state and the decline target vary significantly across runs within the same app. Order opus-2 sends decline to `canceled`; opus-1 sends it to `pending`. This run-to-run variance is larger than any app-to-app difference between A and C, making it harder to draw clean app-level conclusions for this experiment.

2. **Experiment 06 (cancellation fee) is the least discriminating test.** The task is simple enough that all three apps produce nearly identical implementations. There is no state-dependent design decision that would reveal a naming effect.

3. **Model-level differences (Opus vs Sonnet) are sometimes larger than app-level differences.** In experiment 03, Sonnet runs on App C tend to route decline to `canceled`, while Opus runs tend to route to `pending`. This pattern holds across both A and C. The model, not the app, is the dominant variable for this particular design decision.

---

## Most Reliable Findings

1. **State vocabulary is code-determined, not name-determined.** (Confidence: very high, evidence from all 7 experiments, 0 exceptions in 42 C runs.) When C has `pending/confirmed/in_progress/completed`, agents use those states. When B has `created/accepted/started/fulfilled`, agents use those. The entity name "Request" vs "Order" has no detectable effect on which state vocabulary the agent uses.

2. **Extra states attract extra behavior.** (Confidence: high, clearest evidence from experiments 03, 05, 07.) App B's `declined` and `created_accepted` states are not just passively present -- they actively shape agent decisions. Agents route decline-of-proposal to `declined` in B but not in A or C. Agents include `created_accepted` in active-state detection in B but not in A or C. The presence of states in the model is a stronger affordance than the name of the entity.

3. **Complexity of the state machine, not the entity name, drives behavioral differences between B and the other apps.** (Confidence: high.) Every observed difference between B and A/C traces back to B's additional states and services, not to the word "Request." C proves this: it has the same name as B but the same behavior as A.

## Least Reliable Findings

1. **Any claim about naming affecting "conceptual framing" or "domain understanding."** While App B runs sometimes use language like "invitation-era" or "legacy," this traces to comments in the codebase (CLAUDE.md explicitly says "legacy invitation-era states"), not to the entity name. App C runs never use such language because the code gives no such cues.

2. **Any claim about one model (Opus/Sonnet) being systematically more or less affected by naming.** The run-to-run variance within a model is large enough to make model-level claims unreliable at n=3 per condition.

3. **Experiment 02 (rebook) differences between apps.** The task is simple enough that all implementations converge. The only differences are state names, which are code-determined. There is no design decision that the entity name could plausibly influence.

---

## Summary

The experiment has a clean null result for its core question: **the entity name ("Request" vs "Order") has no detectable effect on AI agent behavior when the underlying code structure is identical.** App C behaves like App A in every experiment, without exception. All observed differences between App B and the other apps trace to App B's additional states and services -- structural differences, not naming differences.
