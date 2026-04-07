# Analysis: 02-rebook-feature

> Blind comparison — App A and App B naming not revealed to analyzer.

# Experiment 02 Analysis: Rebook Feature

## 1. Language/Framing

**App A (Order):** Consistently uses "rebook" language naturally. Descriptions are straightforward: "rebook an order," "rebookable orders." The term "order" pairs naturally with "rebook" — it reads as a commercial transaction being repeated.

**App B (Request):** Also uses "rebook" but the framing occasionally feels slightly awkward — "rebook a request" is less idiomatic than "rebook an order." However, all runs adopted the "rebook" verb without hesitation. No run attempted to reframe it as "re-request" or "duplicate request."

**Confidence:** Weak signal. The naming difference didn't produce meaningfully different framing.

## 2. Architectural Choices

### Service reuse patterns

| Run | Delegates to CreateService? | Builds Order/Request manually? |
|---|---|---|
| order-opus-1 | Yes | No |
| order-opus-2 | Yes | No |
| order-opus-3 | Yes | No |
| order-sonnet-1 | **No** | **Yes (manual build + transaction)** |
| order-sonnet-2 | **No** | **Yes (manual build + transaction)** |
| order-sonnet-3 | Yes | No |
| request-opus-1 | **No** | **Yes (manual build + transaction)** |
| request-opus-2 | **No** | **Yes (manual build + transaction)** |
| request-opus-3 | Yes | No |
| request-sonnet-1 | Yes | No |
| request-sonnet-2 | **No** | **Yes (manual build + transaction)** |
| request-sonnet-3 | **No** | **Yes (manual build + transaction)** |

**Tally:** CreateService delegation: Order 4/6, Request 2/6. Manual build: Order 2/6, Request 4/6.

This is a notable difference. The "Request" app runs were **twice as likely** to bypass the existing CreateService and manually construct the record + payment + notification inline. This suggests that the "Request" naming may subtly discourage service reuse — perhaps because "creating a request" feels semantically distinct from "rebooking," while "creating an order" from a rebook feels natural.

**Confidence:** Moderate signal. The pattern holds but the sample is small and there's model-level confounding (Opus-Order always delegates; Sonnet-Request never delegates).

### State gating (rebookable? predicate)

| Approach | Order runs | Request runs |
|---|---|---|
| Added `rebookable?` method with state checks | 3 (opus-1, opus-3, opus-1*) | 0 |
| No state gating at all | 3 (sonnet-1, sonnet-2, sonnet-3) | 6 (all) |
| State check in service only (no model method) | 1 (opus-2: completed/canceled) | 0 |

**Tally:** Order app added rebookable state restrictions in 4/6 runs. Request app added them in **0/6 runs**.

This is the strongest finding. The "Order" app's clean terminal states (completed, canceled, rejected) invited the AI to reason about which states allow rebooking. The "Request" app's complex legacy states (created, created_accepted, accepted, started, fulfilled, declined, missed, canceled, rejected) apparently discouraged this — no run attempted to define which request states are rebookable.

**Confidence:** **Strong pattern.**

### Model-level additions

| Addition | Order | Request |
|---|---|---|
| `rebookable?` model method | 2/6 | 0/6 |
| `rebookable` scope | 1/6 | 0/6 |
| `rebook_attributes` helper | 1/6 | 0/6 |

## 3. Complexity

### Lines of diff (approximate, excluding specs)

| Run | Service LOC | Controller LOC (added) | Model LOC (added) | Total impl LOC |
|---|---|---|---|---|
| order-opus-1 | 44 | 23 | 5 | ~72 |
| order-opus-2 | 38 | 23 | 0 | ~61 |
| order-opus-3 | 30 | 22 | 14 | ~66 |
| order-sonnet-1 | 48 | 27 | 0 | ~75 |
| order-sonnet-2 | 48 | 27 | 0 | ~75 |
| order-sonnet-3 | 28 | 26 | 0 | ~54 |
| request-opus-1 | 48 | 23 | 0 | ~71 |
| request-opus-2 | 44 | 25 | 0 | ~69 |
| request-opus-3 | 32 | 23 | 0 | ~55 |
| request-sonnet-1 | 34 | 25 | 0 | ~59 |
| request-sonnet-2 | 48 | 23 | 0 | ~71 |
| request-sonnet-3 | 48 | 23 | 0 | ~71 |

**Averages:** Order ~67 impl LOC, Request ~66 impl LOC.

### Test file counts

| Run | New spec files | New test examples (approx) |
|---|---|---|
| order-opus-1 | 2 | 12 |
| order-opus-2 | 2 | 12 |
| order-opus-3 | 2 | 14 (includes model specs) |
| order-sonnet-1 | 2 | 14 |
| order-sonnet-2 | 2 | 10 |
| order-sonnet-3 | 2 | 12 |
| request-opus-1 | 1 | 5 (request specs only) |
| request-opus-2 | 2 | 8 |
| request-opus-3 | 2 | 12 |
| request-sonnet-1 | 0 | 0 |
| request-sonnet-2 | 1 | 6 (request specs only) |
| request-sonnet-3 | 0 | 0 |

**Averages:** Order ~12.3 new tests, Request ~5.2 new tests.

Request app received **significantly fewer tests**. Two Request-Sonnet runs (sonnet-1, sonnet-3) shipped **zero test files** — just the route, controller action, and service. No Order run shipped without tests.

**Confidence:** **Strong pattern.** Request app got less thorough testing.

## 4. Scope

### Scope creep indicators

| Feature | Order count | Request count |
|---|---|---|
| Added `rebookable?` / state gating | 4/6 | 0/6 |
| Added model scope (`rebookable`) | 1/6 | 0/6 |
| Added `rebook_attributes` model method | 1/6 | 0/6 |
| Controller validates `scheduled_at` presence | 3/6 (sonnet runs) | 1/6 (sonnet-1) |
| Allows overriding `amount_cents` | 1/6 (sonnet-1) | 4/6 |
| Allows overriding `duration_minutes` | 2/6 (opus-1, opus-2*) | 2/6 (opus-1, opus-3) |
| Allows overriding `location` | 3/6 | 2/6 |

The Order app tended toward **model-level enrichment** (adding methods/scopes to the Order model). The Request app tended toward **parameter permissiveness** (allowing more fields to be overridden).

Notably, `amount_cents` was treated differently: Request runs were 4x more likely to require or allow overriding `amount_cents` in rebook_params, while Order runs mostly carried it forward silently. This may reflect an assumption that a "request" involves negotiation (amount might change), while an "order" has a fixed price.

**Confidence:** Moderate signal for the amount_cents pattern; strong signal for model enrichment in Order.

## 5. Assumptions

**App A (Order) assumptions:**
- Orders have clear lifecycle endpoints — rebooking makes sense from terminal states
- Price carries forward automatically (4/6 runs don't allow overriding amount)
- The action name "rebook" is a first-class concept worth modeling (`rebookable?`)

**App B (Request) assumptions:**
- Any request can be rebooked regardless of state (0/6 added state checks)
- Pricing may need renegotiation (4/6 allow amount_cents override)
- Rebooking is a controller/service concern, not a model concept (no model methods added)

The most striking assumption gap: **Order runs assumed rebooking is a domain concept** (with eligibility rules), while **Request runs treated it as a CRUD operation** (copy and create).

**Confidence:** **Strong pattern.**

## 6. Model Comparison (Opus vs Sonnet)

### Within Order app:
- **Opus** (3 runs): Always delegated to CreateService. 2/3 added `rebookable?`. More model-level abstractions. Average ~66 impl LOC.
- **Sonnet** (3 runs): 2/3 built manually (didn't delegate to CreateService). 0/3 added `rebookable?`. More controller-level validation (`scheduled_at` presence check). Average ~68 impl LOC.

### Within Request app:
- **Opus** (3 runs): 1/3 delegated to CreateService, 2/3 built manually. All added service-level specs. Average ~65 impl LOC.
- **Sonnet** (3 runs): 1/3 delegated to CreateService, 2/3 built manually. 2/3 shipped no service specs. Average ~67 impl LOC.

**Cross-cutting model pattern:** Opus is more likely to delegate to existing services and add domain-level abstractions. Sonnet is more likely to build inline and add controller-level guards. This holds across both apps but is more pronounced in the Order app.

**Confidence:** Moderate signal. Consistent direction but small N.

## Notable Outliers

- **order-sonnet-1**: The only Order run to manually build the record instead of delegating to CreateService *and* allow `amount_cents` override — it behaved more like a Request run.
- **request-sonnet-1 and request-sonnet-3**: Shipped with zero test files. The only runs across both apps with no tests.
- **request-opus-2**: Moved ownership check to the controller instead of the service — the only run to split this responsibility that way.

## Raw Tallies Summary

| Metric | Order (avg/6) | Request (avg/6) |
|---|---|---|
| Delegates to CreateService | 4/6 (67%) | 2/6 (33%) |
| Added rebookable state check | 4/6 (67%) | 0/6 (0%) |
| Added model-level methods | 3/6 (50%) | 0/6 (0%) |
| New test examples | ~12.3 | ~5.2 |
| Runs with zero new test files | 0/6 | 2/6 |
| Allows amount_cents override | 1/6 | 4/6 |
| Impl LOC (approx) | ~67 | ~66 |

## Bottom Line

The naming difference produced a clear divergence in **domain modeling depth**, not in raw implementation size. The "Order" codebase consistently prompted AI to treat rebooking as a **domain concept** — adding rebookable state predicates, model-level methods, and delegating to existing service infrastructure. The "Request" codebase prompted AI to treat rebooking as a **mechanical copy operation** — no state eligibility checks, no model enrichment, more parameter permissiveness (especially around pricing), and significantly fewer tests. The most striking finding is that 4/6 Order runs added state-based rebooking eligibility while 0/6 Request runs did, suggesting the clean terminal states of Order afforded reasoning about lifecycle rules while the complex legacy states of Request discouraged it entirely. Secondary to the naming effect, Opus showed a consistent tendency toward service delegation and domain abstraction across both apps, while Sonnet leaned toward inline construction and controller-level validation.
