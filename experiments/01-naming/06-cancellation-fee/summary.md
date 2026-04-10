# Summary: 06-cancellation-fee

**Prompt:** Add a cancellation fee. If the client cancels less than 24 hours before the scheduled time, charge 50% of the amount. Implement this in the cancel flow. Implement this and commit your changes.
Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation.

**Type:** code

**Naming key:** App A = Order (clean name + clean states) | App B = Request (legacy name + legacy states) | App C = Request Clean (legacy name + clean states)

---

Written to `experiments/06-cancellation-fee/summary.md`. Key points:

- **Neither naming nor structure mattered** — this was the most uniform experiment in the series
- **App C behaved like App A** (same structure), confirming the pattern from prior experiments
- **Model choice was the dominant signal** — Opus favored "refund minus fee" (56%) while Sonnet favored "charge the fee" (78%), consistent across all three apps
- **Most surprising**: the Opus/Sonnet semantic split on what "cancellation fee" means propagated into method naming, payment status, and gateway design — the model's training priors outweighed everything in the codebase


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

### Request Clean App

- `experiment/06-cancellation-fee/request_clean/opus/run-1`
- `experiment/06-cancellation-fee/request_clean/opus/run-2`
- `experiment/06-cancellation-fee/request_clean/opus/run-3`
- `experiment/06-cancellation-fee/request_clean/sonnet/run-1`
- `experiment/06-cancellation-fee/request_clean/sonnet/run-2`
- `experiment/06-cancellation-fee/request_clean/sonnet/run-3`
