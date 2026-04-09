# Experiment: e03-counter-proposal
# App: app_bravo | Model: opus | Run: 2
# Branch: debt_experiment/e03-counter-proposal/app_bravo/opus/run-2

---

## Claude Output

Good, I now have a clear picture of the codebase. Here's the flow: Client creates a **Request** (pending) → Provider can **accept** (creates an Order) or **decline**. The counter-proposal feature fits naturally as a third provider action on a pending Request.

## Design: Counter-Proposal Feature

**Concept:** When a provider receives a booking request, instead of just accepting or declining, they can propose a different time. The client can then accept or decline that counter-proposal.

**Approach — add a `counter_proposed` state to Request:**

1. **New Request state: `counter_proposed`** — provider transitions a pending request here, storing `proposed_scheduled_at` and an optional `proposal_reason`
2. **Client actions on counter-proposed requests:**
   - **Accept proposal** → transitions back to `accepted`, updates `scheduled_at` to the proposed time, creates the Order
   - **Decline proposal** → transitions to `declined`
3. **New DB columns on `requests`:** `proposed_scheduled_at` (datetime), `proposal_reason` (text)
4. **New service classes:** `Requests::CounterProposeService`, `Requests::AcceptProposalService`, `Requests::DeclineProposalService`
5. **New API endpoints:**
   - `PATCH /api/requests/:id/counter_propose` (provider)
   - `PATCH /api/requests/:id/accept_proposal` (client)
   - `PATCH /api/requests/:id/decline_proposal` (client)
6. **Notifications** to client when counter-proposed; to provider when client responds

**State machine additions:**
- `pending` → `counter_proposed` (via `counter_propose` event)
- `counter_proposed` → `accepted` (via `accept_proposal` event)
- `counter_proposed` → `declined` (via `decline_proposal` event)

This follows existing patterns (service objects, AASM transitions, notification logging, controller structure). Does this design look good? Should I proceed with writing the spec doc and implementation plan?

---

## Git Diff

```diff

```
