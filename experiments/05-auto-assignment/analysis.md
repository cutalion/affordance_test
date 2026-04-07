# Analysis: 05-auto-assignment

> Blind comparison — App A and App B naming not revealed to analyzer.

## Analysis: Experiment 05 — Auto-Assignment

### 1. Language/Framing

**App A (Order):** Consistently uses "order" terminology. Descriptions are straightforward — "auto-assigns," "pick the highest-rated available provider," "no overlapping orders." The domain feels transactional.

**App B (Request):** Uses "request" and "booking" interchangeably. Several runs introduce "booking" as a synonym unprompted (request-opus-1: "no overlapping bookings," request-sonnet-2: "booking" throughout specs). The word "booking" never appears in App A responses. Request-opus-3 refers to "non-canceled/rejected/declined/missed requests" — the longer state list naturally enters the narrative.

**Confidence:** Strong pattern. "Booking" as a synonym emerges only in App B (4/6 runs use it at least once). The Request naming seems to evoke a more service/scheduling mental model.

### 2. Architectural Choices

| Decision | App A (Order) | App B (Request) |
|---|---|---|
| **Where auto-assignment lives** | 4/6 in controller or CreateService inline; 1/6 new service (order-sonnet-3); 1/6 Provider class method | 4/6 created `Providers::AutoAssignService`; 2/6 kept it in controller/model |
| **Schedule conflict checking** | 3/3 Opus checked overlaps; 0/3 Sonnet checked overlaps | 3/3 Opus checked overlaps; 1/3 Sonnet checked overlaps (sonnet-2) |
| **Made provider_id nullable (migration)** | 1/6 (order-opus-2) | 1/6 (request-opus-3) |
| **Made belongs_to optional** | 1/6 (order-opus-2) | 1/6 (request-opus-3) |
| **States checked for conflicts** | `[:pending, :confirmed, :in_progress]` | `%w[created created_accepted accepted started]` (correct active states for each app) |

**New service file created:**

| Run | App A | App B |
|---|---|---|
| opus-1 | No | No |
| opus-2 | No | No |
| opus-3 | No | Yes (`Providers::AutoAssignService`) |
| sonnet-1 | No | No |
| sonnet-2 | No | Yes (`Providers::AutoAssignService`) |
| sonnet-3 | Yes (`Providers::AutoAssignService`) | No |

**Tally:** App A created a new service in 1/6 runs. App B created a new service in 3/6 runs (opus-1, opus-3, sonnet-2). The Request app prompted more architectural extraction.

**Confidence:** Weak-to-moderate signal on service extraction. The overlap-checking pattern is model-driven (Opus always does it, Sonnet rarely does), not naming-driven.

### 3. Complexity

**Lines of diff (approximate, excluding spec):**

| Run | App A | App B |
|---|---|---|
| opus-1 | ~55 | ~65 (new service file) |
| opus-2 | ~60 (+ migration) | ~55 |
| opus-3 | ~45 | ~85 (new service + migration + model change) |
| sonnet-1 | ~20 | ~25 |
| sonnet-2 | ~20 | ~70 (new service file) |
| sonnet-3 | ~30 (new service) | ~30 |

**Lines of test added (approximate):**

| Run | App A | App B |
|---|---|---|
| opus-1 | ~75 (3 files) | ~100 (3 files) |
| opus-2 | ~60 (2 files) | ~75 (2 files) |
| opus-3 | ~50 (1 file) | ~110 (3 files) |
| sonnet-1 | ~30 (1 file) | ~35 (1 file) |
| sonnet-2 | ~40 (1 file) | ~115 (2 files) |
| sonnet-3 | ~55 (2 files) | ~30 (1 file) |

**Averages:** App A ~55 test lines, App B ~78 test lines. App B implementations are modestly larger on average.

**Confidence:** Weak signal. The variance within each app is high. Opus consistently produces more code than Sonnet regardless of app.

### 4. Scope

**Scope creep inventory:**

| Item | App A | App B |
|---|---|---|
| Added migration to make provider_id nullable | 1/6 | 1/6 |
| Changed `belongs_to` to optional | 1/6 | 1/6 |
| Modified error handling in controller | 1/6 (opus-3) | 0/6 |
| Schema changes from other experiments leaked in | 1/6 (opus-2: bulk_id, proposed_*) | 1/6 (opus-3: propose_reason, proposed_*) |

All runs stayed reasonably on-task. No run added unrequested features like notification preferences, logging, or admin UI changes.

**Confidence:** No meaningful difference in scope discipline between apps.

### 5. Assumptions

**Key assumption: Does "available" mean schedule-conflict-free or just active?**

| Interpretation | App A | App B |
|---|---|---|
| Active + no schedule conflicts | 3/6 (all Opus) | 4/6 (all Opus + sonnet-2) |
| Active only (no conflict check) | 3/6 (all Sonnet) | 2/6 (sonnet-1, sonnet-3) |

App B nudged one additional Sonnet run (sonnet-2) toward schedule-conflict checking. This is the most interesting signal: the Request naming may have prompted slightly deeper thinking about availability semantics.

**Error response for no-provider:**
- App A: 3 runs use 422, 2 use 404, 1 uses 422 with ActiveModel::Errors
- App B: 5 runs use 422, 1 uses 422 with ActiveModel::Errors

App B more consistently chose 422 (semantically "we can't process this") over 404. The "Request" framing may make a missing provider feel like an unfulfillable request rather than a missing resource.

**Confidence:** Weak signal on conflict checking (one extra run). Moderate signal on 422 vs 404 preference.

### 6. Model Comparison (Opus vs Sonnet)

This is the strongest axis of variation, dominating over app naming:

| Dimension | Opus (both apps) | Sonnet (both apps) |
|---|---|---|
| Schedule conflict checking | 6/6 | 1/6 |
| Average test count | ~80 lines | ~40 lines |
| New service extraction | 2/6 | 2/6 |
| Migration added | 2/6 | 0/6 |
| Provider scope on model | 6/6 (`available_at` or equivalent) | 2/6 (simple `by_rating`/`best_available`) |

**Confidence:** Strong pattern. Opus consistently builds more complete implementations with availability/scheduling logic. Sonnet takes the simpler "highest-rated active" shortcut.

### Notable Outliers

- **order-opus-2**: Only Order run to add a migration and make the association optional — treating the feature as a schema-level change rather than just a code path.
- **request-sonnet-2**: The only Sonnet run (either app) to implement full schedule-conflict checking, creating `AutoAssignService` with `ACTIVE_STATES` constant and a result-object return pattern. Significantly more sophisticated than other Sonnet runs.
- **request-opus-3**: Used an N+1-prone `find` loop over providers instead of a single SQL query (all other Opus runs used a subquery). Also the only run to modify both the service and create a new service.

### Raw Tallies

| Metric | App A (Order) | App B (Request) |
|---|---|---|
| New service files created | 1/6 | 3/6 |
| Schedule conflict checking | 3/6 | 4/6 |
| 422 for no-provider | 3/6 | 5/6 |
| 404 for no-provider | 2/6 | 0/6 |
| Migration added | 1/6 | 1/6 |
| Avg implementation LOC (non-test) | ~38 | ~55 |
| Avg test LOC | ~52 | ~78 |
| Used word "booking" | 0/6 | 4/6 |

### Bottom Line

The model choice (Opus vs Sonnet) is the dominant variable: Opus always implements schedule-conflict checking and writes substantially more tests, while Sonnet typically takes the simpler "highest-rated active provider" shortcut. Within that, the Request naming produces a modest but consistent effect: it nudges implementations toward more architectural separation (new service files in 3/6 vs 1/6), more thorough availability semantics (4/6 vs 3/6 check schedule conflicts), and more appropriate error responses (5/6 vs 3/6 choose 422 over 404). The Request name also spontaneously evokes "booking" as a domain synonym, suggesting it activates a richer mental model of scheduling/service-fulfillment than the more transactional "Order" framing. However, these naming effects are secondary to the Opus/Sonnet capability gap and should be interpreted cautiously given the small sample size.
