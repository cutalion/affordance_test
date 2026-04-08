# Affordance Test

Three parallel Rails 8.1 apps exploring how entity naming affects AI reasoning.

## Structure

### Phase 1+2: Naming vs Structure (3 apps)
- `affordance_order/` — Rails app where the central entity is **Order** (clean name + clean states)
- `affordance_request/` — Rails app where the central entity is **Request** (legacy name + legacy states)
- `affordance_request_clean/` — Rails app where the central entity is **Request** (legacy name + clean states) — isolates naming from structural complexity

### Phase 3b: Technical Debt Threshold (5 apps)
- `invitation_mvp/` — Stage 0: Clean invitation model (Request = invitation, fits perfectly)
- `booking_clean/` — Stage 1 Clean: Request + Order (accepted request creates an order)
- `booking_debt/` — Stage 1 Debt: Request absorbs booking lifecycle (AcceptService captures payment)
- `marketplace_clean/` — Stage 2 Clean: Request + Order + Announcement + Response (three paths to Order)
- `marketplace_debt/` — Stage 2 Debt: Request is god object (announcement responses ARE requests)

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
- invitation_mvp: Request states = pending, accepted, declined, expired (invitation semantics — fits perfectly)
- booking_clean: Request unchanged + Order states = pending, confirmed, in_progress, completed, canceled, rejected
- booking_debt: Request states = pending, accepted, in_progress, completed, declined, expired, canceled, rejected (AcceptService captures payment — name lies)
- marketplace_clean: Same as booking_clean + Announcement (draft/published/closed) + Response (pending/selected/rejected)
- marketplace_debt: Same as booking_debt + Announcement. Responses ARE Requests (no Response model). AcceptService takes `actor:` and branches on `announcement.present?` — serves 3 purposes

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
cd invitation_mvp && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd booking_clean && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd booking_debt && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd marketplace_clean && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd marketplace_debt && bundle install && bin/rails db:create db:migrate && bundle exec rspec
```
