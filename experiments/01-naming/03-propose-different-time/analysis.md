# Analysis: 03-propose-different-time

> Blind comparison — App A and App B naming not revealed to analyzer.

## Analysis: Experiment 03 — Propose Different Time

### 1. Language/Framing

**App A (Order):**
- State names: `provider_proposed_time` (1), `provider_proposed` (2,3), `counter_proposed` (S1,S2), `time_proposed` (S3)
- Endpoint names: `propose_new_time` (O1-3), `propose_time` (S1-S3) for the provider action; `accept_proposed_time`/`accept_proposal`/`accept_counter_proposal` for client accept
- Services consistently use "order" language: "Not your order"
- The word "counter-proposal" appears frequently in Sonnet runs

**App B (Request):**
- State names: `provider_proposed` (O1), `counter_proposed` (O2,O3,S2), `proposed` (S3), `counter_proposed` (S1)
- Endpoint names: `propose_time` (O1,O3,S3), `propose_new_time` (O2), `counter_propose` (S1,S2)
- Services use "request" language: "Not your request"
- The AASM event for proposing is sometimes `propose_different_time` (O1,O3) — a more cautious/elaborate name

**App C (Request Clean):**
- State names: `proposed` (O1), `time_proposed` (O2), `provider_proposed` (O3), `countered` (S1), `counter_proposed` (S2,S3)
- Endpoint names: `propose_new_time` (O1,O2), `propose_time` (S1,S2), `counter_propose` (S3)
- Services use "request" language: "Not your request"

**Pattern summary:** No strong naming divergence driven by entity name. All three apps produce a roughly equal mix of "proposal," "counter-proposal," and "propose_time" terminology. The "Request" name did not cause AI to conflate the entity with the HTTP request concept in any run.

**Confidence:** No difference.

---

### 2. Architectural Choices

| Decision | App A (Order) | App B (Request) | App C (Request Clean) |
|---|---|---|---|
| **Decline → state** | `pending` (O1,O3), `canceled` (O2,S1,S2,S3) | `declined` (all 6) | `pending` (O1,O3), `canceled` (S1,S2,S3), `pending` (O2→`pending`) |
| **Cancel from new state?** | 4/6 yes | 5/6 yes | 2/6 explicit |
| **Validation on proposed_at** | 5/6 add model validation | 4/6 add model validation | 5/6 add model validation |
| **Extra columns** | `proposed_duration_minutes` in 2/6 | `propose_reason` in 3/6 | `original_scheduled_at` in 1/6, `counter_note` in 2/6 |
| **Separate services per action** | 6/6 (3 services each) | 5/6 (3 services), 1 combined (O3→`RespondToProposalService`... no, that's C) | 5/6 (3 services), 1 combined (O3→`RespondToProposalService`) |

**Key difference — Decline target state:**

App B (Request/legacy states) universally transitions decline to `declined` (6/6 runs). This is because the Request app already has a `declined` state in its state machine. The AI consistently reuses the existing `declined` state rather than inventing a new terminal state.

App A (Order) has no `declined` state — it has `canceled` and `rejected`. So decline goes to either `pending` (return to start) or `canceled` (terminal). The split is roughly 50/50.

App C (Request Clean) also has no `declined` state (same states as Order but named Request). Decline goes to `pending` (2 Opus runs) or `canceled` (3 Sonnet runs + 1 Opus run that goes to `pending`).

**Confidence:** Strong pattern for App B's reuse of `declined`.

---

### 3. Complexity

**Raw tallies — new files created:**

| Run | App A | App B | App C |
|---|---|---|---|
| opus-1 | 9 (3 services, 3 mailer views, 1 migration, + spec files) | 6 (3 services, 1 migration, + spec files) | 6 |
| opus-2 | 7 | 7 | 7 |
| opus-3 | 6 | 9 (3 services, 3 mailer views, 1 migration, + specs) | 5 (2 services + combined respond service) |
| sonnet-1 | 6 | 9 (3 services, 3 mailer views, 3 email templates) | 9 (3 services, 3 spec files) |
| sonnet-2 | 6 | 9 | 9 |
| sonnet-3 | 6 | 9 | 6 |

**New DB columns (average):**

| App | Avg new columns |
|---|---|
| A (Order) | 1.7 (range: 1-2) |
| B (Request) | 1.5 (range: 1-2) |
| C (Request Clean) | 1.5 (range: 1-2) |

**Mailer additions:**
- App A: 2/6 runs added mailer methods
- App B: 4/6 runs added mailer methods  
- App C: 3/6 runs added mailer methods

**Test counts (where reported):**
- App A: 265-300 total tests
- App B: 310-322 total tests (higher baseline due to more existing states/services)
- App C: 280-291 total tests

**Confidence:** Weak signal. App B has slightly more mailer additions, likely because the existing codebase already has more mailer methods to pattern-match against. Complexity is broadly similar.

---

### 4. Scope

**Unrequested features added:**

| Feature | App A | App B | App C |
|---|---|---|---|
| `proposed_duration_minutes` | 2/6 (O2, S2) | 0/6 | 0/6 |
| `propose_reason`/`note` field | 2/6 (S1, S3) | 3/6 (O1, O2, S3) | 3/6 (S1, S2, O3) |
| Future time validation | 1/6 (S3) | 0/6 | 1/6 (O3) |
| Payment refund on decline | 1/6 (S3) | 0/6 | 0/6 |
| `original_scheduled_at` preservation | 0/6 | 0/6 | 1/6 (O3) |

App A's `proposed_duration_minutes` is a minor scope creep — the prompt only asked about time, not duration. App A Sonnet-3 added payment refund logic on decline, which is the largest scope creep observed.

**Confidence:** Weak signal. Scope creep is roughly comparable across apps, driven more by model (Sonnet vs Opus) than by entity name.

---

### 5. Assumptions

**What happens when client declines:**

| Assumption | App A | App B | App C |
|---|---|---|---|
| Returns to initial state (re-bookable) | 3/6 | 0/6 | 3/6 |
| Terminal state (canceled/declined) | 3/6 | 6/6 | 3/6 |

This is the most striking difference. **App B universally treats decline as terminal** — the request is `declined` and the flow ends. App A and C split roughly 50/50 between "return to pending" and "cancel/terminate."

The reason: App B's existing `declined` state is a natural, available target. The AI sees it and uses it. App A and C don't have a `declined` state, so the AI must choose between `pending` (optimistic — let them try again) and `canceled` (pessimistic — it's over). This is a direct affordance effect from the existing state machine.

**What the provider action means:**

All three apps consistently frame the provider action as "proposing an alternative" rather than "rejecting with a suggestion." The framing is remarkably uniform — the AI never conflates "propose different time" with "reject."

**Confidence:** Strong pattern for decline-target assumption.

---

### 6. Model Comparison (Sonnet vs Opus)

| Dimension | Opus pattern | Sonnet pattern |
|---|---|---|
| State naming | Prefers descriptive: `provider_proposed`, `provider_proposed_time` | Prefers domain: `counter_proposed`, `countered`, `time_proposed` |
| Decline target in A/C | Leans toward `pending` (4/6) | Leans toward `canceled` (4/6) |
| Reason/note field | 3/9 add it | 4/9 add it |
| Mailer additions | 4/9 | 5/9 |
| Service structure | Always 3 separate services (8/9), one combined (1/9 in C-O3) | Always 3 separate services (9/9) |
| Test depth | Deeper service-level tests | More API-level tests |

Opus tends to produce slightly more conservative designs (decline → return to pending), while Sonnet more often treats decline as terminal. Opus is slightly more likely to use `provider_proposed` (explicit actor in state name); Sonnet uses `counter_proposed` (interaction-oriented).

**Confidence:** Weak signal. Differences are minor.

---

### Notable Outliers

1. **App A, Sonnet-3** (`time_proposed` state): Allowed proposing from both `pending` AND `confirmed` — the only run across all 18 that allows counter-proposal from `confirmed`. Also added payment refund logic and declined → `rejected` (unique target state).

2. **App C, Opus-3** (`RespondToProposalService`): Only run to combine accept/decline into a single service with an `accept:` boolean parameter. Also the only run to add `original_scheduled_at` to preserve the original time.

3. **App B, Sonnet-3** (`proposed` state): Used the shortest state name and expanded `decline` event to cover both `created` and `proposed` states (reusing the existing `decline` event rather than creating a new one). This is the most minimal implementation across all 18 runs.

4. **App B schema pollution**: Runs in App B (request-opus-3, request-sonnet-1, request-sonnet-2, request-sonnet-3) all show an `orders` table appearing in `schema.rb` — these are schema artifacts from other experiment branches leaking through. Not a behavioral difference, but notable.

---

### Raw Tallies

**New AASM state name choices:**

| State name | App A | App B | App C |
|---|---|---|---|
| `provider_proposed` / `provider_proposed_time` | 3 | 1 | 1 |
| `counter_proposed` | 2 | 3 | 3 |
| `proposed` | 0 | 1 | 1 |
| `time_proposed` | 1 | 0 | 1 |
| `countered` | 0 | 0 | 1 |

**Decline target state:**

| Target | App A | App B | App C |
|---|---|---|---|
| `pending` | 3 | 0 | 2 |
| `canceled` | 2 | 0 | 3 |
| `declined` | 0 | 6 | 0 |
| `rejected` | 1 | 0 | 0 |

---

### Pairwise Comparisons

**A vs B (Order vs Request):**
Most different pair on the decline-target dimension. App B's existing `declined` state acts as an attractor — 6/6 runs use it. App A has no such state and splits between `pending` and `canceled`. Otherwise architecturally very similar (same service pattern, same endpoint structure).

**A vs C (Order vs Request Clean):**
Most similar pair. Both have clean state machines without a `declined` state. Both split decline between `pending` and `canceled`. Naming differs only in `Order`→`Request` substitution. This confirms that the entity name alone (`Order` vs `Request`) has minimal impact on AI design decisions.

**B vs C (Request legacy vs Request clean):**
Same entity name, different state complexity. The key difference is the decline target: B→`declined` (6/6), C→`pending`/`canceled` (5/6). This confirms the affordance effect comes from the **state machine structure**, not the entity name. App B also has more service/mailer additions on average, suggesting the legacy structure's complexity slightly encourages the AI to produce more supporting infrastructure.

---

### Bottom Line

The dominant finding is that **existing state machine structure, not entity naming, drives AI design decisions**. App B's pre-existing `declined` state acts as a powerful attractor: all 6 runs route decline there, while Apps A and C (which lack `declined`) split roughly evenly between returning to `pending` and going to `canceled`. The A-vs-C comparison is the control that proves naming is not the factor — both `Order` and `Request` with identical clean state machines produce nearly identical implementations. Sonnet and Opus show minor stylistic differences (Opus prefers actor-prefixed state names like `provider_proposed`; Sonnet prefers interaction-oriented names like `counter_proposed`) but converge on the same architecture. The legacy state machine's complexity did not cause confusion or scope creep — it simply provided more existing states to reuse, which the AI did consistently and correctly.
