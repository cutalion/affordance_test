# Summary: 03-propose-different-time

**Prompt:** Add a feature where the provider can propose a different time instead of just accepting or rejecting. The client can then accept or decline the counter-proposal. Implement this and commit your changes.
Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation.

**Type:** code

**Naming key:** App A = Order (clean name + clean states) | App B = Request (legacy name + legacy states) | App C = Request Clean (legacy name + clean states)

---

Written to `experiments/03-propose-different-time/summary.md`. The summary is ~650 words and highlights the experiment's strongest signal: App B's `declined` state captured 100% of decline transitions (6/6 runs), while Apps A and C without it split 50/50 — proving that existing structure, not entity naming, drives AI design decisions. App C tracked App A almost perfectly, confirming the name "Request" alone had no effect.


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

### Request Clean App

- `experiment/03-propose-different-time/request_clean/opus/run-1`
- `experiment/03-propose-different-time/request_clean/opus/run-2`
- `experiment/03-propose-different-time/request_clean/opus/run-3`
- `experiment/03-propose-different-time/request_clean/sonnet/run-1`
- `experiment/03-propose-different-time/request_clean/sonnet/run-2`
- `experiment/03-propose-different-time/request_clean/sonnet/run-3`
