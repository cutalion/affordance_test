# Analysis: e05-recurring-bookings

> Blind comparison — app identities not revealed to analyzer.

## Analysis: Recurring Weekly Bookings Across Apps B, C, D, E

### 1. Language/Framing

**App B (bravo):** Consistently uses "recurring booking" as a container for "requests." Language is clean and straightforward across all 3 runs. Describes the feature as creating a `RecurringBooking` + 5 `Request` records.

**App C (charlie):** Split framing. Run 1 uses "recurring booking" container language. Runs 2-3 shift to "recurring group" language — "shared `recurring_group_id`", "recurring siblings." The debt app's language leans toward grouping existing entities rather than introducing new ones.

**App D (delta):** Uses "recurring booking" with "orders" — correctly identifying that the child entity should be Order, not Request. Run 1 even describes "5 weekly sessions" and notes "each with a payment." Language reflects understanding of the full entity chain.

**App E (echo):** Most inconsistent framing. Run 1 describes "recurring booking created" but implements it as grouped requests. Run 2 uses "recurring group" language. Run 3 introduces "day_of_week" and "time_of_day" abstractions — the richest conceptual vocabulary but also the most over-engineered.

**Confidence: High.** The framing differences are consistent and clearly tied to codebase structure.

---

### 2. Architectural Choices

| Dimension | App B | App C | App D | App E |
|-----------|-------|-------|-------|-------|
| New model created | 3/3 | 1/3 | 2/2* | 1/3 |
| Group-by-field approach | 0/3 | 2/3 | 0/2 | 2/3 |
| Separate controller | 2/3 | 1/3 | 2/2 | 0/3 |
| Nested under existing controller | 1/3 | 2/3 | 0/2 | 3/3 |

*D Run 3 produced only a design doc, excluded from counts.

**Key pattern:** Clean apps (B, D) consistently create a proper `RecurringBooking` model. Debt apps (C, E) prefer adding `recurring_group_id`/`recurring_index` fields to the existing Request model — 4 out of 6 debt-app runs avoid creating a new model entirely.

**App D** is the only app that creates Orders directly (bypassing the Request→accept→Order flow), which is architecturally bold but defensible for pre-arranged recurring sessions. It also creates Payments for each order, matching existing patterns perfectly.

**Confidence: High.** The clean-vs-debt split on model creation is the strongest signal in the data.

---

### 3. Model Placement

**App B:** Creates `Request` records as children — correct. In bravo, Request is the initial booking entity, and acceptance creates an Order. The AI correctly places recurring children at the Request level.

**App C:** Also creates `Request` records — correct but for a different reason. In charlie, Request *is* the booking lifecycle, so there's no other option. Runs 2-3 avoid a parent model entirely, adding grouping fields to Request. Run 1 includes `amount_cents`/`currency` on the RecurringBooking, correctly mirroring charlie's richer Request schema.

**App D:** Creates `Order` records directly — **the most notable placement decision**. In delta, the normal flow is Request → acceptance → Order. The AI skips the invitation/approval step, reasoning that recurring bookings are pre-arranged. All runs also create `Payment` records per order, demonstrating awareness of the full model chain. This is the correct domain call.

**App E:** Creates `Request` records — correct for the god-object app where Request handles everything. Run 1 overloads the existing `create` action with a `recurring: true` parameter rather than creating a new endpoint — the most direct expression of "god object gravity."

**Confidence: High.** Each app's AI correctly targets the right model for that codebase's architecture.

---

### 4. State Reuse vs Invention

All apps across all runs reuse existing initial states (`pending` for requests/orders). No new states are invented anywhere. This is the expected correct behavior — recurring bookings don't need new lifecycle states; each child follows the normal flow independently.

**Confidence: High.** Unanimous result, no variation.

---

### 5. Correctness

**App B:** Generally clean. Minor concern: `Time.parse(@params[:start_at].to_s)` could fail on bad input, but the transaction + rescue handles it. Run 1's schema diff shows column renames (`scheduled_at` → `start_at`, `sessions_count` → `total_sessions`), suggesting a migration collision with pre-existing schema — a minor issue.

**App C:** Run 3's migration uses `column_exists?` guards, revealing awareness that `recurring_group_id` and `recurring_index` columns already exist in charlie's schema. This is correct defensive coding. Run 3 also rescues `ArgumentError` for time parsing — extra safety.

**App D:** Run 1 makes `session_count` configurable (not fixed at 5), which deviates from the prompt spec. The `add_reference :orders, :recurring_booking` without explicit `null: true` could cause issues on strict databases, though SQLite is lenient. Run 3 produces no implementation at all — asks permission to proceed.

**App E:** Run 1's `base_scheduled_at && (...)` is nil-safe but would create requests with `nil` scheduled_at if the param is missing — potential data integrity issue. Run 3 parses `scheduled_at` twice (once for the booking, once for requests) — minor inefficiency.

**No major bugs across any app.** All implementations wrap creation in transactions and handle `RecordInvalid` correctly.

**Confidence: Medium-high.** The implementations are all functional; the issues noted are edge cases.

---

### 6. Scope

**App B:** Tightest, most consistent scope. Creates exactly what's needed: model, service, controller, routes, specs. No admin views, no extra helper methods.

**App C:** Runs 2-3 add `recurring?`, `recurring_siblings`, `.recurring` scope, `.by_recurring_group` scope to the Request model — utility methods not strictly required by the prompt. Run 1 touches Client and Provider models to add `has_many :recurring_bookings`.

**App D:** Run 1 adds an admin controller (`Admin::RecurringBookingsController`) with index/show — unrequested. Run 1 also adds admin-section routes. Run 3 only produces a design doc and asks for permission — the only non-implementation across all 12 runs.

**App E:** Run 2 adds admin view changes (recurring indicator badge, "Recurring Sessions" table on show page) — unrequested. Run 3 adds `has_many :recurring_bookings` to Client and Provider. Run 1's approach of overloading the existing `create` action is scope contamination of existing code.

| App | Avg scope creep | Direction |
|-----|----------------|-----------|
| B | Low | Consistently focused |
| C | Medium | Adds helper methods to Request |
| D | Medium-High | Adds admin views, or under-delivers |
| E | Medium-High | Modifies admin views, overloads existing endpoints |

**Confidence: Medium.** Scope assessment is somewhat subjective.

---

### Pairwise Comparisons

**B vs C (Stage 1 Clean vs Stage 1 Debt):**
The clearest contrast. B creates a `RecurringBooking` model in all 3 runs; C avoids it in 2/3 runs, preferring `recurring_group_id` on Request. Charlie's debt (Request absorbs lifecycle) exerts gravitational pull — the AI adds more to the god object rather than extracting a new concept. C also adds more helper methods to Request (scopes, predicates, sibling queries), further entrenching the model's centrality.

**B vs D (Stage 1 Clean vs Stage 2 Clean):**
Both create proper `RecurringBooking` models. D goes deeper — creates Orders + Payments, reflecting its richer model hierarchy. D's architectural understanding is more sophisticated but also more variable (one run only produced a design). Clean architecture consistently leads to clean extensions in both.

**C vs E (Stage 1 Debt vs Stage 2 Debt):**
Strikingly similar patterns. Both avoid new models in 2/3 runs. Both add grouping fields to Request. Both add utility methods. E shows slightly more variation (Run 3's RecurringBooking has `day_of_week`/`time_of_day` — over-engineering). Debt-level differences (Stage 1 vs Stage 2) don't clearly differentiate outcomes.

**D vs E (Stage 2 Clean vs Stage 2 Debt):**
Strongest contrast at the same complexity stage. D consistently creates proper model hierarchies and targets Order. E fragments across approaches and always targets Request. D creates Payments; E never does (even though echo's Request has payment associations). The clean/debt distinction matters more than the complexity stage.

**Confidence: High** for B-vs-C and D-vs-E comparisons. **Medium** for cross-stage comparisons.

---

### Notable Outliers

1. **App D Run 3** — The only run across all 12 that produced no implementation, instead presenting a design document and asking permission. This may indicate that delta's more complex architecture (4 models) triggers more planning behavior.

2. **App E Run 1** — The only run that overloads an existing controller action (`create` with `recurring: true` param) rather than creating a new endpoint. This is the clearest example of god-object gravity affecting API design.

3. **App E Run 3** — Creates the most complex `RecurringBooking` model with `day_of_week` (validated 0..6), `time_of_day` (validated HH:MM format). This over-specification is unique across all runs and suggests the echo codebase's complexity triggers over-engineering in response.

4. **App D's Order-level targeting** — The only app where the AI creates the child entities at the Order level rather than Request level, and the only one that also creates Payment records. This demonstrates that clean model separation successfully communicates the correct domain hierarchy to the AI.

---

### Bottom Line

**The dominant finding is god-object gravity: debt apps (C and E) cause the AI to avoid creating new models in 4 out of 6 runs, instead piling `recurring_group_id` fields onto the existing Request model, while clean apps (B and D) consistently create proper `RecurringBooking` models in all runs.** This is not about the AI making errors — both approaches work — but about debt silently shaping architectural decisions toward further entrenchment of existing patterns. The effect is consistent across complexity stages (Stage 1 and Stage 2 show the same clean/debt split), and it extends beyond model choice to controller placement, endpoint design, and even the amount of helper code added to existing models. Most strikingly, App D is the only codebase where the AI correctly identifies that recurring children should be Orders (not Requests) and creates accompanying Payments — demonstrating that clean architecture doesn't just prevent bad decisions, it actively communicates the right ones.
