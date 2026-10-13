#!/usr/bin/env bash
# Connects Application Insights to the shared Foundry project so hosted
# agent traces appear under Agents > Traces. Idempotent; safe to re-run.
# Run after deploy.sh: scripts/enable-tracing.sh [connection-name]
# Bash equivalent of enable-tracing.ps1 (works with the macOS default bash 3.2).
set -eo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONNECTION_NAME="${1:-appinsights-tracing}"
ARM="https://management.azure.com"
FIRST="$ROOT/01-langgraph-deepagents"

dim()   { printf '\033[90m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }

PROJECT_ID="$(azd env get-value AZURE_AI_PROJECT_ID -C "$FIRST" 2>/dev/null | tr -d '[:space:]')" || true
LOCATION="$(azd env get-value AZURE_LOCATION -C "$FIRST" 2>/dev/null | tr -d '[:space:]')" || true
[ -n "$PROJECT_ID" ] || { echo "Deploy first: no AZURE_AI_PROJECT_ID in 01." >&2; exit 1; }

# /subscriptions/<sub>/resourceGroups/<rg>/providers/<ns>/accounts/<acct>/projects/<proj>
SUBSCRIPTION="$(printf '%s' "$PROJECT_ID" | cut -d/ -f3)"
GROUP="$(printf '%s' "$PROJECT_ID" | cut -d/ -f5)"
ACCOUNT="$(printf '%s' "$PROJECT_ID" | cut -d/ -f9)"
SUFFIX="${ACCOUNT#cog-}"

ACTIVE="$(az account show --query id -o tsv --only-show-errors)"
if [ "$ACTIVE" != "$SUBSCRIPTION" ]; then
  echo "Azure CLI is on $ACTIVE, the project is in $SUBSCRIPTION. Run: az account set --subscription $SUBSCRIPTION" >&2
  exit 1
fi

arm_put() {
  # arm_put <url> <json-body> <jmespath-query>; the body goes through a file
  # so the secret never appears in the process list.
  local file out
  file="$(mktemp)"
  printf '%s' "$2" > "$file"
  out="$(az rest --method put --url "$1" --body "@$file" --query "$3" -o tsv --only-show-errors)" || { rm -f "$file"; return 1; }
  rm -f "$file"
  printf '%s' "$out"
}

WORKSPACE="log-trail-$SUFFIX"
dim "Log Analytics workspace $WORKSPACE"
WORKSPACE_ID="$(az monitor log-analytics workspace create -g "$GROUP" -n "$WORKSPACE" -l "$LOCATION" --query id -o tsv --only-show-errors)"

INSIGHTS="appi-trail-$SUFFIX"
INSIGHTS_ID="/subscriptions/$SUBSCRIPTION/resourceGroups/$GROUP/providers/Microsoft.Insights/components/$INSIGHTS"
dim "Application Insights $INSIGHTS"
INSIGHTS_BODY="$(python3 -c 'import json,sys; print(json.dumps({"location": sys.argv[1], "kind": "web", "properties": {"Application_Type": "web", "WorkspaceResourceId": sys.argv[2]}}, separators=(",", ":")))' "$LOCATION" "$WORKSPACE_ID")"
CONNECTION_STRING="$(arm_put "$ARM${INSIGHTS_ID}?api-version=2020-02-02" "$INSIGHTS_BODY" 'properties.ConnectionString')"

dim "Project connection $CONNECTION_NAME"
CONN_BODY="$(python3 -c 'import json,sys; ins=sys.argv[2]; print(json.dumps({"properties": {"category": "AppInsights", "target": ins, "authType": "ApiKey", "isSharedToAll": False, "credentials": {"key": sys.argv[1]}, "metadata": {"ApiType": "Azure", "ResourceId": ins}}}, separators=(",", ":")))' "$CONNECTION_STRING" "$INSIGHTS_ID")"
arm_put "$ARM$PROJECT_ID/connections/${CONNECTION_NAME}?api-version=2025-06-01" "$CONN_BODY" 'name' >/dev/null

green "Tracing connected to $INSIGHTS. Redeploy the agents (scripts/deploy.sh --skip-provision); traces then show in the portal within a few minutes of each call."
