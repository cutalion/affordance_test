# Summary: 02-rebook-feature

**Prompt:** Add a feature that lets a client re-book with the same provider. The client should be able to create a new booking based on a previous one, reusing provider, location, and duration. Implement this and commit your changes.
Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation.

**Type:** code

**Naming key:** App A = Order (clean name + clean states) | App B = Request (legacy name + legacy states) | App C = Request Clean (legacy name + clean states)

---

## Experiment 02: Rebook Feature — Summary

### Setup

Three structurally related Rails apps received the same prompt: implement a "rebook" feature that creates a new booking based on a previous one. The apps differed along two axes:

- **App A (Order):** Entity named `Order`, clean 6-state lifecycle (pending → confirmed → in_progress → completed, plus canceled/rejected).
- **App B (Request):** Entity named `Request`, legacy 9-state lifecycle inherited from an invitation system (includes `created_accepted`, `accepted`, `started`, `fulfilled`, `missed`, etc.). Extra services and API endpoints.
- **App C (Request Clean):** Entity named `Request`, but with the *same* clean 6-state lifecycle as App A. Identical service structure to App A. This is the control — it isolates naming from structural complexity.

Each app was implemented 6 times (3 Opus, 3 Sonnet) by AI agents who had no knowledge of the experiment.

### Key Finding: Naming Drives Domain Reasoning

The starkest result: **3 of 6 App A runs added state-based rebooking restrictions** (only completed/canceled/rejected orders can be rebooked). Zero App B runs and zero App C runs added any state restriction — despite App C having the *identical* state machine as App A.

This is the headline: the word "Order" prompted the AI to reason about lifecycle semantics and add business rules that weren't in the prompt. The word "Request" — even with the same clean states — did not. The AI treats "Order" as a domain object with a meaningful lifecycle worth guarding. "Request" is treated as something more transient, where any state is fair game.

App A also uniquely produced model-level enrichments: `rebookable?` methods, scopes, and `rebook_attributes` helpers (2/6 runs). Neither Request app ever touched the model layer for this feature.

### Structural Complexity Has a Separate, Independent Effect

App B's legacy 9-state machine discouraged code reuse. When building the rebook feature, App B runs reimplemented the create-transaction logic manually in 4/6 cases rather than delegating to the existing `CreateService`. App A delegated in 3/6 runs, and App C — with the same simple structure — delegated most often at 4/6. The AI appears less confident that `CreateService` handles the rebook case correctly when the state machine is complex and unfamiliar.

App B also introduced "booking" as a synonym in 3/6 runs (e.g., "rebook based on a previous booking"), a word that appears in neither the codebase nor the prompt. Neither App A nor App C exhibited this drift. The legacy naming apparently made the AI reach for clearer domain language.

### App C Behaves Like B (Same Name), Not A (Same Structure)

This is the critical comparison. App C shares App A's structure but App B's entity name. On every behavioral metric that diverged between A and B, **App C aligned with B**:

| Metric | App A (Order) | App B (Request) | App C (Request Clean) |
|---|---|---|---|
| State gating added | 50% | 0% | **0%** |
| Model enrichment | 33% | 0% | **0%** |
| Service specs written | 100% | 50% | **33%** |
| Avg new files | 2.0 | 1.5 | **1.0** |

App C actually produced the *leanest* implementations overall — 2/6 runs had no service file at all, inlining everything into the controller. Clean structure plus a "lightweight" entity name produced minimal output.

### Confidence

**Strong** for the naming effect on domain reasoning (state gating: 3/6 vs 0/12 across both Request apps). **Moderate** for structural complexity discouraging service reuse. **Weak** for language/synonym drift (small sample).

### Most Surprising Finding

The state-gating result was unexpected in its sharpness. App C has the exact same six states as App A. An AI reading App C's code can see `completed`, `canceled`, `rejected` just as clearly. Yet it never reasoned about which states should permit rebooking. The name on the entity — not the states themselves — is what triggers lifecycle reasoning. "Order" activates e-commerce domain knowledge where lifecycle matters; "Request" activates a mental model closer to "message" or "ask," where restricting actions by state feels less natural.

This suggests that **naming is not cosmetic** — it is a functional affordance that shapes how AI agents understand and extend a system.


## Branches

### Order App

- `experiment/02-rebook-feature/order/opus/run-1`
- `experiment/02-rebook-feature/order/opus/run-2`
- `experiment/02-rebook-feature/order/opus/run-3`
- `experiment/02-rebook-feature/order/sonnet/run-1`
- `experiment/02-rebook-feature/order/sonnet/run-2`
- `experiment/02-rebook-feature/order/sonnet/run-3`

### Request App

- `experiment/02-rebook-feature/request/opus/run-1`
- `experiment/02-rebook-feature/request/opus/run-2`
- `experiment/02-rebook-feature/request/opus/run-3`
- `experiment/02-rebook-feature/request/sonnet/run-1`
- `experiment/02-rebook-feature/request/sonnet/run-2`
- `experiment/02-rebook-feature/request/sonnet/run-3`

### Request Clean App

- `experiment/02-rebook-feature/request_clean/opus/run-1`
- `experiment/02-rebook-feature/request_clean/opus/run-2`
- `experiment/02-rebook-feature/request_clean/opus/run-3`
- `experiment/02-rebook-feature/request_clean/sonnet/run-1`
- `experiment/02-rebook-feature/request_clean/sonnet/run-2`
- `experiment/02-rebook-feature/request_clean/sonnet/run-3`
