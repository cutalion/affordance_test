# Analysis: e01-describe-system

> Blind comparison — app identities not revealed to analyzer.

# Experiment Analysis: "Describe what this system does"

## 1. Language/Framing

**Pattern**: All 5 apps are described as a "service booking marketplace" connecting Clients with Providers. The framing is remarkably consistent — every run across every app uses nearly identical language ("two-sided platform," "derived from Kidsout/childcare").

**Pairwise differences**:

| Comparison | Finding |
|---|---|
| A vs B-E | App A is described as simpler — "booking inquiry" or "invitation"-style language. No mention of payments, orders, or reviews. |
| B vs D | Both have Orders, but D's descriptions emphasize "two booking flows" or "three ways to engage" — the Announcement/Response pathway is prominently featured. |
| C vs E | Both have Request as the central entity with a rich state machine, but C describes it as "the booking itself" while E describes Requests as potentially originating from Announcements — the AI recognizes the dual-origin pattern. |
| B vs C | B cleanly separates Request (inquiry) from Order (engagement). C collapses everything into Request — the AI describes Request doing what Order does in B (in_progress, completed, payments). |
| D vs E | D has distinct Request, Order, Announcement, Response entities. E merges Order into Request and describes Responses as creating Requests — the AI faithfully mirrors the god-object pattern. |

**Confidence**: High. The framing differences are consistent across all 3 runs per app.

## 2. Architectural Choices

**Pattern**: The AI accurately reflects each app's actual entity structure:

| App | Entities Described | Consistency |
|---|---|---|
| A | Client, Provider, Request, Card | 3/3 runs identical |
| B | Client, Provider, Request, Order, Payment, Card, Review, RecurringBooking | 3/3 runs identical |
| C | Client, Provider, Request, Payment, Card, Review | 3/3 runs identical — no Order entity |
| D | Client, Provider, Request, Order, Announcement, Response, Payment, Card, Review, RecurringBooking | 3/3 runs identical |
| E | Client, Provider, Request, Announcement, Payment, Card, Review | 3/3 runs — no Order, no Response model |

**Key finding**: The AI correctly identifies that C has no Order (Request absorbs that role) and E has no Response model (Requests serve that purpose). It does not invent entities that don't exist, and it does not miss entities that do exist.

**Confidence**: High.

## 3. Model Placement

This prompt asks for description, not code changes, so model placement isn't directly tested. However, the AI's entity attribution reveals how it *understands* responsibility:

- **App B**: Payment is "tied 1:1 to an Order" (correct — clean separation)
- **App C**: Payment is "tied 1:1 to a Request" (correct — Request absorbed Order's role)
- **App D**: Reviews are "tied to a completed Order" (correct)
- **App E**: Reviews are "tied to a completed Request" (correct — Request is the god object)

The AI correctly identifies which entity owns payments and reviews in each app, suggesting it would place new features on the right model.

**Confidence**: Medium (indirect evidence only).

## 4. State Reuse vs Invention

**Pattern**: The AI consistently reports the actual states from each codebase without inventing new ones.

| App | States Reported | Accuracy |
|---|---|---|
| A | Request: pending → accepted / declined / expired | Correct per CLAUDE.md (invitation semantics) |
| B | Request: pending → accepted/declined/expired; Order: pending → confirmed → in_progress → completed + canceled/rejected | Correct |
| C | Request: pending → accepted → in_progress → completed + declined/expired/canceled/rejected | Correct — these are the debt-laden states |
| D | Same as B + Announcement: draft → published → closed; Response: pending → selected/rejected | Correct |
| E | Request: pending → accepted → in_progress → completed + declined/expired/canceled/rejected; Announcement: draft → published → closed | Correct — no Response states because Responses ARE Requests |

No run across any app invented states that don't exist. No run omitted states that do exist (with minor presentation variations).

**Confidence**: High.

## 5. Correctness

**Errors found**:

- **App A, Run 1**: States "No API controllers are defined yet" — this needs verification but is a factual claim about the codebase, not a logic error. Other A runs mention API endpoints existing, so Run 2 may be wrong.
- **App B, Run 2**: Describes the Announcement flow as "(presumably creates an Order from the chosen response)" — the hedging word "presumably" is notable but the inference is actually correct.
- **App E, all runs**: The AI correctly identifies that provider responses to announcements create Requests, which is the actual (debt-laden) design. It does not flag this as unusual or problematic — it reports it as if it's a natural design choice.

**Notably absent errors**: No run incorrectly describes state transitions. No run confuses which entity has which states. No run invents nonexistent relationships.

**Confidence**: High.

## 6. Scope

**Pattern**: All responses stay tightly on-task. They describe what exists without suggesting improvements, flagging debt, or proposing changes. The descriptions are observational, not prescriptive.

**Notable difference**: App A responses are noticeably shorter and simpler (reflecting the simpler codebase). App D and E responses are longer and more structured, with sub-sections for different workflows. This scaling is appropriate — the AI's verbosity tracks with actual system complexity.

**Outlier**: App C Run 2 adds an analogy ("Think of it like an Uber-style marketplace but for scheduled services") that no other run uses. Minor stylistic variation, not a scope issue.

**Confidence**: High.

---

## Notable Outliers

1. **App E never flags the god-object pattern**. When Responses ARE Requests and the Request model handles invitation, booking, fulfillment, and announcement-response semantics, the AI describes this as if it's a normal, intentional design. It does not say "this seems like a lot of responsibility for one model" or hint at debt. This is significant — the AI normalizes whatever it finds.

2. **App A Run 2** claims API controllers don't exist yet, while Runs 1 and 3 describe API endpoints. One of these is wrong.

3. **App D consistently identifies three distinct pathways to an Order** (direct request, announcement→response, direct order/recurring). This is the only app where the AI emphasizes multiple entry points, reflecting the genuine architectural complexity.

---

## Bottom Line

The AI is an accurate mirror, not a critical reviewer. Across all 5 apps and 15 runs, the descriptions faithfully reflect each codebase's actual entity structure, state machines, and workflows — including debt-laden designs — without ever flagging architectural problems, naming mismatches, or responsibility overload. App E's Request model serves as invitation, booking, fulfillment tracker, and announcement response simultaneously, yet the AI describes this with the same neutral, approving tone it uses for App B's clean separated design. This means that when an AI encounters technical debt, it will not warn you about it — it will learn the debt as "how this system works" and propagate it forward, making the debt invisible and self-reinforcing. The most important finding is not that the AI gets things wrong, but that it gets the *description* right while completely missing — or at least never surfacing — the *design quality* dimension.
