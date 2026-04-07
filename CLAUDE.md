# Affordance Test

Three parallel Rails 8.1 apps exploring how entity naming affects AI reasoning.

## Structure

- `affordance_order/` — Rails app where the central entity is **Order** (clean name + clean states)
- `affordance_request/` — Rails app where the central entity is **Request** (legacy name + legacy states)
- `affordance_request_clean/` — Rails app where the central entity is **Request** (legacy name + clean states) — isolates naming from structural complexity
- `docs/superpowers/specs/` — Design specification

## Key Rules

- Order has clean states: pending, confirmed, in_progress, completed, canceled, rejected
- Request has legacy states: created, created_accepted, accepted, started, fulfilled, declined, missed, canceled, rejected
- Request app has extra services: CreateAcceptedService, DeclineService
- Request app has extra API endpoint: POST /api/requests/direct
- Request Clean has the SAME clean states and services as Order, only the entity name differs (Request instead of Order)

## Tech Stack

- Ruby 3.3.5, Rails 8.1.3
- SQLite, AASM, RSpec + FactoryBot
- API mode (JSON) + admin HTML section (ERB, basic auth)

## Running

```bash
cd affordance_order && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd affordance_request && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd affordance_request_clean && bundle install && bin/rails db:create db:migrate && bundle exec rspec
```
