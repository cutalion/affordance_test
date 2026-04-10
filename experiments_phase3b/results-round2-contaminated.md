# Phase 3b Results — Round 2 (Schema-Contaminated)

> **Status:** These results were collected with neutral app names but contaminated schemas.
> The clean apps (bravo/delta) had pre-existing `recurring_bookings` tables and the debt apps
> (charlie/echo) had pre-existing `recurring_group_id`/`recurring_index` columns and
> `withdraw_reason`/`withdrawn_at` columns from prior experiment runs. This means E05 and E06
> findings about "architectural decisions" are partially artifacts of schema hints.
>
> **Date:** April 2026
> **Runs:** 72 total (5 apps × 3 runs × ~5 experiments per app, minus exclusions)
> **Model:** Opus only
> **Known contamination sources:**
> - Pre-baked schema artifacts from prior experiment branches
> - MEMORY.md leaks "Kidsout" domain references into E01 runs
> - Analyzer was not truly blind (deduced app identities from code structure)

---

## Experiment Summaries

### E01 — Describe System (15 runs, all 5 apps)

The AI accurately mirrors each app's entity structure, state machines, and workflows without
inventing or omitting anything. Most importantly, it **never flags architectural problems** —
App E's Request model serves as invitation, booking, fulfillment tracker, and announcement
response simultaneously, yet the AI describes this with the same neutral tone as App D's clean
four-model architecture. The AI normalizes whatever it finds.

### E02 — Happy Path (15 runs, all 5 apps)

Happy-path descriptions for debt apps read as clean and simple as clean apps. App E's AcceptService
branching (which serves 3 purposes depending on context) is entirely invisible in happy-path
analysis. **"The happy path is the one angle from which debt looks exactly like clean design."**

### E03 — Counter-Proposal (12 runs, 4 apps, skip alpha)

**Counterintuitive result:** Debt apps (C, E) produced more correct implementations.
- Dead-code bug (`raise ActiveRecord::Rollback` + unreachable `return`): 5/6 clean runs, 0/6 debt runs
- Terminal decline (kills request on counter-proposal rejection): 3/6 clean, 0/8 debt
- Extended cancel from counter_proposed: 1/6 clean, 5/6 debt

**Caveat (Judge 2):** The dead-code bug exists in the clean apps' existing AcceptService. The AI
copied it, not independently generated it. This is pattern mimicry, not architectural reasoning.

### E04 — Cancellation Fee (12 runs, 4 apps, skip alpha)

No systematic correctness difference between clean and debt. The notable finding is **inverse
scope creep**: App D (Stage 2 Clean) showed the most scope creep (D-R2 created payments from
scratch, modified notifications), while App E (Stage 2 Debt) stayed minimal in all 3 runs.
Clean architecture may invite elaboration; visible complexity triggers conservative behavior.

### E05 — Recurring Bookings (12 runs, 4 apps, skip alpha)

**God-object gravity:** Clean apps create a proper `RecurringBooking` model in 5/5 code-producing
runs; debt apps avoid new models in 4/6 runs, adding `recurring_group_id` to Request instead.

**Caveat (Judge 2):** Clean apps already had a `recurring_bookings` table in schema; debt apps
already had `recurring_group_id` columns. The AI followed pre-existing schema, not making
independent architectural decisions. This is the most contaminated experiment.

App D is the only app where the AI creates Orders (not Requests) as children and adds Payments —
demonstrating that clean architecture communicates the correct domain hierarchy.

### E06 — Withdraw Response (6 runs, 2 apps: delta + echo only)

**Convergence signal:** App D produced byte-identical diffs across all 3 runs. App E showed
routing divergence (2/3 on RequestsController, 1/3 on AnnouncementsController). When a domain
concept has its own model, there is one obvious implementation path.

**Language mismatch:** All App E runs say "withdraw request" when the prompt said "withdraw
response" — entity naming affects AI communication even when implementation is correct.

**Caveat (Judge 2):** App E's schema already had `withdraw_reason` and `withdrawn_at` columns,
pre-determining the "extra ceremony" attributed to debt conventions.

---

## Cross-Experiment Patterns

### 1. AI as Faithful Mirror (Strong evidence, all experiments)
The AI accurately describes and extends whatever architecture it encounters without ever
flagging design problems, naming mismatches, or responsibility overload. It treats debt as
the intended design and faithfully reproduces it.

### 2. Pattern Mimicry is the Dominant Mechanism (Strong evidence)
Most observed differences can be explained by the AI copying existing patterns wholesale —
including bugs (E03's dead-code pattern), schema structures (E05's pre-existing tables/columns),
and naming conventions (E06's `_reason`/`_at` suffixes). This is pattern completion, not
architectural reasoning.

### 3. God-Object Gravity (Moderate evidence, partially contaminated)
Debt apps cause the AI to pile new features onto existing models rather than creating new
abstractions. The E05 evidence is contaminated by pre-existing schema, but the E06 convergence
difference is clean evidence — when a concept has no dedicated model, different runs reach
different implementation decisions.

### 4. Clean Apps: Logic Bugs; Debt Apps: Architecture Bugs (Moderate evidence)
Clean apps' more layered service-delegation patterns introduce failure modes (dead code after
raise, wrong terminal states). Debt apps' inline patterns are simpler but reinforce the god
object. Logic bugs crash in tests; architecture bugs pass every test and silently accumulate.

### 5. The 3-Run Convergence Test (Moderate evidence, E06 primarily)
If 3 identical prompts produce 3 different architectures, the codebase has an ambiguity problem.
App D in E06: 3/3 identical. App E in E05: 3 different approaches. This variability is itself
a signal of architectural ambiguity in the codebase.

### 6. Debt Threshold is Binary, Not Gradual (Moderate evidence)
The clean/debt split is more predictive than Stage 1 vs Stage 2. C-vs-E comparisons show
"nearly identical behavior" (E03) and "strikingly similar patterns" (E05). The decisive factor
is whether each domain concept has its own model, not how many concepts are collapsed.

---

## Judge Reviews Summary

### Judge 1 — Fair (balanced assessment)
Confirmed all 3 cross-experiment patterns. Noted the threshold is at Stage 1 (model separation),
not Stage 2. Called the counterintuitive E03/E04 findings credibility-enhancing. Rated evidence
quality medium-high. Key insight: "Clean architecture communicates domain intent; debt obscures
intent but constrains scope."

### Judge 2 — Skeptic (adversarial review)
**Critical findings that led to this re-run:**
- Pre-baked schemas invalidate E05's headline finding (god-object gravity is schema artifact)
- E03's dead-code bug is inherited from existing code, not independently generated
- n=3 per condition is too small for credible conclusions
- The "blind" analysis was not truly blind (analyzer deduced identities)
- MEMORY.md leaks "Kidsout" into E01 runs
- Several findings are overstated for the sample size

**What held up:** AI as faithful mirror (strong), convergence differences (moderate),
AI copies patterns including bugs (moderate), language mismatch in debt apps (moderate).

### Judge 3 — Practitioner (engineering manager perspective)
Most actionable review. Key contributions:
- Error taxonomy: clean apps make logic bugs (caught by tests), debt apps make architecture
  bugs (invisible in tests, accumulate silently)
- The "3-run convergence test" as a practical refactoring signal
- ROI model: extracting core model boundaries (Request+Order split) is highest-ROI refactoring
- "Do not trust AI to flag debt" — 15 E01 runs, zero mentions of design problems
- Recommendation: review AI PRs for architecture, not just correctness

---

## My Analysis

### What's Real

**1. The AI is an aggressive pattern mimic.** This is the strongest, most defensible finding.
Across all 72 runs, the AI copies existing code structures wholesale — entity relationships,
service patterns, naming conventions, column naming patterns, and yes, bugs. It does not
exercise independent architectural judgment. It does not flag problems. It treats whatever
exists as specification.

**2. Convergence correlates with model clarity.** When a domain concept has its own model
(Response in delta), 3 runs produce identical code. When it doesn't (Request-as-response in
echo), runs diverge on where to put the feature. This is clean evidence uncontaminated by
schema artifacts — the divergence comes from conceptual ambiguity, not schema hints.

**3. The AI never critiques architecture.** In 30 descriptive runs (E01 + E02), zero instances
of the AI saying "this model has too many responsibilities" or "this naming is misleading."
The god object is invisible to the AI as a problem — it's just "how this system works."

### What's Contaminated

**E05 (recurring bookings)** is the most contaminated experiment. The "god-object gravity"
headline is largely an artifact of pre-existing schema structures. The clean apps already had
`recurring_bookings` tables; the debt apps already had `recurring_group_id` columns. The AI
read the schema and followed it. This needs a clean re-run with fresh databases.

**E06 (withdraw response)** is partially contaminated. Echo already had `withdraw_reason` and
`withdrawn_at` columns, inflating the measured "ceremony" difference. However, the routing
divergence finding is clean — that comes from model ambiguity, not schema hints.

**E03 (counter-proposal)** is less contaminated by schema but the dead-code bug is pattern
copying, not an independent architectural decision. The finding is real but should be framed
as "AI copies bugs from existing code" rather than "debt produces fewer bugs."

### What Needs Re-Running

All code experiments (E03-E06) need a clean re-run with:
1. Fresh database before each run (now added to run.sh)
2. No pre-existing schema artifacts from prior experiments
3. Ideally, MEMORY.md hidden or cleared of domain references

E01 and E02 (descriptive, no code changes) are less affected but still have the MEMORY.md
leak causing "Kidsout" references.

### The Story So Far

Even with contamination caveats, a coherent picture emerges:

**AI coding assistants are pattern amplifiers.** They read existing code as specification and
reproduce its patterns forward. This makes clean architecture self-reinforcing (the AI creates
new models when existing code uses many models) and debt self-reinforcing (the AI piles onto
god objects when existing code does that). The AI does not distinguish between intentional
design and accumulated debt — both are treated as "how this system works."

**The practical risk is not broken code — it's invisible architectural erosion.** The debt apps'
implementations pass tests, follow existing conventions, and look locally reasonable in PR diffs.
The problem is global: each AI-generated feature that adds columns to the god object instead of
extracting a new model makes the next AI-generated feature more likely to do the same thing.
This is a feedback loop that accelerates debt accumulation while making it invisible to
standard code review practices.

**The threshold appears to be model separation, not debt volume.** Whether you have 1 collapsed
model or 3 collapsed models matters less than whether each domain concept has its own model at
all. The Request+Order split is the critical boundary — once that exists, the AI produces
convergent, correct implementations. Without it, the AI produces varied, locally-reasonable
implementations that gradually entrench the collapse.

These hypotheses need validation with clean data. That's what round 3 is for.
