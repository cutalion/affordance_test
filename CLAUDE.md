# Affordance Test

Two experiments exploring how code structure shapes AI agent behavior.

## Structure

### Experiment 01: Naming vs Structure (3 apps)
- `experiments/01-naming/apps/order/` — Rails app where the central entity is **Order** (clean name + clean states)
- `experiments/01-naming/apps/request/` — Rails app where the central entity is **Request** (legacy name + legacy states)
- `experiments/01-naming/apps/request_clean/` — Rails app where the central entity is **Request** (legacy name + clean states) — isolates naming from structural complexity

### Experiment 02: Technical Debt Threshold (5 apps)
- `experiments/02-debt-threshold/apps/alpha/` — Stage 0: Clean invitation model (Request = invitation, fits perfectly)
- `experiments/02-debt-threshold/apps/bravo/` — Stage 1 Clean: Request + Order (accepted request creates an order)
- `experiments/02-debt-threshold/apps/charlie/` — Stage 1 Debt: Request absorbs booking lifecycle (AcceptService captures payment)
- `experiments/02-debt-threshold/apps/delta/` — Stage 2 Clean: Request + Order + Announcement + Response (three paths to Order)
- `experiments/02-debt-threshold/apps/echo/` — Stage 2 Debt: Request is god object (announcement responses ARE requests)

### Docs and Experiments
- `experiments/01-naming/` — Experiment 1 runner, results, judges, DESIGN.md, REPORT.md
- `experiments/02-debt-threshold/` — Experiment 2 runner, results, judges, DESIGN.md, REPORT.md
- `docs/superpowers/specs/` — Original design specifications

## Key Rules

### Experiment 01 Apps
- Order has clean states: pending, confirmed, in_progress, completed, canceled, rejected
- Request has legacy states: created, created_accepted, accepted, started, fulfilled, declined, missed, canceled, rejected
- Request app has extra services: CreateAcceptedService, DeclineService
- Request app has extra API endpoint: POST /api/requests/direct
- Request Clean has the SAME clean states and services as Order, only the entity name differs (Request instead of Order)

### Experiment 02 Apps
- alpha: Request states = pending, accepted, declined, expired (invitation semantics — fits perfectly)
- bravo: Request unchanged + Order states = pending, confirmed, in_progress, completed, canceled, rejected
- charlie: Request states = pending, accepted, in_progress, completed, declined, expired, canceled, rejected (AcceptService captures payment — name lies)
- delta: Same as bravo + Announcement (draft/published/closed) + Response (pending/selected/rejected)
- echo: Same as charlie + Announcement. Responses ARE Requests (no Response model). AcceptService takes `actor:` and branches on `announcement.present?` — serves 3 purposes

## Tech Stack

- Ruby 3.3.5, Rails 8.1.3
- SQLite, AASM, RSpec + FactoryBot
- API mode (JSON) + admin HTML section (ERB, basic auth)

## Running

```bash
# Experiment 01 apps
cd experiments/01-naming/apps/order && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd experiments/01-naming/apps/request && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd experiments/01-naming/apps/request_clean && bundle install && bin/rails db:create db:migrate && bundle exec rspec

# Experiment 02 apps
cd experiments/02-debt-threshold/apps/alpha && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd experiments/02-debt-threshold/apps/bravo && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd experiments/02-debt-threshold/apps/charlie && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd experiments/02-debt-threshold/apps/delta && bundle install && bin/rails db:create db:migrate && bundle exec rspec
cd experiments/02-debt-threshold/apps/echo && bundle install && bin/rails db:create db:migrate && bundle exec rspec
```
