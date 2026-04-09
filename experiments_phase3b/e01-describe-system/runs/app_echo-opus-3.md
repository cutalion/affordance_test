# Experiment: e01-describe-system
# App: app_echo | Model: opus | Run: 3

---

This is a **service marketplace platform** — a two-sided marketplace connecting **Clients** (who need services) with **Providers** (who deliver them). The domain resembles childcare/babysitting (derived from a "Kidsout"-like concept) but is generalized.

## Main Entities

- **Client** — a person who needs a service. Has payment cards, can post announcements, and create requests. Authenticated via API token.
- **Provider** — a service professional with a specialization, rating, and active/inactive status. Accepts and fulfills requests.
- **Request** — the core entity. Represents a booking of a provider by a client for a specific time, duration, location, and price. Has a rich state machine: `pending → accepted → in_progress → completed`, with alternative paths for `declined`, `expired`, `canceled`, and `rejected`.
- **Announcement** — a "job posting" by a client. Goes through `draft → published → closed`. Providers can respond, which creates Requests linked to the announcement.
- **Payment** — tied 1:1 to a request. Tracks money flow with statuses (`pending`, held, charged, refunded) and a platform fee.
- **Card** — a client's saved payment method (tokenized). One can be marked as default.
- **Review** — polymorphic (either client or provider can author). Left after a request is completed, with a rating and body.

## Typical Workflow

1. **Client posts an Announcement** (draft → publish) describing what they need, when, where, and budget
2. **Providers respond** to the announcement, creating a **Request** (possibly with a counter-offer via `proposed_amount_cents`)
3. Alternatively, a **Client creates a Request directly** to a specific provider
4. **Provider accepts** (or declines) the pending request
5. At the scheduled time, the provider **starts** the session (accepted → in_progress)
6. When done, the provider **completes** it (in_progress → completed)
7. A **Payment** is processed against the client's card
8. Both parties can leave **Reviews**

The app exposes two interfaces: a JSON **API** (for client/provider mobile apps) and a read-only **Admin** dashboard.
