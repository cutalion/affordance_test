# Summary: 03-propose-different-time

**Prompt:** Add a feature where the provider can propose a different time instead of just accepting or rejecting. The client can then accept or decline the counter-proposal. Implement this and commit your changes.
Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation.

**Type:** code

**Naming key:** App A = Order (clean states) | App B = Request (legacy invitation-era states)

---

## Summary: Experiment 03 — Propose Different Time

### The Setup

Two structurally identical Rails booking apps were given the same task: let a provider propose a different time for a booking. The only difference was naming — **App A uses "Order"** with clean states (pending → confirmed → completed), while **App B uses "Request"** with legacy invitation-era states (created → accepted → fulfilled, plus decline/miss paths). A blind analyzer compared the AI outputs without knowing which app was which.

### Key Finding: Legacy Names Act as Semantic Anchors

The strongest signal was in **decline behavior**. When a parent declines the provider's proposed time:

- **Request app: 6/6 runs** treated decline as terminal (→ `declined`). Every AI agent, both Opus and Sonnet, mapped "decline a counter-proposal" onto the existing `decline` event that already transitions to a `declined` state. The legacy naming provided a ready-made concept.
- **Order app: only 4/6 terminal**, with 2/6 returning to `pending` for further negotiation. The Order app has no existing "decline" event — its closest equivalent is `reject` (from `confirmed` → `rejected`), which doesn't map cleanly to declining a proposal from a pre-confirmed state. This created genuine design ambiguity.

**Confidence: Strong.** This is a concrete case where naming directly shaped state machine design. The Request app's legacy vocabulary — built for an invitation system where declining is a first-class concept — gave AI agents a clear template. The Order app's cleaner but thinner vocabulary left room for interpretation.

### Secondary Findings

**State name convergence.** Request app runs converged on `counter_proposed` (4/6), while Order app runs scattered across four different names. The "Request" framing, with its negotiation connotations, nudged agents toward counter-proposal language.

**Scope creep direction differed.** Order app agents added `proposed_duration_minutes` (2/6 runs, never in Request) — extending negotiation to *what* is ordered. Request app agents were more likely to add mailer notifications (4/6 vs 2/6) — extending *communication* about the request. Each name primed different kinds of feature expansion.

**Order produced more outliers.** The biggest scope creep came from order-sonnet-3: payment refunds on decline, future-time validation, proposing from `confirmed` state. The Order app's semantic ambiguity seemed to invite more creative interpretation.

### Confidence Assessment

The decline behavior divergence is the one strong, clearly attributable signal. The state naming convergence and scope creep patterns are directionally interesting but at weak confidence — sample sizes are small and individual run variance is high.

### The Interesting Bit

The most surprising finding is that **legacy naming outperformed clean naming** for design consistency. The Request app's invitation-era vocabulary — which a human developer might want to refactor away — actually gave AI agents better conceptual scaffolding. "Decline a request" is a phrase with clear semantics; "decline an order" is ambiguous (cancel it? reject just the proposal?). Sometimes the messy, historically-evolved name carries more meaning than the tidy abstraction.


## Branches

### Order App

- `experiment/03-propose-different-time/order/opus/run-1`
- `experiment/03-propose-different-time/order/opus/run-2`
- `experiment/03-propose-different-time/order/opus/run-3`
- `experiment/03-propose-different-time/order/sonnet/run-1`
- `experiment/03-propose-different-time/order/sonnet/run-2`
- `experiment/03-propose-different-time/order/sonnet/run-3`

### Request App

- `experiment/03-propose-different-time/request/opus/run-1`
- `experiment/03-propose-different-time/request/opus/run-2`
- `experiment/03-propose-different-time/request/opus/run-3`
- `experiment/03-propose-different-time/request/sonnet/run-1`
- `experiment/03-propose-different-time/request/sonnet/run-2`
- `experiment/03-propose-different-time/request/sonnet/run-3`
