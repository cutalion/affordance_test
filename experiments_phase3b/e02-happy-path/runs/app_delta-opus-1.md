# Experiment: e02-happy-path
# App: app_delta | Model: opus | Run: 1

---

The main entity is the **Order**. Here's the happy path, step by step:

## Happy Path for an Order

There are two ways an Order can originate, then they converge:

### Path A: Direct Request

1. **Client creates a Request** — specifies a provider, scheduled time, and duration. Starts in `pending` state.
2. **Provider accepts the Request** — transitions to `accepted`, records `accepted_at`.
3. **Order is created** from the accepted Request — linked via `request_id`, with amount/currency set. Starts in `pending` state.

### Path B: Announcement (marketplace-style)

1. **Client creates an Announcement** — starts as `draft`.
2. **Client publishes the Announcement** — transitions to `published`.
3. **Providers submit Responses** — each in `pending` state (one per provider per announcement).
4. **Client selects a Response** — transitions to `selected`; others get `rejected`.
5. **Announcement is closed**.
6. **Order is created** from the selected response. Starts in `pending`.

### Converged Order Lifecycle

7. **Order is confirmed** — `pending` → `confirmed` (e.g., provider confirms availability).
8. **Payment is created** with status `pending`, then **held** — `held_at` recorded. This is a pre-authorization against the client's card.
9. **Order starts** — `confirmed` → `in_progress`, records `started_at`.
10. **Order completes** — `in_progress` → `completed`, records `completed_at`.
11. **Payment is charged** — status moves to `charged`, records `charged_at`.
12. **Reviews are left** — both client and provider can leave a review (rating 1-5) on the completed order. Each party can review only once.

That's the full happy path: need expressed → provider matched → order confirmed → payment held → service delivered → payment charged → mutual reviews.
