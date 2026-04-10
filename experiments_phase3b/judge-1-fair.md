# Independent Judge Review: Phase 3b Technical Debt Threshold Experiment

> Reviewer context: Read all 6 analysis files and sampled 10 raw run files across experiments e01-e06 and apps alpha through echo to verify claims against primary data.

---

## 1. Cross-Experiment Synthesis

Six patterns emerge consistently across the experiments:

**Pattern 1: The AI is a mirror, not a critic.** This is the single strongest finding. Across all 72 runs, the AI never once flags semantic overloading, naming mismatches, or god-object concerns. A "Request" that captures payments and tracks work execution is described with the same confidence as a "Request" that is purely an invitation (e01, e02). When building features, the AI faithfully replicates whatever patterns it finds (e03, e04, e05). It naturalizes debt as intentional design.

**Pattern 2: Clean codebases produce more consistent AI output.** This appears in every experiment where it can be measured. In e05 (recurring bookings), clean apps generated a dedicated RecurringBooking model 6/6 times; debt apps diverged in 2/6 runs toward a UUID-column hack. In e06 (withdraw response), app_delta's 3 runs are near-identical diffs while app_echo's 3 runs diverge on whether to require a reason and how many columns to add. In e04, app_delta (clean) is completely consistent on fee placement (Order, 3/3) while app_echo varies. This consistency signal is the most reproducible finding across experiments.

**Pattern 3: Debt apps route new features away from overloaded models.** In e04, the AI places cancellation_fee on Order in clean apps (7/9 placements) but on Payment in debt apps (5/6 runs), systematically avoiding the god-object Request. This is architecturally intuitive avoidance behavior -- the AI can sense that Request is "full" even though it never says so.

**Pattern 4: Clean architecture introduces composition risks.** This is the most counterintuitive finding. In e03, all 6 clean-app runs contain an identical unreachable-code bug (`return` after `raise ActiveRecord::Rollback`) in the accept service because they delegate to a sub-service and mishandle the result check. All 6 debt-app runs avoid this bug because their simpler, direct-to-Payment pattern has no such error path. In e05, the only serious bug (silent rollback with success notification) is in clean app_delta. Clean architecture invites ambitious composition that the AI does not fully reason through.

**Pattern 5: Debt apps show more scope creep.** In e03, debt apps generate plan documents (app_echo Run 1: 768 lines) and expanded feature interpretations (app_charlie Run 3: added duration/notes). In e05, debt apps generate more documentation artifacts. In e06, debt-app implementations require migrations and additional columns driven by pattern-following pressure that clean apps avoid. The more complex the codebase, the more the AI adds unrequested elements.

**Pattern 6: Descriptive accuracy degrades at the highest debt levels.** In e01, the only factual error across 15 runs (actor role inversion) occurs in app_echo, the highest-debt codebase. In e02, the only factual error (misattributing Order creation) occurs at an entity boundary seam. These are rare errors (2 across 30 descriptive runs) but they cluster in the more complex codebases.

---

## 2. Threshold Finding

The data suggests two distinct thresholds:

**Threshold 1 (Consistency): Stage 1 Debt (app_charlie).** The transition from app_bravo (clean Request + Order) to app_charlie (Request absorbs Order's lifecycle) is where cross-run consistency first drops. In e05, both app_charlie and app_echo Run 1 independently arrive at the UUID-grouping hack, while app_bravo never does. In e04, app_charlie shows more variation in fee placement than app_bravo. However, the magnitude is moderate -- app_charlie still produces functionally correct code in most runs.

**Threshold 2 (Correctness): Stage 2 Debt (app_echo).** The transition to app_echo, where Requests serve triple duty (direct booking, announcement response, and lifecycle carrier), is where measurable correctness issues appear. The e01 actor inversion, the e04 `fee_cents` reuse bug, the e06 semantic confusion ("Not your request" when meaning "Not your response") all concentrate here. App_echo also produces the most inter-run variance in every experiment.

**Important caveat:** The thresholds are not sharp boundaries. App_alpha (clean invitation model) and app_bravo (clean two-entity model) perform similarly. App_charlie (Stage 1 debt) shows consistency degradation. App_echo (Stage 2 debt) shows both consistency and correctness degradation. App_delta (Stage 2 clean) performs well on correctness but shows its own issues (composition bugs). The picture is nuanced rather than step-function.

---

## 3. Quality of Evidence

**Strengths:**

- The experimental design is well-controlled. Using neutral app names (alpha through echo) and running identical prompts prevents contamination. Three runs per app-experiment combination provides a basic check on consistency.
- The analyses are thorough and largely accurate. I verified the raise/return bug claim (e03, app_bravo Run 1 and app_delta Run 2), the UUID-grouping divergence (e05, app_charlie Run 1 and app_echo Run 1), the fee_cents reuse issue (e04, app_echo Run 2), the e06 delta-vs-echo implementation differences, and the app_bravo Run 3 error in e02. All claims checked out against the raw data.
- The six-dimension framework (language, architecture, model placement, state reuse, correctness, scope) provides systematic coverage without cherry-picking.

**Weaknesses:**

- **Sample size is thin.** Three runs per condition is the minimum for observing variance, not enough for statistical significance. When the analysis says "2/6 debt runs used UUID grouping vs 0/6 clean runs," the p-value on a Fisher exact test would not reach conventional significance. The findings are suggestive, not proven.
- **Single model (Opus) limits generalizability.** The experiment explicitly chose Opus-only to reduce variables, but this means findings may not transfer to other models. A model with different pattern-matching heuristics might behave differently.
- **The analyses occasionally overinterpret.** The e03 analysis frames the raise/return bug as "codebase structure determined whether the AI produced a bug," which is accurate but could be read as implying clean architecture causes bugs. The real lesson is that the AI copies patterns including their error-handling flaws, and more indirection creates more surface area for subtle bugs. The framing matters.
- **Experiment e06 only covers two apps** (delta and echo), limiting the comparison space. The analysis is sound within its scope but contributes less to cross-experiment patterns.
- **No baseline measurement.** There is no control condition (e.g., a professional developer implementing the same features) to calibrate what "good" performance looks like. We cannot say whether the AI is worse at handling debt than a human would be.

---

## 4. Key Insights

**Most useful for practitioners:**

1. **AI coding assistants will perpetuate whatever architectural patterns they find.** They will not push back on god objects, naming mismatches, or semantic drift. If you want the AI to produce clean code, the existing codebase must already be clean. This has direct implications for codebase maintenance priorities.

2. **The consistency signal is more actionable than the correctness signal.** If the AI produces different architectures on repeated runs against the same codebase, that is a measurable indicator that the codebase has ambiguous or confusing structure. This could be turned into a diagnostic tool: run the same prompt N times and measure variance.

3. **More indirection does not always help AI performance.** The clean apps' delegation-based accept pattern produced a systematic bug that the debt apps' simpler direct approach avoided. The lesson is not "debt is better" but rather "the AI mimics patterns without understanding their error-handling contracts." Service delegation patterns require careful error-path handling that the AI consistently misses.

4. **The AI exhibits implicit "avoidance" of overloaded entities.** It routes new attributes away from god objects (e04 fee placement) even though it never articulates why. This is interesting behavior -- the AI's architectural instinct is better than its explicit reasoning about architecture.

**Most useful for researchers:**

5. **Debt normalizes itself through AI descriptions.** The e01 finding that AI descriptions of clean and debt codebases are equally confident and plausible means AI-generated documentation cannot be used to detect debt. This has implications for AI-assisted code review and onboarding.

6. **Architectural confusion in code propagates as descriptive confusion in AI output.** The variance signal (e01 inter-run consistency, e05 architectural divergence, e06 implementation variation) is a more reliable indicator of codebase health than any single factual error. This is a measurable, reproducible effect.

---

## 5. Verdict

This experiment provides credible evidence that technical debt affects AI coding assistant behavior in specific, measurable ways: primarily through reduced cross-run consistency and subtly degraded correctness at the highest debt levels, rather than through dramatic failures. The strongest finding is that the AI mirrors existing patterns without questioning their fitness, meaning it will perpetuate debt silently. The most surprising finding is that clean architecture's additional indirection can paradoxically produce buggier AI output when the AI copies delegation patterns without understanding error contracts. The evidence quality is good for a pilot study -- the analyses are accurate against the raw data and the experimental design is sound -- but the sample size (3 runs per condition) means the quantitative claims should be treated as directional hypotheses rather than confirmed results. The experiment would benefit from larger N, multiple models, and a human-developer baseline. As it stands, it is a well-executed exploratory study that identifies real patterns worth investigating further, with the consistency-as-signal finding being the most immediately actionable for practitioners.
