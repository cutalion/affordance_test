# How Entity Naming Shapes AI Agent Reasoning

## Cross-Experiment Report

**Date:** 2026-04-07
**Scope:** 7 experiments, 86 runs (Claude Opus and Sonnet, 3 runs each per model per app), 3 independent judge reviews

---

## Executive Summary

Two structurally related Rails booking apps — one calling its central entity "Order" (with 6 clean states), the other calling it "Request" (with 9 legacy invitation-era states) — were given identical prompts across 7 experiments. AI agents produced measurably different outputs depending on which app they worked with. The differences were not in comprehension (no agent misunderstood either app) but in design judgment: which abstractions to create, which states to reason about, which features to add unprompted, and how to frame the domain narrative.

Three independent reviewers agreed on the core finding but disagreed sharply on its cause. The central question — whether the differences are driven by **naming** ("Order" vs "Request") or by **structural complexity** (6 clean states vs 9 messy states, 6 services vs 8 services) — cannot be resolved by this experiment alone. The two variables co-vary by design, as they do in real codebases.

**What is well-supported:** AI agents respond differently to these two codebases in consistent, replicable ways. Existing vocabulary constrains new designs. Prompt specificity modulates the effect. Model capability (Opus vs Sonnet) explains more variance than app differences.

**What is not proven:** That the entity *name* per se, independent of structural complexity, drives the observed effects.

**What is practically relevant regardless:** Engineering teams using AI agents should treat their naming conventions and state machine designs as inputs to AI reasoning — because that is what they are, whether the mechanism is "naming" or "structure" or both.

---

## Methodology

### Design

| Component | Detail |
|---|---|
| Apps | `affordance_order/` (Order, 6 states, 6 services) and `affordance_request/` (Request, 9 states, 8 services) |
| Models | Claude Opus 4.6, Claude Sonnet 4.6 |
| Runs per cell | 3 (= 12 runs per experiment, 84 total for experiments + 2 extra from pilot) |
| Experiment types | 2 readonly (describe, happy path) + 5 code-writing (rebook, counter-proposal, bulk booking, auto-assignment, cancellation fee) |
| Isolation | CLAUDE.md hidden during runs; `--disable-slash-commands`; fresh git branch per code run |
| Analysis | Blind comparison (App A / App B) followed by unblinded summary |

### Known Limitations

**1. Naming and structure are confounded.** The Request app is not merely renamed — it has 3 extra states, 2 extra services, 1 extra API endpoint, and different transition semantics. Many observed effects could be the AI responding to the larger codebase surface, not the name. (All three judges flagged this; Judge 3 called it "the single most important methodological issue.")

**2. The blind analysis was not truly blind.** Run file headers contained `# App: order` / `# App: request`, and the AI-generated content used entity names throughout. The analyzer could determine which app was which from content alone. (Judge 3)

**3. Sample sizes are small.** With N=3 per model per app, no individual finding reaches conventional statistical significance. The strongest result (4/6 vs 0/6 in Experiment 02) yields Fisher's exact p ~0.06. (Judge 3)

**4. Experiment 01 has unbalanced samples.** 8 Order runs (5 Sonnet + 3 Opus) vs 6 Request runs due to a pilot configuration. (Judge 2)

**5. Meta-context leakage.** The `docs/superpowers/specs/` directory contained design documents describing the experiment itself. While CLAUDE.md was hidden, these files were accessible from the repo root. Some Experiment 01 runs referenced the "experiment" and "sibling app," suggesting possible contamination. (Judge 3)

---

## Findings by Confidence Level

### Tier 1: Well-Supported (all three judges concur)

#### Existing code vocabulary constrains new feature design

**Experiment 03 (counter-proposal).** The Request app has a pre-existing `decline` event (created -> declined). All 6 Request runs mapped "client declines the counter-proposal" onto this existing transition — terminal, no negotiation loop. The Order app has no `decline` event. Order runs scattered: 2/6 returned to `pending` (allowing re-negotiation), 3/6 went to `canceled`, 1/6 to `rejected`.

The two Order-Opus runs that chose `pending` (order-opus-1, order-opus-3) produced arguably the most flexible design — a negotiation loop. But no Request run even considered this option. The existing `decline` event acted as a semantic anchor that foreclosed alternatives.

**Judge consensus:** All three judges rated this the most convincing causal finding. Judge 3 notes it demonstrates *structural* anchoring (presence/absence of a `decline` event) rather than naming per se — a valid distinction.

#### Clean state machines invite lifecycle reasoning; complex ones suppress it

**Experiment 02 (rebook).** 4/6 Order runs added a `rebookable?` predicate checking which terminal states allow rebooking. 0/6 Request runs added any state eligibility check. Verified across raw diffs: order-opus-1 adds `rebookable?` checking completed/canceled/rejected with 7 tests; request-opus-1 copies fields into `Request.new` with no state guards.

This held across both models: Opus-Order 3/3, Sonnet-Order 1/3, Opus-Request 0/3, Sonnet-Request 0/3. The naming/complexity variable dominates the model variable for this specific behavior — a rarity in this dataset.

**Debate on cause:** Judge 1 attributes this to "legacy complexity suppressing domain reasoning." Judge 2 reframes: "the state space was genuinely harder to reason about — the AI may have been appropriately cautious." Judge 3 calls it "suggestive but confounded." The practical consequence is the same: a team using AI on the Request codebase would ship a rebook feature with no state guards.

#### Prompt specificity neutralizes codebase differences

**Experiment 04 (bulk booking).** Both apps produced structurally identical solutions: a service class wrapping a transaction, a `/bulk` endpoint, the same parameters, comparable test coverage (~6-7 tests), near-identical LOC (63 vs 61). The prompt ("book 5 sessions at once, weekly recurring") left no room for interpretation.

**All judges agree** this is the most methodologically informative result. It serves as a control: it shows that differences in other experiments are not pure noise (if they were, Experiment 04 would show them too). It also establishes a practical principle: specific prompts produce equivalent results regardless of naming.

#### Model choice explains more variance than app choice

Across every experiment where both variables were measured, Opus vs Sonnet produced larger and more consistent differences than Order vs Request:

| Behavior | Model effect | App effect |
|---|---|---|
| Schedule conflict checking (Exp 05) | Opus 6/6, Sonnet 1/6 (83% gap) | Request 4/6, Order 3/6 (17% gap) |
| Service delegation in rebook (Exp 02) | Opus-Order 3/3, others ~1/3 | Confounded with model |
| Test thoroughness (Exp 02) | Opus > Sonnet consistently | Order > Request consistently |
| Scope creep (Exp 07) | Sonnet amplifies; Opus stays disciplined | Request triggers more |

Judge 2's framing: "Model choice determines the *quality ceiling*. Naming determines the *interpretation frame*. Both matter, but for different reasons."

---

### Tier 2: Consistent Direction, Debated Cause

#### Entity name shapes domain narrative

**Experiments 01 and 07 (readonly).** Every Order run (8/8 in Exp 01) described the provider's role as "confirming." Every Request run (6/6) described it as "accepting or declining." In Experiment 07, Request runs used relational language ("reviews and accepts," "signals commitment") while Order runs used mechanical language ("confirms," "starts," "completes").

**Judges split:** Judge 3 calls this "tautological — the Order app literally has a `confirm` event; the Request app has `accept` and `decline`. The AI described what exists." Judges 1 and 2 see it as meaningful: the same underlying business logic (provider agrees to do the job) was framed as rubber-stamping vs genuine choice, which would shape documentation, API design, and feature proposals.

#### Legacy naming triggers explanatory behavior

In Experiment 01, 67% of Request runs pulled in meta-context (mentioning the experiment, the sibling app, or "invitation era" origins) vs 12% of Order runs. In Experiment 07, all 3 Sonnet-Request runs discussed the `created_accepted` state unprompted; 0/3 Sonnet-Order runs flagged anything unusual.

**Practical implication (if real):** Legacy-named codebases cause AI agents to spend tokens and attention on archaeology — explaining why naming is the way it is — rather than answering the prompt. Clean codebases avoid this overhead.

**Counterpoint (Judge 3):** The Request app objectively has unusual constructs (`created_accepted`). The AI discussed unusual things because they were unusual, not because the entity was named "Request."

#### More complex codebases produce more elaborated AI outputs

In Experiment 06 (cancellation fee), Request runs added a dedicated `charge_cancellation_fee` gateway method in 5/6 runs vs 2/6 for Order. In Experiment 05 (auto-assignment), Request runs created a dedicated `AutoAssignService` in 3/6 vs 1/6 for Order.

**Judge 3's explanation:** The Request app already has more services (8 vs 6). The AI is pattern-matching the existing code structure, adding more named methods because the codebase already has more. This is mimicry, not naming-induced reasoning.

**Judges 1 and 2 partially agree** but note that the naming and the structure co-evolved — the extra services exist *because* of the invitation-era design. In practice, the distinction may not matter.

---

### Tier 3: Fragile or Disputed

#### Destructive data mutation correlated with Request app

In Experiment 06, the original analysis claimed 2/6 Request runs and 0/6 Order runs destructively overwrote `payment.amount_cents` with the cancellation fee. **Judge 3 found a factual error:** order-opus-2 also performs this mutation (`@order.payment.update!(amount_cents: @order.cancellation_fee_cents)`), making the actual count 1/6 Order vs 2/6 Request. Still directional, but not the clean split originally claimed. At N=3, this is anecdotal.

#### "Booking" vocabulary activation

In Experiment 05, the word "booking" appeared spontaneously in 4/6 Request runs and 0/6 Order runs. Judge 1 sees this as evidence that naming activates training-corpus associations ("request" evokes scheduling/booking domains). Judge 2 notes it could be a linguistic association rather than deeper understanding. Judge 3 points out that Request's state names (`accepted`, `fulfilled`, `started`) sound more like appointments than Order's (`confirmed`, `in_progress`, `completed`).

#### Test coverage gap

In Experiment 02, Order runs averaged ~12 tests vs ~5 for Request, with 2 Request-Sonnet runs shipping zero tests. All three judges agree this is likely a *downstream consequence* of the state-gating gap (more state checks = more things to test), not an independent naming effect.

---

## The Central Debate: Naming or Structure?

The three judges represent three positions on a spectrum:

**Judge 1 (pattern finder):** "Naming is an affordance that operates in the gap between what the prompt says and what the code implies." Naming shapes the *interpretation frame* — which design paths the AI considers, which associations it activates. The structural differences are real but secondary to the semantic signal.

**Judge 2 (practical advisor):** "The most actionable finding is about state machines, not names." The biggest effect was the clarity of the state space (6 clean states inviting reasoning vs 9 messy states discouraging it). If you can't rename the entity, cleaning up the state machine would capture most of the benefit. But naming carries independent semantic weight — "decline a request" has clear meaning; "decline an order" is ambiguous.

**Judge 3 (skeptic):** "The data is equally consistent with a more mundane explanation: more complex codebases produce different AI behavior than simpler ones." The experiment cannot separate naming from structure because they co-vary. The strongest finding (Exp 03 decline behavior) actually demonstrates structural anchoring (presence/absence of a `decline` event), not naming. A third app — "Request naming + clean states" — would be needed to isolate the variable.

### Synthesis

All three positions have merit. The experiment answers the *practical* question ("does your codebase's naming legacy affect AI output?") with a clear yes. It does not cleanly answer the *theoretical* question ("is it the word itself, or the structures the word implies?") because in real codebases, naming and structure always co-evolve.

For engineering teams, the practical question is what matters. Whether the mechanism is "the word Request" or "the 9-state machine that Request implies" or "the extra DeclineService that Request's history created," the end result is the same: AI agents working on the Request codebase produce different — and in some cases less thorough — output.

---

## Practical Recommendations

These recommendations synthesize all three judges' assessments, weighted by confidence level.

**1. Treat your codebase as a prompt.** Entity names, state machine designs, and existing service patterns are not just documentation — they are inputs that shape AI-generated code. This is the one finding all judges and all experiments agree on.

**2. Clean up state machines even if you can't rename entities.** The state-gating gap (Exp 02) and the decline-anchoring effect (Exp 03) are both driven by state machine clarity more than by the entity name itself. Reducing ambiguous states, eliminating dead states, and making terminal states obvious would likely improve AI output quality. (Judge 2's recommendation, endorsed by Judge 1)

**3. Write specific prompts for critical features.** Experiment 04 shows that precise, prescriptive prompts eliminate naming effects entirely. When the AI has no room to interpret intent, codebase naming becomes a string substitution. Reserve open-ended prompts for exploration; use specific prompts for production features.

**4. Review AI-generated code for omissions, not just errors.** Across all experiments, naming never caused incorrect code. It caused *less thorough* code — missing state guards, fewer tests, skipped domain modeling. These gaps are easy to miss in code review because the code that's there works fine.

**5. Be aware that legacy vocabulary can help.** Experiment 03 showed that the Request app's existing `decline` event produced more consistent counter-proposal designs than the Order app's clean-but-thin vocabulary. Before removing legacy naming, ask whether it encodes domain knowledge that the replacement wouldn't.

**6. Expect model improvements to reduce the effect.** Opus handled both codebases more competently than Sonnet — the naming effects were smaller for the stronger model. As models improve, naming effects may shrink. (Judge 2)

---

## Recommended Follow-Up Experiments

Based on Judge 3's critique, with input from Judges 1 and 2:

### Isolate the confound
Create a third app: **"Request" naming with Order's clean 6-state machine** (no `created_accepted`, no `decline`/`miss`). If "Request + clean states" behaves like Order, the effect is structural. If it behaves like the current Request, the effect is naming.

### Increase sample size
10+ runs per condition. With N=3, single outliers dominate tallies. The strongest finding (4/6 vs 0/6) has p ~0.06 — suggestive but not significant.

### Fix the blind analysis
Strip app-identifying information from run files. Replace "Order"/"Request" with a neutral placeholder in both code output and headers.

### Control for model
Run a single model per experiment to eliminate model-as-confound. Study model differences separately.

### Add objective metrics
Supplement subjective analysis with measurable outcomes: does the code pass tests? Does it handle specified edge cases? How many new files/lines/states were added?

---

## Experiment Results at a Glance

| # | Experiment | Type | Naming Effect | Confidence | Key Finding |
|---|---|---|---|---|---|
| 01 | Describe System | readonly | Framing shift | Moderate | "Confirms" (Order) vs "accepts/declines" (Request) — zero overlap |
| 02 | Rebook Feature | code | State reasoning suppressed | Strong | `rebookable?` added in 4/6 Order vs 0/6 Request |
| 03 | Counter-Proposal | code | Vocabulary anchoring | Strong | Decline = terminal in 6/6 Request vs 4/6 Order; 2 Order runs created negotiation loops |
| 04 | Bulk Booking | code | None | High | Specific prompt → identical outputs |
| 05 | Auto-Assignment | code | Weak nudge | Low-moderate | Service extraction 3/6 vs 1/6; 422 vs 404 error semantics |
| 06 | Cancellation Fee | code | Architectural layering | Moderate | Gateway methods 5/6 vs 2/6 (confounded by existing code patterns) |
| 07 | Happy Path | readonly | Scope and framing | Strong | Request runs discussed legacy states, added unsolicited context |

---

## Judge Agreement Matrix

| Finding | Judge 1 | Judge 2 | Judge 3 |
|---|---|---|---|
| Something real differs between apps | Yes | Yes | Yes |
| Exp 02 rebookable gap is strongest quantitative result | Yes | Yes | Yes (but confounded) |
| Exp 03 decline anchoring is most convincing causal evidence | Yes | Yes | Yes (structural, not naming) |
| Exp 04 null result is informative | Yes | Yes | Yes |
| Model > naming as variance source | Yes | Yes | Yes |
| Naming per se is proven as cause | Likely | Partially | No |
| Exp 05 analysis overstates naming effect | Yes | Yes | Yes |
| Exp 06 destructive mutation finding is reliable | Noted, fragile | Noted, fragile | Factual error found |
| Exp 01 framing shift is meaningful | Yes | Yes | Tautological |
| Legacy naming can help (Exp 03) | Overstated | Underreported | Structural, not naming |

---

## Appendix: Run Inventory

| Experiment | Order-Opus | Order-Sonnet | Request-Opus | Request-Sonnet | Total |
|---|---|---|---|---|---|
| 01-describe-system | 3 | 5* | 3 | 3 | 14 |
| 02-rebook-feature | 3 | 3 | 3 | 3 | 12 |
| 03-propose-different-time | 3 | 3 | 3 | 3 | 12 |
| 04-bulk-booking | 3 | 3 | 3 | 3 | 12 |
| 05-auto-assignment | 3 | 3 | 3 | 3 | 12 |
| 06-cancellation-fee | 3 | 3 | 3 | 3 | 12 |
| 07-happy-path | 3 | 3 | 3 | 3 | 12 |
| **Total** | **21** | **23** | **21** | **21** | **86** |

*Experiment 01 has 2 extra Order-Sonnet runs from an earlier pilot configuration.

---

*Report generated from 7 experiment analyses, 86 run files, and 3 independent judge reviews (judge-1.md, judge-2.md, judge-3.md). Individual experiment summaries are in each experiment's summary.md file.*
