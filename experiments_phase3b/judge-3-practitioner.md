# Practitioner Review: Technical Debt Threshold Experiment

**Reviewer perspective:** Senior engineering manager running a team that ships 60%+ of feature code through AI coding assistants. I care about PR review load, production bugs, and whether refactoring actually saves money.

---

## 1. Does debt matter in practice?

**Yes, but not the way I expected.** The headline finding is not "debt makes AI write worse code." It is more nuanced and, frankly, more troubling:

- **For simple features** (describe the system, walk the happy path): debt makes zero difference. The AI mirrors whatever it finds with equal fluency. A reviewer would not notice. (e01, e02)
- **For medium features** (counter-proposal, cancellation fee): debt apps actually produced *fewer bugs* in some experiments. The clean apps' `Orders::CreateService` delegation pattern led to a dead-code bug (`raise ActiveRecord::Rollback` followed by unreachable `return`) in 5 of 6 clean-app runs in e03. The debt apps' inline pattern avoided it entirely. (e03)
- **For structural features** (recurring bookings, withdraw response): debt causes the AI to pile onto the god object instead of creating proper new models (4/6 debt-app runs in e05), and causes routing divergence when the domain concept has no dedicated model (e06, 2/3 vs 3/3 convergence).

**Bottom line for a code reviewer:** You would catch the issues from debt apps, but they are *different* issues than you would expect. You are not looking for crashes or wrong logic. You are looking for architectural erosion -- the AI quietly adding `recurring_group_id` to the Request model instead of creating a RecurringBooking, or adding `withdraw_reason` and `withdrawn_at` as the 14th and 15th columns on an already-bloated table.

---

## 2. What kind of mistakes?

I categorized every error and questionable decision across all 72 runs:

| Error Type | Clean Apps | Debt Apps | Notes |
|---|---|---|---|
| **Dead code (unreachable after raise)** | 5 runs | 0 runs | Only in e03, only in service delegation pattern |
| **Wrong terminal state (decline kills request)** | 3 runs | 0 runs | e03: clean apps reused `declined` (terminal); debt apps created new events |
| **God-object gravity (piling onto existing model)** | 0 runs | 4 runs | e05: debt apps avoid new models, add fields to Request |
| **Scope creep (unrequested features)** | 3 runs | 1 run | e04-D2 (admin views, payment creation); e05-D1 (admin controller) |
| **Routing divergence (same feature, different endpoints)** | 0 runs | 1 run | e06-E3 put withdraw on AnnouncementsController instead of RequestsController |
| **Naming mismatch (code says "request" when domain says "response")** | 0 runs | 6 runs | All e06 echo runs say "withdraw request" for "withdraw response" |
| **Mutating payment amount (destroys audit trail)** | 2 runs | 3 runs | e04, spread across both; this is an AI-wide tendency |
| **Over-engineering** | 1 run | 1 run | D-R3 756-line plan doc; E-R3 day_of_week/time_of_day abstractions |

The pattern: **clean apps make logic bugs (dead code, wrong state semantics). Debt apps make architecture bugs (wrong model, naming mismatch, god-object reinforcement).** Logic bugs crash in tests. Architecture bugs pass every test and silently accumulate.

---

## 3. Would a human catch these?

**Logic bugs: yes.** The dead-code-after-raise pattern is a classic Ruby gotcha. Any reviewer who reads the service code line by line will spot `raise ActiveRecord::Rollback` followed by `return error(...)`. A linter could catch it too.

**Architecture bugs: probably not, and that is the real risk.** When the AI adds `recurring_group_id` to Request in a debt codebase, the PR diff looks *clean*. It follows existing patterns. Tests pass. The reviewer who approves it is not making a mistake in the moment -- they are approving a locally reasonable change that globally entrenches the god object. You would need a reviewer who holds the full domain model in their head and asks "should this be a new model?" That is a senior engineer spending 20+ minutes on a PR review, not a quick scan.

**Naming mismatches: unlikely.** When e06 echo runs say `Requests::WithdrawService` for what is conceptually "withdraw a response to an announcement," the code is internally consistent. The Request model *is* the response in that codebase. The mismatch is between the business domain and the code, and you would only notice if you read the PR description against the code and thought "wait, the ticket says 'response' but every class says 'request'."

---

## 4. ROI of refactoring

Based on the data, here is my rough model:

**Stage 0 to Stage 1 (invitation to booking):** Refactor from debt to clean **pays off immediately** if you are adding booking-lifecycle features. The clean app (bravo) produced a proper RecurringBooking model in 3/3 runs; the debt app (charlie) avoided it in 2/3 runs. That is the difference between clean architecture and months of future pain.

**Stage 1 to Stage 2 (booking to marketplace):** This is where the data gets interesting. Within the debt category, Stage 1 and Stage 2 debt apps produced nearly identical output quality (e03 C vs E, e04 C vs E). The *amount* of debt mattered less than the *existence* of debt. This suggests diminishing returns on partial refactoring -- if you are going to refactor, refactor the core model separation (Request vs Request+Order), not the peripheral complexity.

**The counterintuitive finding:** For one-off, well-scoped features (e03 counter-proposal), the debt apps actually outperformed clean apps on correctness. The mechanism is that debt apps' simpler inline patterns had fewer failure modes than clean apps' service-delegation patterns. This does NOT mean debt is good -- it means the clean apps' abstraction layer introduced a new category of bugs (the delegation gap) that the debt apps' monolithic approach avoided.

**My estimate:** If your team ships 3-5 AI-generated features per month on a god-object codebase, extracting the core model (the "Request+Order split") would save approximately 1-2 senior review hours per feature in architectural oversight, and prevent 1-2 silent architecture regressions per quarter. Whether that justifies a 2-week refactoring project depends on your codebase size, but for a codebase of this scale, it clearly does.

---

## 5. The "3 runs" test

This is the most actionable finding in the entire experiment. Run the same prompt 3 times on your codebase. If you get 3 different architectures, your codebase has an ambiguity problem.

**What happened here:**

| App | e05 (recurring bookings) | e06 (withdraw response) |
|---|---|---|
| **app_delta (clean)** | 2/3 same architecture, 1 design-only | 3/3 byte-identical diffs |
| **app_echo (debt)** | 3 different approaches (overload create, new endpoint, new model) | 2/3 same, 1 different routing |

app_delta in e06 is the gold standard: three independent runs producing the same diff, down to the line. That means the codebase communicates one clear answer. app_echo in e05 is the red flag: three runs, three approaches (overload existing create action; add a new endpoint with grouped fields; create a full RecurringBooking model with day_of_week/time_of_day). That means the codebase communicates no clear answer about where recurring bookings should live.

**Practical recommendation:** Before any major feature, run the prompt 3 times with temperature > 0. If the AI gives you 3 different architectures, you have a design problem that will cost you regardless of whether AI or humans write the code. The AI is just making the ambiguity visible faster.

---

## 6. Practical recommendations

**For engineering managers:**

1. **Do not trust AI to flag debt.** In 15 runs across e01 (describe the system), the AI never once said "this Request model has too many responsibilities." It described a god object with the same neutral, professional tone as a clean architecture. If you rely on AI to identify refactoring targets, you will never refactor.

2. **Add architectural guardrails to prompts for debt codebases.** The debt apps produced better results when the prompt was tightly scoped (e03, e04) and worse results when the prompt required structural decisions (e05, e06). For debt codebases, add a line like: "If this feature requires a new domain concept, create a new model rather than adding columns to an existing one."

3. **Review AI PRs for architecture, not just correctness.** Tests passing is necessary but not sufficient. The most dangerous AI output is code that works perfectly but entrenches the wrong model. Assign senior engineers to review AI-generated PRs specifically for model placement decisions.

4. **Use the 3-run convergence test as a refactoring signal.** If 3 runs produce 3 architectures, the codebase is ambiguous and needs structural work. If 3 runs converge, the codebase communicates clearly.

5. **Prioritize core model extraction over peripheral cleanup.** The data shows that Stage 1 debt and Stage 2 debt produce nearly identical AI output quality. The value is in the Request-vs-Request+Order split, not in cleaning up every service class.

**For individual developers:**

6. **Read the full diff, not just the summary.** The AI's self-description of its changes is always confident and clean-sounding, even when the implementation has dead-code bugs or wrong state semantics.

7. **Be suspicious of AI output that "follows existing patterns" in debt codebases.** That is exactly how god objects grow. The AI's pattern-following instinct is a feature for clean codebases and a liability for messy ones.

---

## 7. Limitations

These findings come with significant caveats:

**Small, purpose-built apps.** Each app is a few thousand lines with a single bounded context. Real codebases have dozens of models, cross-cutting concerns, and years of accumulated decisions. The "god object gravity" effect measured here (4/6 debt runs avoiding new models) is likely *stronger* in real codebases where the god object has more existing columns and associations to pattern-match against.

**Single model (Opus).** The experiment ran only Opus. Sonnet, GPT-4, and other models may show different sensitivity to architectural signals. The dead-code bug in particular (raise + return) may be model-specific.

**3 runs per condition.** With n=3, individual outliers (like D-R3's 756-line plan document) have outsized impact. The directional findings are credible, but the specific percentages (e.g., "5/6 clean-app runs had the dead-code bug") should be treated as signals, not statistics.

**No real codebase history.** These apps were built to a spec, not evolved over years. Real debt includes inconsistent patterns, dead code, abandoned migrations, and contradictory comments. The "clean" signal from well-structured debt apps may overstate how clearly real debt communicates its patterns.

**Prompts are clean and unambiguous.** Real tickets have vague requirements, conflicting stakeholder input, and implicit assumptions. The experiment tests AI behavior with clear instructions; real-world performance may be worse for both clean and debt codebases.

**No multi-turn interaction.** Each run is a single prompt. In practice, developers iterate with the AI, asking follow-up questions and requesting changes. Multi-turn interaction might mitigate some of the architectural issues (a developer could say "actually, create a new model for that").

---

## 8. Verdict

Here is what I would tell my VP of Engineering:

Technical debt does not make AI write broken code -- it makes AI write code that works today and creates problems next quarter. In our experiment, the AI produced functionally correct output on both clean and debt codebases, but on debt codebases it consistently reinforced the existing god-object pattern: piling new columns onto overloaded models, avoiding new abstractions, and producing different architectures on different runs (a signal that the codebase fails to communicate clear design intent). The practical impact is not in production bugs -- our tests catch those -- but in the invisible accumulation of architectural decisions that make future features harder and future AI output worse, creating a feedback loop. The single highest-ROI action is extracting your core model boundaries (the equivalent of splitting Request into Request + Order), which in this experiment was the difference between 3/3 runs producing identical, correct implementations and 3 runs producing 3 different approaches. That extraction costs days; the ongoing review burden of compensating for its absence costs more every month. Clean architecture is not just for humans anymore -- it is the specification language your AI tools read to decide where new code belongs.
