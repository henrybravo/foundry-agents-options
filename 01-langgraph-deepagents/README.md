# 01 - Deep Agents harness on LangGraph

| Aspect | Value |
|---|---|
| Agent style | Harness |
| Framework | LangChain Deep Agents on LangGraph |
| Foundry agent name | `trail-deepagents` |
| Hosting | Foundry hosted agent, Responses protocol, code deploy |
| Based on | [Foundry sample `langgraph/responses/11-deep-agents`](https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/python/hosted-agents/langgraph/responses/11-deep-agents) |

## How it reviews

The harness receives the proposal and decides its own steps. It discovers the `trail-review` skill from `skills/` through progressive disclosure and reads the reference files when it needs them. `FoundryCheckpointSaver` persists LangGraph checkpoints in Foundry.

## Files

- `main.py` - Foundry Responses host and durable checkpointer
- `agent.py` - `create_deep_agent` with the shared skill
- `utils.py` - Foundry-backed chat model
- `requirements.txt` - locked dependencies (from the sample)
- `skills/` - copy of `shared/skills` (refresh with `pwsh ..\scripts\sync-shared.ps1`)

## Run

```powershell
azd ai agent run                     # local server on :8088 plus Agent Inspector
azd ai agent invoke --local "Review this proposal: ..."
azd ai agent invoke "Review this proposal: ..."   # hosted on Foundry
```

For deployment and the side-by-side demo, see the [root README](../README.md).
