# Affordance Test

Two parallel Rails 8.1 apps exploring how entity naming affects AI reasoning.

## Structure

- `affordance_order/` — Rails app where the central entity is **Order** (clean, refactored states)
- `affordance_request/` — Rails app where the central entity is **Request** (legacy invitation-era states)
- `docs/superpowers/specs/` — Design specification

## Key Rules

- Both apps must remain structurally identical except for Order/Request naming and state differences
- Order has clean states: pending, confirmed, in_progress, completed, canceled, rejected
- Request has legacy states: created, created_accepted, accepted, started, fulfilled, declined, missed, canceled, rejected
- Request app has extra services: CreateAcceptedService, DeclineService
- Request app has extra API endpoint: POST /api/requests/direct

## Tech Stack

- Ruby 3.3.5, Rails 8.1.3
- SQLite, AASM, RSpec + FactoryBot
- API mode (JSON) + admin HTML section (ERB, basic auth)

## Running

```bash
cd affordance_order && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd affordance_request && bundle install && bin/rails db:create db:migrate && bundle exec rspec
```
