# Analysis: 04-bulk-booking

> Blind comparison — App A and App B naming not revealed to analyzer.

# Bulk Booking Experiment Analysis

## 1. Language/Framing

All 18 implementations describe the domain identically — "sessions," "recurring," "weekly," "bulk" — with the only difference being the entity name substitution (`order` vs `request`). No run in any app introduced different metaphors or framing based on the entity name. App B correctly uses state `"created"` in test assertions; Apps A and C correctly use `"pending"`.

**Confidence:** Strong pattern — no difference in framing beyond entity name.

## 2. Architectural Choices

All 18 runs converge on the same architecture:
- New service class (`{Entity}s::BulkCreateService`)
- New controller action (`bulk_create` or `bulk`)
- New collection route (`POST /api/{entities}/bulk` or `/bulk_create`)
- DB transaction wrapping all creates
- Payment creation per session
- Provider notification

**Endpoint naming tally:**

| Pattern | App A (Order) | App B (Request) | App C (Request Clean) |
|---------|:---:|:---:|:---:|
| `/bulk` | 4 | 6 | 3 |
| `/bulk_create` | 2 | 0 | 3 |

App B unanimously chose `/bulk`; Apps A and C split. This may reflect the existing `POST /direct` collection route in App B providing a naming convention to follow.

**Notable outliers:**
- **order-opus-2**: Added a `bulk_id` database column + migration + index + model scope — only run across all 18 to add a schema change.
- **request_clean-opus-1**: Used a `sessions` array parameter instead of count+interval — only run to take this fundamentally different API shape.

**Confidence:** Strong pattern — architecture is identical across apps. Outliers are random, not app-correlated.

## 3. Complexity

**Service file size (lines):**

| | App A (Order) | App B (Request) | App C (Request Clean) |
|---|:---:|:---:|:---:|
| Opus avg | 67 | 66 | 62 |
| Sonnet avg | 63 | 59 | 64 |
| Overall avg | **65** | **62** | **63** |

**New files created:**

| | App A | App B | App C |
|---|:---:|:---:|:---:|
| Avg new files | 1.5 | 1.5 | 1.7 |

**Service spec file created:**

| | App A | App B | App C |
|---|:---:|:---:|:---:|
| Yes | 2/6 | 3/6 | 4/6 |

**Runs with zero tests:** order-sonnet-1, request_clean-sonnet-1 (both Sonnet run-1, different apps).

**Confidence:** No meaningful difference across apps. Complexity is virtually identical.

## 4. Scope

The key scope question: did runs add configurability beyond the stated requirement of "5 sessions, weekly recurring"?

**Configurable count + interval added:**

| | App A | App B | App C |
|---|:---:|:---:|:---:|
| **Opus** | 3/3 | 3/3 | 3/3 |
| **Sonnet** | 1/3 | 1/3 | 1/3 |
| **Total** | 4/6 | 4/6 | 4/6 |

The split is **entirely model-driven**: every Opus run added configurability; only 1 Sonnet run per app did. App identity has no effect.

**Max sessions cap (when configurable):**

| | App A | App B | App C |
|---|:---:|:---:|:---:|
| Cap ≤ 5 | 3 | 1 | 1 |
| Cap 10-20 | 0 | 2 | 2 |

Apps B and C (both named "Request") allowed higher max counts. Weak signal — small sample, but possibly the "Request" framing suggests a lighter-weight entity that can be created in larger batches.

**Notification strategy:**

| | App A | App B | App C |
|---|:---:|:---:|:---:|
| Per-entity | 3 | 2 | 2 |
| Single bulk | 3 | 4 | 4 |

Slight tendency for Request-named apps to prefer a single bulk notification. Weak signal.

**Confidence:** Strong pattern that Opus adds scope; no app-driven scope difference.

## 5. Assumptions

All 18 runs assumed:
- Weekly (7-day) recurrence as default
- 5 sessions as default count
- Atomic transaction (all-or-nothing rollback)
- Payment with 10% fee for each session
- Client-only endpoint (403 for providers)
- Provider notification

No run questioned whether the "Request" app's extra states (created → created_accepted → accepted flow in App B) required a different initial state or workflow for bulk-created entities. App B runs correctly start in `"created"` state. No run attempted to use the `create_direct` endpoint pattern from App B for the bulk feature.

**Confidence:** Strong — assumptions are identical across all apps.

## 6. Model Comparison (Opus vs Sonnet)

| Dimension | Opus (9 runs) | Sonnet (9 runs) |
|---|---|---|
| Configurable count/interval | **9/9** (100%) | **3/9** (33%) |
| Service spec created | **5/9** (56%) | **3/9** (33%) |
| Count validation (bounds) | **8/9** (89%) | **2/9** (22%) |
| Runs with 0 tests | **0/9** | **2/9** |
| Avg request test count | ~6.3 | ~5.5 |

Opus consistently builds more configurable, more thoroughly validated, and better-tested implementations. This pattern holds identically across all three apps.

**Confidence:** Strong pattern.

## Pairwise Comparisons

**A vs B (Order vs Request with legacy states):** Nearly identical implementations. The only structural difference is the correct initial state (`pending` vs `created`). App B's extra complexity (legacy states, `create_direct` endpoint) did not bleed into the bulk feature. **Most different pair** only in that App B has slightly higher max-count caps.

**A vs C (Order vs Request Clean):** Extremely similar. Both use `pending` state. Test patterns, service structure, and scope are virtually interchangeable. **Most similar pair.**

**B vs C (Request legacy vs Request clean):** Similar despite different state machines. Both named "Request," both show slightly higher max-count caps than App A, both lean toward bulk notifications. B correctly uses `"created"` state; C uses `"pending"`.

## Bottom Line

**Entity naming ("Order" vs "Request") has no measurable effect on the architecture, complexity, or quality of AI-generated bulk booking implementations.** All 18 runs produced structurally identical solutions — a service class, controller action, collection route, and transactional creation loop — differing only in the entity name substituted throughout. The strongest signal in this dataset is **model-driven, not app-driven**: Opus systematically adds configurability (count/interval parameters, input validation, higher test coverage) while Sonnet produces minimal fixed-5-weekly implementations, and this pattern holds uniformly across all three apps. The legacy state complexity in App B was handled correctly but did not cause any additional confusion, scope creep, or architectural divergence. The two most notable outliers (order-opus-2's `bulk_id` migration, request_clean-opus-1's sessions-array API) appear to be random variation in Opus's tendency toward over-engineering, not systematic effects of naming.
