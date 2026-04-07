# Judge Report: Affordance Test Experiment Series

## Executive Summary

This experiment series asks a genuinely interesting question: does entity naming in code shape how AI agents reason about that code? The data shows some real signal, but the experimental design has serious confounds that the analyses consistently understate. The strongest findings are plausible but not proven by this data. The weakest findings are narrative-driven pattern-matching on sample sizes too small to support them.

---

## 1. The Elephant in the Room: These Apps Are Not "Structurally Identical"

Every summary repeats the claim that the two apps are "structurally identical except for naming." This is false, and it matters.

The Request app has:
- **8 services** vs the Order app's **6 services** (extra: `CreateAcceptedService`, `DeclineService`)
- **9 states** vs **6 states** (extra: `created_accepted`, `declined`, `missed`)
- **An additional API endpoint** (`POST /api/requests/direct`)
- **Different state transition semantics** (e.g., Request has `accept`/`decline`/`miss` events; Order has `confirm`)
- **More mailer templates** (9 vs 7)

These are not naming differences. They are structural differences. The Request app has a larger and more complex codebase surface area. When the analysis for Experiment 05 reports that Request runs were more likely to create a dedicated `AutoAssignService` (3/6 vs 1/6), this could simply be because the Request app already has more services, establishing a pattern the AI follows. When Experiment 06 reports that Request runs added more PaymentGateway methods (5/6 vs 2/6), this could be the AI mimicking the Request app's more elaborated service layer, not responding to the word "Request."

The CLAUDE.md project instructions (hidden during runs but available at the repo root via `.CLAUDE.md.hidden`) explicitly state: "Request app has extra services: CreateAcceptedService, DeclineService" and "Request app has extra API endpoint." The experiment design acknowledges the structural difference but the analyses consistently attribute behavioral differences to naming rather than structure.

**This is the single most important methodological issue.** The experiment confounds naming with structural complexity. You cannot isolate the naming effect because the thing named differently also IS different.

---

## 2. The "Blind Analysis" Was Not Blind

The `analyze.sh` script labels runs as "App A" and "App B" in its prompt to the analyzer. However:

- Each run file's header contains `# App: order | Model: opus | Run: 1` or `# App: request | Model: sonnet | Run: 2`
- The AI-generated content in every run file uses the words "Order" or "Request" extensively (e.g., `order-opus-1.md` contains 95 mentions of "Order/order")
- The code diffs reference `Orders::CreateService` vs `Requests::CreateService`, `orders_controller` vs `requests_controller`, etc.

The analyzer could trivially determine which app was which from the content itself. Labeling this "blind" overstates the rigor. At best, the analyzer was told to compare "App A" vs "App B" but could immediately see what each was. The analysis text itself freely refers to "Order" and "Request" naming in its interpretations, confirming the analyzer used this information.

---

## 3. Experiment-by-Experiment Assessment

### Experiment 01 (Describe System) -- Mostly Tautological

**Claim:** Order runs used "confirms" language; Request runs used "accepts/declines" language.

**Assessment: This is a tautology, not a finding.** The Order app literally has a `confirm` event. The Request app literally has `accept` and `decline` events. The AI described what exists. It would be wrong to say "the Order app's provider accepts or declines" because the Order app has no `accept` or `decline` event. The 8/8 vs 6/6 split on "confirms" vs "accepts/declines" reflects the code, not a naming-induced framing effect.

The meta-context finding (67% of Request runs discussed the experiment vs 12% of Order runs) is more interesting but has a simpler explanation: the Request app's `created_accepted` state and `DeclineService` are genuinely unusual constructs that invite explanation. An Order app with 6 clean states needs no explanation. This is a complexity effect, not a naming effect.

**Verdict: Weak.** The findings are real but the causal attribution is wrong.

### Experiment 02 (Rebook Feature) -- Strongest Finding, But Confounded

**Claim:** 4/6 Order runs added `rebookable?` state gating; 0/6 Request runs did.

**Assessment: This is the most striking quantitative result in the series.** The 4/0 split is hard to dismiss as noise. However, the causal story is not as clean as presented.

The Order app has 3 clean terminal states: `completed`, `canceled`, `rejected`. It is trivial to reason about "which of these 3 allow rebooking?" The Request app has 5 potential terminal states: `fulfilled`, `declined`, `missed`, `canceled`, `rejected`. Some of these (`declined`, `missed`) have ambiguous rebookability semantics -- was a declined request never actually serviced? Is a missed request rebookable? The Request app's state complexity may have discouraged state gating not because the name "Request" suppresses reasoning, but because the actual state machine is harder to reason about correctly.

The summary's claim that "Legacy naming didn't cause errors -- it suppressed reasoning" is a stretch. An equally valid interpretation: "A more complex state machine made the AI correctly cautious about adding eligibility rules it wasn't sure about."

The testing gap (12.3 vs 5.2 average tests, 0/6 vs 2/6 runs with zero tests) is notable but also confounded: if the AI skipped state gating, there's simply less to test.

**Verdict: Moderate.** The pattern is real. The causal attribution to naming specifically (vs state machine complexity) is unproven.

### Experiment 03 (Propose Different Time) -- Strongest Causal Evidence

**Claim:** 6/6 Request runs treated decline as terminal (-> `declined`); Order runs split 2/6 to `pending`, 3/6 to `canceled`, 1/6 to `rejected`.

**Assessment: This is the most convincing finding in the series.** The Request app has a pre-existing `decline` event that transitions to `declined`. Every AI agent mapped "decline the counter-proposal" onto this existing concept. The Order app has no `decline` event, creating genuine design ambiguity.

This is a clean demonstration of existing vocabulary acting as a semantic anchor. But note: this is a structural difference (the Request app has a `decline` event; the Order app does not), not purely a naming difference. The analysis correctly identifies this as "the existing decline event providing a clear semantic anchor" but the summaries reframe it as a naming effect.

The state name convergence claim (`counter_proposed` in 4/6 Request runs vs scattered names in Order) is a weak signal that could be noise at N=6.

**Verdict: Strong pattern, but it demonstrates structural anchoring, not naming effects per se.**

### Experiment 04 (Bulk Booking) -- The Null Result

**Claim:** Naming had no effect.

**Assessment: This is the most honest analysis in the series.** When the prompt was specific enough ("book 5 sessions at once"), both apps produced near-identical solutions. The analysis correctly notes this shows "specific, well-scoped prompts neutralize naming effects."

However, this also serves as an important control: it shows that the AI does not always behave differently across the two apps. If the differences in other experiments were pure noise, we would expect to see them here too. The null result in Experiment 04 strengthens (slightly) the signal in other experiments.

**Verdict: Sound. This is a useful data point.**

### Experiment 05 (Auto-Assignment) -- Weak Signals Overinterpreted

**Claim:** Request naming nudged toward richer architectural thinking (service extraction 3/6 vs 1/6, 422 vs 404 error codes).

**Assessment:** The service extraction difference (3/6 vs 1/6) is confounded by the Request app already having more services. The AI is pattern-matching the existing architecture, not responding to the name "Request."

The 422 vs 404 difference (5/6 vs 3/6) is interesting but the sample is tiny. The "booking" vocabulary finding (4/6 vs 0/6 using the word "booking" spontaneously) is the most interesting signal here -- but could also be explained by the Request app's state names (`accepted`, `fulfilled`, `started`) sounding more like a booking/appointment system than the Order app's (`confirmed`, `in_progress`, `completed`) which sound more transactional.

The summary's claim that model choice "mattered far more than naming" is correct and somewhat undermines the rest of the findings.

**Verdict: Weak. The strongest signal (vocabulary) is interesting but other signals are confounded.**

### Experiment 06 (Cancellation Fee) -- Analysis Error Found

**Claim:** 5/6 Request runs added a `charge_cancellation_fee` gateway method vs 2/6 Order runs. Two Request/Sonnet runs destructively mutated `amount_cents`; zero Order runs did.

**Assessment:** The gateway method pattern (5/6 vs 2/6) is again confounded by the Request app's more elaborate service landscape.

More importantly, **the "zero Order runs mutated amount_cents" claim is incorrect.** `order-opus-2` does `@order.payment.update!(amount_cents: @order.cancellation_fee_cents)` -- it records the fee on the order model first, but then destructively overwrites the payment's `amount_cents` with the fee value, exactly the same net effect as `request-sonnet-2` and `request-sonnet-3`. The analysis classified order-opus-2 differently because it adds a column to the orders table, but the payment mutation is identical. The correct count is 1/6 Order vs 2/6 Request for destructive payment mutation -- still directional, but not the clean 0-vs-2 claimed.

**Verdict: The gateway method pattern is moderate but confounded. The destructive mutation claim is factually inaccurate.**

### Experiment 07 (Happy Path) -- Real But Explained by Complexity

**Claim:** Request runs discussed legacy states, speculated about design history; Order runs stayed focused.

**Assessment:** This is real and consistent (4/6 Request runs discussed `created_accepted`, 0/6 Order runs flagged anything unusual). But the explanation is straightforward: the Request app objectively has unusual constructs (`created_accepted` is a genuinely weird state name). The Order app does not. The AI discussed unusual things because they were unusual, not because the entity was named "Request."

The "Sonnet + Request = maximum scope creep" observation is interesting but only tests one interaction -- Sonnet may simply be more prone to discussing unusual constructs, and the Request app has more of them.

**Verdict: Real pattern, simpler explanation than naming affordance.**

---

## 4. Statistical Rigor

With 3 runs per model per app (6 total per app), the experiments cannot support most of the claims made:

- A 4/6 vs 0/6 split (Experiment 02, rebookable?) has a Fisher's exact test p-value of ~0.06 -- suggestive but not significant at conventional thresholds.
- A 6/6 vs 4/6 split (Experiment 03, terminal decline) has a p-value of ~0.45 -- not significant. However, the 6/6 vs 2/6 "back to pending" split is p ~0.06.
- A 5/6 vs 2/6 split (Experiment 06, gateway methods) has p ~0.24.
- The Experiment 04 null result is consistent with the hypothesis that some prompts eliminate the effect, but it is also consistent with no effect existing at all.

The analyses hedge with phrases like "moderate confidence" and "small sample," which is appropriate. But the summaries then proceed to draw strong causal conclusions. The summary for Experiment 02 states categorically: "Legacy naming didn't cause errors -- it suppressed reasoning." This is not supported by 6 data points per group with a known confound.

---

## 5. What IS Well-Supported

Despite the above criticisms, some findings survive scrutiny:

1. **The AI's behavior was not random.** The Order and Request apps consistently produced different outputs across multiple experiments. Something real is different about working with these two codebases.

2. **Existing vocabulary acts as a semantic anchor** (Experiment 03). When the Request app had a `decline` event, 6/6 runs reused it. When the Order app lacked one, solutions diverged. This is well-demonstrated.

3. **Prompt specificity modulates the effect** (Experiment 04). Concrete, prescriptive prompts eliminated measurable differences. Open-ended or ambiguous prompts amplified them.

4. **Model choice (Opus vs Sonnet) is a stronger variable than app choice.** This was acknowledged in most analyses.

5. **More complex codebases produce more elaborate AI outputs.** This is the simplest explanation for many findings and is well-supported across experiments.

---

## 6. What Is NOT Well-Supported

1. **That naming per se causes the observed differences.** Naming is confounded with structural complexity (more states, more services, more endpoints). The experiment cannot separate these.

2. **That "Request" suppresses reasoning** (Experiment 02 summary claim). An equally valid interpretation is that complex state machines make the AI appropriately cautious.

3. **That legacy naming steers AI toward the original designer's mental model.** This is the framing of several summaries, but the data equally supports "AI agents respond to structural complexity, not names."

4. **Any claim at the individual-run level.** With N=3 per condition, outliers (like `order-sonnet-3` in Experiment 03 or `request-sonnet-2` in Experiment 07) carry disproportionate weight. They are anecdotes, not evidence.

---

## 7. Follow-Up Experiment Design

To actually isolate naming from structure, a follow-up would need:

### Fix the Confound
Create a third app: **"Request" naming with Order's clean state machine** (6 states, no `created_accepted`, no `decline`/`miss`). This separates the naming variable from the structural variable. If "Request + clean states" behaves like Order, the effect is structural. If it behaves like the current Request app, the effect is naming.

### Increase Sample Size
10+ runs per condition minimum. With 3 runs, you cannot distinguish a real 70/30 tendency from a 50/50 coin flip that happened to come up 2-1.

### Fix the Blind Analysis
Strip app-identifying information from run files before analysis. Remove headers, replace "Order"/"Request" with "Entity" in the output text, replace service names. This is not trivial but is necessary for the "blind" label to mean anything.

### Control for Model
Run a single model (not both Opus and Sonnet) to eliminate the model-as-confound issue. The Opus/Sonnet split halves an already small sample. If you want to study model differences, that is a separate experiment.

### Add Objective Metrics
"Did the code pass tests?" "Does it compile?" "Does it handle the edge case X?" Subjective assessment of "domain modeling depth" or "architectural richness" is analyst-dependent and not reproducible.

### Remove Meta-Context
The `docs/superpowers/specs/` directory contains design documents describing the experiment itself. While CLAUDE.md was hidden, these spec files were accessible from the repo root. Any AI agent that explored the parent directory could discover the experiment's purpose, contaminating its behavior.

---

## 8. Bottom Line

This experiment series demonstrates that two Rails apps with different internal complexity produce different AI outputs. That is unsurprising. The interesting hypothesis -- that the *name* of the central entity, independent of structural differences, shapes AI reasoning -- is not tested cleanly because naming and structure co-vary. The strongest individual finding (Experiment 03's decline-behavior convergence) actually demonstrates structural anchoring (the presence or absence of a `decline` event), not naming effects. The most frequently cited finding (Experiment 02's rebookable gap) is suggestive but confounded and statistically marginal.

The experiment is well-executed as an exploratory study. The run infrastructure, the analysis pipeline, and the breadth of prompts tested are impressive. But the summaries over-claim. They present a compelling narrative ("naming is an affordance that shapes AI reasoning") and fit the data to it, when the data is equally consistent with a more mundane explanation ("more complex codebases produce different AI behavior than simpler ones"). A follow-up that controls for structural complexity would determine which explanation is correct.
