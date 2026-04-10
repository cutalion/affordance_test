# Experiment: e01-describe-system
# App: app_bravo | Model: opus | Run: 1

---

This is a **service marketplace / booking platform** built as a Rails API app. Here's the breakdown:

## Domain

A two-sided marketplace connecting **Clients** (who need services) with **Providers** (who deliver services). Currency defaults to RUB, suggesting a Russian market. The domain is generic — it could be home services, tutoring, consulting, etc. Providers have a `specialization` field and a `rating`.

## Main Entities

- **Client** — registers, stores payment cards, books services
- **Provider** — registers, has a specialization, rating, and active/inactive status
- **Card** — client's payment card (tokenized, with a "default" flag)
- **Request** — a client asks a specific provider for availability. States: `pending → accepted / declined / expired`
- **Order** — the actual booked appointment. States: `pending → confirmed → in_progress → completed`, or `canceled` / `rejected`. Tracks scheduling, duration, amount, and location
- **Payment** — one per order, with a 10% platform fee. States: `pending → held → charged → refunded`
- **Review** — polymorphic author (client or provider), tied to a completed order. One review per author per order

## Typical Workflow

1. **Client creates a Request** to a chosen Provider (date, duration, location, notes)
2. **Provider accepts or declines** the request
3. On acceptance, an **Order is created** (either from the request or directly) with a **Payment** record (pending, with a 10% fee)
4. Provider **confirms** the order, then **starts** it (marks in-progress), then **completes** it
5. Payment moves through `held → charged` as the order progresses
6. Either party can leave a **Review** after completion
7. Orders can be **canceled** (by client, before start) or **rejected** (by provider, after confirmation)

There's also a read-only **Admin** panel for viewing all entities and a dashboard.
