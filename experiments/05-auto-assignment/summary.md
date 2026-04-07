# Summary: 05-auto-assignment

**Prompt:** Add automatic provider assignment. When a client creates a booking without specifying a provider, the system should automatically assign the highest-rated available provider. Implement this and commit your changes.
Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation.

**Type:** code

**Naming key:** App A = Order (clean states) | App B = Request (legacy invitation-era states)

---

## Experiment 05: Auto-Assignment — Summary

**Setup:** Both apps received an identical prompt: implement auto-assignment of a provider when creating an order/request. The only difference was entity naming — "Order" (clean transactional states) vs "Request" (legacy invitation-era states). An analyzer compared the outputs blind, without knowing which app used which name.

### The Naming Effect

The blind analysis found that **"Request" naming nudged AI agents toward richer architectural thinking**, even though the underlying codebase was structurally identical.

**Service extraction:** Request app runs created a dedicated `Providers::AutoAssignService` in 3/6 runs vs 1/6 for Order. The "Request" framing — with its connotation of something that needs to be *fulfilled* — apparently encouraged agents to treat auto-assignment as a distinct responsibility worth isolating, rather than inline logic in a controller or existing service.

**Availability semantics:** 4/6 Request runs implemented schedule-conflict checking vs 3/6 for Order. The extra run was a Sonnet instance (sonnet-2) that would not have done so in the Order app. The "Request" name seems to activate a mental model where fulfillment depends on real availability, not just picking the top-rated provider.

**Error handling:** 5/6 Request runs chose HTTP 422 for "no provider available" vs 3/6 for Order (where 2 runs chose 404). A request that can't be fulfilled is naturally "unprocessable"; an order with no provider feels more like a "missing resource." The naming shaped the semantic interpretation of the same failure mode.

**Domain vocabulary:** The word "booking" appeared spontaneously in 4/6 Request runs and 0/6 Order runs. The "Request" name activated associations with scheduling and service fulfillment that "Order" — more transactional and self-contained — did not.

### The Dominant Variable

Model choice (Opus vs Sonnet) mattered far more than naming. Opus implemented schedule-conflict checking in 6/6 runs regardless of app, wrote ~2x more test code, and consistently used SQL subqueries for availability. Sonnet typically took the simpler "highest-rated active provider" shortcut. The naming effect operated *within* model capability — it was a nudge, not a transformation.

### Most Interesting Finding

The 422-vs-404 split is the sharpest signal. It reveals that naming doesn't just affect architecture — it affects how agents *interpret the semantics of identical failure states*. "No available provider" is the same situation in both apps, but "Request" framed it as an unfulfillable ask (422) while "Order" sometimes framed it as a missing thing (404). This is a subtle but meaningful difference that would affect API consumers.

### Confidence

**Low-to-moderate.** The service-extraction and error-code patterns are consistent but the sample is small (6 runs per app). The conflict-checking difference is a single run. The "booking" vocabulary pattern is strong (4/6 vs 0/6) and the most robust signal. All naming effects are secondary to the Opus/Sonnet capability gap.


## Branches

### Order App

- `experiment/05-auto-assignment/order/opus/run-1`
- `experiment/05-auto-assignment/order/opus/run-2`
- `experiment/05-auto-assignment/order/opus/run-3`
- `experiment/05-auto-assignment/order/sonnet/run-1`
- `experiment/05-auto-assignment/order/sonnet/run-2`
- `experiment/05-auto-assignment/order/sonnet/run-3`

### Request App

- `experiment/05-auto-assignment/request/opus/run-1`
- `experiment/05-auto-assignment/request/opus/run-2`
- `experiment/05-auto-assignment/request/opus/run-3`
- `experiment/05-auto-assignment/request/sonnet/run-1`
- `experiment/05-auto-assignment/request/sonnet/run-2`
- `experiment/05-auto-assignment/request/sonnet/run-3`
