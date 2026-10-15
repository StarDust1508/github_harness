---
name: frontier-model-release-research
description: Research a new frontier-model release when vendor launch pages are partially blocked or benchmark claims need grounding from mixed sources.
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [AI-models, research, benchmarks, OpenAI, Anthropic, Gemini, Cloudflare]
---

# Frontier model release research

Use when the user wants substance behind a new model launch: what actually improved, how agentic/autonomous it is, how it compares to Claude/Gemini, and what is likely product/runtime vs base-model capability.

## When to use
- New model announcement is circulating on X/Telegram/screenshots
- Primary launch pages are blocked by Cloudflare or inaccessible in browser tools
- User cares about autonomy, tool use, Codex/autopilot, not just leaderboard numbers
- Need to separate benchmark gains from orchestration/runtime gains

## Workflow
1. **Start from primary source if reachable.** Try vendor launch post / newsroom / docs first.
2. **If primary pages are blocked, switch fast.** Do not get stuck on Cloudflare pages.
3. **Use benchmark aggregators for grounding.** Artificial Analysis main models page is useful for relative positioning even when direct model detail URLs fail or 404.
4. **Use the user’s own local knowledge base.** Search the Obsidian vault/session history for related notes (e.g. Karpathy on agentic engineering, verify loops, Software 3.0).
5. **Extract the mechanism, not just the scores.** Translate benchmark deltas into likely runtime components:
   - better planning
   - stronger long-horizon context retention
   - better tool selection/use
   - stronger verify loop / self-checking
   - better stop/escalation behavior
   - orchestration layer around the model
6. **Explain autonomy correctly.** Frame “autopilot” as a closed-loop agent runtime around the model, not magic inside one forward pass.
7. **Compare by operating regime, not only absolute score.** For Claude/Gemini/OpenAI, distinguish:
   - raw model capability
   - tool/runtime integration
   - computer-use maturity
   - coding sandbox / Codex-style environment
8. **Give a practical testing recommendation.** Suggest evaluating on messy multi-step tasks with files, browser/terminal, tests, and self-verification — not simple chat prompts.

## Good source order
1. Vendor announcement / newsroom
2. Vendor docs for agents/tools/computer use
3. Artificial Analysis or similar benchmark aggregator
4. Credible analyst/blog coverage
5. User’s existing notes/wiki/session history

## Pitfalls
- Do not over-interpret benchmark gains as pure model gains; many “agentic” wins come from runtime/orchestration.
- Do not treat Codex/autopilot as just a chat wrapper; assume sandbox + tools + repeated execution/verification loop unless disproven.
- Do not rely on direct Artificial Analysis model URLs without checking; some paths 404 while the main models page still contains usable leaderboard data.
- If OpenAI pages hit Cloudflare, pivot instead of repeatedly retrying the same blocked page.

## Verification
- Confirm at least one grounded benchmark signal
- Confirm at least one mechanism claim tied to tool use / verify loop / long-horizon execution
- Distinguish observed evidence from inference
- End with a concrete test the user can run to validate real autonomy
