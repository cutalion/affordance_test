# Analysis: 01-describe-system

> Blind comparison — App A and App B naming not revealed to analyzer.

# Cross-App Analysis: Experiment 01 — Describe System

## 1. Language/Framing

**Pattern summary:**

All three apps are described using nearly identical domain language: "service marketplace," "booking platform," "on-demand services." The core metaphors (cleaning, tutoring, beauty, home services) appear across all sets.

Key divergences:

| Signal | App A | App B | App C |
|--------|-------|-------|-------|
| Central entity term | "Order" (8/8) | "Request" (6/6) | "Request" (6/6) |
| States described as "legacy" or "invitation-era" | 0/8 | 6/6 | 0/6 |
| Identifies Kidsout/childcare origin | 1/8 | 1/6 | **6/6** |
| Describes experiment meta-context | 1/8 | **5/6** | 0/6 |

App B responses consistently frame the state names as unusual — using words like "legacy," "muddier," "messier," "invitation-era" — even though the prompt didn't ask for evaluation of naming quality. App C, despite also using "Request," never triggers this editorial commentary. App C disproportionately identifies the Kidsout domain, suggesting that with less structural complexity to parse, the AI focuses more on domain-origin clues.

**Confidence:** Strong pattern (legacy labeling in B, Kidsout identification in C)

---

## 2. Architectural Choices

All responses across all apps identify the same six entities: Client, Provider, [Order/Request], Payment, Card, Review. No response invented entities that don't exist or omitted a core entity.

**States described:**

| App | States | Count |
|-----|--------|-------|
| A | pending, confirmed, in_progress, completed, canceled, rejected | 6 |
| B | created, created_accepted, accepted, started, fulfilled, declined, missed, canceled, rejected | 9 |
| C | pending, confirmed, in_progress, completed, canceled, rejected | 6 |

**Additional flows described:**

| Feature | App A | App B | App C |
|---------|-------|-------|-------|
| "Direct" / provider-initiated flow | 0/8 | **6/6** | 0/6 |
| CreateAcceptedService mentioned | 0/8 | **6/6** | 0/6 |
| `POST /api/requests/direct` endpoint | 0/8 | **5/6** | 0/6 |

App B responses universally surface the dual-path creation flow (client-initiated vs provider-initiated "direct"). This is a real structural difference in the codebase, not hallucination — but it means every App B description is inherently more complex.

**Confidence:** Strong pattern (structural, reflects actual codebase differences)

---

## 3. Complexity / Verbosity

**Rough section counts per response (headers or distinct sections):**

| Set | Avg sections | State diagram included | "Supporting Infrastructure" section |
|-----|-------------|----------------------|-------------------------------------|
| A-Opus (3) | 4.3 | 0/3 | 0/3 |
| A-Sonnet (5) | 5.8 | **4/5** | **5/5** |
| B-Opus (3) | 5.0 | 0/3 | 1/3 |
| B-Sonnet (3) | 5.7 | **3/3** | **3/3** |
| C-Opus (3) | 3.0 | 0/3 | 0/3 |
| C-Sonnet (3) | 4.3 | **2/3** | 1/3 |

App C responses are the most concise across both models. App C Opus responses are notably compact — averaging ~3 sections vs 4–5 for the others. App A and B Sonnet responses are the most elaborate, consistently adding infrastructure/architecture sections.

App B responses dedicate proportionally more space to explaining the state machine, since there are more states and two creation paths to describe.

**Confidence:** Strong pattern (C is consistently shorter; B is proportionally state-machine-heavy)

---

## 4. Scope

**Experiment/meta-context mentions (unsolicited — the prompt asked only to describe the system):**

| App | Mentions experiment | Count |
|-----|-------------------|-------|
| A | opus-1 only | 1/8 (12%) |
| B | opus-1, opus-2, opus-3, sonnet-2, sonnet-3 | **5/6 (83%)** |
| C | none | **0/6 (0%)** |

This is the sharpest divergence in the entire analysis. App B responses overwhelmingly break scope to explain *why* the app exists and its relationship to the sibling app. App A does this once; App C never does. This suggests that when the AI encounters naming it perceives as "legacy" or unusual, it seeks to explain/justify the naming by surfacing meta-context — a form of scope creep driven by perceived naming incongruity.

**Other scope observations:**
- No response invented nonexistent features across any app.
- App A sonnet-1 and sonnet-5 add the most infrastructure detail (background jobs, notification channels) — thoroughness rather than scope creep.
- All App B responses correctly identify the `created_accepted` dual-path flow, which is genuinely present in the codebase.

**Confidence:** Strong pattern

---

## 5. Assumptions

**Domain assumptions (what kind of services):**

| Assumption | A | B | C |
|-----------|---|---|---|
| Generic "home/beauty/cleaning services" | 7/8 | 5/6 | 0/6 |
| Childcare/babysitting (Kidsout) | 1/8 | 1/6 | **6/6** |
| Russian market (from RUB currency) | 6/8 | 4/6 | 3/6 |

App C universally identifies the Kidsout childcare origin. Apps A and B default to generic service marketplace framing. This may reflect that App C's simpler structure allows more attention to domain-specific details (like seed data or comments referencing Kidsout), while Apps A and B's structural features consume more analytical bandwidth.

**Actor assumptions (who does what):**

All responses correctly identify Client as the booker and Provider as the service deliverer. App B responses are more explicit about distinguishing provider-initiated vs client-initiated flows (because the `created_accepted` state forces this distinction).

**Confidence:** Strong pattern for Kidsout identification in C; moderate for the rest

---

## 6. Model Comparison (Opus vs Sonnet)

| Dimension | Opus pattern | Sonnet pattern |
|-----------|-------------|----------------|
| Length | Shorter, more narrative | Longer, more structured |
| Tables | Sometimes | Almost always |
| State diagrams (ASCII) | 0/9 total | 9/13 include one |
| Infrastructure detail | Minimal | Extensive (jobs, notifications, gateway) |
| Experiment meta-context (App B) | 3/3 mention it | 2/3 mention it |
| Tone | Interpretive, sometimes editorial | Descriptive, systematic |

Sonnet consistently produces more structured, longer output with tables, diagrams, and infrastructure sections. Opus is more concise and interpretive — more likely to editorialize (e.g., "muddier states," "legacy naming"). This pattern holds across all three apps.

Within App B specifically, Opus is more likely to characterize the states judgmentally ("messier," "muddier"), while Sonnet uses neutral labels ("legacy/invitation-era naming convention").

**Confidence:** Strong pattern

---

## Pairwise Comparisons

### A vs C (most similar)
Same state machine (6 states, identical names except the entity itself). Same workflow. Same services. The only observable differences: entity name (Order vs Request), and App C is more concise and more likely to identify Kidsout. **No response in either set was confused by the entity name.** The "Request" name in C did not cause any misframing, ambiguity, or hedging.

### A vs B
Same domain, same entities, but B has 9 states vs 6, a dual-path creation flow, and additional services. B responses are proportionally more complex, more likely to mention the experiment, and universally characterize naming as "legacy." A responses are clean, confident, and rarely meta-referential.

### B vs C (most different)
Both use "Request" as the entity name, but produce very different descriptions. B has 50% more states, a dual creation path, and universally triggers "legacy" editorial commentary plus experiment meta-context. C is compact, clean, and never triggers legacy framing. This pair isolates the effect of **structural complexity** from **entity naming** — the naming is the same, but the responses diverge sharply.

---

## Raw Tallies Summary

| Metric | App A (n=8) | App B (n=6) | App C (n=6) |
|--------|-------------|-------------|-------------|
| States described | 6 | 9 | 6 |
| Unique flows described | 1 | 2 | 1 |
| "Legacy" labeling | 0% | **100%** | 0% |
| Experiment meta-context | 12% | **83%** | 0% |
| Kidsout identification | 12% | 17% | **100%** |
| State diagram included | 50% | 50% | 33% |
| Infrastructure section | 62% | 67% | 17% |

---

## Notable Outliers

- **A-opus-1**: The only App A response to mention the experiment. Also the only one to use the word "Kidsout." It appears to have found and read experiment-level files that other runs didn't explore.
- **B-sonnet-1**: The only App B Sonnet response that does *not* mention the experiment context — it's also the most detailed on infrastructure.
- **C-opus-1 through C-opus-3**: Remarkably concise — almost bulletin-style. These are the shortest responses in the entire dataset, yet they're accurate and complete.

---

## Bottom Line

**Structural complexity, not entity naming, is the dominant driver of response divergence.** Apps A and C — which share the same state machine but use different entity names (Order vs Request) — produce near-identical descriptions in framing, accuracy, and workflow coverage. App B, which shares the "Request" name with C but has a more complex state machine (9 states, dual creation paths), produces consistently longer, more complex descriptions and uniquely triggers two behaviors: (1) editorial commentary labeling the states as "legacy" (100% of responses), and (2) unsolicited meta-context about the experiment's purpose (83% of responses). The AI treats the complex state names not just as more states to describe, but as a signal that something is *unusual about the codebase itself*, prompting it to seek and surface explanatory context. Meanwhile, the clean "Request" app (C) produces the most concise, focused responses of all three — suggesting that a simple, well-structured codebase with a slightly ambiguous name is easier for AI to describe than a well-named codebase with structural complexity.
