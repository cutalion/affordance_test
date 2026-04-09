# Analysis: e02-happy-path

> Blind comparison — app identities not revealed to analyzer.

## Analysis: Happy Path Responses Across 5 Apps

---

### 1. Language/Framing

**App A**: All 3 runs describe a simple invitation-style interaction. Language is minimal — "the provider reviews and accepts." Run 3 adds a brief mention of actual service delivery ("the provider shows up") but acknowledges this is outside the modeled states. The AI consistently frames Request as a **matching/invitation** mechanism, not a booking.

**App B**: All 3 runs frame the system as a **two-phase lifecycle** — "Request then Order." The AI clearly separates the matching phase (Request) from the fulfillment phase (Order). Run 1 even uses the header "Phase 1 / Phase 2 / Phase 3." The language treats Request and Order as distinct concerns with distinct responsibilities.

**App C**: All 3 runs describe a **single entity spanning the full booking lifecycle** — from creation through payment and reviews. The language is uniform: "the request is started," "the request is completed." No second entity is introduced. The AI accepts the Request-as-everything framing without question.

**App D**: All 3 runs identify **Order as the main entity**, not Request. The AI frames Request as an acquisition channel leading to Order. All runs also surface the Announcement pathway as an alternative acquisition flow. Language emphasizes convergence: "two ways an Order can originate, then they converge."

**App E**: All 3 runs identify **Request as the main entity** and describe it spanning the full lifecycle (pending → completed), same as App C. Announcements are mentioned but only in passing ("optionally linked to an announcement"). The AI treats the Request as the single throughline.

**Pattern**: The AI mirrors whatever framing the codebase implies. When a single model owns the lifecycle, the AI describes a single entity journey. When models are separated, the AI separates its narrative. No run in any app challenges the architecture it finds.

---

### 2. Architectural Choices

| Dimension | App A | App B | App C | App D | App E |
|-----------|-------|-------|-------|-------|-------|
| Main entity | Request | Order (with Request as precursor) | Request | Order (with Request as precursor) | Request |
| Models surfaced | Request, Client, Provider | Request, Order, Payment, Review, Card | Request, Payment, Review, Card | Request, Order, Announcement, Response, Payment, Review, Card | Request, Announcement, Payment, Review |
| State count (happy) | 2 (pending, accepted) | Request: 2, Order: 4, Payment: 3 | 4 (pending→accepted→in_progress→completed) | Request: 2, Order: 4, Payment: 3 | 4 (pending→accepted→in_progress→completed) |
| Payment modeled? | No | Yes (separate model) | Yes (separate model) | Yes (separate model) | Yes (separate model) |
| Reviews modeled? | No | Yes | Yes | Yes | Yes |

**Pattern**: Apps B and D both decompose the lifecycle across Request + Order, resulting in cleaner per-entity state machines (2 states each for Request, 4 for Order). Apps C and E collapse everything onto Request, resulting in a single 4+ state machine that handles matching, fulfillment, and payment. App A is the simplest — only the matching phase exists.

---

### 3. Model Placement

This experiment asks a descriptive question ("what is the happy path?"), so the AI isn't placing new features — it's identifying which model owns which concern. The key finding:

- **App B**: AI correctly identifies the Request/Order boundary. Request owns matching (pending→accepted), Order owns fulfillment (pending→confirmed→in_progress→completed). All 3 runs are consistent.
- **App D**: Same clean separation as B, plus the AI correctly identifies that both Request and Announcement/Response are acquisition channels that feed into Order. All 3 runs converge on this.
- **App C**: AI places the entire lifecycle on Request without hesitation. Payment hold happens "on accept," payment charge happens "on complete" — all on the Request model.
- **App E**: Same as C — everything on Request. The Announcement is mentioned but the AI doesn't surface that Responses *are* Requests or that AcceptService branches on context. The god-object complexity is invisible in the happy path description.

**Confidence**: High. The AI faithfully reflects each codebase's architecture; the question is whether it *should* have flagged architectural concerns in C and E. It didn't.

---

### 4. State Reuse vs. Invention

All runs across all apps are **strictly descriptive** — the AI reports the states it finds in the AASM definitions without inventing new ones. No run introduces a state that doesn't exist in the codebase.

- App A: pending, accepted (plus declined, expired in unhappy paths) — **correct**
- App B: Request (pending, accepted); Order (pending, confirmed, in_progress, completed) — **correct**
- App C: pending, accepted, in_progress, completed — **correct**
- App D: Same as B plus Announcement (draft, published, closed) and Response (pending, selected, rejected) — **correct**
- App E: pending, accepted, in_progress, completed — **correct**

**Notable**: No run invents transitional or synthetic states. The AI reads the state machine and reports it faithfully. This is expected for a descriptive prompt.

---

### 5. Correctness

**App A**: All runs correct. Run 3 adds a soft "Step 3: service is delivered" which is reasonable interpretation but not modeled in code. Minor embellishment, not an error.

**App B**: 
- Run 1: Correctly sequences Request→Order→Payment→Review. States and transitions are accurate.
- Run 2: States "Accepting a Request creates an Order" — this is a reasonable inference from `has_one :order` but the actual creation mechanism matters. No factual error.
- Run 3: Says "A Payment record is created (status: pending). The day before the scheduled time, the payment hold is placed" — the "day before" is **invented detail** not derivable from the code. Minor speculation.

**App C**:
- Run 1: Says payment is held "at accept" — needs verification against AcceptService. If AcceptService captures payment (per CLAUDE.md hint about charlie), this is accurate.
- Runs 2-3: Consistent with Run 1. All correct given the codebase structure.

**App D**: 
- All runs correctly identify the dual acquisition path (Request vs Announcement→Response).
- Run 1 provides the most detailed Announcement flow and is accurate.
- No errors detected.

**App E**:
- All runs describe the happy path correctly.
- **Key omission**: None of the 3 runs surface that AcceptService does different things depending on context (announcement vs direct request). The happy path description doesn't reveal the god-object complexity lurking underneath.
- Run 1 mentions "optionally linked to an announcement" but doesn't explore what that changes.

**Confidence**: High for correctness of stated facts. The one invented detail is App B Run 3's "day before" timing.

---

### 6. Scope

| App | Scope adherence | Notes |
|-----|----------------|-------|
| A | Tight | 2-step happy path, brief unhappy path summary. Run 3 slightly expansive with "service is delivered" step. |
| B | Moderate | All runs include Payment and Review lifecycle. Run 1 adds ASCII flow diagram. Justified — these are integral to the happy path. |
| C | Moderate | All runs include Payment and Review. Same justification as B. |
| D | Slightly broad | All runs describe both the Request path and Announcement path. Run 1 provides full detail on both. This is arguably on-task since both are legitimate happy paths. |
| E | Moderate | Similar to C but with brief Announcement mentions. |

**Pattern**: No app produces genuinely off-topic content. The scope naturally scales with codebase complexity — more models in the codebase means more models in the response. No run adds unrequested features or speculative extensions.

---

### Pairwise Comparisons

**A vs B**: A describes a simple matching protocol (2 states). B describes A's matching protocol *plus* a full fulfillment lifecycle via Order. The Request in both apps behaves identically (pending→accepted), but B's system continues the journey through Order.

**A vs C**: Both use Request as the main entity, but C's Request does everything A's Request does *plus* the entire fulfillment lifecycle (in_progress, completed, payment). The AI doesn't note that "accept" means very different things in each system (A: invitation accepted; C: accept + payment hold).

**B vs D**: D is B plus the Announcement/Response acquisition channel. The Order lifecycle is identical. All D runs correctly identify Order as the main entity, same as B. The Announcement pathway is described as an alternative, not a complication.

**B vs C**: This is the most revealing comparison. Both systems model the same real-world process (matching → fulfillment → payment → review), but:
- B splits it across Request (2 states) and Order (4 states) — clean separation of concerns
- C collapses it into Request (4+ states) — single entity owns everything

The AI describes both architectures with equal confidence and clarity. It does not flag C's design as problematic or unusual.

**C vs E**: Nearly identical responses. Both describe Request spanning the full lifecycle with the same states. The key difference is E mentions Announcements peripherally, but the AI doesn't explore how Announcements interact with the Request model. The god-object nature of E's Request is invisible in happy-path analysis.

**D vs E**: This is the most architecturally divergent pair, yet they model the same domain. D cleanly separates concerns (4 models, each with small state machines). E collapses them (Request absorbs Response behavior, AcceptService branches on context). The AI describes D with clear architectural boundaries and E as a simple linear flow — the structural complexity difference is enormous but the happy-path descriptions feel equally clean.

---

### Notable Outliers

1. **App B Run 3** invents "the day before the scheduled time" for payment hold timing — the only factual embellishment across all 15 runs.

2. **App D Run 1** is the most thorough single response — it details both acquisition paths with full state flows. Other D runs relegate Announcements to a footnote.

3. **App A Run 3** uniquely adds a "Step 3: service is delivered" that goes beyond the modeled states, acknowledging the gap between the state machine and the real-world process.

4. **App E** across all runs fails to surface the AcceptService branching behavior — the most architecturally significant hidden complexity in the experiment, completely invisible to happy-path analysis.

---

### Confidence Levels

| Dimension | Confidence | Rationale |
|-----------|-----------|-----------|
| Language/framing | **High** | 15 runs, consistent patterns within apps, clear divergences between apps |
| Architectural choices | **High** | AI faithfully mirrors each codebase's structure |
| Model placement | **High** | Descriptive task, AI reports what it finds |
| State reuse vs invention | **High** | No invention in any run |
| Correctness | **High** | One minor invented detail (B-R3), otherwise accurate |
| Scope | **High** | All responses appropriately scoped |

---

### Bottom Line

The AI acts as a faithful mirror of whatever architecture it encounters — it describes single-entity lifecycles and multi-entity decompositions with equal fluency and equal confidence, never questioning whether a Request that handles matching, fulfillment, payment, and reviews *should* be a single entity. This means happy-path analysis is a poor tool for detecting architectural debt: Apps C and E produce responses that read as clean and simple as Apps B and D, despite collapsing multiple concerns into one model. The most striking evidence is the C-vs-E comparison, where a god object serving three purposes (direct requests, announcement responses, and full booking lifecycle) produces nearly identical happy-path descriptions to its clean counterpart — the branching complexity inside AcceptService is entirely invisible. **The happy path is the one angle from which debt looks exactly like clean design.**
