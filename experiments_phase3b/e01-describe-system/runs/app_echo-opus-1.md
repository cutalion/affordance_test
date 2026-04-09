# Experiment: e01-describe-system
# App: app_echo | Model: opus | Run: 1

---

This is a **service marketplace** — a platform connecting **Clients** (who need services) with **Providers** (who deliver them). The domain resembles childcare/babysitting (derived from "Kidsout") but is abstracted with neutral names.

## Main Entities

- **Client** — a person seeking services. Has payment cards, can post announcements and create requests. Authenticated via API token.
- **Provider** — a service professional. Has a rating, specialization, and active/inactive status. Authenticated via API token.
- **Announcement** — a public posting by a Client describing what they need (title, description, schedule, location, budget). Lifecycle: `draft → published → closed`.
- **Request** — the core entity. Represents a booking between a Client and a specific Provider for a scheduled time slot, with agreed amount and duration. Can originate from an Announcement (provider responds) or be created directly.
- **Payment** — one-to-one with a Request. Tracks money flow: `pending → held → charged → refunded`. Linked to a Card.
- **Card** — a saved payment method for a Client (brand, last four, expiry). One can be marked as default.
- **Review** — polymorphic, left by either Client or Provider after a completed Request. Rating 1-5 with optional text body. Each party can review once per request.

## Typical Workflow

1. **Client posts an Announcement** (draft → publish) describing what they need, or directly creates a Request to a known Provider.
2. **Provider responds** to an Announcement, which creates a Request linking them.
3. **Request lifecycle**: `pending → accepted → in_progress → completed`
   - Provider can **accept** or **decline** (with reason). Pending requests can **expire**.
   - Either party can **cancel** (from pending/accepted). Provider can **reject** (from accepted/in_progress).
4. **Payment** is created for the request — funds are held, then charged on completion (or refunded on cancellation).
5. **After completion**, both Client and Provider can leave **Reviews**.

The app exposes two namespaces: an **API** (for client/provider-facing mobile/web apps) and an **Admin** panel (read-only dashboard for operators).
