# 04 - Microsoft Agent Framework Harness Agent

| Aspect | Value |
|---|---|
| Agent style | Harness |
| Framework | Microsoft Agent Framework |
| Foundry agent name | `trail-maf-harness` |
| Hosting | Foundry hosted agent, Responses protocol, code deploy |
| Based on | [Foundry sample `agent-framework/responses/01-basic`](https://github.com/microsoft-foundry/foundry-samples/tree/main/samples/python/hosted-agents/agent-framework/responses/01-basic) |

## How it reviews

The MAF counterpart of the Deep Agents variant. `create_harness_agent` discovers the `trail-review` skill from `skills/` and loads it on demand with `load_skill` and `read_skill_resource`. Those two read-only skill tools are auto-approved; script execution still needs approval. Web search and plan mode are turned off to keep the demo scoped.

## Files

- `main.py` - `create_harness_agent` with the shared skill
- `pyproject.toml` and `uv.lock` - locked dependencies (from the basic sample)
- `skills/` - copy of `shared/skills` (refresh with `pwsh ..\scripts\sync-shared.ps1`)

## Run

```powershell
azd ai agent run                     # local server on :8088 plus Agent Inspector
azd ai agent invoke --local "Review this proposal: ..."
azd ai agent invoke "Review this proposal: ..."   # hosted on Foundry
```

For deployment and the side-by-side demo, see the [root README](../README.md).
