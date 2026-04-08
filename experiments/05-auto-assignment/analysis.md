# Analysis: 05-auto-assignment

> Blind comparison — App A and App B naming not revealed to analyzer.

# Cross-App Analysis: Experiment 05 — Auto-Assignment

## 1. Language/Framing

**App A (Order):** Consistently uses "order" language. Descriptions are straightforward: "auto-assign," "available provider," "overlapping orders." No metaphorical confusion. All 6 runs describe the feature in direct, transactional terms.

**App B (Request):** Language splits between domain-neutral ("booking," "scheduling conflict") and Request-specific terms. Notably, request-opus-1 uses "overlapping bookings" in its description despite the entity being `Request`. request-sonnet-2 uses "booking" 4 times in test descriptions. The word "request" creates ambiguity — several runs use phrasing like "has a non-blocking request (canceled)" where "request" means both the entity and the abstract concept.

**App C (Request Clean):** Similar to App B in entity naming, but descriptions are cleaner. Less "booking" substitution than App B. request_clean-opus-2 uses "booked_provider_ids" as a variable name (borrowing from booking domain). Overall framing is closer to App A's directness.

**Confidence:** Weak signal. The "booking" substitution in App B is notable but inconsistent. The naming ambiguity of "Request" doesn't cause major framing shifts.

---

## 2. Architectural Choices

### Where auto-assignment logic lives

| Placement | App A | App B | App C |
|-----------|-------|-------|-------|
| Provider model (scope/class method) | opus-1, opus-2, opus-3 | opus-2 | opus-1, opus-2, opus-3 |
| Separate service (`Providers::AutoAssignService`) | sonnet-3 | opus-1, opus-3, sonnet-2 | — |
| CreateService (private method) | opus-1, opus-3 | opus-3 | opus-1, opus-2, opus-3 |
| Controller only | sonnet-1, sonnet-2 | sonnet-1, sonnet-3 | sonnet-1, sonnet-2, sonnet-3 |

**Key finding:** App B produced a dedicated `Providers::AutoAssignService` in 3/6 runs (opus-1, opus-3, sonnet-2). App A produced one in 1/6 (sonnet-3). App C produced zero. The "Request" naming appears to nudge toward more architectural separation — possibly because the AI treats "Request" as a more complex domain requiring its own service.

### Schedule conflict checking

| Approach | App A | App B | App C |
|----------|-------|-------|-------|
| Full overlap query (time-based) | opus-1, opus-2, opus-3 | opus-1, opus-2, opus-3, sonnet-2 | opus-1, opus-2 |
| Simple `active.order(rating)` (no conflict check) | sonnet-1, sonnet-2, sonnet-3 | sonnet-1, sonnet-3 | opus-3, sonnet-1, sonnet-2, sonnet-3 |

**Tally of runs with schedule conflict checking:**
- App A: 3/6 (all Opus)
- App B: 4/6 (all Opus + sonnet-2)
- App C: 2/6 (opus-1, opus-2)

App B is most likely to implement conflict checking. App C is least likely — 4/6 runs did a simple rating query with no overlap logic. This is surprising given App C has the same clean states as App A.

### Schema changes (migrations/model changes)

| Change | App A | App B | App C |
|--------|-------|-------|-------|
| Migration to make provider_id nullable | opus-2 | opus-3 | opus-1 |
| `belongs_to :provider, optional: true` | opus-2 | opus-3 | opus-1 |
| No schema changes | 5/6 | 5/6 | 5/6 |

Each app had exactly one run that made a schema change. No difference.

**Confidence on architecture:** Strong pattern for AutoAssignService extraction in App B. Moderate pattern for conflict checking (App B > App A > App C).

---

## 3. Complexity

### Lines of diff (estimated, excluding tests)

| Run | App A | App B | App C |
|-----|-------|-------|-------|
| opus-1 | ~45 | ~55 | ~60 |
| opus-2 | ~50 | ~50 | ~50 |
| opus-3 | ~40 | ~70 | ~20 |
| sonnet-1 | ~20 | ~20 | ~20 |
| sonnet-2 | ~15 | ~55 | ~15 |
| sonnet-3 | ~25 | ~20 | ~20 |

### New files created

| App | Runs with new files | Files |
|-----|-------------------|-------|
| A | 1/6 (sonnet-3) | `providers/auto_assign_service.rb` |
| B | 3/6 (opus-1, opus-3, sonnet-2) | `providers/auto_assign_service.rb` |
| C | 0/6 | — |

### New test files created

| App | Runs with new spec files |
|-----|------------------------|
| A | 1/6 (sonnet-3) |
| B | 3/6 (opus-1, opus-3, sonnet-2) |
| C | 0/6 |

### Test count (new examples added)

| Run | App A | App B | App C |
|-----|-------|-------|-------|
| opus-1 | 10 | 7 | 9 |
| opus-2 | 7 | 8 | 9 |
| opus-3 | 4 | 7 | 5 |
| sonnet-1 | 2 | 3 | 2 |
| sonnet-2 | 3 | 9 | 5 |
| sonnet-3 | 5 | 2 | 5 |
| **Average** | **5.2** | **6.0** | **5.8** |

**Confidence:** Moderate. App B has higher structural complexity (more new files), driven primarily by Opus. Test counts are roughly similar across apps.

---

## 4. Scope

### Scope creep indicators

All 18 runs stayed on-task. No run added unrequested features (no new endpoints, no new states, no UI changes). The feature is well-bounded and all implementations are reasonable interpretations.

**One notable divergence:** The `POST /api/requests/direct` endpoint exists only in App B. No run attempted to add auto-assignment to that endpoint, which is appropriate since the prompt says "when a client creates a booking" (the direct endpoint is a different flow). This shows the AI correctly scoped the change.

**Confidence:** No difference. All runs are well-scoped.

---

## 5. Assumptions

### What "available" means

| Assumption | App A | App B | App C |
|------------|-------|-------|-------|
| Available = active + no schedule conflict | 3/6 | 4/6 | 2/6 |
| Available = active only (no conflict check) | 3/6 | 2/6 | 4/6 |

App C most often assumes "available" means simply "active," without checking for scheduling conflicts. This is the simpler (and arguably less correct) interpretation.

### Error response for no provider

| Response | App A | App B | App C |
|----------|-------|-------|-------|
| 422 Unprocessable Entity | 4/6 | 5/6 | 6/6 |
| 404 Not Found | 2/6 (sonnet-2, sonnet-3) | 0/6 | 0/6 |

App A Sonnet runs sometimes return 404 when no provider is available, treating it as "resource not found." App B and C always use 422 or an explicit error. This may reflect "Order" being perceived as more transactional (the provider is a resource you're looking for), while "Request" frames the failure as a validation issue.

**Confidence:** Weak signal on 404 vs 422. Moderate signal on conflict checking (App C least thorough).

---

## 6. Model Comparison (Sonnet vs Opus)

### Across all apps

| Dimension | Opus | Sonnet |
|-----------|------|--------|
| Schedule conflict check | 8/9 runs | 1/9 runs |
| New service file created | 3/9 runs | 1/9 runs |
| Migration added | 3/9 runs | 0/9 runs |
| Avg new test count | ~7.3 | ~3.4 |

**This is the strongest signal in the data.** Opus consistently produces more thorough implementations: schedule overlap queries, dedicated service objects, schema migrations, and more tests. Sonnet consistently takes the minimal path: simple `active.order(rating).first` with controller-level changes only.

This Opus/Sonnet gap is far larger than any app-to-app difference.

**Confidence:** Strong pattern.

### Notable outliers
- **request-sonnet-2** is the only Sonnet run that built a full `AutoAssignService` with conflict checking — it behaves like an Opus run. This was in App B, further supporting that App B's naming/structure nudges toward more complexity.
- **request_clean-opus-3** is the only Opus run that did NOT implement conflict checking — it used a simple `Provider.highest_rated.first`. This was the simplest Opus implementation across all 9 Opus runs.

---

## Pairwise Comparisons

### A vs B (Order vs Request-legacy)
- App B produces more dedicated service objects (3/6 vs 1/6)
- App B implements conflict checking slightly more often (4/6 vs 3/6)
- App B has more complex state filtering (`created, created_accepted, accepted, started` vs `pending, confirmed, in_progress`)
- App B's legacy states force the AI to reason about which states are "active" — this appears to increase implementation thoroughness
- **Similarity: moderate.** Same general approach but B trends more complex.

### A vs C (Order vs Request-clean)
- Very similar state sets (both clean), different entity names
- App C implements conflict checking *less* often than A (2/6 vs 3/6)
- App C never creates a new service file; App A does once
- The "Request" name in App C doesn't drive complexity the way it does in App B
- **Similarity: high** in structure, with C slightly simpler.

### B vs C (Request-legacy vs Request-clean)
- Same entity name, different state complexity
- App B: 4/6 conflict checking, 3/6 new service files
- App C: 2/6 conflict checking, 0/6 new service files
- This is the most informative comparison: **legacy states drive more thorough implementations**, not entity naming alone
- **Similarity: low.** Despite sharing the "Request" name, B is consistently more complex.

---

## Raw Tallies Summary

| Metric | App A (Order) | App B (Request) | App C (Request Clean) |
|--------|:---:|:---:|:---:|
| Runs with conflict checking | 3/6 | 4/6 | 2/6 |
| Runs with new service file | 1/6 | 3/6 | 0/6 |
| Runs with schema migration | 1/6 | 1/6 | 1/6 |
| Avg new tests | 5.2 | 6.0 | 5.8 |
| Runs returning 404 for no-provider | 2/6 | 0/6 | 0/6 |
| Runs with `belongs_to optional` | 1/6 | 1/6 | 1/6 |

---

## Bottom Line

**The dominant factor shaping implementation quality is the model (Opus vs Sonnet), not the app naming.** Opus consistently builds schedule-conflict-aware availability checks, dedicated services, and comprehensive tests regardless of whether the entity is called "Order" or "Request." Sonnet consistently takes the minimal path. Within that model-level gap, there is a secondary signal: **App B's legacy state complexity (not just the "Request" name) nudges the AI toward more architectural separation** — the `Providers::AutoAssignService` pattern appears 3x in App B but never in App C, even though both use "Request." The B-vs-C comparison isolates this: when the AI must reason about which states are "active" (`created, created_accepted, accepted, started` vs `pending, confirmed, in_progress`), it responds by building more robust, better-encapsulated solutions. Entity naming alone (A vs C) produces no meaningful difference in architecture or complexity.
