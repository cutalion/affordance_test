# Analysis: e01-describe-system

> Blind comparison — app identities not revealed to analyzer.

## Analysis: "Describe This System" Across 5 Codebases

### Dimension 1: Language/Framing

**Pattern**: All five apps are described as a "service marketplace/booking platform" — the AI converges on nearly identical domain framing regardless of structural complexity. The only meaningful variation is how the central entity "Request" is characterized:

| App | How "Request" is framed | Consistency across runs |
|-----|------------------------|------------------------|
| **A** | "booking request," "booking inquiry" — an invitation/ask | 3/3 consistent |
| **B** | "booking inquiry" — a precursor to the real work (Order) | 3/3 consistent |
| **C** | "the core transaction," "a scheduled service booking" — the entire engagement | 3/3 consistent |
| **D** | "direct booking inquiry" — one of two intake paths to Order | 3/3 consistent |
| **E** | "the core transactional entity," "a booking of a specific provider" — does everything | 3/3 consistent |

**Key finding**: The AI promotes Request's importance in proportion to how much responsibility the model carries. In A, it's a simple ask. In C and E, it becomes "the core transaction." The AI doesn't just list states — it reframes the *narrative role* of Request to match what the code actually does. This is correct behavior, but it means the AI **naturalizes** accumulated debt rather than flagging it.

**Confidence**: High (9 consistent characterizations across A/C/E divide).

---

### Dimension 2: Architectural Choices

**Pattern**: The AI accurately mirrors the model graph of each codebase without inventing or omitting entities.

| App | Entities reported | Matches expected architecture? |
|-----|------------------|-------------------------------|
| **A** | Client, Provider, Card, Request | Yes — minimal invitation model |
| **B** | Client, Provider, Card, Request, Order, Payment, Review | Yes — clean separation |
| **C** | Client, Provider, Card, Request, Payment, Review | Yes — Request absorbs Order's role |
| **D** | Client, Provider, Card, Request, Order, Announcement, Response, Payment, Review | Yes — clean multi-path |
| **E** | Client, Provider, Card, Request, Announcement, Payment, Review | Yes — no Response model; Requests serve double duty |

**Notable**: In App E, the AI correctly identifies that announcements generate Requests (not a separate Response model). Run 2 is most explicit: *"A provider views published announcements and responds to one, which creates a request."* However, no run flags this as architecturally unusual — it's presented as a natural design choice.

**Confidence**: High.

---

### Dimension 3: Model Placement

Not applicable for this experiment (descriptive prompt, no feature implementation requested).

---

### Dimension 4: State Reuse vs. Invention

**Pattern**: The AI reports states directly from each codebase without invention or omission.

| App | Request states reported | Accurate? |
|-----|------------------------|-----------|
| **A** | pending → accepted / declined / expired | Yes |
| **B** | pending → accepted / declined / expired | Yes |
| **C** | pending → accepted → in_progress → completed + declined/expired/canceled/rejected | Yes |
| **D** | pending → accepted / declined / expired | Yes |
| **E** | pending → accepted → in_progress → completed + declined/expired/canceled/rejected | Yes |

The AI does not conflate states across models. In B and D, it correctly keeps Request states simple and attributes the richer lifecycle to Order. In C and E, it correctly reports the expanded Request states.

**Confidence**: High — all 15 runs report states accurately.

---

### Dimension 5: Correctness

**Errors found**:

- **App B, Run 3**: States a "hardcoded 350,000 kopecks / 3,500 RUB price" — this is likely accurate to the code but the run uniquely surfaces implementation details the others abstract away. Minor inconsistency in reporting granularity, not a factual error.
- **App C, Run 1**: Describes the system as "Uber-style" — a slight overreach in analogy (Uber is real-time dispatch, this is scheduled bookings), but not a logical error.
- **App E, Run 2**: Describes the workflow as *client* accepting/declining requests from providers responding to announcements. This inverts the actor model compared to Runs 1 and 3 (where the *provider* accepts). This is a notable inconsistency — in app_echo, AcceptService branches on `announcement.present?`, and Run 2 appears to have gotten confused about who does what in the announcement flow.

**Confidence**: Medium-high. Most runs are accurate; the E-Run-2 actor inversion is the only clear logical error across 15 runs.

---

### Dimension 6: Scope

**Pattern**: All responses stay tightly on task. No run suggests features, proposes improvements, or critiques the architecture. The descriptions are observational.

One subtle scope variation: **App D** runs consistently describe the two booking paths (direct request vs. announcement/bidding) as a first-class structural distinction, using headers and subsections. This organizational choice reflects the codebase's clean separation. **App E** runs, by contrast, mention announcements almost as an afterthought — typically a single paragraph at the end. This mirrors the code: in E, announcements are bolted onto the Request model rather than being a separate domain concept.

**Confidence**: High.

---

### Pairwise Comparisons

**A vs. C** (invitation vs. god-object Request): The starkest contrast. Both have a model called "Request," but the AI describes completely different systems. A's Request is a simple ask with 3 terminal states. C's Request is "the core transaction" with 8 states spanning the entire service lifecycle. The AI correctly tracks the semantic drift but *never mentions* that Request is doing something unusual in C.

**B vs. C** (clean vs. debt at Stage 1): B has Request + Order; C collapses them. The AI describes B's workflow in 6 clear steps with distinct phases (booking → fulfillment → payment). C's workflow is described in similar steps but everything hangs on Request. Payment in B is tied to Order; in C it's tied to Request. The AI accurately reflects this without commenting on the design difference.

**D vs. E** (clean vs. debt at Stage 2): D gets the clearest structural descriptions — all three runs use headers to separate the two booking flows and the fulfillment phase. E's descriptions are muddier: the announcement flow is inconsistently explained across runs (Run 1 mentions it briefly, Run 2 gets the actor model wrong, Run 3 handles it best). The debt in E's codebase produces measurably less consistent AI descriptions.

**B vs. D** (Stage 1 clean vs. Stage 2 clean): Both get accurate, well-structured descriptions. D's added complexity (Announcement + Response) is handled cleanly. The AI scales well with *clean* complexity.

**C vs. E** (Stage 1 debt vs. Stage 2 debt): Both have Request as a god object. E adds the announcement dimension. C gets described more consistently (3/3 runs agree on workflow). E shows the only factual error in the entire dataset (Run 2 actor inversion). More debt = more description variance.

---

### Notable Outliers

1. **App E, Run 2** — the only run across all 15 that gets an actor role wrong (client accepts instead of provider). This is the highest-debt codebase.
2. **App C, Run 3** — the only run that includes an ASCII state diagram. Notably, this is the debt codebase where such a diagram is most useful (8 states with complex transitions).
3. **App D, all runs** — consistently the best-organized descriptions, with the clearest structural communication. Clean architecture begets clean descriptions.

---

### Bottom Line

**The AI accurately describes what each codebase does but systematically normalizes technical debt as intentional design.** When Request absorbs Order's lifecycle (App C) or when Responses are eliminated in favor of overloaded Requests (App E), the AI presents these as natural architectural choices rather than accumulated debt — it reshapes its narrative framing to make the god object feel coherent. This means an AI "system description" cannot be used to detect debt: a clean two-model system (B) and a debt-laden single-model system (C) both receive equally confident, equally plausible descriptions. The only measurable signal of debt is *consistency*: the highest-debt codebase (E) produced the only factual error and the most inter-run variance, suggesting that architectural confusion in code propagates as descriptive confusion in AI output.
