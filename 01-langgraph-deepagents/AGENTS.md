# Coding agent instructions

This folder is one variant of the Foundry hosted-agent options demo: a harness built with LangChain Deep Agents on LangGraph, hosted as Foundry hosted agent `trail-deepagents` over the Responses protocol.

- `azure.yaml` - Foundry hosted-agent manifest (shared model deployment `gpt-5.4-mini`)
- `src/trail-deepagents/agent.py` - agent definition
- `src/trail-deepagents/skills/` - generated copy of `../shared/skills`; edit the shared copy, then run `pwsh ../scripts/sync-shared.ps1`

Keep the review behaviour aligned with the other three variants: same skill, same output format, same model. Cap code lines at 80 columns. Validate offline with `pwsh ../scripts/smoke-test.ps1`.
