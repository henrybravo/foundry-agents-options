# 03 - Microsoft Agent Framework workflow

| Aspect | Value |
|---|---|
| Agent style | Workflow |
| Framework | Microsoft Agent Framework |
| Foundry agent name | `trail-maf-workflow` |
| Hosting | Foundry hosted agent, Responses protocol, code deploy |
| Based on | [Foundry sample `agent-framework/responses/05-workflows`](https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/python/hosted-agents/agent-framework/responses/05-workflows) |

## How it reviews

The same three-step topology and prompts as the LangGraph workflow, built with `WorkflowBuilder` and exposed as one agent with `as_agent()`. Each step reads its rules from the same `trail-review` skill files.

## Files

- `main.py` - `WorkflowBuilder` with three `AgentExecutor` steps
- `pyproject.toml` and `uv.lock` - locked dependencies (from the sample)
- `skills/` - copy of `shared/skills` (refresh with `pwsh ..\scripts\sync-shared.ps1`)

## Run

```powershell
azd ai agent run                     # local server on :8088 plus Agent Inspector
azd ai agent invoke --local "Review this proposal: ..."
azd ai agent invoke "Review this proposal: ..."   # hosted on Foundry
```

For deployment and the side-by-side demo, see the [root README](../README.md).
