# Practitioner Review: Does Technical Debt Break AI Coding Assistants?

> 72 runs of Claude Opus across 5 Rails apps, 6 experiments. Reviewed by an engineering manager who cares about Monday morning, not academic novelty.

---

## 1. Does Debt Matter in Practice?

**Short answer: it depends entirely on what you're asking the AI to build.**

I categorized the 6 experiments by feature complexity and looked at where debt actually caused problems:

### Simple features (add a state + service + endpoint)
**Experiments: e06-withdraw-response**

Debt barely matters for simple, additive features. Both the clean app (delta) and the debt app (echo) produced correct implementations across all 6 runs. Zero bugs either way. The debt app's code was slightly heavier (migrations for extra columns, guard clauses for the god object), but it worked.

**Verdict: Debt is a nuisance, not a hazard. Skip the refactor.**

### Medium features (new state + business logic + payment integration)
**Experiments: e03-counter-proposal, e04-cancellation-fee**

This is where debt starts to matter -- but not how you'd expect. In e03 (counter-proposal), the clean apps (bravo, delta) had an identical unreachable-code bug in all 6 runs (`return` after `raise ActiveRecord::Rollback`). The debt apps (charlie, echo) avoided this bug entirely because their payment-creation pattern was structurally simpler. In e04 (cancellation fee), the worst bug was in the debt app echo (silently repurposing an existing `fee_cents` column for a completely different concept), and debt apps showed more cross-run variation in where to place the fee column.

**Verdict: Debt creates different bugs, not more bugs. Clean apps fail at service composition seams; debt apps fail at semantic confusion.**

### Structural features (new model + multi-entity orchestration)
**Experiments: e05-recurring-bookings**

This is where debt clearly hurts. Clean apps (bravo, delta) produced a dedicated `RecurringBooking` model in 6/6 runs. Debt apps (charlie, echo) diverged -- 2 of 6 runs punted on a new model entirely, using a UUID column hack instead. That hack is the kind of thing that deepens existing debt. The clean app delta also had the experiment's most serious bug (silent `ActiveRecord::Rollback` in a composed service call), but the architectural consistency was dramatically better.

**Verdict: For structural features, debt causes architectural indecision. The AI hedges, and you get inconsistent designs across team members using the same tool.**

---

## 2. Error Taxonomy: What Kind of Mistakes?

I found three distinct categories across the 72 runs:

### Logic bugs (would fail in production)
- **Unreachable code after `raise`**: `raise ActiveRecord::Rollback` followed by `return error(...)`. The return never executes, so the method falls through to the success path. Found in 6/6 clean-app runs for e03, and 1 run for e05 delta. This is a real, silent data-corruption bug.
- **Semantic column reuse**: e04 echo run 2 repurposes the existing `fee_cents` column (platform fee) for cancellation fees, conflating two different business concepts. Tests pass because the test checks the wrong thing.
- **Amount mutation**: Several runs in e04 mutate `payment.amount_cents` directly, destroying the audit trail of the original charge.

### Architecture bugs (would cause maintenance pain)
- **UUID-column-instead-of-model**: e05 debt app runs 1 chose a flat UUID column over a proper model. Works today, creates orphan-management problems tomorrow.
- **Terminal-vs-recoverable state choices**: e03 delta runs 2-3 made declining a counter-proposal terminal (kills the whole request), while 9/12 other runs made it return to pending. Both "work" but represent fundamentally different product decisions the AI made unilaterally.
- **God object column accumulation**: e06 echo adds `withdrawn_at` and `withdraw_reason` to the already-bloated Request model because the existing pattern pressures the AI to follow suit.

### Scope issues (would waste reviewer time)
- **Design documents nobody asked for**: e05 charlie run 1 generated a 408-line implementation plan document alongside the code. e03 echo run 1 generated a 768-line plan.
- **Extra features**: e05 delta run 1 added a cancel endpoint with state management that wasn't requested. e04 runs variously added model convenience methods, API response enrichments, and notification changes.
- **Defensive over-engineering**: e03 echo run 3 added future-time validation and a custom `revert_to_pending` event name. Correct but unrequested.

### Bug frequency by app type

| Bug type | Clean apps (bravo+delta) | Debt apps (charlie+echo) |
|----------|------------------------|-------------------------|
| Logic bugs | 7 runs (all the raise/return bugs) | 1 run (fee_cents reuse) |
| Architecture bugs | 2 runs (terminal decline in delta) | 4 runs (UUID hack, column pressure) |
| Scope issues | 3 runs (cancel endpoint, etc.) | 5 runs (plan docs, extra columns) |

Clean apps produce more logic bugs at composition boundaries. Debt apps produce more architecture and scope issues. Neither is categorically "safer."

---

## 3. Would a Human Catch These?

This is the question that matters for your PR review process.

### A typical code reviewer WOULD catch:
- **Scope creep**: The 408-line plan document, the unrequested cancel endpoint, the extra columns. These are visible in the diff and obviously out of scope. Time cost: 2 minutes to comment "remove this."
- **Column placement disagreements**: "Why is cancellation_fee on Payment instead of Order?" is a normal architectural review comment.
- **The terminal-vs-recoverable decline**: A product-aware reviewer would catch that declining a counter-proposal shouldn't kill the request.

### A typical code reviewer MIGHT catch:
- **The `fee_cents` reuse** (e04 echo run 2): You'd have to know what `fee_cents` already means in the codebase. A reviewer unfamiliar with the payment model would miss this. The test passes, the diff looks clean. This is the most dangerous bug in the dataset.
- **Amount mutation**: Depends on whether your team has a "never mutate financial records" norm. Many teams don't.

### A typical code reviewer WOULD NOT catch:
- **The `raise`/`return` unreachable code bug**: This appeared in 7 runs across 2 experiments. It looks correct at a glance -- there's a `raise` for rollback and a `return` for the error case. You have to know that `raise ActiveRecord::Rollback` doesn't propagate out of the transaction block, and that the `return` after it is dead code. The method then falls through to the success notification. I estimate fewer than 30% of Rails developers would catch this in review. **This is the kind of bug that ships.**

### Practical implication
The bugs that survive review are concentrated in clean-architecture apps, not debt apps. The clean apps' delegation patterns create subtle composition errors that look correct. The debt apps' bugs are more obvious (wrong column, extra scope) and more likely to get flagged.

---

## 4. ROI of Refactoring for AI-Assisted Development

Based on this data, here is when refactoring pays off and when it doesn't:

### HIGH ROI: Refactor god objects before asking AI to build structural features
The recurring-bookings experiment (e05) is the clearest signal. Clean apps got consistent, correct architectures 6/6 times. Debt apps produced inconsistent designs (4/6 model, 2/6 UUID hack). If your team is building features that require new models or cross-entity orchestration, the debt in your existing models will cause the AI to hedge and produce divergent approaches across team members.

**Estimated value**: Saves 1-2 rounds of review rework per structural feature. Over a quarter with 4-5 such features, that's 8-10 hours of senior engineer review time saved.

### LOW ROI: Refactor before simple additive features
The withdraw-response experiment (e06) shows that even the most debt-laden app (echo, 9 AASM states on a god object) produces correct code for simple features. The extra columns and guard clauses are ugly but functional. Don't refactor a god object just because you need to add one more state to it.

### COUNTERINTUITIVE: Clean architecture can produce more subtle bugs
The biggest surprise in the data. The `raise`/`return` bug appeared exclusively in clean apps because those apps use service delegation patterns that require careful transaction handling. The debt apps' direct, inline approach was structurally simpler and therefore harder to get wrong. This does NOT mean debt is better -- it means you need to pair clean architecture with explicit error-handling patterns that the AI can reliably copy.

**Action item**: If your codebase uses the service-object pattern with `ActiveRecord::Rollback`, add a linter rule or a documented pattern for transaction error handling. The AI will copy whatever pattern it finds, and the common pattern is wrong.

### MODERATE ROI: Consistent naming reduces AI confusion
The e06 experiment is a clean comparison. In delta (clean), the AI calls it "withdraw response" everywhere -- error messages, notification events, service names. In echo (debt), it says "withdraw request" in error messages ("Not your request", "Cannot withdraw request") when the user is conceptually withdrawing a response. The code works, but the semantic confusion means worse error messages, confusing logs, and slightly misleading test descriptions. Over time, this erodes codebase clarity.

---

## 5. The "3 Runs" Test

Running the same prompt 3 times on the same codebase reveals important signals:

### High convergence = the AI is confident in the pattern
- **Clean apps consistently converge**: Bravo and delta produced near-identical implementations across 3 runs in most experiments. When you see this, the codebase has clear enough patterns that any AI run will follow them.
- **e06 delta**: All 3 runs produced effectively the same diff. Zero migrations, same service, same test structure. This is what a well-factored codebase looks like to an AI.

### Low convergence = the AI is guessing
- **Debt apps diverge on architecture**: Charlie and echo runs 1 vs runs 2-3 in e05 used completely different approaches (UUID column vs dedicated model). This means the codebase doesn't strongly suggest a "right answer."
- **e04 across all apps**: Column placement varied within apps (fee on Order vs Payment vs Request). The 24h boundary condition used `<=` in 11 runs and `<` in 1 run. These are design decisions the AI is making arbitrarily.

### What this means for your team
If you have 3 developers using AI on the same feature area and they're getting different architectures, your codebase is ambiguous. The fix isn't to tell them which AI output to pick -- it's to clarify the patterns in the codebase itself (or write an ADR the AI can reference).

**Practical test**: Before a major feature, have the AI describe the system (e01-style). If the description is muddled or inconsistent across runs, the codebase needs clarification before you ask the AI to build on it.

---

## 6. Practical Recommendations

### For engineering managers

1. **Prioritize refactoring based on upcoming feature type, not debt severity.** If next quarter's roadmap is mostly additive features (new endpoints, new states), leave the god objects alone. If it includes new domain concepts (new models, new entity relationships), refactor first.

2. **Add a "3-run divergence check" to your planning process.** Before starting a complex feature, run the AI prompt 3 times. If the architectures diverge, invest in clarifying the codebase patterns before letting the team build.

3. **Your biggest AI risk is not debt -- it's composition bugs that pass review.** The `raise`/`return` unreachable-code bug appeared in 7/72 runs and would likely survive most code reviews. Invest in static analysis, integration tests that verify error paths, and documented transaction patterns.

4. **Expect 10-15% scope creep from AI-generated code on debt codebases.** Debt apps produced more unsolicited plan documents, extra model methods, and defensive code. Build this into your review time estimates.

### For individual developers

1. **Always check the error path in AI-generated service objects.** The AI is excellent at happy paths and consistently bad at transaction error handling with composed services.

2. **When the AI avoids adding to a model, ask why.** In e04, the AI systematically routed cancellation fees away from the overloaded Request model to Payment. This is a sign the AI is working around debt. Sometimes the workaround is fine; sometimes it creates a worse design.

3. **Read the AI's error messages as a code smell detector.** When the AI writes `"Not your request"` in a service that's conceptually about responses (e06 echo), that's a signal that the model is overloaded.

4. **Don't trust AI-generated tests for error paths.** The e03 tests for the `AcceptCounterProposalService` test that an order is created on success, but they don't test what happens when order creation fails inside the transaction. The unreachable-code bug lives in exactly that gap.

---

## 7. Limitations

- **Single model (Opus), single domain (marketplace bookings).** Results may differ with other models or domains. The Rails service-object pattern is particularly tricky for transaction handling; other frameworks may not have this failure mode.

- **3 runs per configuration is enough to detect convergence patterns but not enough for statistical significance.** The 2/6 UUID-hack rate in debt apps could be 1/6 or 3/6 with more data.

- **All apps are small (~1000 LOC).** Production codebases with 50k+ LOC may amplify or dampen these effects. Larger codebases give the AI more patterns to copy, which could increase consistency (more examples) or decrease it (conflicting examples).

- **Tests passing is not correctness.** Multiple runs produced code where all tests pass but the implementation has real bugs (the raise/return issue, the fee_cents reuse). The AI writes tests that validate its own implementation, not tests that challenge it.

- **No human-in-the-loop.** These runs are "one-shot" implementations. In practice, developers iterate with the AI, which might catch some of these issues. The data shows first-pass quality only.

- **The experiment measures code generation, not code understanding.** The e01 and e02 experiments show the AI describes debt codebases fluently -- perhaps too fluently. We can't measure whether a developer using the AI's description would form correct mental models.

---

## 8. Verdict

Technical debt does not make AI coding assistants produce more bugs -- it makes them produce different bugs and less consistent architectures. For simple features, debt is irrelevant: the AI gets it right regardless. For structural features that require new models or cross-entity orchestration, debt causes the AI to hedge, producing divergent designs across runs that will fragment your codebase if different team members ship different AI outputs. The most dangerous finding is not about debt at all: clean codebases with service-delegation patterns produce a specific, recurring transaction-handling bug (unreachable code after `raise ActiveRecord::Rollback`) that looks correct in review and ships with passing tests. The highest-ROI action for any team using AI assistants is not refactoring debt -- it is establishing explicit, documented patterns for the error paths in your most common architectural patterns, because the AI will faithfully replicate whatever it finds, and what it finds is usually only the happy path done right.
