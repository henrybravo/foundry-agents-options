# 02 - LangGraph workflow

| Aspect | Value |
|---|---|
| Agent style | Workflow |
| Framework | LangGraph |
| Foundry agent name | `trail-langgraph-workflow` |
| Hosting | Foundry hosted agent, Responses protocol, code deploy |
| Based on | [Foundry sample `langgraph/responses/05-workflows`](https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/python/hosted-agents/langgraph/responses/05-workflows) |

## How it reviews

A fixed, code-defined graph runs a safety reviewer, an environment reviewer, and a summarizer in that order. No model decides what runs next. Each node reads its rules from the same `trail-review` skill files.

## Files

- `main.py` - `StateGraph` with three nodes, exported as `create_graph`
- `langgraph.json` - graph registration for the hosting entry point
- `requirements.txt` - locked dependencies (from the sample)
- `skills/` - copy of `shared/skills` (refresh with `pwsh ..\scripts\sync-shared.ps1`)

## Run

```powershell
azd ai agent run                     # local server on :8088 plus Agent Inspector
azd ai agent invoke --local "Review this proposal: ..."
azd ai agent invoke "Review this proposal: ..."   # hosted on Foundry
```

For deployment and the side-by-side demo, see the [root README](../README.md).
