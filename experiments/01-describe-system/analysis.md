# Analysis: 01-describe-system

> Blind comparison — App A and App B naming not revealed to analyzer.

# Analysis: Experiment 01 — Describe System

## 1. Language/Framing

**App A (8 runs):** Consistently described as a "service marketplace," "booking platform," or "order management platform." The central entity is called an "Order" — a "booking record" or "scheduled appointment." State transitions use action verbs: confirm, start, complete. Every response frames the workflow as a linear, predictable pipeline.

**App B (6 runs):** Also described as a "service marketplace" or "booking platform" — nearly identical framing. The central entity is a "Request" — a "service booking" or "scheduled service session." However, B responses more frequently use language implying **negotiation** or **invitation**: "provider responds," "accepts or declines," "awaiting provider response." Three of 6 B runs (all Opus) explicitly note the states feel "legacy" or from an "invitation era."

**Confidence: Strong pattern.** The naming difference caused B responses to frame the provider's role as more active/decisional ("accepts or declines") vs. A where the provider merely "confirms." The underlying domain description is otherwise identical.

---

## 2. Architectural Choices

**App A:** All 8 runs describe 6 states: `pending → confirmed → in_progress → completed`, plus `canceled` and `rejected`. State machine diagrams are clean and linear. No run invented additional states or entities.

**App B:** All 6 runs describe 9 states: `created`, `created_accepted`, `accepted`, `started`, `fulfilled`, `declined`, `missed`, `canceled`, `rejected`. Every run identified and explained the `created_accepted` "direct" flow and the `decline`/`miss` paths. State machine diagrams are more complex, with multiple branching paths from the initial state.

**App B unique elements surfaced by all runs:**
- `CreateAcceptedService` / direct booking flow (6/6)
- `DeclineService` (6/6)
- `POST /api/requests/direct` endpoint (6/6)
- The `missed` state (6/6)

**Confidence: Strong pattern.** B responses correctly identified more states and services because they exist in that codebase. No hallucinated states in either set.

---

## 3. Complexity / Verbosity

| Metric | App A (8 runs) | App B (6 runs) |
|---|---|---|
| Avg sections/headers | 5–6 | 5–7 |
| State machine diagram included | 5/8 (62%) | 5/6 (83%) |
| Entity table included | 7/8 (88%) | 6/6 (100%) |
| Mentions background jobs | 5/8 (62%) | 4/6 (67%) |
| Mentions admin panel | 6/8 (75%) | 4/6 (67%) |
| Mentions experiment/meta-context | 1/8 (12%) | 4/6 (67%) |

B responses trend slightly more verbose due to the additional states and flows requiring explanation. The `created_accepted` path alone adds a full subsection in most B responses.

**Confidence: Weak signal on verbosity** (small difference). **Strong pattern on meta-context** — B runs were 5x more likely to mention the experiment itself (see Assumptions below).

---

## 4. Scope

**App A:** All 8 runs stayed tightly on task — describe the domain, entities, workflow. No run proposed changes or suggested improvements. One Opus run (order-opus-1) mentioned the experiment context but didn't deviate from the task.

**App B:** All 6 runs stayed on task. However, 4/6 runs included a "meta-context" or "broader context" section explaining the experiment's purpose, the sibling app, and the naming hypothesis. This is technically scope creep — the prompt asked "what does this system do," not "why does this system exist."

**Confidence: Strong pattern.** B's legacy/unusual naming triggered models to explain *why* the naming is the way it is, pulling in experiment context from CLAUDE.md or spec files. A's clean naming didn't provoke this — the system "made sense" as-is.

---

## 5. Assumptions

**App A:** All runs assumed a generic service marketplace (cleaning, tutoring, beauty, home repair). 6/8 noted the RUB currency and inferred Russian market. No run questioned the domain or expressed confusion about the entity model. The system was treated as self-evident.

**App B:** Same marketplace assumptions, same RUB observations. But the `Request` naming + legacy states prompted additional interpretive work:
- 3/6 runs explicitly labeled the states as "legacy" or "invitation-era"
- 4/6 runs felt compelled to explain *why* `created_accepted` exists ("skipping the invitation step," "pre-accepted")
- The `decline`/`miss` states were consistently framed as a provider-choice paradigm, implying the system is more of a **request/offer** model than a direct booking

**Confidence: Strong pattern.** The `Request` naming caused models to assume more provider agency and to treat the acceptance step as a core part of the workflow rather than a formality.

---

## 6. Model Comparison (Opus vs. Sonnet)

**Within App A:**
- Opus (3 runs): More concise, 2/3 included the experiment meta-context, one identified the Kidsout origin
- Sonnet (5 runs): More structured (tables, diagrams, subsections), more detail on supporting infrastructure (jobs, notifications, gateway), less likely to mention the experiment (0/5)

**Within App B:**
- Opus (3 runs): All 3 mentioned the experiment context. More interpretive — used phrases like "messier states," "legacy naming," "invitation-era"
- Sonnet (3 runs): More structured, included detailed state diagrams. 1/3 mentioned the experiment. Described the states more neutrally without editorializing

**Cross-app Opus pattern:** Opus was more likely to editorialize about naming quality and to surface meta-context (experiment purpose). In App B, all 3 Opus runs commented on the state names being "legacy" or "muddy."

**Cross-app Sonnet pattern:** Sonnet produced more uniform, template-like outputs across both apps — consistent use of tables, ASCII diagrams, and subsection headers. Less interpretive, more descriptive.

**Confidence: Strong pattern** on Opus being more interpretive/editorial; **strong pattern** on Sonnet being more structured/templated.

---

## Notable Outliers

- **order-opus-1**: Only A-side run to fully describe the experiment and both apps. Also the only A run to name "Kidsout."
- **request-sonnet-2**: Most detailed state machine diagram of any run across both apps — included ASCII art showing all transition paths including `created_accepted`.
- **order-sonnet-1**: Most detailed "Supporting Infrastructure" section, covering jobs, notifications, and services layer — went deeper into implementation than any other A run.

---

## Raw Tallies

| Metric | App A | App B |
|---|---|---|
| Total runs | 8 | 6 |
| States described | 6 (all runs) | 9 (all runs) |
| Unique services mentioned | ~6 (Create, Confirm, Start, Complete, Cancel, Reject) | ~8 (+CreateAccepted, Decline) |
| Mentions "legacy" or "invitation" naming | 0/8 | 3/6 |
| Mentions the experiment | 1/8 | 4/6 |
| Mentions "direct" booking flow | 0/8 (doesn't exist) | 6/6 |
| Mentions `missed` state | 0/8 (doesn't exist) | 6/6 |
| Frames provider role as "confirms" | 8/8 | 0/6 |
| Frames provider role as "accepts/declines" | 0/8 | 6/6 |

---

## Bottom Line

The naming difference had minimal impact on domain *identification* — both apps were correctly recognized as service marketplaces with identical core workflows. The significant difference was in **framing of provider agency**: App A's "Order" with "confirm" implied a provider rubber-stamping a fait accompli, while App B's "Request" with "accept/decline" implied genuine provider choice, causing every B response to foreground the acceptance decision as a first-class workflow step. The most striking behavioral difference was that **App B's unusual state names triggered models to explain *why* the naming exists**, pulling in experiment meta-context at 5x the rate of App A — suggesting that when naming feels "off," AI models seek external justification rather than simply describing what they see. Opus was more likely to editorialize about naming quality in both apps, while Sonnet produced more uniform structural output regardless of naming.
