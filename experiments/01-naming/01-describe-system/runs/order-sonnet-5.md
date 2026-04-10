# Experiment: 01-describe-system
# App: order | Model: sonnet | Run: 5

---

Now I have a thorough understanding of the system. Here's a complete description:

---

## System Overview

This is a **service-booking marketplace platform** built in Ruby on Rails. It connects **clients** (customers) with **providers** (service professionals) for scheduling and managing appointments or service sessions.

---

## Domain

The domain is a **two-sided marketplace for on-demand or scheduled services** — think something like a platform for booking freelance professionals, home services, tutors, or similar service providers. The currency defaults to RUB (Russian Rubles), suggesting a Russian market context.

---

## Main Entities

| Entity | Description |
|---|---|
| **Client** | A customer who books services. Has an email, name, API token for authentication, saved payment cards, and configurable notification preferences (push, SMS, email). |
| **Provider** | A service professional. Has a specialization, a 0–5 star rating, an active/inactive flag, and similar notification preferences. Providers can be activated or deactivated. |
| **Order** | The core entity — a booking linking a client and a provider. Records the scheduled time, duration, location, notes, price, and moves through a state machine lifecycle. |
| **Payment** | A financial record attached to each order. Tracks the amount, currency, a 10% platform fee, which card was charged, and transitions through `pending → held → charged` (or `refunded`). |
| **Card** | A saved payment method belonging to a client (brand, last four digits, expiry, token). One card can be marked as the default. |
| **Review** | A post-completion rating (1–5 stars, optional text body) that either the client or provider can leave for a completed order. Both sides can review — it's polymorphic. |

---

## Typical Workflow

### 1. Booking Creation
A **client** creates an order by specifying a provider, scheduled time, duration, location, amount, and optional notes. On creation, a **Payment** record is immediately created in `pending` status with a 10% fee calculated. The **provider is notified** of the new booking.

### 2. Payment Hold
A background job (`PaymentHoldJob`) runs periodically and pre-authorizes ("holds") payments for orders scheduled within the next 24 hours, charging the client's default card. This is a card hold, not yet a capture.

### 3. Provider Confirms
The assigned **provider** confirms the order (`pending → confirmed`). The **client is notified** of the confirmation.

### 4. Service Begins
The provider marks the order as started (`confirmed → in_progress`), recording `started_at`.

### 5. Service Completes
The provider marks the order as completed (`in_progress → completed`), recording `completed_at`. At this point, if the payment is in `held` status, it is **captured/charged** automatically. Both the client and provider are notified.

### 6. Review Period
A background job (`ReviewReminderJob`) runs after 24–48 hours post-completion and sends reminders to both the client and provider to leave a review, if they haven't done so. Reviews can only be submitted for completed orders, and each party can review once per order.

### 7. Cancellation / Rejection
- A **client** can cancel a `pending` or `confirmed` order with a mandatory reason. Any held/charged payment is automatically **refunded**. The provider is notified.
- A **provider** can reject a `confirmed` or `in_progress` order with a mandatory reason (e.g., emergency cancellation).

---

## Supporting Infrastructure

- **API layer** (`/api/*`): Token-based REST API for both clients and providers, with scoped order visibility (each party only sees their own orders).
- **Admin panel** (`/admin/*`): Separate controllers for managing clients, providers, orders, and payments with oversight.
- **NotificationService**: Multi-channel notification dispatcher (push, SMS, email via mailer) respecting each user's preferences.
- **PaymentGateway**: A service wrapper simulating card holds, charges, and refunds (currently logs to file rather than integrating a live payment processor).
