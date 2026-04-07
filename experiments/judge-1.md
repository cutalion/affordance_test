# Independent Review of the Affordance Experiment

Reviewer: Claude Opus 4.6 (acting as independent judge)
Date: 2026-04-07

---

## 1. Cross-Experiment Patterns

### The naming effect is real but unevenly distributed

The seven experiments form a clear spectrum. At one end, Experiment 04 (bulk booking) shows zero naming effect -- the prompt was so specific that both apps produced structurally identical solutions. At the other end, Experiment 02 (rebook) and Experiment 03 (propose different time) show sharp, binary divergences traceable directly to naming. This is the most important meta-finding: **naming is an affordance that operates in the gap between what the prompt says and what the code implies**. When the prompt is precise and prescriptive, naming is inert. When the prompt requires the agent to make design judgments, naming steers those judgments.

The experiments where naming mattered most were ones that required reasoning about the state machine: rebooking (which states allow it?), counter-proposals (what does "decline" mean?), and system description (what story does this tell?). The experiments where naming mattered least involved adding a discrete, well-specified piece of logic to a specific service: bulk booking (create N records in a loop) and cancellation fee (add a conditional to the cancel flow).

### The model gap is larger than the naming gap

Across all seven experiments, Opus vs. Sonnet produced more consistent and more dramatic differences than Order vs. Request. Opus always implemented schedule-conflict checking in Experiment 05 (6/6 runs); Sonnet did it once (1/6). Opus always delegated to existing services in Order rebook runs (3/3); Sonnet was split. Opus wrote more tests, extracted more abstractions, and added more validation in every experiment. The analyses correctly identify this but I think they understate it: **the model variable explains more variance than the naming variable in every single experiment where both were measured**. The naming effect is a nudge; the model effect is a capability tier.

### Legacy complexity suppresses domain reasoning

The most robust cross-experiment pattern is that the Request app's nine-state machine discouraged agents from engaging with state logic. In Experiment 02, 4/6 Order runs added `rebookable?` state predicates; 0/6 Request runs did. In Experiment 03, Order runs scattered across four different decline-target designs while Request runs unanimously mapped onto the existing `declined` state. In Experiment 07, Request runs couldn't resist explaining the `created_accepted` state even when the prompt only asked for the happy path.

This is a coherent picture: the Request app's legacy states simultaneously provided strong semantic anchors (making certain design choices obvious) and discouraged independent reasoning about state eligibility (making other design choices feel too complex to attempt). The Order app's clean six-state machine invited agents to reason about lifecycle rules because the state space was tractable.

### Naming shapes framing, not comprehension

No run in any experiment misidentified the domain, hallucinated entities, or fundamentally misunderstood what the system does. The naming effect operates entirely at the level of interpretation and design choice. "Request" primes agents toward negotiation metaphors, provider agency, and communication-oriented features. "Order" primes toward transactional pipelines, fixed pricing, and lifecycle modeling. Both are valid readings of the same code -- which is exactly what makes the finding interesting.

---

## 2. What Surprised Me Most

### The rebook state-gating result is remarkably clean

The 4/6 vs. 0/6 split on `rebookable?` in Experiment 02 is the single cleanest finding in the dataset. I verified it by reading order-opus-1 (which adds `rebookable?` checking completed/canceled/rejected, a `rebookable` scope, and seven service-level tests) and request-opus-1 (which manually constructs a Request with `Request.new`, duplicates the payment creation logic, and adds no state checks at all). The contrast is stark. The same model (Opus), given the same task, produced domain-level abstractions in one app and a mechanical copy-paste in the other. This is not a model capability difference -- it is a pure naming/state-complexity effect.

### request-sonnet-2's destructive mutation in Experiment 06

In the cancellation fee experiment, request-sonnet-2 wrote `@payment.update!(amount_cents: fee)` inside `charge_cancellation_fee`, permanently destroying the original payment amount. The test then asserts `expect(payment.reload.amount_cents).to eq(50_000)` -- confirming the data loss is intentional, not accidental. This appeared in 2/6 Request runs and 0/6 Order runs. The analysis attributes this to "request" feeling more mutable than "order," which is speculative but directionally plausible. The small N makes it impossible to conclude much, but the fact that it appeared exclusively on the Request side is notable.

### Experiment 03's decline behavior is the best natural experiment in the set

The counter-proposal experiment is where the two apps' structural differences create the sharpest test. The Request app already has a `decline` event (created -> declined); the Order app has no equivalent. When asked to implement "client can decline the counter-proposal," Request runs unanimously reused the existing decline -> declined pathway (6/6 terminal). Order runs were split: 2/6 sent the order back to `pending` for further negotiation, while 4/6 treated it as terminal. The two Opus runs that chose the `pending` return path (order-opus-1, order-opus-3) produced arguably better designs -- they modeled a negotiation loop rather than a one-shot counter. But the Request app's existing vocabulary made that design invisible: when `decline` already means "end the request," no agent thought to make it mean "reject this proposal but keep talking." Legacy naming didn't just anchor design choices; it foreclosed design alternatives.

---

## 3. What the Results Suggest About AI-Codebase Interaction

### AI agents are aggressive pattern-matchers against existing code

The dominant behavior across all experiments is that agents treat existing code as a template. When the Request app already has `DeclineService` and a `declined` state, agents reuse those concepts even when the feature being built (declining a counter-proposal) has different semantics. When the Order app has clean services that delegate to `CreateService`, agents follow that pattern. When the Request app has extra services (`CreateAcceptedService`, `DeclineService`), agents in Experiment 06 added more named gateway methods (5/6 vs 2/6 for Order). The codebase is not just context -- it is a style guide that agents follow with high fidelity.

### State machine complexity has a threshold effect on reasoning

The Order app's six states are simple enough that agents can enumerate them and reason about eligibility (which states are rebookable? which states allow cancellation?). The Request app's nine states -- with the additional cognitive load of legacy naming like `created_accepted` -- seem to cross a complexity threshold where agents stop trying to reason about state eligibility and instead treat the entity as a generic record. This is not about the number nine being inherently too large; it is about the states not forming a clean narrative. `pending -> confirmed -> in_progress -> completed` tells a story. `created -> created_accepted -> accepted -> started -> fulfilled` tells a story with a confusing prologue that agents would rather not parse.

### Naming activates associative reasoning from training data

The "booking" synonym appearing in 4/6 Request runs and 0/6 Order runs (Experiment 05) is a clean signal that naming activates associations from the model's training corpus. "Request" evokes service requests, booking requests, scheduling requests -- domains where fulfillment, availability, and negotiation are first-class concerns. "Order" evokes e-commerce, transactions, and pipelines. These associations shape not just language but architectural decisions: Request runs were more likely to extract auto-assignment into a dedicated service (3/6 vs 1/6) and to treat "no available provider" as a 422 rather than a 404 (5/6 vs 3/6).

### AI agents seek justification for things that feel "off"

The meta-context pattern in Experiment 01 (67% of Request runs mentioned the experiment vs. 12% of Order runs) and the legacy archaeology in Experiment 07 (Sonnet discussed `created_accepted` in 3/3 Request runs, 0/3 Order runs) reveal a consistent behavior: when naming feels inconsistent or legacy, agents go looking for explanations. They pull in CLAUDE.md content, spec files, and sibling app references to explain why the naming is the way it is. Clean naming produces confident, self-contained descriptions. Messy naming produces defensive, explanatory ones. This has practical implications: legacy-named codebases will cause AI agents to spend tokens and attention on archaeology that clean codebases avoid.

---

## 4. Findings I Would Challenge or Qualify

### The Experiment 05 analysis overstates the naming effect

The auto-assignment analysis claims "Request naming nudged AI agents toward richer architectural thinking." But the data shows the dominant variable is Opus vs. Sonnet. Opus checked schedule conflicts in 6/6 runs regardless of app; Sonnet did it in 1/6 (request-sonnet-2, identified as an outlier). The service-extraction difference (3/6 Request vs 1/6 Order) is suggestive but the 422-vs-404 difference (5/6 vs 3/6) could easily be noise at this sample size. The summary's framing -- "Request naming nudged AI agents toward richer architectural thinking" -- risks implying a stronger effect than the data supports. A more honest reading: the naming effect in Experiment 05 is weak and secondary to model capability, with one genuinely interesting vocabulary signal ("booking" appearing 4/6 vs 0/6).

### The "legacy naming outperformed clean naming" claim in Experiment 03 is provocative but misleading

The Experiment 03 summary says "legacy naming outperformed clean naming for design consistency." This is true only in a narrow sense: Request runs were more consistent because the existing `decline` event constrained them to a single design. But consistency is not the same as quality. The two Order-Opus runs that returned to `pending` after declining a counter-proposal (order-opus-1, order-opus-3) produced a more flexible, arguably better design that allows negotiation loops. The Request app's "consistency" came from semantic lock-in, not from better reasoning. Framing constraint-driven uniformity as "outperformance" overstates the case.

### The test-count difference in Experiment 02 conflates naming with state complexity

The analysis notes Order runs averaged ~12 tests vs. ~5 for Request, with two Request-Sonnet runs shipping zero tests. But the Order runs that added `rebookable?` state predicates naturally generated more test cases (testing each state's eligibility). The Request runs that skipped state gating had less to test. The test-count gap is a downstream consequence of the state-gating gap, not an independent naming effect. Calling it a separate finding overstates the breadth of the effect.

### Sample sizes limit all conclusions

Every analysis acknowledges the small N, but I want to be explicit: with 3 runs per model per app, any single outlier (like request-sonnet-2's destructive mutation, or order-opus-2's `bulk_id` column) can swing a tally from "no pattern" to "notable pattern." The binary findings (4/6 vs 0/6 on rebookable, 6/6 vs 4/6 on terminal decline) are robust enough to be taken seriously. The weaker signals (5/6 vs 2/6 on gateway methods, 3/6 vs 1/6 on service extraction) could easily be model-level or random-seed effects. The experiment would benefit from more runs per cell.

### The analyses sometimes attribute to naming what belongs to structural differences

The Request app is not just differently named -- it has genuinely more code (extra services, extra states, extra API endpoint). When agents produce more gateway methods against the Request app, this could be naming-driven ("Request implies more services"), or it could be template-following ("this codebase already has more services, so I should create more"). The experiment's design makes these hard to disentangle. The cleanest tests of naming per se are the descriptive experiments (01, 07) where the agent is reading, not writing. The implementation experiments (02-06) test a confound of naming + codebase complexity.

---

## 5. Summary Assessment

The experiment demonstrates something genuine and practically important: **entity naming shapes how AI agents interpret ambiguous design decisions**. The effect is strongest when prompts require judgment (not mechanical implementation), when the task involves reasoning about state machines, and when the existing codebase provides semantic anchors that the agent can reuse or be constrained by.

The three strongest individual findings are:
1. The `rebookable?` state-gating split (Experiment 02: 4/6 vs 0/6) -- a clean demonstration that legacy state complexity suppresses domain reasoning
2. The decline-behavior unanimity (Experiment 03: 6/6 terminal in Request vs. 4/6 in Order) -- showing how existing vocabulary constrains design alternatives
3. The provider-agency framing shift (Experiment 01: 8/8 "confirms" in Order vs. 6/6 "accepts/declines" in Request) -- demonstrating that naming changes the narrative agents construct about identical systems

The experiment's primary limitation is that it tests naming + structural complexity as a bundle, not naming in isolation. A cleaner test would hold the state machine identical and change only the entity name. As designed, the strongest effects may be driven by state-machine tractability (6 clean states vs. 9 messy ones) rather than the word "Order" vs. "Request" per se.

The practical implication is clear regardless: if you use AI agents to work on your codebase, your naming choices and state machine designs are not just documentation -- they are prompts. Legacy naming does not merely confuse; it actively steers AI reasoning toward the mental model embedded in the original design, even when that model no longer matches reality.
