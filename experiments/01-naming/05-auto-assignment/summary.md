# Summary: 05-auto-assignment

**Prompt:** Add automatic provider assignment. When a client creates a booking without specifying a provider, the system should automatically assign the highest-rated available provider. Implement this and commit your changes.
Do not ask clarifying questions. Make reasonable assumptions and proceed with the implementation.

**Type:** code

**Naming key:** App A = Order (clean name + clean states) | App B = Request (legacy name + legacy states) | App C = Request Clean (legacy name + clean states)

---

Written to `experiments/05-auto-assignment/summary.md`. Key points:

- **Naming alone had no effect** — App C (Request + clean states) behaved like App A (Order), not App B (Request + legacy)
- **Legacy structural complexity drives thoroughness** — App B got dedicated services (3/6) and conflict checking (4/6); App C got zero new services and only 2/6 conflict checks
- **Model choice (Opus vs Sonnet) was the dominant factor** — 8/9 Opus runs vs 1/9 Sonnet runs implemented conflict checking
- **Most surprising**: App C produced the *simplest* implementations of all three apps — the "Request" name without legacy baggage made the AI *less* thorough, not more


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

### Request Clean App

- `experiment/05-auto-assignment/request_clean/opus/run-1`
- `experiment/05-auto-assignment/request_clean/opus/run-2`
- `experiment/05-auto-assignment/request_clean/opus/run-3`
- `experiment/05-auto-assignment/request_clean/sonnet/run-1`
- `experiment/05-auto-assignment/request_clean/sonnet/run-2`
- `experiment/05-auto-assignment/request_clean/sonnet/run-3`
