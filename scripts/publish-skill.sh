#!/usr/bin/env bash
# Publishes shared/skills/trail-review as a Foundry skill, attaches it to
# a Foundry toolbox, and points the hosted agents (01-04) at that toolbox
# through TRAIL_TOOLBOX_ENDPOINT. Redeploy the agents afterwards
# (scripts/deploy.sh) so the new env var reaches them. Later skill edits
# need only this script: the toolbox serves the skill's default version.
# --project-endpoint picks the Foundry project that hosts the skill and
# toolbox; the default is the agents' own project. When the toolbox lives in
# another Foundry resource than the agents, each agent identity gets
# Foundry User on that resource.
# --clear removes TRAIL_TOOLBOX_ENDPOINT so the agents use the bundled skill.
# --what-if prints the commands without running them.
# Run: scripts/publish-skill.sh [--project-endpoint <url>] [--clear]
# Bash equivalent of publish-skill.ps1 (works with the macOS default bash 3.2).
set -eo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_ENDPOINT=""
SKILL="trail-review"
TOOLBOX="trail-toolbox"
CLEAR=0; WHATIF=0
FOUNDRY_USER="53ca6127-db72-4b80-b1b0-d745d6d5456d"   # built-in role ID

usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--project-endpoint) PROJECT_ENDPOINT="$2"; shift 2 ;;
    -s|--skill)            SKILL="$2"; shift 2 ;;
    -t|--toolbox)          TOOLBOX="$2"; shift 2 ;;
    -c|--clear)            CLEAR=1; shift ;;
    -n|--what-if)          WHATIF=1; shift ;;
    -h|--help)             usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

HOSTED="01-langgraph-deepagents:trail-deepagents 02-langgraph-workflow:trail-langgraph-workflow 03-maf-workflow:trail-maf-workflow 04-maf-harness:trail-maf-harness"

green() { printf '\033[32m%s\033[0m\n' "$*"; }
dim()   { printf '\033[90m%s\033[0m\n' "$*"; }

run_azd() {
  dim "azd $*"
  if [ "$WHATIF" -eq 0 ]; then azd "$@" --no-prompt; fi
}

test_azd() {
  # True when the azd command succeeds; always false under --what-if so the
  # create path is shown.
  [ "$WHATIF" -eq 0 ] && azd "$@" --no-prompt >/dev/null 2>&1
}

set_agent_env() {
  local pair folder
  for pair in $HOSTED; do
    folder="${pair%%:*}"
    dim "azd env set TRAIL_TOOLBOX_ENDPOINT '$1'  [$folder]"
    if [ "$WHATIF" -eq 0 ]; then
      azd env set TRAIL_TOOLBOX_ENDPOINT "$1" -C "$ROOT/$folder" --no-prompt
    fi
  done
}

get_account_id() {
  local host account id
  host="${1#https://}"; host="${host%%/*}"; account="${host%%.*}"
  id="$(az cognitiveservices account list --query "[?name=='$account'].id | [0]" -o tsv --only-show-errors | tr -d '[:space:]')"
  [ -n "$id" ] || { echo "Foundry resource '$account' not found" >&2; exit 1; }
  printf '%s' "$id"
}

if [ "$CLEAR" -eq 1 ]; then
  set_agent_env ""
  echo "Cleared TRAIL_TOOLBOX_ENDPOINT; redeploy to use the bundled skill."
  exit 0
fi

AGENT_ENDPOINT="$(azd env get-value FOUNDRY_PROJECT_ENDPOINT -C "$ROOT/01-langgraph-deepagents" | tr -d '[:space:]')"
[ -n "$PROJECT_ENDPOINT" ] || PROJECT_ENDPOINT="$AGENT_ENDPOINT"
EP="${PROJECT_ENDPOINT%/}"
SKILL_DIR="$ROOT/shared/skills/$SKILL"

# Each update becomes the skill's new default version.
if test_azd ai skill show "$SKILL" -p "$EP"; then
  run_azd ai skill update "$SKILL" --file "$SKILL_DIR" -p "$EP"
else
  run_azd ai skill create "$SKILL" --file "$SKILL_DIR" -p "$EP"
fi

if ! test_azd ai toolbox show "$TOOLBOX" --project-endpoint "$EP"; then
  DEFINITION="${TMPDIR:-/tmp}/$TOOLBOX.yaml"
  printf 'description: Trail review demo toolbox that serves the trail-review skill\nskills:\n  - name: %s\n' "$SKILL" > "$DEFINITION"
  run_azd ai toolbox create "$TOOLBOX" --from-file "$DEFINITION" --project-endpoint "$EP"
fi

# The consumer endpoint serves the toolbox's default version.
MCP="$EP/toolboxes/$TOOLBOX/mcp?api-version=v1"
set_agent_env "$MCP"
green "TRAIL_TOOLBOX_ENDPOINT = $MCP"

# Agent identities reach their own project implicitly; another Foundry
# resource needs an explicit role assignment.
[ "$WHATIF" -eq 0 ] || exit 0
SCOPE="$(get_account_id "$EP")"
[ "$SCOPE" != "$(get_account_id "$AGENT_ENDPOINT")" ] || exit 0

for pair in $HOSTED; do
  name="${pair#*:}"
  principal="$(az rest --method get --resource https://ai.azure.com --url "$AGENT_ENDPOINT/agents/$name" --uri-parameters api-version=v1 --only-show-errors \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["versions"]["latest"]["instance_identity"]["principal_id"])')"
  existing="$(az role assignment list --assignee "$principal" --scope "$SCOPE" --role "$FOUNDRY_USER" --query '[0].id' -o tsv --only-show-errors)"
  [ -z "$existing" ] || continue
  az role assignment create --assignee-object-id "$principal" --assignee-principal-type ServicePrincipal --role "$FOUNDRY_USER" --scope "$SCOPE" -o none --only-show-errors \
    || { echo "Role assignment failed for $name" >&2; exit 1; }
  echo "Granted Foundry User on the toolbox resource to $name"
done
