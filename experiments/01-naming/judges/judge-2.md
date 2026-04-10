# Independent Review: Affordance Naming Experiment

**Reviewer:** Claude Opus 4.6 (independent review, not involved in original runs or analysis)
**Date:** 2026-04-07
**Scope:** All 7 experiments, 82 total runs, raw data and blind analyses

---

## Executive Summary

The experiment demonstrates that entity naming has real but situational effects on AI-generated code. The effects are strongest when the task requires the agent to make design judgments (state machine design, domain modeling, eligibility rules) and weakest when the task is mechanically specified (bulk creation, fee calculation). Across most experiments, the Opus-vs-Sonnet capability gap is a larger source of variation than the Order-vs-Request naming difference. The existing analyses are generally accurate but occasionally overstate naming effects where model-level confounding is the more parsimonious explanation.

---

## 1. Where Naming Mattered

### Strong evidence: State-based reasoning (Experiment 02 -- Rebook)

This is the single most compelling finding across all seven experiments. Order runs added state-eligibility checks (`rebookable?`) in 4/6 runs. Request runs added them in 0/6 runs. I verified this against the raw diffs: `order-opus-1`, `order-opus-2`, `order-opus-3`, and `order-sonnet-3` (at minimum -- the analysis counts `order-opus-2` which has `unless @original_order.completed? || @original_order.canceled?` inline rather than a named predicate, which I'll count as state gating). No Request run contains any equivalent check.

The mechanism is plausible: Order's 6 clean states with 3 clear terminal states (completed, canceled, rejected) make it obvious which states "should" allow rebooking. Request's 9 states, with ambiguous terminal-vs-active boundaries (is `created_accepted` terminal? is `missed`?), apparently discourage the agent from attempting lifecycle reasoning at all. The agent doesn't get the logic wrong -- it skips the question entirely.

**Practical consequence:** A team using AI to build on the Request codebase would ship a rebook feature with no state guards. Any request, even one currently in progress, could be rebooked. This is a real bug that a code reviewer would need to catch.

### Strong evidence: Decline semantics as anchor (Experiment 03 -- Propose Different Time)

All 6 Request runs transitioned decline-of-proposal to `declined` (terminal). Order runs split: 2/6 went back to `pending`, 3/6 to `canceled`, 1/6 to `rejected`. The Request app's existing `decline` event provided an unambiguous semantic template that the Order app lacks.

I verified this in the raw AASM transitions. For example, `request-opus-1` adds `event :decline_proposal do transitions from: :provider_proposed, to: :declined end` -- reusing the existing `declined` state. Meanwhile `order-opus-1` adds `transitions from: :provider_proposed_time, to: :pending` and `order-opus-3` also goes to `pending`. The Order app has `reject` but not `decline`, so the agents must invent semantics rather than reuse them.

**Practical consequence:** The Request app produces more consistent designs across independent AI runs -- a team running the same prompt three times would get the same state machine. The Order app produces divergent designs, requiring more human alignment work.

This is the one case where legacy naming *helps*. The existing analyses correctly identify this.

### Moderate evidence: Provider agency framing (Experiments 01, 07)

Every Order run (8/8 in Exp 01) used "confirms" for the provider action. Every Request run (6/6) used "accepts or declines." This is a clean split with zero overlap. In Experiment 07 (happy path), Request runs described social dynamics while Order runs described mechanical workflows.

This matters less for code generation than for documentation, onboarding materials, and API naming. If an AI agent writes your API docs, the entity name will shape whether the provider is described as having choice or merely rubber-stamping.

### Moderate evidence: Test coverage gap (Experiment 02)

Order runs averaged ~12 new tests; Request runs averaged ~5. Two Request-Sonnet runs shipped zero test files. Zero Order runs shipped without tests. I verified `request-sonnet-1` and `request-sonnet-3` -- both have diffs with no spec files at all.

However, I'm less confident this is purely a naming effect. The two zero-test runs are both Sonnet-on-Request. Sonnet-on-Order runs also had fewer tests than Opus-on-Order. The confound is model capability, not just naming. Still, the fact that both zero-test runs are Request-side and neither is Order-side is directionally meaningful.

---

## 2. Where Naming Did Not Matter

### No effect: Bulk booking (Experiment 04)

The analyses are correct here. Both apps produced structurally identical solutions with near-identical LOC, test counts, parameter patterns, and authorization models. The prompt ("book 5 sessions at once, weekly recurring") is specific enough to eliminate interpretive latitude. The two scope-creep outliers (bulk_id, recurrence enum) both came from Order-Opus runs, but at N=1 each, this is noise.

**Key insight:** Specific, well-scoped prompts neutralize naming effects. When the AI has no room to interpret intent, entity naming becomes a string substitution.

### Weak effect: Cancellation fee core logic (Experiment 06)

All 12 runs implemented the same business rule correctly: 24-hour check, 50% of amount_cents. Naming had zero effect on comprehension. The architectural layering difference (Request runs adding `charge_cancellation_fee` gateway methods at 5/6 vs 2/6 for Order) is real but I attribute it partly to the Request app already having more services (`CreateAcceptedService`, `DeclineService`) -- the AI pattern-matches the existing code structure, not just the entity name.

### Weak effect: Auto-assignment (Experiment 05)

The analysis claims naming nudged Request toward richer architectural thinking (3/6 new service files vs 1/6 for Order). But the schedule-conflict checking difference (4/6 vs 3/6) is a single extra Sonnet run -- too thin to draw conclusions. The 422-vs-404 error code split (5/6 Request use 422 vs 3/6 Order) is the most interesting signal here, but I note the analysis itself rates this as "low-to-moderate" confidence, which I agree with.

---

## 3. Naming vs. Model Differences

This is where I most disagree with the emphasis in the existing summaries. Several summaries frame the findings as "naming shaped domain reasoning" when the data more often shows "Opus shaped domain reasoning, and naming provided a secondary nudge."

**Schedule conflict checking (Experiment 05):** 6/6 Opus runs checked conflicts vs 1/6 Sonnet. This is a 100%-vs-17% split on the model axis. The naming axis (4/6 Request vs 3/6 Order) is a 67%-vs-50% split. The model effect is 5x larger than the naming effect.

**Service delegation in rebook (Experiment 02):** The analysis reports Order delegating to CreateService at 67% vs Request at 33%. But Opus-Order delegates 3/3 (100%) while Sonnet-Order delegates 1/3 (33%). And Opus-Request delegates 1/3 (33%) while Sonnet-Request delegates 1/3 (33%). The real pattern is: Opus-on-Order always delegates, everything else delegates about a third of the time. This is a model-x-naming interaction, not a pure naming effect.

**State gating in rebook (Experiment 02):** This is the exception. The 4/6 vs 0/6 split holds across both models: Opus-Order adds state checks (3/3), Sonnet-Order adds them in 1/3 runs, but Request never does (0/3 Opus, 0/3 Sonnet). Here naming is the dominant variable.

**Scope creep in happy path (Experiment 07):** The analysis notes Sonnet-Request produces maximum scope creep. But this is really a Sonnet effect amplified by Request naming: Sonnet-Order also tends toward more structural output than Opus-Order. Request naming turns up the volume on tendencies that already exist within each model.

**My summary:** Model choice (Opus vs Sonnet) determines the *quality ceiling* -- how thorough the implementation is, how many edge cases are handled, how many tests are written. Naming determines the *interpretation frame* -- what the agent assumes about the domain, which design paths it considers, and whether it attempts lifecycle reasoning at all. Both matter, but for different reasons.

---

## 4. Disagreements with Existing Analyses

### The "Request suppresses reasoning" narrative is too strong

The Experiment 02 summary states: "Legacy naming didn't cause errors -- it suppressed reasoning." This is accurate for state gating but I'd frame it differently. The Request app's complex states didn't suppress reasoning -- they presented a more complex reasoning task that the agents chose not to attempt. There's a difference between "the name discouraged thought" and "the state space was genuinely harder to reason about."

Consider: if you have 9 states and need to decide which ones allow rebooking, you must evaluate each one. With 6 states and 3 obvious terminal states, the decision is trivial. The agents' choice to skip the question in the Request app may be rational avoidance of a legitimately ambiguous design decision, not a naming-induced failure.

### Experiment 03 understates the positive finding for legacy naming

The Experiment 03 summary correctly notes that Request produced more consistent decline behavior (6/6 terminal vs Order's split). But it buries this as a secondary finding. I'd promote it: this is the clearest evidence that legacy naming can be *beneficial* by providing semantic scaffolding that clean naming lacks. The word "decline" in the Request codebase gives AI agents a ready-made concept to reuse; the Order codebase forces them to invent one, producing inconsistent results.

### The "booking" synonym finding (Experiment 05) needs more skepticism

The analysis highlights that "booking" appeared in 4/6 Request runs and 0/6 Order runs. I checked the raw data and confirmed this. But I'm not convinced it indicates deeper domain understanding. The word "booking" may simply feel like a natural synonym for "request" in a scheduling context but not for "order." This is a linguistic association, not evidence of richer architectural thinking.

### Destructive mutation finding (Experiment 06) is intriguing but fragile

Two Request-Sonnet runs destructively mutated `payment.amount_cents`. The analysis suggests Request naming makes amounts feel more mutable. This is a provocative claim built on N=2. I'd note it as a data point worth watching in future experiments but not something to base decisions on.

### Experiment 01 has an unbalanced sample

Experiment 01 had 8 Order runs (5 Sonnet + 3 Opus) vs 6 Request runs (3 Sonnet + 3 Opus). The analyses sometimes report percentages without noting this asymmetry. The extra Order-Sonnet runs don't invalidate findings but should be flagged as a methodological imperfection.

---

## 5. What I Would Tell a Team Lead

**The short version:** Renaming legacy entities will not make AI agents write better code in mechanical, well-specified tasks. It will make them produce more consistent domain reasoning in open-ended design tasks. Whether that's worth the investment depends on how you use AI in your workflow.

**The longer version:**

1. **If your team uses AI primarily for well-defined implementation tasks** (add this endpoint, add this validation, create this CRUD) -- renaming has minimal payoff. Experiments 04 and 06 show that specific prompts produce equivalent results regardless of naming.

2. **If your team uses AI for design exploration or feature scoping** -- legacy naming creates measurable divergence. The rebook experiment shows agents skipping domain-modeling questions when state names are complex. The propose-time experiment shows agents producing inconsistent state machine designs when they lack semantic anchors. A team reviewing AI-generated designs would spend more time aligning divergent approaches.

3. **The most actionable finding is about state machines, not names.** The biggest effect wasn't the entity name itself -- it was the clarity of the state space. "Order" with 6 clean states invited lifecycle reasoning; "Request" with 9 legacy states discouraged it. If you can't rename the entity, you can still clean up the state machine. Reducing the number of states, eliminating dead states, and making terminal states obvious would likely capture most of the benefit.

4. **Consider the interaction with model capability.** Opus handled both codebases competently -- the naming effects were smaller for Opus than for Sonnet. As AI models improve, naming effects may shrink. Investing heavily in renaming to accommodate today's models may be fighting a retreating problem.

5. **Legacy naming has one overlooked advantage.** The Request app's existing `decline` event gave agents better scaffolding for the counter-proposal feature (Experiment 03). Sometimes the messy, historically-evolved vocabulary carries semantic information that a clean rename would discard. Before renaming, ask: does the legacy name encode domain knowledge that the replacement wouldn't?

6. **The real risk is not errors but omissions.** Across all experiments, naming never caused agents to produce incorrect code. It caused them to produce *less thorough* code -- skipping state checks, writing fewer tests, avoiding domain modeling. These are precisely the kinds of gaps that slip through code review because the code that's there works fine. The missing code is the problem.

---

## 6. Methodological Notes

- The CLAUDE.md file was hidden during runs (`run.sh` moves it to `.CLAUDE.md.hidden`), preventing agents from seeing the experiment framing. This is good practice but I note that the project-level CLAUDE.md mentions "affordance test" and "Order/Request naming" -- if any of that leaked through other channels (git history, file names, etc.), it could contaminate results. Experiment 01 Opus runs mentioning the "experiment" suggest some leakage may have occurred, possibly through doc files in the codebase.

- The sample sizes (3 runs per model per app per experiment) are small enough that single outliers can dominate aggregate statistics. Many of the "moderate" findings would not survive a larger replication.

- The experiments were run sequentially with branch resets between runs, but for code experiments the agent sees the full codebase including any artifacts from previous experiment branches that were merged to main. The analysis notes some schema.rb leakage (Experiment 05 picking up Experiment 02's columns). This is minor but worth noting.

- Experiment 01's unbalanced sample (5 vs 3 Sonnet runs) slightly undermines percentage-based comparisons for that experiment.

---

## Confidence-Ranked Findings

| Rank | Finding | Evidence Strength | Naming Effect Size |
|------|---------|-------------------|-------------------|
| 1 | Clean states invite lifecycle reasoning; complex states suppress it | 4/6 vs 0/6 across both models (Exp 02) | Large |
| 2 | Existing events serve as semantic anchors for new features | 6/6 vs 4/6 terminal decline (Exp 03) | Large |
| 3 | Entity name shapes provider-agency framing | 8/8 vs 6/6, zero overlap (Exp 01) | Medium (affects docs, not code) |
| 4 | Request naming reduces test thoroughness in rebook | 12.3 vs 5.2 avg tests (Exp 02) | Medium, confounded by model |
| 5 | Specific prompts neutralize naming effects entirely | Near-identical outputs (Exp 04) | None |
| 6 | Model choice (Opus vs Sonnet) dominates naming effects | Consistent across Exp 02-06 | N/A (different axis) |
| 7 | Legacy naming triggers meta-context seeking | 67% vs 12% mention experiment (Exp 01) | Medium |
| 8 | Request naming encourages more gateway abstractions | 5/6 vs 2/6 new gateway methods (Exp 06) | Small, confounded by existing code patterns |
| 9 | Request naming risks destructive data mutations | 2/6 vs 0/6 (Exp 06) | Small, N too low |
