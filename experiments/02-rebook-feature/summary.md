# Summary: 02-rebook-feature

**Prompt:** Add a feature that lets a client re-book with the same provider. The client should be able to create a new booking based on a previous one, reusing provider, location, and duration. Implement this and commit your changes.
Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation.

**Type:** code

**Naming key:** App A = Order (clean states) | App B = Request (legacy invitation-era states)

---

## Experiment 02: Rebook Feature — Summary

### The Setup

Two structurally identical Rails booking apps were given to AI agents (Claude Opus and Sonnet) with the same prompt: "add a rebook feature." The only difference was naming. **App A** called its central entity **Order** with clean states (pending, confirmed, in_progress, completed, canceled, rejected). **App B** called it **Request** with legacy invitation-era states (created, created_accepted, accepted, started, fulfilled, declined, missed, canceled, rejected). Both apps do the same thing — manage babysitter bookings. The Request app simply never had its naming refactored after evolving from an invitation system.

### The Key Finding: Naming Shaped Domain Reasoning, Not Code Volume

The naming difference didn't change *how much* code the AI wrote (~67 vs ~66 lines). It changed *how the AI thought about the problem*.

**Order runs treated rebooking as a domain concept.** 4/6 runs added a `rebookable?` predicate with state-based eligibility rules. 3/6 added model-level methods or scopes. The AI reasoned: "an order has a lifecycle — which terminal states allow rebooking?"

**Request runs treated rebooking as a copy operation.** 0/6 runs added any state eligibility check. 0/6 added model-level methods. The AI just copied fields and created a new record, skipping the question of *when* rebooking is appropriate entirely.

The clean terminal states of Order (completed, canceled, rejected) *invited* lifecycle reasoning. The nine legacy states of Request apparently *discouraged* it — the AI didn't attempt to sort out which states should be rebookable.

### Secondary Findings

- **Service reuse diverged.** Order runs delegated to the existing CreateService 67% of the time vs 33% for Request. "Creating an order from a rebook" felt natural; "creating a request from a rebook" apparently did not.
- **Testing quality dropped.** Order runs averaged ~12 new tests; Request runs averaged ~5. Two Request-Sonnet runs shipped zero test files. No Order run went untested.
- **Pricing assumptions differed.** 4/6 Request runs allowed overriding `amount_cents`, while only 1/6 Order runs did — suggesting "request" primed the AI to expect negotiation, while "order" implied fixed pricing.

### Confidence

**Strong** for the state-gating pattern (4/6 vs 0/6 is hard to attribute to chance). **Moderate** for service reuse and pricing assumptions (consistent direction but small sample with model-level confounding). **Weak** for framing/language differences (both apps used "rebook" naturally).

### The Surprising Takeaway

The AI didn't struggle more with the Request app. It didn't produce worse code structurally or write fewer lines. What it did was *think less deeply*. Legacy naming didn't cause errors — it suppressed reasoning. The Request app's complex state machine, a legacy artifact nobody cleaned up, silently told the AI "don't try to model this domain" — and the AI listened.


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
