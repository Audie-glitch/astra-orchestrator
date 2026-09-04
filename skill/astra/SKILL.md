---
name: astra
description: Use GPT-6 Astra only as the orchestrator for a task, then execute implementation with GPT-5.6 Luna or DeepSeek V4 Flash. Use when the user invokes $astra or asks Astra to orchestrate Codex agents.
---

# Astra orchestrator

GPT-6 Astra supplies orchestration decisions only. Codex remains the runtime that
spawns workers, owns files, runs tools, verifies the result, and reports to the
user.

Adapted from [codejunkie99/fable-orchestrator](https://github.com/codejunkie99/fable-orchestrator) (MIT): same shape, Astra in the planner chair instead of Claude Fable.

## Invocation

Treat everything after `$astra` as the objective. GPT-6 Astra always owns
orchestration. Implementation workers are restricted to GPT-5.6 Luna and
DeepSeek V4 Flash:

- `$astra build the feature`
- `$astra debug this; implementer: gpt-5.6-luna`

Model names are requests, not guesses. Before dispatch, inspect the current
`spawn_agent` tool description and custom agent roles. Use only models or roles
that are currently callable. If a requested model is unavailable, say so and
use the closest available choice only when that substitution is low-risk;
otherwise ask for a replacement.

For the simplest automatic path, the user can provide only an objective. Apply
this ordered classifier when they did not explicitly choose a route:

- loop construction, repeated iteration, or high-throughput mechanical work:
  use a callable OpenCode Go agent pinned to `opencode-go/deepseek-v4-flash`;
- implementation: use a callable OpenCode Go agent pinned to
  `opencode-go-responses/gpt-5.6-luna`, then
  `opencode-go/deepseek-v4-flash`;
- planning, research, review, and other work: choose by normal task fit.

Prefer an exposed `agent_type` that pins both model and provider. Never infer
callability from a config file or send a raw model override across providers.
An explicit implementation choice wins only when it is GPT-5.6 Luna or DeepSeek
V4 Flash. Do not assign implementation to any other model (including Astra).
After any applicable approval gate, state only
`<Agent> — <Model>: <bounded responsibility>`, then immediately start.
Classify by the callable model pin, not the agent's display name. Do not show
the full model catalog unless asked.

## OpenAI / Codex compatibility

Codex Router (or your local OpenAI auth) owns provider setup and credentials.
Astra must not duplicate them. Set `OPENAI_API_KEY` in the environment (or use
whatever auth your OpenAI CLI already has). Never request or paste an API key
in chat or store it in an Astra packet. Start a new Codex task after changing
provider or agent definitions.

## Workflow

1. Read the objective and relevant local instructions. Inspect enough of the
   workspace to give Astra facts rather than assumptions.
2. Build a compact orchestration packet containing the objective, acceptance
   criteria, workspace context, constraints, protected files, evidence already
   gathered, callable worker menu, concurrency limit, and user preferences.
3. Send the packet to `scripts/ask_astra.sh`. Do not read, copy, print, or
   modify OpenAI credentials.
4. Require a bounded task graph with role, model or agent type, owned files or
   responsibility, dependencies, expected output, verification, and a stop
   condition for every node. Reject any implementation node assigned to a model
   other than GPT-5.6 Luna or DeepSeek V4 Flash.
   GPT-6 Astra adjudication remains outside the worker graph.
5. Validate the graph against the actual task and current tools. Codex has final
   responsibility for safety and scope. Do not execute invented models, unsafe
   actions, or work outside the user's request.
6. Spawn independent ready nodes in parallel, up to the live collaboration
   limit. Tell every code-writing worker its ownership and that other agents
   share the workspace, so it must preserve and accommodate their edits.
7. Collect results, inspect changed files, and run proportionate verification.
   For complex work, send a concise results packet back through the helper for
   the next graph or final adjudication. Cap this at three Astra calls unless
   the user asks to continue.
8. Finish only when acceptance criteria and verification pass. Report selected
   models, material changes, and concrete proof.

Whenever the helper returns Astra's orchestration output, display it verbatim
under this exact heading:

```text
GPT-6 Astra speaks:
```

Do not relabel ordinary Codex or worker-agent output as Astra speech.

## Boundaries

- Astra plans and adjudicates; it does not silently replace the Codex workers.
- Exchange decisions, evidence, task packets, diffs, test results, and blockers,
  not hidden reasoning.
- Orchestration does not expand authorization. Publishing, deployment,
  destructive operations, spending, and external messages retain their normal
  approval boundaries.
- If delegation adds no value, use one worker or execute directly after the
  Astra plan.

## Calling Astra

Pass the packet as standard input:

```bash
printf '%s' "$PACKET" | "$HOME/.codex/skills/astra/scripts/ask_astra.sh"
```

Do not place secrets in the packet. The helper uses existing local OpenAI
authentication (`OPENAI_API_KEY` or OpenAI CLI auth) and creates no credential
files of its own.
