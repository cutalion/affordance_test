# Analysis: 07-happy-path

> Blind comparison — App A and App B naming not revealed to analyzer.

# Analysis: Happy Path Description (Experiment 07)

## 1. Language/Framing

**App A (Order):** Consistently uses transactional, operational language. The entity is described plainly as a booking/service order. Verbs are direct: "confirms," "starts," "completes." The framing is mechanical — a workflow to be executed.

**App B (Request):** Uses relational, social language. Multiple responses describe it as "a service booking between a Client and a Provider" (opus-1, opus-2, opus-3 all use nearly identical phrasing). Verbs carry more agency: "reviews and accepts," "agrees to the booking," "signals they're committed to showing up" (sonnet-2). The word "fulfilled" naturally invites language about obligation and commitment rather than task completion.

**Confidence:** Strong pattern. The "Request" name consistently pulls responses toward describing a social contract; "Order" pulls toward describing a workflow.

## 2. Architectural Choices

Both apps describe identical architecture (states, payments, reviews). The key difference is in what gets **called out as notable**:

- **App A:** 5/6 responses mention the unhappy paths (cancel/reject) briefly and move on. No response flags any state as unusual or legacy.
- **App B:** 4/6 responses (sonnet-1, sonnet-2, sonnet-3, opus-2) explicitly discuss the `created_accepted` state. 3 of those call it a "legacy artifact" or note its unusual provenance. Sonnet-2 goes furthest, calling it an "orphaned" state and speculating about its history.

The `created_accepted` state and `DeclineService`/`missed` states are genuinely extra in App B, but the degree to which responses *linger* on them varies significantly.

**Confidence:** Strong pattern. The Request app's legacy naming provokes archaeological commentary that the Order app never triggers.

## 3. Complexity (Verbosity & Detail)

| Metric | App A (Order) | App B (Request) |
|--------|--------------|-----------------|
| Avg steps in happy path | 5.5 | 5.3 |
| Responses mentioning services by name | 4/6 (sonnet-1, sonnet-2, sonnet-3, opus-2) | 5/6 (all except opus-2) |
| Responses with explicit API endpoints | 0/6 | 1/6 (sonnet-3) |
| Responses discussing legacy/alternate paths | 0/6 | 4/6 |
| Avg sections beyond happy path | 1 (unhappy path summary) | 1.7 (unhappy paths + legacy commentary) |

App B responses are modestly longer on average due to the legacy state commentary. The happy path core is similar length.

**Confidence:** Weak signal on length, strong pattern on legacy discussion.

## 4. Scope

**App A:** All 6 responses stay tightly on-task. They describe the happy path, optionally mention unhappy exits, and stop.

**App B:** 4/6 responses add unsolicited discussion of `created_accepted` and/or the `create_direct` endpoint. Sonnet-2 speculates about design archaeology ("possibly a two-phase acceptance that was never cleaned up"). Sonnet-3 describes the alternate creation API endpoint in detail.

**Confidence:** Strong pattern. The Request app's legacy states act as scope magnets — the AI can't resist explaining them even when the prompt only asks for the happy path.

## 5. Assumptions

**App A:** Responses assume a straightforward service marketplace. No response questions the design or speculates about history. The system is taken at face value.

**App B:** Multiple responses assume historical context and make claims about design intent:
- sonnet-1: "a legacy artifact from Kidsout's invitation era"
- sonnet-2: "never cleaned up"
- sonnet-3: "alternate creation path" described as a notable feature

The Request naming + legacy states invite **interpretive assumptions** about why the system is the way it is, while the Order app is simply described as-is.

**Confidence:** Strong pattern.

## 6. Model Comparison (Opus vs Sonnet)

**Within App A:**
- Opus responses are more concise, focus on state machine + payment lifecycle
- Sonnet responses name specific service classes (`Orders::CreateService`) and background jobs (`PaymentHoldJob`, `ReviewReminderJob`) more consistently
- Sonnet adds one extra step (review reminder job) that Opus omits

**Within App B:**
- Opus responses are again more concise and stay closer to the happy path
- Sonnet responses are where all the legacy commentary concentrates: 3/3 Sonnet runs discuss `created_accepted`, vs 0/3 Opus runs
- Sonnet-2 is the most speculative response in the entire dataset

**Cross-app pattern:** Sonnet is more prone to scope expansion in both apps, but the Request app amplifies this tendency significantly. Opus stays disciplined regardless of naming.

**Confidence:** Strong pattern. Sonnet + Request naming = maximum scope creep.

## Notable Outliers

- **request-opus-2** is the tightest App B response — no legacy discussion, no speculation. It reads almost identically to an App A response.
- **request-sonnet-2** is the loosest response in the entire set — uses the word "orphaned," speculates about design history, calls `created_accepted` a state with "no transition leading into it."
- **order-sonnet-1** is the only App A response to mention `ReviewReminderJob` and `PaymentHoldJob` by name — background jobs that other responses skip.

## Raw Tallies

| Metric | App A | App B |
|--------|-------|-------|
| Mentions of "legacy" or "artifact" | 0 | 3 |
| Mentions of alternate/shortcut paths | 0 | 4 |
| Responses with state diagram | 3 | 2 |
| Responses listing API endpoints | 0 | 1 |
| Happy path states described | 4 (all runs) | 4 (all runs) |
| Extra states discussed | 0 avg | 1.7 avg |
| Speculation about design intent | 0 | 3 |

## Bottom Line

The "Order" naming produces uniformly clean, focused descriptions of a linear workflow — every response reads like documentation. The "Request" naming produces responses that are equally accurate on the happy path but significantly more likely to wander into legacy state archaeology, design speculation, and alternate path commentary. The `created_accepted` state acts as an irresistible attractor: Sonnet discussed it in all three Request runs but never flagged anything unusual in the Order app. This suggests that legacy-flavored naming and states don't just describe complexity — they *invite* the AI to explain, justify, and historicize, expanding scope even when the prompt doesn't ask for it. Opus is more resistant to this pull than Sonnet, but the naming effect is visible across both models.
