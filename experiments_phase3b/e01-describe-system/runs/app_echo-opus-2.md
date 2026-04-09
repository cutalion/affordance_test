# Experiment: e01-describe-system
# App: app_echo | Model: opus | Run: 2

---

This is a **service marketplace platform** — a two-sided marketplace connecting **Clients** (who need services) with **Providers** (who deliver them). The domain appears derived from a childcare/babysitting marketplace (Kidsout).

## Main Entities

- **Client** — a person who needs a service. Has payment cards, can create announcements and requests.
- **Provider** — a service professional with a specialization, rating, and active/inactive status.
- **Announcement** — a public listing a client posts to attract providers (draft → published → closed). Includes title, description, budget, location, and scheduled time.
- **Request** — the core transactional entity. Represents a specific service engagement between one client and one provider, with a scheduled time, duration, amount, and location. Has a rich state machine (pending → accepted → in_progress → completed, with decline/expire/cancel/reject paths). Can optionally originate from an announcement. Supports recurring bookings via `recurring_group_id`.
- **Payment** — tied 1:1 to a request. Follows a hold → charge → refund lifecycle. Linked to a client's card.
- **Card** — stored payment card for a client (tokenized, with one marked as default).
- **Review** — polymorphic by author (client or provider), tied to a completed request. Both sides can rate and comment.

## Typical Workflow

1. A **Client** creates an **Announcement** describing what they need (or skips straight to a direct request).
2. The client sends a **Request** to a specific **Provider**, specifying schedule, duration, and price.
3. The provider **accepts** or **declines**. If no response, the request **expires**.
4. Once accepted, the service **starts** (in_progress) and then **completes**.
5. A **Payment** is held when accepted, charged on completion (or refunded if canceled/rejected).
6. Both parties can leave **Reviews** after completion.

The app exposes both an **API** (token-authenticated, for client/provider mobile apps) and an **Admin** panel (for back-office management).
