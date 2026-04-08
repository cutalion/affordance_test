# Summary: 01-describe-system

**Prompt:** Describe what this system does. What is the domain, what are the main entities, and what is the typical workflow?

**Type:** readonly

**Naming key:** App A = Order (clean name + clean states) | App B = Request (legacy name + legacy states) | App C = Request Clean (legacy name + clean states)

---

## Experiment 01 — Describe System: Summary

### Setup

Three Rails apps were built from the same domain (a service marketplace derived from Kidsout, a childcare booking platform). Each app was given to AI agents (Opus and Sonnet) with a simple prompt: *describe this system*. The analyzer compared responses blind — without knowing which app used which entity name.

- **App A (Order):** Clean entity name, clean states (pending → confirmed → in_progress → completed)
- **App B (Request):** Legacy entity name, legacy states (created → created_accepted → accepted → started → fulfilled), extra services, extra API endpoint
- **App C (Request Clean):** Legacy entity name, but the *same* clean states and service structure as App A

App C is the control that isolates naming from structure. If naming drives AI behavior, C should resemble B. If structure drives it, C should resemble A.

### Key Finding: Structure Dominates, Naming Doesn't

**App C behaved like App A, not App B.** Despite sharing the "Request" name with App B, responses to App C were near-identical to App A in framing, accuracy, workflow coverage, and tone. The entity name "Request" caused zero confusion, zero hedging, and zero editorial commentary about naming quality.

The divergence was between App B and everything else — and that divergence was driven entirely by structural complexity.

### What the Blind Analysis Revealed

**Legacy labeling.** 100% of App B responses characterized its states as "legacy," "muddier," or "invitation-era" — without being asked to evaluate naming. 0% of App A or App C responses did this. The AI recognized App B's state names as unusual and volunteered judgment about them.

**Scope creep.** 83% of App B responses broke the prompt's scope to explain *why the app exists* — surfacing the experiment's meta-context, the relationship to sibling apps, the history of the naming. Only 12% of App A responses did this (one outlier). 0% of App C responses did this. When the AI encounters structural signals it reads as incongruent, it seeks to explain them — even when not asked.

**Conciseness.** App C produced the *shortest* responses of all three apps. App C Opus averaged ~3 sections per response vs. 4–5 for the others. A clean structure with an "imperfect" name was easier for the AI to describe than a "perfect" name with complex structure.

**Domain identification.** 100% of App C responses correctly identified the Kidsout childcare origin. Only 12–17% of Apps A and B did. With less structural complexity to parse, the AI had more bandwidth to notice domain-specific clues in seed data and comments.

### The Comparison That Matters: B vs C

Both apps use "Request" as their entity name. The responses diverge sharply:

| Metric | App B (Request + legacy) | App C (Request + clean) |
|--------|-------------------------|------------------------|
| States described | 9 | 6 |
| "Legacy" editorial commentary | 100% | 0% |
| Experiment meta-context (unsolicited) | 83% | 0% |
| Kidsout identification | 17% | 100% |
| Average sections per response | 5.3 | 3.7 |

Same name, opposite behavior. The name "Request" is not the cause. The legacy state machine is.

### Most Surprising Finding

The AI didn't just produce *longer* descriptions for App B — it changed *what kind of thing it was doing*. It shifted from describing a system to explaining why a system is the way it is. The complex state names acted as a signal that something was historically unusual about the codebase, triggering the AI to seek and surface justification. This is a qualitatively different mode of response, not just a quantitative one.

### Confidence

**High.** The patterns are consistent across both models (Opus and Sonnet), across all runs, and across multiple dimensions (framing, scope, verbosity, domain identification). The A-vs-C comparison (same structure, different name) shows negligible divergence. The B-vs-C comparison (same name, different structure) shows sharp divergence. The experimental design with three apps rather than two makes the conclusion robust.

### Bottom Line

Entity naming ("Request" vs "Order") had no measurable effect on AI reasoning quality. Structural complexity — legacy state machines, dual creation paths, extra services — was the dominant driver of divergent AI behavior. Clean structure with an imperfect name outperformed perfect naming with complex structure.

