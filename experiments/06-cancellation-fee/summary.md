# Summary: 06-cancellation-fee

**Prompt:** Add a cancellation fee. If the client cancels less than 24 hours before the scheduled time, charge 50% of the amount. Implement this in the cancel flow. Implement this and commit your changes.
Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation.

**Type:** code

**Naming key:** App A = Order (clean states) | App B = Request (legacy invitation-era states)

---

## Summary: Experiment 06 — Cancellation Fee

**App A is the Order app; App B is the Request app.** Both received the same prompt: add a cancellation fee (50% charge) when a booking is canceled within 24 hours of the scheduled time.

### Did naming affect AI reasoning?

Yes — not in understanding the feature, but in where the AI placed the logic.

The core business rule was implemented identically across all 12 runs: check if cancellation is within 24 hours of `scheduled_at`, calculate 50% of `amount_cents`, apply the fee. Naming had zero effect on comprehension.

The difference showed up in **architectural layering**. Request app runs added a dedicated `charge_cancellation_fee` method to the PaymentGateway in 5 out of 6 runs. Order app runs kept the fee logic inside the cancel service itself, with only 2 out of 6 adding any new gateway method. The Request app's more complex service landscape (it already has extra services like `CreateAcceptedService` and `DeclineService`) appears to have primed the AI to treat payment operations as first-class concerns deserving their own named abstractions. The Order app's cleaner, more transactional structure encouraged the AI to handle everything inline.

This pattern is consistent with earlier experiments: the Request app's legacy complexity acts as a signal that "this codebase uses lots of named services and methods," causing the AI to produce more of them — even when the feature doesn't require it.

### The most surprising finding

Two Request/Sonnet runs (and zero Order runs) chose to **destructively mutate** `payment.amount_cents` — overwriting the original amount with the 50% fee value, permanently losing the original data. This is a meaningful data integrity risk. While the sample is small (2/12), the fact that it appeared exclusively in the Request context suggests that the legacy naming's looser conceptual framing may slightly reduce the AI's instinct to preserve data. An "order amount" feels like a fixed contract; a "request amount" may feel more mutable.

### Confidence level

**Moderate** on the gateway method pattern (5/6 vs 2/6 is a clear split). **Low** on the destructive mutation finding (2/12 is too small to generalize, but the directionality is notable). **High** confidence that naming did not affect understanding of the core business rule.

### Key takeaway

For a well-specified, concrete feature like "add a cancellation fee," naming doesn't change *what* the AI builds — but it changes *how it structures* the solution. The Request app's legacy complexity consistently pulled the AI toward more abstraction layers, while the Order app's clean naming produced more contained implementations. The cancellation fee experiment reinforces the pattern seen across the full experiment suite: naming is an architectural affordance, not a comprehension barrier.


## Branches

### Order App

- `experiment/06-cancellation-fee/order/opus/run-1`
- `experiment/06-cancellation-fee/order/opus/run-2`
- `experiment/06-cancellation-fee/order/opus/run-3`
- `experiment/06-cancellation-fee/order/sonnet/run-1`
- `experiment/06-cancellation-fee/order/sonnet/run-2`
- `experiment/06-cancellation-fee/order/sonnet/run-3`

### Request App

- `experiment/06-cancellation-fee/request/opus/run-1`
- `experiment/06-cancellation-fee/request/opus/run-2`
- `experiment/06-cancellation-fee/request/opus/run-3`
- `experiment/06-cancellation-fee/request/sonnet/run-1`
- `experiment/06-cancellation-fee/request/sonnet/run-2`
- `experiment/06-cancellation-fee/request/sonnet/run-3`
