#!/usr/bin/env bash
# Builds each agent offline (no model calls, no Azure access) to prove the
# code, dependencies, and shared skill wiring load. Uses a placeholder
# project endpoint. Needs each agent's .venv (see the README setup step).
# Run: scripts/smoke-test.sh
# Bash equivalent of smoke-test.ps1 (works with the macOS default bash 3.2).
set -eo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export FOUNDRY_PROJECT_ENDPOINT='https://example.services.ai.azure.com/api/projects/demo'
export AZURE_AI_MODEL_DEPLOYMENT_NAME='gpt-5.4-mini'

check_for() {
  case "$1" in
    01-langgraph-deepagents) cat <<'PY'
from agent import build_agent
from utils import build_chat_model
graph = build_agent(build_chat_model())
print("nodes:", sorted(graph.get_graph().nodes))
PY
    ;;
    02-langgraph-workflow) cat <<'PY'
from main import create_graph
graph = create_graph()
print("nodes:", list(graph.get_graph().nodes))
PY
    ;;
    03-maf-workflow) cat <<'PY'
from main import build_agent
agent = build_agent()
print("agent:", type(agent).__name__, agent.name)
PY
    ;;
    04-maf-harness) cat <<'PY'
from azure.identity import DefaultAzureCredential
from main import build_agent
agent = build_agent(DefaultAzureCredential())
print("agent:", type(agent).__name__, agent.name)
print("providers:", [type(p).__name__ for p in agent.context_providers])
PY
    ;;
  esac
}

FAILED=""
for name in 01-langgraph-deepagents 02-langgraph-workflow 03-maf-workflow 04-maf-harness; do
  src="$(find "$ROOT/$name/src" -mindepth 1 -maxdepth 1 -type d | sort | head -n 1)"
  py="$src/.venv/bin/python"
  [ -x "$py" ] || py="$src/.venv/Scripts/python.exe"   # Windows layout (Git Bash)
  echo "==> $name"
  if [ ! -x "$py" ]; then
    echo "No .venv in $src; install the agent dependencies first." >&2
    FAILED="${FAILED:+$FAILED, }$name"
    continue
  fi
  if ! ( cd "$src" && check_for "$name" | "$py" - ); then
    FAILED="${FAILED:+$FAILED, }$name"
  fi
done

if [ -n "$FAILED" ]; then
  echo "Smoke test failed: $FAILED" >&2
  exit 1
fi
echo "All four agents build."
