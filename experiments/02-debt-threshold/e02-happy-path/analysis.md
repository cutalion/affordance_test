# Analysis: e02-happy-path

> Blind comparison — app identities not revealed to analyzer.

# Cross-App Analysis: Happy Path Experiment

## 1. Language/Framing

**App A**: All 3 runs describe Request as a "service booking" or "appointment" — simple, invitation-like language. The framing is clean: register, book, accept, done. No mention of payment processing, work execution, or fulfillment. The entity "fits" its name perfectly — a request that gets accepted or not.

**App B**: Runs 1-2 correctly identify Order as the "main entity," but Run 3 pivots and calls Request the main entity, walking through the entire Request→Order→Payment chain. The framing is marketplace/fulfillment-oriented. All runs describe a multi-entity lifecycle clearly.

**App C**: All 3 runs frame Request as carrying the full service lifecycle — accept, start, complete, charge. The language is naturally "request = work order" without any friction or hedging. Notably, none of the runs question whether a "Request" should handle payment capture and work execution.

**App D**: All 3 runs identify Order as the main entity and describe a clean Request→Order handoff. The language is the most architecturally precise of all apps — "two-sided marketplace where Clients book Providers through requests, which convert into paid orders" (Run 3).

**App E**: All 3 runs frame Request as carrying the full lifecycle (same as App C). Run 3 is the only response across all 45 runs (5 apps × 3 runs × 3 dimensions... well, 15 runs here) that mentions Announcements: "There's also an alternative entry point via Announcements." This is a significant signal.

**Pattern**: The AI mirrors back whatever the code tells it. When a single model absorbs lifecycle responsibilities (C, E), the AI describes that as natural. It never flags the semantic mismatch of a "Request" capturing payment and tracking work execution.

---

## 2. Architectural Choices

| App | Models Described | State Chain (Happy Path) | Payment Model |
|-----|-----------------|-------------------------|---------------|
| A | Request only | pending → accepted (terminal) | None |
| B | Request + Order + Payment | Request: pending→accepted; Order: pending→confirmed→in_progress→completed | Separate Payment entity |
| C | Request + Payment | pending→accepted→in_progress→completed | Payment created at accept |
| D | Request + Order + Payment | Request: pending→accepted; Order: pending→confirmed→in_progress→completed | Separate Payment entity |
| E | Request + Payment (+Announcement in Run 3) | pending→accepted→in_progress→completed | Payment created at accept |

**Key split**: Apps B and D have a clean architectural boundary — Request handles the "ask," Order handles the "do." Apps C and E collapse this into one entity. App A doesn't need the distinction at all (it's just an invitation).

**Confidence**: High. All runs within each app are highly consistent on architecture.

---

## 3. Model Placement

This was a "describe what exists" prompt, not a "build something new" prompt, so model placement is about whether the AI correctly identifies where behavior lives.

- **App A**: Correct. AcceptService on Request, no overreach.
- **App B**: Runs 1-2 correct. **Run 3 is wrong** — it describes Order creation as a separate client-initiated `POST /api/orders` call, when the code actually auto-creates the Order inside `Requests::AcceptService`. This is a significant misread.
- **App C**: Correct. All runs accurately describe AcceptService creating payment and capturing holds on the Request.
- **App D**: Correct across all runs. The Request→Order handoff via AcceptService is consistently described.
- **App E**: Mostly correct. Run 3 names the internal method `accept_invitation!` which is a notable detail — it suggests the AI is reading deeply into the service code. The Announcement mention is also correct per the codebase.

**Outlier**: App B Run 3 invents a separate order creation step that doesn't exist. This is the most significant factual error across all 15 runs.

---

## 4. State Reuse vs. Invention

All responses faithfully report existing states. No AI run invents new states or proposes additions. This is expected for a "describe" prompt but worth confirming.

| App | States Reported | Accuracy |
|-----|----------------|----------|
| A | pending, accepted, declined, expired | Correct |
| B | Request: pending, accepted, declined, expired; Order: pending, confirmed, in_progress, completed, canceled, rejected | Correct |
| C | pending, accepted, in_progress, completed, declined, expired, canceled, rejected | Correct |
| D | Same as B + (Announcement/Response states not mentioned) | Partially correct — omits Announcement/Response |
| E | Same as C + mentions Announcements in Run 3 only | Partially correct |

**Notable**: App D never mentions Announcement or Response models in any run, despite them existing in the codebase. The prompt asked about "the main entity," which gives the AI license to focus, but it's a contrast with App E Run 3 which does surface the Announcement pathway. This suggests the clean separation in App D makes secondary entities feel truly separate, while the god-object in App E leaks cross-cutting concerns into the main entity's description.

---

## 5. Correctness

| App | Run | Errors |
|-----|-----|--------|
| A | 1-3 | None. All accurate. Run 1 notes "no automated expiration job is wired up yet" — good observational detail. |
| B | 1 | Clean |
| B | 2 | Clean |
| B | 3 | **Error**: Describes Order creation as a separate client API call (`POST /api/orders`), not as automatic side-effect of accept. Misattributes agency. |
| C | 1-3 | None. Consistently accurate. |
| D | 1-3 | None. All accurate on the Request→Order flow. |
| E | 1-2 | Clean |
| E | 3 | Mentions `accept_invitation!` method name — correct but reveals internal naming that hints at the domain tension. Also correctly surfaces Announcement as alternative entry. |

**Error rate**: 1 significant error out of 15 runs (6.7%), occurring in App B Run 3. The error is specifically about the *boundary* between Request and Order — the AI got confused about which actor triggers Order creation. This is the exact kind of architectural seam that multi-entity systems create.

---

## 6. Scope

**App A**: Tightly scoped. No run adds unrequested features. The responses are the shortest and most focused.

**App B**: Mostly scoped. Run 3 over-describes by walking through the entire chain from Request through Review, arguably going broader than "main entity."

**App C**: Well scoped. All runs include Payment lifecycle as integral to the Request happy path, which is appropriate since the code couples them.

**App D**: Well scoped but omits secondary entities entirely. No run mentions Announcements or Responses.

**App E**: Run 3 adds the Announcement mention, which is arguably out of scope for "main entity happy path" but reveals real architectural coupling.

**Pattern**: Simpler apps (A) produce tighter responses. God-object apps (E) leak adjacent concerns. Clean multi-entity apps (B, D) occasionally confuse boundaries.

---

## Pairwise Comparisons

**A vs. C vs. E** (all named "Request", increasing complexity):
- A's Request is a true invitation — 2 states, no payment. AI describes it cleanly.
- C's Request absorbs the full lifecycle — AI describes this without friction, as if a "Request" doing payment capture is natural.
- E's Request is the same as C but also entangled with Announcements — Run 3 leaks this.
- **Finding**: The AI never questions the semantic overloading. "Request" meaning "invitation" (A) vs. "Request" meaning "work order with payment" (C/E) produces no commentary about naming mismatch.

**B vs. D** (both have Request + Order, increasing complexity):
- Nearly identical descriptions across all runs. Both correctly identify the Request→Order handoff.
- D's extra entities (Announcement, Response) are invisible in the happy path descriptions — clean separation works.
- B has the one factual error (Run 3 misplacing Order creation).
- **Finding**: Adding more entities (D) doesn't degrade accuracy when architecture is clean. The boundary confusion in B suggests even clean multi-entity systems can trip the AI at the seam.

**C vs. E** (both god-objects, different complexity):
- Nearly identical happy paths described. Both: pending→accepted→in_progress→completed.
- E Run 3 is the only one that surfaces the Announcement alternative pathway.
- **Finding**: The god-object pattern produces consistent (if uncritical) descriptions. The AI adapts to whatever the code says without pushback.

**B vs. C** (same complexity level, clean vs. debt):
- B describes two distinct lifecycles with a clear handoff point.
- C describes one lifecycle with payment as a side-effect.
- Both are "correct" relative to their codebase — the AI doesn't prefer one architecture.
- **Finding**: The AI is a mirror, not a critic. It will accurately describe either pattern without noting tradeoffs.

---

## Confidence Levels

| Dimension | Confidence | Reasoning |
|-----------|-----------|-----------|
| Language/framing | **High** | 15 runs, consistent patterns within apps, clear divergence between apps |
| Architecture | **High** | All runs agree on entity boundaries within each app |
| Model placement | **High** | Only 1 error in 15 runs |
| State reuse | **High** | No invention anywhere |
| Correctness | **High** | One clear error, easily identified |
| Scope | **Medium** | Scope judgments are somewhat subjective (is mentioning Announcements in E out of scope or insightful?) |

---

## Notable Outliers

1. **App B Run 3**: Only run to misattribute Order creation to a separate API call. The multi-entity seam confused the AI.
2. **App E Run 3**: Only run across all 15 to mention Announcements. The god-object's coupling made the alternative entry point visible during happy-path analysis.
3. **App A Run 1**: Only run to editorialize about missing implementation ("no automated expiration job is wired up yet").
4. **App D**: Zero mention of Announcements or Responses across all 3 runs, despite these models existing — clean separation made them invisible to the happy-path question.

---

## Bottom Line

The AI faithfully mirrors whatever architecture it finds without questioning semantic fitness — a "Request" that captures payments and tracks work execution is described with the same confidence as a "Request" that's purely an invitation. The most important finding is the **asymmetry of leakage**: in clean multi-entity architectures (B, D), secondary entities stay invisible to the happy-path question (good encapsulation), but the one factual error (B Run 3) occurs precisely at the entity boundary seam; in god-object architectures (C, E), the AI never flags the overloaded semantics, but the entanglement does leak — App E Run 3 surfaces Announcements unprompted, revealing that coupling in code becomes coupling in explanation. Clean architecture contains complexity at the cost of occasional boundary confusion; debt architecture eliminates boundaries at the cost of conceptual bleed.
