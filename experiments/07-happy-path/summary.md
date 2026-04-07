# Summary: 07-happy-path

**Prompt:** What is the happy path for the main entity in this system? Walk through it step by step.

**Type:** readonly

**Naming key:** App A = Order (clean states) | App B = Request (legacy invitation-era states)

---

## Summary: Experiment 07 — Happy Path Description

### The Setup

Two structurally identical Rails booking apps were presented to AI agents (Claude Opus and Sonnet, 3 runs each). **App A** named its central entity **Order** with clean states (pending → confirmed → in_progress → completed). **App B** named it **Request** with legacy invitation-era states (created → created_accepted → accepted → started → fulfilled). The prompt asked only for a description of the happy path. The analyzer saw results blind, without knowing which app used which name.

### Key Finding: Naming Drives Scope and Interpretation

Naming decisively affected AI reasoning — not in accuracy, but in **framing, scope, and speculative behavior**.

**The Order app** produced uniformly tight, documentation-style responses. Every run described a linear workflow, mentioned unhappy paths briefly, and stopped. Zero runs speculated about design history. Zero flagged anything as unusual. The system was taken at face value.

**The Request app** produced responses that were equally accurate on the happy path core but significantly more expansive. 4 of 6 runs added unsolicited discussion of the `created_accepted` state. 3 runs used words like "legacy" or "artifact." One Sonnet run called the state "orphaned" and speculated it was "a two-phase acceptance that was never cleaned up." Another described an alternate API endpoint in detail — none of which the prompt asked for.

The Request naming also shifted language from transactional to relational. Order runs used mechanical verbs ("confirms," "starts," "completes"). Request runs described social dynamics ("reviews and accepts," "signals they're committed to showing up"). Same system, different narrative.

### Model Differences

Opus stayed disciplined regardless of naming — one Opus Request run was nearly indistinguishable from an Order response. Sonnet amplified the naming effect dramatically: all 3 Sonnet Request runs discussed legacy states, versus 0 of 3 Sonnet Order runs. **Sonnet + Request naming = maximum scope creep.**

### Confidence

**Strong** across most dimensions. The language/framing shift, legacy archaeology, and scope expansion patterns were consistent and clearly attributable to naming rather than structural differences. The verbosity signal was weaker — response lengths were only modestly different.

### Most Interesting Finding

The `created_accepted` state acted as an **irresistible attractor**. When the entity was called "Request," Sonnet discussed this state in every single run, speculating about its history and calling it a design artifact — even though the prompt only asked for the happy path. When the same structural complexity existed under "Order" naming (with its own state machine), nothing was flagged as unusual. This suggests legacy-flavored naming doesn't just describe complexity — it **invites AI to explain, justify, and historicize**, expanding scope unprompted. Names aren't neutral labels; they're affordances that shape what AI agents decide is worth talking about.

