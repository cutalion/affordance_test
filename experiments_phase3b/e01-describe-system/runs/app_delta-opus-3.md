# Experiment: e01-describe-system
# App: app_delta | Model: opus | Run: 3

---

This is a **service marketplace platform** — a two-sided marketplace connecting **Clients** (who need services) with **Providers** (who deliver them). The domain is inspired by Kidsout (likely a babysitting/childcare service) but generalized.

## Main Entities

- **Client** — a person who needs a service. Has payment cards, notification preferences.
- **Provider** — a service professional with a specialization, rating, and active/inactive status.
- **Card** — a client's saved payment method (tokenized).

## Core Workflows

There are **three ways** a client can engage a provider:

### 1. Direct Request (Client → specific Provider)
A **Client** sends a **Request** to a specific **Provider** for a given time/location/duration. The provider can **accept**, **decline**, or let it **expire**. An accepted request can lead to an **Order**.

### 2. Announcement (Client → open market)
A **Client** posts an **Announcement** (draft → published → closed) describing what they need, with an optional budget. Multiple **Providers** submit **Responses** (with optional counter-pricing). The client **selects** one response and **rejects** the rest. The selected response leads to an Order.

### 3. Direct Order / Recurring Booking
A **Client** can create an **Order** directly with a known provider. Orders can also be created via **RecurringBooking** (a series of sessions with the same provider).

## Order Lifecycle
`pending → confirmed → in_progress → completed` (or `canceled`/`rejected` at various stages)

## Payment Lifecycle
Tied 1:1 to an Order: `pending → held → charged → refunded`

## Reviews
Both clients and providers can leave **Reviews** (polymorphic author) with a rating and body text after an order completes.

## API
The app is an **API-only Rails app** with token-based auth, exposing RESTful endpoints for all entities under `Api::`.
