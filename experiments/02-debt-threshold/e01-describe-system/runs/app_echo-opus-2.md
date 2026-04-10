# Experiment: e01-describe-system
# App: app_echo | Model: opus | Run: 2

---

This is a **service marketplace platform** — a Rails API application that connects **clients** who need services with **providers** who deliver them. The domain resembles platforms like TaskRabbit or YouDo (given the RUB currency default, likely a Russian market).

## Main Entities

- **Client** — a person who needs a service. Has an API token, email, phone, and notification preferences. Can save payment cards.
- **Provider** — a person who offers services. Has a specialization, rating, and active/inactive status.
- **Announcement** — a client's public post describing a needed service (title, description, budget, location, schedule). Follows a `draft → published → closed` lifecycle.
- **Request** — the core transactional entity. Represents a specific service engagement between a client and a provider, with a scheduled time, duration, amount, and location. Can optionally be linked to an announcement. Has a rich state machine: `pending → accepted → in_progress → completed`, with alternative paths for `declined`, `expired`, `canceled`, and `rejected`.
- **Payment** — tied 1:1 to a request. Tracks money flow through `pending → held → charged → refunded` statuses.
- **Card** — a client's saved payment method (tokenized, stores last four digits). One card can be marked as default.
- **Review** — polymorphic by author (either client or provider), tied to a completed request. Has a rating and body text. Each author can review a request only once.

## Typical Workflow

1. A **client registers** and optionally adds a **payment card**.
2. The client creates an **announcement** (draft) describing the service needed, then **publishes** it.
3. A **provider** views published announcements and **responds** to one, which creates a **request** (pending).
4. The client **accepts** or **declines** the request. Either party can **cancel**.
5. Once accepted, the provider **starts** the work (in_progress), then marks it **complete**.
6. A **payment** is created for the request — funds are held, then charged upon completion (or refunded if canceled/rejected).
7. After completion, both client and provider can leave **reviews** with ratings.

The app also has a read-only **admin dashboard** for viewing all entities.
