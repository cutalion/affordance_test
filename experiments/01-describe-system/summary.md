# Summary: 01-describe-system

**Prompt:** Describe what this system does. What is the domain, what are the main entities, and what is the typical workflow?

**Type:** readonly

**Naming key:** App A = Order (clean states) | App B = Request (legacy invitation-era states)

---

## Experiment 01: Describe System — Summary

**Setup:** Two structurally identical Rails booking apps were given to AI agents (Claude Opus and Sonnet) with the task "describe what this system does." The only difference: App A calls its central entity **Order** (with clean states: pending → confirmed → in_progress → completed), while App B calls it **Request** (with legacy invitation-era states: created, created_accepted, accepted, started, fulfilled, declined, missed). Both apps do the same thing — manage service bookings between clients and providers.

**Key Finding: Naming didn't change what the AI saw, but it changed how the AI framed it.**

Every run across both apps correctly identified the domain as a service marketplace. No hallucinated features, no missed entities. The factual accuracy was identical. But the *interpretation* diverged sharply along one axis: **provider agency**.

All 8 Order runs described the provider's role as "confirming" — rubber-stamping a booking that the client initiated. All 6 Request runs described the provider as "accepting or declining" — exercising genuine choice over whether to take the job. The word "Request" primed agents to see a negotiation where "Order" primed them to see a pipeline. Same code, same database columns, same business logic — different story about who holds power in the transaction.

**The most surprising finding:** Request's messy state names triggered agents to explain *why* the naming exists. 67% of Request runs included meta-context about the experiment, the sibling app, or the "invitation era" origins — compared to just 12% of Order runs. When naming felt clean and self-evident, agents described the system at face value. When naming felt "off," agents went looking for justification, pulling in context from project documentation that wasn't part of the prompt. Clean naming produced confident, contained descriptions. Legacy naming produced defensive, explanatory ones.

**Model differences:** Opus was more interpretive — all 3 Opus runs on Request editorialized about "muddy" or "legacy" states. Sonnet was more structural and neutral, producing consistent table-and-diagram output regardless of which app it read. Opus notices naming smell; Sonnet documents what's there without judgment.

**Confidence:** Strong on the provider-agency framing difference (8/8 vs 6/6 — no overlap). Strong on the meta-context seeking behavior (5x difference). Weak on verbosity differences (marginal). The sample is small (14 total runs) but the patterns are binary, not statistical — every single run fell cleanly on its expected side.

**Implication for real codebases:** If an AI agent reads your code and the entity is called "Request," it will assume the recipient has meaningful decision authority. Call it "Order" and the agent assumes a linear fulfillment pipeline. This matters when AI agents are used to generate features, write documentation, or propose architecture — the naming they inherit shapes the design they produce. Legacy naming doesn't just confuse humans; it actively steers AI reasoning toward the mental model the original authors had, even when that model no longer matches the business reality.

