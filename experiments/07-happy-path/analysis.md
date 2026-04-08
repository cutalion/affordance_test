# Analysis: 07-happy-path

> Blind comparison — App A and App B naming not revealed to analyzer.

# Analysis: Experiment 07 — Happy Path

## 1. Language/Framing

**App A (Order):** Consistently uses transactional, business-process language. "Confirms," "starts," "completes." The entity is framed as something the provider *acts on*. States are described as clean lifecycle phases. All 6 runs describe the flow as self-evidently clear.

**App B (Request):** Uses relational, agreement-oriented language. "Accepts," "fulfills." The entity is framed as something one party *asks for* and the other *grants*. Every single run (6/6) spontaneously discusses unhappy paths or legacy complexity — the `created_accepted` state and alternate creation paths. Sonnet runs especially call out `created_accepted` as "legacy artifact," "orphaned," or "never cleaned up."

**App C (Request Clean):** Language mirrors App A's patterns almost exactly ("confirms," "starts," "completes") but applied to an entity called "Request." No legacy commentary appears in any run. The framing is transactional despite the entity name.

**Confidence:** Strong pattern

**Pairwise:** A≈C (same verbs, same framing) ≠ B (different verbs, legacy commentary)

---

## 2. Architectural Choices

### State sequences reported

| App | Happy path states | Runs agreeing |
|-----|------------------|---------------|
| A (Order) | pending → confirmed → in_progress → completed | 6/6 |
| B (Request) | created → accepted → started → fulfilled | 6/6 |
| C (Request Clean) | pending → confirmed → in_progress → completed | 6/6 |

### Additional states/paths mentioned

| Element | App A | App B | App C |
|---------|-------|-------|-------|
| `created_accepted` state discussed | 0/6 | 4/6 | 0/6 |
| `create_direct` / alternate creation path | 0/6 | 2/6 | 0/6 |
| Cancel path mentioned | 5/6 | 3/6 | 5/6 |
| Reject path mentioned | 5/6 | 2/6 | 5/6 |
| Decline/missed states mentioned | 0/6 | 3/6 | 0/6 |
| Payment lifecycle detailed | 6/6 | 6/6 | 6/6 |
| Reviews described | 6/6 | 5/6 | 6/6 |

**Confidence:** Strong pattern. App B's legacy states pull attention — models feel compelled to explain `created_accepted` even when asked only about the happy path.

---

## 3. Complexity (Verbosity & Detail)

### Step counts in happy path

| App | Avg steps described | Range |
|-----|-------------------|-------|
| A (Order) | 5.7 | 5–6 |
| B (Request) | 5.5 | 4–7 |
| C (Request Clean) | 5.8 | 5–6 |

### Qualitative detail level

- **App A Sonnet** runs are the most detailed — they name specific services (`Orders::CreateService`, `Orders::ConfirmService`), background jobs (`PaymentHoldJob`, `ReviewReminderJob`), API endpoints, and notification event names. All 3 Sonnet runs follow an identical structural template.
- **App B Sonnet** runs are similarly detailed but invest significant space on legacy commentary. Sonnet-2 spends ~30% of its response on `created_accepted` analysis.
- **App C Sonnet** runs match App A Sonnet in detail and structure, naming services, jobs, and endpoints identically (just with `Requests::` namespace).

**Confidence:** Strong pattern. Sonnet is consistently more operationally detailed across all apps. Opus is more conceptual/summarized.

---

## 4. Scope

**App A:** All 6 runs stay tightly on-task. Unhappy paths are mentioned as brief footnotes (1–3 sentences). No scope creep.

**App B:** 4/6 runs go off-scope to explain `created_accepted`. Sonnet-2 explicitly calls it "orphaned" and analyzes it architecturally. Sonnet-3 describes the alternate API endpoint `POST /api/requests/create_direct`. The legacy complexity acts as a scope attractor — models feel they must explain it even when not asked.

**App C:** All 6 runs stay on-task, matching App A's discipline. No digressions.

**Confidence:** Strong pattern. The legacy states in App B consistently pull responses off the happy path.

**Notable outlier:** request-sonnet-2 spends the most time on `created_accepted`, calling it a state with "no transition leading into it from the defined events" — a structural analysis that wasn't requested.

---

## 5. Assumptions

**App A:** All runs assume a two-sided marketplace (client books provider). 3/6 mention RUB currency. The domain is treated as generic service booking.

**App B:** Same marketplace assumption, but 2/6 runs (both Sonnet) explicitly reference "Kidsout" and its "invitation era" — the legacy naming triggers domain archaeology. The models assume the naming reflects historical baggage that needs explanation.

**App C:** Same marketplace assumption as App A. 1/6 (request_clean-sonnet-2) calls it "a babysitting booking" — the only run across all apps to guess the specific domain. No legacy assumptions.

**Confidence:** Weak signal on domain guessing. Strong signal that App B's naming triggers historical/legacy assumptions.

---

## 6. Model Comparison (Opus vs Sonnet)

| Dimension | Opus pattern | Sonnet pattern |
|-----------|-------------|---------------|
| Structure | Numbered steps with bold state names | Numbered steps with service/job names |
| Detail | Conceptual — "the provider confirms" | Operational — "`Orders::ConfirmService` calls `order.confirm!`" |
| Services named | Rarely | Always |
| Background jobs | Mentioned 2/9 | Mentioned 6/9 |
| API endpoints | 0/9 | 4/9 |
| Notification events | 1/9 | 7/9 |
| Legacy commentary (App B) | 1/3 reference `created_accepted` briefly | 3/3 analyze `created_accepted` in depth |
| State diagrams | Text summary | ASCII art / code blocks in 4/9 |

**Confidence:** Strong pattern. Sonnet is consistently more implementation-oriented, naming concrete classes and endpoints. Opus describes behavior abstractly. This holds across all three apps.

**Notable outlier:** opus-2 (App A) names specific notification symbols (`:order_created`, `:order_completed`) — unusually operational for Opus.

---

## Pairwise Comparisons

**A vs C (most similar):** Near-identical responses. Same state names, same verbs, same structure, same scope discipline. The only difference is the entity name (Order vs Request). This pair isolates naming from structure — and naming alone caused essentially no behavioral difference in happy-path description.

**A vs B (moderately different):** Different state names and verbs (confirm/complete vs accept/fulfill). App B responses are pulled toward legacy complexity discussion. The structural differences in the codebase cause measurable differences in response scope and framing.

**B vs C (most different):** Despite both using "Request" as the entity name, they diverge significantly. App C responses read like App A responses with a find-replace on the entity name. App B responses carry legacy baggage, extra states, and defensive explanations. This confirms that structural complexity, not naming, drives the behavioral differences.

---

## Raw Tallies

| Metric | App A (Order) | App B (Request) | App C (Request Clean) |
|--------|--------------|-----------------|----------------------|
| Runs mentioning legacy/historical context | 0/6 | 4/6 | 0/6 |
| Runs mentioning `created_accepted` or alternate paths | 0/6 | 4/6 | 0/6 |
| Runs that stay strictly on happy path | 6/6 | 2/6 | 6/6 |
| Runs naming specific service classes | 3/6 | 4/6 | 4/6 |
| Runs naming background jobs | 3/6 | 1/6 | 4/6 |
| Average unhappy-path sentences | 2.3 | 3.5 | 2.2 |
| Runs referencing "Kidsout" by name | 0/6 | 2/6 | 0/6 |

---

## Bottom Line

**Structural complexity, not entity naming, is the dominant factor.** Apps A and C produce nearly indistinguishable responses despite one using "Order" and the other "Request" — same states, same verbs, same scope discipline. App B, which shares the "Request" name with C but adds legacy states (`created_accepted`, `declined`, `missed`) and alternate creation paths, consistently pulls AI responses off the happy path and into unsolicited architectural commentary. The legacy states act as a cognitive attractor: even when asked only about the happy path, 4/6 App B runs feel compelled to explain `created_accepted`. Sonnet amplifies this effect — all 3 Sonnet runs on App B analyze the legacy state in depth, compared to 1/3 Opus runs. The naming of the entity ("Request" vs "Order") has negligible impact on how the AI describes the happy path; the structural noise in the state machine is what changes behavior.
