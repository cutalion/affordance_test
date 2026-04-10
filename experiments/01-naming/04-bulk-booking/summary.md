# Summary: 04-bulk-booking

**Prompt:** Add a feature where a client can book 5 sessions at once with the same provider (e.g., weekly recurring). All sessions should be created in a single API call. Implement this and commit your changes.
Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation.

**Type:** code

**Naming key:** App A = Order (clean name + clean states) | App B = Request (legacy name + legacy states) | App C = Request Clean (legacy name + clean states)

---

Done. The summary is at `experiments/04-bulk-booking/summary.md`. Key points:

- **Naming had no effect** — all 18 runs produced structurally identical solutions
- **App C behaved like App A**, confirming structure matters more than naming
- **Legacy complexity didn't leak** into the new feature (contrast with Experiment 01 where it triggered editorial commentary)
- **Model choice (Opus vs Sonnet) was the strongest predictor** of implementation scope
- **Most surprising finding**: when building new features (vs. describing existing code), structural complexity becomes background noise — the AI navigates it correctly without being distracted


## Branches

### Order App

- `experiment/04-bulk-booking/order/opus/run-1`
- `experiment/04-bulk-booking/order/opus/run-2`
- `experiment/04-bulk-booking/order/opus/run-3`
- `experiment/04-bulk-booking/order/sonnet/run-1`
- `experiment/04-bulk-booking/order/sonnet/run-2`
- `experiment/04-bulk-booking/order/sonnet/run-3`

### Request App

- `experiment/04-bulk-booking/request/opus/run-1`
- `experiment/04-bulk-booking/request/opus/run-2`
- `experiment/04-bulk-booking/request/opus/run-3`
- `experiment/04-bulk-booking/request/sonnet/run-1`
- `experiment/04-bulk-booking/request/sonnet/run-2`
- `experiment/04-bulk-booking/request/sonnet/run-3`

### Request Clean App

- `experiment/04-bulk-booking/request_clean/opus/run-1`
- `experiment/04-bulk-booking/request_clean/opus/run-2`
- `experiment/04-bulk-booking/request_clean/opus/run-3`
- `experiment/04-bulk-booking/request_clean/sonnet/run-1`
- `experiment/04-bulk-booking/request_clean/sonnet/run-2`
- `experiment/04-bulk-booking/request_clean/sonnet/run-3`
