# Affordance Test

Three parallel Rails 8.1 apps exploring how entity naming affects AI reasoning.

## Structure

### Phase 1+2: Naming vs Structure (3 apps)
- `affordance_order/` — Rails app where the central entity is **Order** (clean name + clean states)
- `affordance_request/` — Rails app where the central entity is **Request** (legacy name + legacy states)
- `affordance_request_clean/` — Rails app where the central entity is **Request** (legacy name + clean states) — isolates naming from structural complexity

### Phase 3b: Technical Debt Threshold (5 apps, neutral names to prevent experiment contamination)
- `app_alpha/` — Stage 0: Clean invitation model (Request = invitation, fits perfectly)
- `app_bravo/` — Stage 1 Clean: Request + Order (accepted request creates an order)
- `app_charlie/` — Stage 1 Debt: Request absorbs booking lifecycle (AcceptService captures payment)
- `app_delta/` — Stage 2 Clean: Request + Order + Announcement + Response (three paths to Order)
- `app_echo/` — Stage 2 Debt: Request is god object (announcement responses ARE requests)

### Docs and Experiments
- `experiments/` — Phase 1+2 experiment runner and results
- `experiments_debt/` — Phase 3b experiment runner (6 experiments, 72 Opus-only runs)
- `docs/superpowers/specs/` — Design specifications
- `docs/superpowers/plans/` — Implementation plans

## Key Rules

### Phase 1+2 Apps
- Order has clean states: pending, confirmed, in_progress, completed, canceled, rejected
- Request has legacy states: created, created_accepted, accepted, started, fulfilled, declined, missed, canceled, rejected
- Request app has extra services: CreateAcceptedService, DeclineService
- Request app has extra API endpoint: POST /api/requests/direct
- Request Clean has the SAME clean states and services as Order, only the entity name differs (Request instead of Order)

### Phase 3b Apps
- app_alpha: Request states = pending, accepted, declined, expired (invitation semantics — fits perfectly)
- app_bravo: Request unchanged + Order states = pending, confirmed, in_progress, completed, canceled, rejected
- app_charlie: Request states = pending, accepted, in_progress, completed, declined, expired, canceled, rejected (AcceptService captures payment — name lies)
- app_delta: Same as app_bravo + Announcement (draft/published/closed) + Response (pending/selected/rejected)
- app_echo: Same as app_charlie + Announcement. Responses ARE Requests (no Response model). AcceptService takes `actor:` and branches on `announcement.present?` — serves 3 purposes

## Tech Stack

- Ruby 3.3.5, Rails 8.1.3
- SQLite, AASM, RSpec + FactoryBot
- API mode (JSON) + admin HTML section (ERB, basic auth)

## Running

```bash
# Phase 1+2
cd affordance_order && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd affordance_request && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd affordance_request_clean && bundle install && bin/rails db:create db:migrate && bundle exec rspec

# Phase 3b
cd app_alpha && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd app_bravo && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd app_charlie && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd app_delta && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd app_echo && bundle install && bin/rails db:create db:migrate && bundle exec rspec
```
