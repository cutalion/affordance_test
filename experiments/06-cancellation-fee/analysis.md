# Analysis: 06-cancellation-fee

> Blind comparison — App A and App B naming not revealed to analyzer.

# Analysis: Cancellation Fee Experiment

## 1. Language/Framing

**App A (Order)**: Descriptions are straightforward and transactional. "Cancel service," "late cancellation," "cancellation fee." The language treats this as a simple business rule addition to a clean workflow.

**App B (Request)**: Nearly identical framing. Same terminology: "late cancellation," "cancellation fee," "50% fee." No meaningful difference in how the domain is described.

**Confidence**: No difference. The prompt was concrete enough that naming didn't influence how the feature was described.

## 2. Architectural Choices

### Fee storage strategy

| Approach | App A (Order) | App B (Request) |
|----------|--------------|-----------------|
| Use existing `payment.fee_cents` column | order-opus-1, order-sonnet-1, order-sonnet-3 | request-opus-2, request-opus-3 |
| Add `cancellation_fee_cents` to orders | order-opus-2 | — |
| Add `cancellation_fee_cents` to payments | order-sonnet-2 | request-sonnet-1 |
| Mutate `payment.amount_cents` to 50% | — | request-sonnet-2, request-sonnet-3 |
| Use existing `payment.fee_cents` + return in hash | order-opus-3 | request-opus-1 |

**Notable**: Two Request/Sonnet runs (sonnet-2, sonnet-3) chose to **mutate the payment amount** itself rather than recording the fee separately. This is a destructive approach — the original amount is lost. Zero Order runs did this.

### Payment handling after fee

| Approach | App A (Order) | App B (Request) |
|----------|--------------|-----------------|
| Refund (with fee recorded) | opus-1, sonnet-2, sonnet-3 | opus-1, opus-2 |
| Charge (keep fee portion) | opus-2, opus-3, sonnet-1 | opus-3, sonnet-1, sonnet-2, sonnet-3 |

App B leans slightly more toward "charge" (4/6) vs App A (3/6). Weak signal.

### New PaymentGateway methods

| Method name | App A (Order) | App B (Request) |
|-------------|--------------|-----------------|
| `charge_fee` | opus-3 | — |
| `partial_refund` | sonnet-2 | — |
| `refund_with_fee` | — | opus-1 |
| `charge_cancellation_fee` | — | opus-3, sonnet-1, sonnet-2, sonnet-3 |
| No new gateway method | opus-1, opus-2, sonnet-1, sonnet-3 | opus-2 |

**Strong pattern**: App B (Request) introduced `charge_cancellation_fee` as a named PaymentGateway method in 4/6 runs. App A used generic names or no new method at all. The Request naming appears to have encouraged more domain-specific method naming in the payment layer.

**Confidence**: Moderate signal on gateway method naming. The `charge_cancellation_fee` name appeared 4× in Request but 0× in Order.

## 3. Complexity

### Lines of diff (approximate, excluding schema.rb noise)

| Run | App A (Order) | App B (Request) |
|-----|--------------|-----------------|
| opus-1 | ~45 | ~95 |
| opus-2 | ~55 + migration | ~40 |
| opus-3 | ~75 | ~60 |
| sonnet-1 | ~45 | ~75 + migration |
| sonnet-2 | ~65 + migration | ~55 |
| sonnet-3 | ~55 | ~60 |

**Averages**: Roughly comparable. No consistent size difference.

### New files created

| | App A (Order) | App B (Request) |
|--|--------------|-----------------|
| Migrations | opus-2, sonnet-2 (2/6) | sonnet-1 (1/6) |
| New gateway methods | opus-3, sonnet-2 (2/6) | opus-1, opus-3, sonnet-1, sonnet-2, sonnet-3 (5/6) |

**Strong pattern**: App B added new PaymentGateway methods far more often (5/6 vs 2/6).

### Files touched

| Run | App A (Order) files | App B (Request) files |
|-----|--------------------|-----------------------|
| opus-1 | 2 (service + spec) | 3 (service + spec + gateway spec) |
| opus-2 | 3 (service + spec + migration) | 2 (service + spec) |
| opus-3 | 3 (service + spec + gateway) | 3 (service + spec + gateway) |
| sonnet-1 | 2 (service + spec) | 5 (service + spec + gateway + model + migration) |
| sonnet-2 | 4 (service + spec + gateway + migration) | 3 (service + spec + gateway) |
| sonnet-3 | 3 (service + spec + gateway) | 2 (service + spec + gateway) |

**App A average**: 2.8 files. **App B average**: 3.0 files. No meaningful difference.

## 4. Scope

**App A (Order)**: All 6 runs stayed tightly scoped. No unrequested features.

**App B (Request)**: All 6 runs stayed tightly scoped. 

**Notable outlier**: order-opus-2's schema.rb diff includes unrelated changes (bulk_id, proposed_scheduled_at, provider nullable) — artifacts from a dirty branch state, not scope creep by the AI.

**One scope addition**: request-opus-1 added `fee_cents` to the API response JSON. No Order run touched the controller. This is a reasonable inclusion (expose the fee to the client) but technically unrequested.

**Confidence**: Weak signal (1 instance in Request, 0 in Order).

## 5. Assumptions

All runs made the same core assumptions:
- "Client" is the one who cancels (not provider)
- 50% is calculated from `amount_cents` 
- The existing cancel flow is the right place
- `scheduled_at` is the time to compare against

**Divergence on "charge 50%"**:
- **Charge the fee and refund the rest**: Most runs in both apps
- **Mutate the amount**: request-sonnet-2, request-sonnet-3 interpreted "charge 50%" as "reduce the payment to 50% and charge that" — losing the original amount

**Confidence**: Weak signal. The destructive-mutation pattern only appeared in Request/Sonnet.

## 6. Model Comparison (Opus vs Sonnet)

### Within App A (Order)

**Opus** was more likely to:
- Extract constants (opus-3: `LATE_CANCEL_WINDOW`, `LATE_CANCEL_FEE_PERCENT`)
- Add a `cancellation_fee_cents` return value to the result hash (opus-1, opus-3)
- Test boundary conditions (opus-3 tested the 25-hour boundary)

**Sonnet** was more likely to:
- Keep changes minimal and in-place
- Avoid extracting new abstractions

### Within App B (Request)

**Opus** was more likely to:
- Add fewer test cases but more targeted ones
- Use existing columns when possible (opus-2 used `fee_cents` directly)

**Sonnet** was more likely to:
- Create new PaymentGateway methods with domain-specific names
- Mutate `amount_cents` rather than recording fees separately (sonnet-2, sonnet-3)
- Add factory traits (sonnet-2 added `:scheduled_soon`)

**Confidence**: Moderate signal. Opus tends toward more structured, extractive code; Sonnet tends toward simpler inline changes but occasionally makes more destructive data choices.

## Raw Tallies

| Metric | App A (Order) | App B (Request) |
|--------|--------------|-----------------|
| New gateway methods added | 2/6 | 5/6 |
| `charge_cancellation_fee` specifically | 0/6 | 4/6 |
| Migrations created | 2/6 | 1/6 |
| Used existing `fee_cents` column | 4/6 | 3/6 |
| Mutated `amount_cents` destructively | 0/6 | 2/6 |
| Added fee to API response | 0/6 | 1/6 |
| Returned fee in service result hash | 3/6 | 0/6 |
| Test cases added (avg) | 3.2 | 2.3 |
| Private helper name: `late_cancellation?` | 5/6 | 4/6 |
| Private helper name: `cancellation_fee_applies?` | 0/6 | 1/6 |

## Notable Outliers

- **order-opus-3**: Most thorough of all runs — extracted constants, added `charge_fee` gateway method, tested boundary at 25 hours, tested no-payment case
- **request-sonnet-2 & request-sonnet-3**: Only runs to destructively mutate `amount_cents`, losing the original payment amount
- **request-opus-1**: Only run to touch the API controller and add gateway tests

## Bottom Line

The most consistent difference is in the **payment gateway layer**: Request (App B) runs added dedicated `charge_cancellation_fee` methods to PaymentGateway in 5/6 runs, while Order (App A) runs mostly kept changes confined to the cancel service itself (only 2/6 added gateway methods). This suggests the "Request" naming — with its more complex state machine and additional services — primed the AI to treat payment operations as first-class gateway concerns requiring their own named methods, while "Order" — with its cleaner, more transactional framing — encouraged inline logic within the existing cancel service. Additionally, the two destructive `amount_cents` mutations appeared only in Request/Sonnet runs, hinting that the Request context may slightly increase the risk of the AI making lossy data changes, though the sample is too small for high confidence. The core cancellation logic (24-hour check, 50% fee) was identical across all 12 runs — naming did not affect the fundamental understanding of the feature.
