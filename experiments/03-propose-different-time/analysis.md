# Analysis: 03-propose-different-time

> Blind comparison — App A and App B naming not revealed to analyzer.

## Analysis: Experiment 03 — Propose Different Time

### 1. Language/Framing

**App A (Order):**
- Consistently uses transactional/commercial language: "propose new time," "accept proposal," "decline proposal"
- State names lean toward process descriptions: `provider_proposed_time`, `provider_proposed`, `counter_proposed`, `time_proposed`
- Error messages: "Not your order," "Cannot propose new time for order in X state"
- The word "counter-proposal" appears frequently in Sonnet runs

**App B (Request):**
- Uses negotiation/communication language: "propose time," "counter propose," "accept counter," "decline counter"
- State names show more variation: `provider_proposed`, `counter_proposed`, `proposed`
- Error messages: "Not your request," "Cannot propose time for request in X state"
- Sonnet runs in App B lean harder into "counter-proposal" framing (2/3 use `counter_propose` as the action name vs. `propose_time`)

**Confidence: Weak signal.** The language differences are subtle. Both apps use similar vocabulary. The main observable difference is that App B Sonnet runs gravitate toward "counter" terminology more than App A Sonnet runs.

---

### 2. Architectural Choices

#### New State Names

| Run | App A (Order) | App B (Request) |
|-----|--------------|-----------------|
| opus-1 | `provider_proposed_time` | `provider_proposed` |
| opus-2 | `provider_proposed` | `counter_proposed` |
| opus-3 | `provider_proposed` | `counter_proposed` |
| sonnet-1 | `counter_proposed` | `counter_proposed` |
| sonnet-2 | `counter_proposed` | `counter_proposed` |
| sonnet-3 | `time_proposed` | `proposed` |

**App A state name distribution:** `provider_proposed` x2, `provider_proposed_time` x1, `counter_proposed` x2, `time_proposed` x1
**App B state name distribution:** `counter_proposed` x4, `provider_proposed` x1, `proposed` x1

**Confidence: Weak signal.** App B converges more strongly on `counter_proposed` (4/6), while App A is more scattered. This may reflect the "Request" framing encouraging negotiation metaphors.

#### Decline Behavior (Key Design Decision)

| Run | App A: Decline → ? | App B: Decline → ? |
|-----|--------------------|--------------------|
| opus-1 | → `pending` (back to start) | → `declined` (terminal) |
| opus-2 | → `canceled` (terminal) | → `declined` (terminal) |
| opus-3 | → `pending` (back to start) | → `declined` (terminal) |
| sonnet-1 | → `canceled` (terminal) | → `declined` (terminal) |
| sonnet-2 | → `canceled` (terminal) | → `declined` (terminal) |
| sonnet-3 | → `rejected` (terminal) | → `declined` (terminal) |

**App A:** 2/6 return to `pending`, 3/6 go to `canceled`, 1/6 goes to `rejected` — split between reversible and terminal
**App B:** 6/6 go to `declined` — unanimously terminal

**Confidence: Strong pattern.** This is the clearest difference. App B (Request) universally treats declining a counter-proposal as terminal (`declined`), matching the existing `decline` event's semantics. App A (Order) is split — some implementations allow the negotiation to restart (back to `pending`), others treat it as terminal. The "Order" framing seems to create ambiguity about whether declining a proposal should end the order entirely or just reject that specific proposal.

#### Cancel from New State

| App A | App B |
|-------|-------|
| 4/6 explicitly add cancel from new state | 4/6 explicitly add cancel from new state |

No meaningful difference.

#### Propose Transition Source

| Run | App A: Propose from? | App B: Propose from? |
|-----|---------------------|---------------------|
| opus-1 | `pending` only | `created` only |
| opus-2 | `pending` only | `created` only |
| opus-3 | `pending` only | `created` only |
| sonnet-1 | `pending` only | `created` only |
| sonnet-2 | `pending` only | `created` only |
| sonnet-3 | `pending` + `confirmed` | `created` only |

**App A outlier:** sonnet-3 allows proposing from `confirmed` too — treating it as renegotiation even after acceptance.
**App B:** Unanimously from `created` only.

**Confidence: Weak signal** (only one outlier), but directionally interesting — the "Order" framing may encourage broader state transitions.

---

### 3. Complexity

#### New Database Columns

| Run | App A | App B |
|-----|-------|-------|
| opus-1 | 1 (`proposed_scheduled_at`) | 2 (`proposed_scheduled_at`, `propose_reason`) |
| opus-2 | 2 (`proposed_scheduled_at`, `proposed_duration_minutes`) | 2 (`proposed_scheduled_at`, `propose_reason`) |
| opus-3 | 1 (`proposed_scheduled_at`) | 1 (`proposed_scheduled_at`) |
| sonnet-1 | 2 (`counter_proposed_scheduled_at`, `counter_proposal_note`) | 2 (`proposed_at`, `counter_proposal_note`) |
| sonnet-2 | 2 (`proposed_at`, `proposed_duration_minutes`) | 1 (`counter_proposed_at`) |
| sonnet-3 | 2 (`proposed_time`, `proposal_reason`) | 2 (`proposed_at`, `propose_reason`) |

**App A average:** 1.67 columns
**App B average:** 1.67 columns

No meaningful difference in schema complexity.

#### New Services

Both apps consistently add exactly 3 new services across all runs. No difference.

#### New Mailer Methods

| App A | App B |
|-------|-------|
| opus-1: 3 mailer methods + 3 templates | opus-1: 0 new mailer methods |
| opus-2: 0 | opus-2: 0 |
| opus-3: 0 | opus-3: 3 mailer methods |
| sonnet-1: 0 | sonnet-1: 3 mailer methods + 3 templates |
| sonnet-2: 0 | sonnet-2: 3 mailer methods + 3 templates |
| sonnet-3: 3 mailer methods | sonnet-3: 3 mailer methods + 3 templates |

**App A:** 2/6 added mailer methods
**App B:** 4/6 added mailer methods

**Confidence: Weak signal.** App B is somewhat more likely to add mailer methods/templates, possibly because the "Request" framing encourages more communication-oriented features.

#### Extra Fields (Scope Creep Indicator)

- **App A opus-2** and **App A sonnet-2** added `proposed_duration_minutes` — an unrequested enhancement allowing the provider to propose a different duration too
- **App A sonnet-3** added `proposal_reason` (a reason field for proposals) plus allowed proposing from `confirmed` state
- **App A sonnet-1** added `counter_proposal_note`
- **App B opus-1** added `propose_reason` (required)
- **App B opus-2** added `propose_reason` (required)
- **App B sonnet-1** added `counter_proposal_note`
- **App B sonnet-3** added `propose_reason`

The `proposed_duration_minutes` field only appeared in App A (2 runs), never in App B.

**Confidence: Weak signal.** App A shows slightly more scope creep with the duration field addition.

---

### 4. Scope

#### Unrequested Features

| Feature | App A | App B |
|---------|-------|-------|
| Proposed duration_minutes | 2/6 (opus-2, sonnet-2) | 0/6 |
| Reason/note field | 3/6 | 4/6 |
| Mailer templates | 2/6 | 4/6 |
| Payment refund on decline | 1/6 (sonnet-3) | 0/6 |
| Time validation (must be future) | 1/6 (sonnet-3) | 0/6 |
| Propose from confirmed state | 1/6 (sonnet-3) | 0/6 |

**Confidence: Weak signal.** App A sonnet-3 is the biggest scope creep outlier — it added future-time validation, payment refund logic, and allowed proposing from `confirmed`. App B stays more tightly scoped overall.

---

### 5. Assumptions

**App A (Order):**
- Opus runs split on whether declining returns to negotiation (pending) or ends it
- Two runs assumed duration should also be negotiable
- One run assumed proposing should also work after confirmation
- Overall: more design ambiguity, more variation in assumptions

**App B (Request):**
- Universal agreement that declining ends the request
- More consistent interpretation of the feature
- The existing `decline` event (→ `declined`) may anchor this interpretation
- Overall: the existing decline/accept pattern in Request provides a clearer template

**Confidence: Strong pattern.** The Request app's existing `decline` event creates a natural semantic anchor — declining a counter-proposal maps cleanly onto the existing `decline` transition. The Order app has no equivalent existing "decline" event; its `reject` goes from `confirmed` → `rejected`, which doesn't map as cleanly to declining a proposal from a pre-confirmed state.

---

### 6. Model Comparison (Opus vs Sonnet)

#### Within App A (Order)

| Dimension | Opus | Sonnet |
|-----------|------|--------|
| State name | `provider_proposed` (2/3) | `counter_proposed` (2/3) |
| Decline target | 2/3 → `pending`, 1/3 → `canceled` | 3/3 terminal (`canceled`/`rejected`) |
| Duration field | 1/3 | 1/3 |
| Mailer additions | 1/3 | 1/3 |

**Opus** in App A leans toward reversible decline (back to pending). **Sonnet** universally treats it as terminal.

#### Within App B (Request)

| Dimension | Opus | Sonnet |
|-----------|------|--------|
| State name | 2/3 `counter_proposed`, 1/3 `provider_proposed` | varied (`counter_proposed`, `counter_proposed`, `proposed`) |
| Decline target | 3/3 `declined` | 3/3 `declined` |
| Reason field required | 2/3 | 1/3 |

Both models agree on terminal decline in App B. Opus in App B is slightly more likely to require a reason field.

**Confidence: Weak signal** for model-level differences. The app-level differences (Order vs Request) are more pronounced than model-level differences.

---

### Raw Tallies

| Metric | App A (Order) avg | App B (Request) avg |
|--------|-------------------|---------------------|
| New states | 1 | 1 |
| New DB columns | 1.67 | 1.67 |
| New services | 3 | 3 |
| New mailer methods | 1.0 | 2.0 |
| Decline → terminal | 4/6 (67%) | 6/6 (100%) |
| Decline → pending | 2/6 (33%) | 0/6 (0%) |
| Duration field added | 2/6 | 0/6 |
| Reason field added | 3/6 | 4/6 |

### Notable Outliers

- **order-sonnet-3**: Most scope creep — payment refund on decline, future-time validation, propose from `confirmed`, `time_proposed` state name, decline → `rejected`
- **order-opus-1**: Only run to name the state `provider_proposed_time` (most verbose state name)
- **request-sonnet-3**: Used `proposed` as state name (most minimal), reused existing `decline` event instead of creating `decline_proposal`
- **request-opus-3**: Cleanest implementation in App B — only 1 new column, no extra fields

---

### Bottom Line

The most important finding is the **decline behavior divergence**: App B (Request) unanimously treats declining a counter-proposal as terminal (→ `declined`), while App A (Order) is split between terminal outcomes and returning to `pending` for further negotiation. This is likely driven by the Request app's existing `decline` event providing a clear semantic anchor — when the entity is a "Request," declining a counter-proposal naturally maps to the existing concept of declining. The Order app lacks this anchor, creating ambiguity about whether a declined proposal should end the transaction or merely reset it. This represents a concrete case where entity naming influences AI design decisions about state machine semantics, with the "Request" framing producing more consistent (though arguably less flexible) designs. Secondary findings — App A's tendency toward `proposed_duration_minutes` scope creep and App B's stronger convergence on state naming — reinforce this pattern but at lower confidence.
