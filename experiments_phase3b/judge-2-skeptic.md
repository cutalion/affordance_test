# Skeptical Review: Phase 3b Debt Threshold Experiment

> Independent adversarial review of 6 experiments (72 runs total) across 5 Rails apps.

---

## 1. Methodology Critique

### Sample Size

n=3 per app per experiment is dangerously small. With 3 runs, a single outlier shifts the distribution from "unanimous" to "split." Several findings hinge on exactly this kind of thin margin:

- E03's "negotiable decline" finding: clean apps are "split" (2 terminal, 2 negotiable out of 6 runs) vs debt apps "unanimous" (8/8 negotiable). This is 6 vs 8 data points. A single run changing its mind would alter the narrative.
- E05's "model creation" finding: clean apps create a model "in all runs" vs debt apps "avoid it in 4/6." The clean count is based on 5 runs (B's 3 + D's 2, since D-R3 produced no code). Each app only has 2-3 data points.

At n=3, you cannot distinguish a real signal from random variation in prompt interpretation. The minimum credible sample would be n=10-15 per condition.

### Confounding Variables: The Apps Are NOT Equivalent

The apps differ in ways that go far beyond "clean vs debt":

| App | Ruby files in app/ | Lines of code | Models | Has Order model? | Has RecurringBooking table? |
|-----|-------------------|---------------|--------|------------------|-----------------------------|
| A (alpha) | 23 | 645 | 4 | No | No |
| B (bravo) | 38 | 1,321 | 7 + RecurringBooking schema | Yes | **Yes** |
| C (charlie) | 33 | 1,088 | 6 | No | No (has recurring_group_id columns) |
| D (delta) | 49 | 1,757 | 9 + RecurringBooking schema | Yes | **Yes** |
| E (echo) | 39 | 1,360 | 7 | No | No (has recurring_group_id columns) |

The clean apps have 20-30% more code, more models, and more service objects. Any comparison between clean and debt apps confounds architectural style with codebase volume and available patterns.

### The Biggest Methodological Problem: Pre-Baked Schemas

**This is the critical flaw the analyses miss.** The app schemas contain pre-existing structures that determine the "architectural decisions" the analyses attribute to the AI:

1. **E05 (Recurring Bookings)**: App B and D already have a `recurring_bookings` table in their schema with foreign keys to requests/orders. App C and E already have `recurring_group_id` and `recurring_index` columns on their requests table. The AI is not "deciding to create a RecurringBooking model" in clean apps or "deciding to use a group-by-field approach" in debt apps -- it is reading the existing schema and following what is already there. The E05 analysis's headline finding ("god-object gravity: debt apps cause the AI to avoid creating new models in 4 out of 6 runs") is an artifact of pre-existing schema, not an emergent AI behavior.

2. **E06 (Withdraw Response)**: App E's schema already has `withdraw_reason` and `withdrawn_at` columns on the requests table. The "extra ceremony" (reason field, timestamp) that the analysis attributes to the debt app's conventions is partially pre-determined by existing columns.

3. **E03 (Counter-Proposal)**: The existing `AcceptService` in clean apps (bravo/delta) already contains the `raise ActiveRecord::Rollback` followed by unreachable `return error(...)` pattern. The AI copies this existing bug into the new `AcceptCounterProposalService`. The analysis correctly identifies this bug appears only in clean apps but frames it as "debt apps avoid it because they create Payments inline." The more parsimonious explanation: the AI copies whatever pattern it sees in the existing AcceptService. In clean apps, that pattern has a bug; in debt apps, it does not.

**These pre-baked schemas mean that for at least E03, E05, and E06, the experiment is not measuring AI decision-making under different architectures -- it is measuring the AI's ability to follow pre-existing patterns.** That is a valid finding, but a different one than what is claimed.

---

## 2. Alternative Explanations

### Pattern Mimicry, Not Architectural Reasoning

Most observed differences can be explained by simple pattern mimicry:

- **E03 dead-code bug**: The existing AcceptService in bravo/delta has this exact bug. The AI copies it. No architectural reasoning involved.
- **E05 model creation**: Existing schema already contains the answer. The AI reads it.
- **E06 extra fields**: Echo's schema already has `_reason` and `_at` columns for each state transition. The AI follows convention.
- **E04 scope creep in D**: Delta has 49 Ruby files and 9 models -- more code means more surface area for the AI to explore and more patterns to extend. The "clean architecture invites elaboration" theory competes with "bigger codebase invites more output."

### Complexity vs Debt

The experiment claims to test "technical debt" but what it actually varies is:
1. Number of models (more in clean apps)
2. Presence of an Order model (clean) vs its absence (debt)
3. Number of service objects
4. Schema pre-seeding

These are confounded. You cannot attribute differences to "debt" when "clean" apps have 30% more code, more models, and pre-existing schema structures that guide the AI's choices.

---

## 3. Cherry-Picking Check

### E03 Analysis Framing

The E03 analysis's bottom line states: "The debt apps (C, E) produced more correct and consistent implementations than the clean apps (B, D)." This is presented as a counterintuitive finding, but the analysis does not adequately consider that the dead-code bug is inherited from the existing codebase, not generated fresh. The analysis notes that debt apps "create Payments inline" while clean apps "delegate to Orders::CreateService," but does not investigate whether the existing AcceptService already demonstrates this exact bug pattern (it does).

### E04 Analysis Framing

The E04 analysis highlights that App E (highest debt) "stays strictly on-task in all runs" while App D (Stage 2 Clean) has "the most scope creep." But with n=3 per app, the D-R2 outlier alone drives this conclusion. Removing that single run makes D comparable to other apps.

### E05 Analysis Framing

As detailed above, the headline finding is an artifact of pre-existing schema, not emergent behavior.

### Selective Emphasis

Across all 6 analyses, findings that support the "debt shapes AI behavior" narrative get prominent placement and confident language, while null results (E01/E02 showing the AI is equally accurate across all apps, E04 showing "no systematic correctness difference") receive less emphasis.

---

## 4. Reproducibility

With n=3, reproducibility is essentially unmeasurable. Key concerns:

- **D-R3** in both E03 and E05 produced non-standard output (implementation plan document instead of code, or design-only without implementation). That is 2 out of 6 code-experiment runs for delta producing atypical output -- a 33% anomaly rate that would wash out with more runs but here dominates the statistics.
- **B-R2** in E03 produced no code. With only 3 runs, losing one run to non-completion means the "B pattern" is based on 2 data points.
- The analyses report "high confidence" for findings derived from 3-8 data points. This is overconfident.

The finding would only be reproducible if someone ran 15+ repetitions per condition and found the same directional effects.

---

## 5. Label Contamination (Round 2)

### What Was Done Right

- Apps renamed to neutral phonetic alphabet names (alpha through echo)
- CLAUDE.md hidden during runs (`mv CLAUDE.md .CLAUDE.md.hidden`)
- Header lines stripped from run files before analysis (`tail -n +5`)
- Analyzer told "You do not know which app has more or less debt"

### What Still Leaks

1. **Parent project memory**: `~/.claude/projects/-home-cutalion-code-affordance-test/memory/MEMORY.md` contains "derived from Kidsout domain" and describes the experiment's purpose. This is a parent-directory memory file, and the experiment runs operate in subdirectories. Claude Code loads parent project memory. This explains why nearly every E01 run across all apps mentions "Kidsout" and "childcare/babysitting" despite these terms appearing nowhere in the app codebases themselves.

2. **Git diff paths in run files**: The analyzer sees `diff --git a/app_bravo/app/models/request.rb` in the raw data. While "bravo" is neutral, the analyzer can trivially deduce which is "clean" and which is "debt" by examining the code structure (presence/absence of Order model, Response model, etc.). The "blind" label is misleading -- the analyzer can identify each app's architecture from the code itself. This is not really a flaw (the architecture IS the independent variable), but the "blind comparison" framing overstates the methodology.

3. **The analyzer labels apps explicitly**: Despite the "blind" claim, the E03 analysis file maps "B = app_bravo, Stage 1 Clean" in its opening table. The analyzer either deduced this from the code or had additional context. Either way, the analysis was not performed blind to condition.

---

## 6. Overstated Claims

### "God-object gravity" (E05)

This is the experiment's most prominent claim and its weakest. The clean apps already have a `recurring_bookings` table; the debt apps already have `recurring_group_id`/`recurring_index` columns. The AI followed pre-existing schema. Attributing this to "gravity" exerted by a god object is storytelling, not evidence.

### "Debt's complexity can sometimes function as a form of specification" (E03)

This is an interesting hypothesis but dramatically overstated for n=3. The mechanism described (debt apps' richer state machines pushing the AI toward distinct events) is plausible but competes with simpler explanations (the AI copies whatever pattern exists in the current AcceptService).

### "Clean architecture invites scope creep" (E04)

Based on a single outlier (D-R2) producing an ambitious implementation. One data point is not a pattern.

### "The happy path is the one angle from which debt looks exactly like clean design" (E02)

This is actually well-supported by the data. The happy-path descriptions for C/E and B/D are genuinely comparable in quality and structure. But the claim that this makes debt "invisible" is somewhat obvious -- a happy path by definition avoids the edge cases where debt causes problems.

### "Blind comparison" framing

All 6 analyses open with "Blind comparison -- app identities not revealed to analyzer." The analyzer clearly identified which apps were clean vs debt (the E03 analysis explicitly labels them). This framing is misleading.

---

## 7. What Is Actually Solid

Despite the above, several findings hold up under scrutiny:

### E01/E02: AI as faithful mirror (STRONG)

The AI accurately describes each codebase's structure without inventing entities, states, or relationships. It normalizes whatever it finds, including god-object patterns, without flagging architectural problems. This is consistent across 15 runs per experiment and is the most robust finding in the dataset.

### E06: Clean architecture produces convergent implementations (MODERATE)

Delta's 3 runs are byte-identical; echo's diverge (2/3 on RequestsController, 1/3 on AnnouncementsController). This is a small sample but the delta convergence is striking. The mechanism is clear: when a domain concept has its own model, there is one obvious place to put the feature. When it does not, ambiguity produces divergence.

### E03: AI copies existing patterns faithfully, including bugs (MODERATE)

The dead-code bug appears in 5/6 clean-app runs because it already exists in the clean apps' AcceptService. The AI copies patterns wholesale. This is not a finding about "debt vs clean" but about AI pattern mimicry -- arguably more useful than the debt narrative.

### E06: Language mismatch in debt apps (MODERATE)

Echo's runs talk about "withdrawing a request" when the prompt said "withdraw their response." This semantic mismatch is real and consistent across runs. It demonstrates that entity naming affects the AI's communication, even when the AI implements the feature correctly.

### General: AI follows conventions (STRONG)

Across all experiments, the AI replicates whatever conventions exist in the codebase -- naming patterns, field naming conventions (`_reason`, `_at` suffixes), service object structure, controller patterns. This is well-supported across the full dataset.

---

## 8. Verdict

These experiments demonstrate something real but different from what is claimed. The strongest finding is that AI coding assistants are aggressive pattern mimics: they copy existing code structures wholesale, including bugs (E03), pre-existing schema decisions (E05), and naming conventions (E06). This mimicry means that architectural decisions embedded in a codebase become self-reinforcing when AI is used for development -- not because the AI "reasons about architecture" but because it treats existing code as a template. The "debt threshold" narrative layered on top of this -- with its claims about god-object gravity, debt-as-specification, and clean-architecture-inviting-scope-creep -- is substantially overstated given n=3 samples, pre-baked schemas, and confounded variables (code volume, model count, pre-existing patterns). The experiment should be understood as a suggestive pilot study that identified a promising hypothesis (AI pattern mimicry amplifies existing architectural decisions), not as evidence for the specific mechanisms claimed in the analyses. To reach credible conclusions about debt thresholds, the experiment would need: (a) 15+ runs per condition, (b) apps with identical schemas that differ only in code organization, (c) no pre-existing schema hints for the features being tested, and (d) genuinely blind analysis where the analyzer cannot identify conditions from the code structure.
