#!/usr/bin/env bash
# Deploys the five Trail review demo agents into ONE shared Foundry project.
# Without --project-id, 01 provisions a new project (azd up) and the others
# attach to it; with --project-id, all attach to that existing project.
# 00-prompt-agent always deploys last: it is a prompt agent without code,
# so it needs the project and model deployments to exist first.
# --model picks the model deployment each agent version uses. With several
# models, every agent gets one version per model, deployed in the given
# order; the last model becomes the latest (default) version.
# Uses the current Azure CLI sign-in. The first run records its subscription
# and tenant in each azd environment; later runs switch to that subscription
# and refuse to run against any other. --subscription/--tenant-id override.
# --project-name names the new Foundry project and its resource group
# (default foundry-agent-options); without it azd would name the project
# after the first agent's folder. Ignored when --project-id is given.
# --skip-provision runs only 'azd deploy' (new agent versions, no ARM changes)
# once the project and model deployments exist. --what-if prints the azd
# commands without running them.
# Run: scripts/deploy.sh
#      scripts/deploy.sh --model gpt-6-sol,gpt-5.6-sol,gpt-5.4-mini
#      scripts/deploy.sh --skip-provision
# Bash equivalent of deploy.ps1 (works with the macOS default bash 3.2).
set -eo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPT="00-prompt-agent"
FIRST="01-langgraph-deepagents"

LOCATION="swedencentral"
PROJECT_NAME="foundry-agent-options"
SUBSCRIPTION=""
TENANT_ID=""
PROJECT_ID=""
AGENTS_ARG=""
MODELS_ARG=""
SKIP_PROVISION=0
WHATIF=0

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    -l|--location)       LOCATION="$2"; shift 2 ;;
    -s|--subscription)   SUBSCRIPTION="$2"; shift 2 ;;
    -t|--tenant-id)      TENANT_ID="$2"; shift 2 ;;
    -p|--project-id)     PROJECT_ID="$2"; shift 2 ;;
    -N|--project-name)   PROJECT_NAME="$2"; shift 2 ;;
    -a|--agent)          AGENTS_ARG="${AGENTS_ARG:+$AGENTS_ARG,}$2"; shift 2 ;;
    -m|--model)          MODELS_ARG="${MODELS_ARG:+$MODELS_ARG,}$2"; shift 2 ;;
    -k|--skip-provision) SKIP_PROVISION=1; shift ;;
    -n|--what-if)        WHATIF=1; shift ;;
    -h|--help)           usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$AGENTS_ARG" ] || AGENTS_ARG="00-prompt-agent,01-langgraph-deepagents,02-langgraph-workflow,03-maf-workflow,04-maf-harness"
[ -n "$MODELS_ARG" ] || MODELS_ARG="gpt-5.4-mini"

# Split the comma lists; the prompt agent always goes last.
IFS=',' read -r -a RAW_AGENTS <<< "$AGENTS_ARG"
AGENTS=()
HAS_PROMPT=0
for a in "${RAW_AGENTS[@]}"; do
  a="$(echo "$a" | tr -d '[:space:]')"
  [ -n "$a" ] || continue
  if [ "$a" = "$PROMPT" ]; then HAS_PROMPT=1; else AGENTS+=("$a"); fi
done
[ "$HAS_PROMPT" -eq 1 ] && AGENTS+=("$PROMPT")

IFS=',' read -r -a RAW_MODELS <<< "$MODELS_ARG"
MODELS=()
for m in "${RAW_MODELS[@]}"; do
  m="$(echo "$m" | tr -d '[:space:]')"
  [ -n "$m" ] && MODELS+=("$m")
done

green() { printf '\033[32m%s\033[0m\n' "$*"; }
dim()   { printf '\033[90m%s\033[0m\n' "$*"; }

run_azd() {
  local folder="$1"; shift
  dim "azd $*  [$folder]"
  if [ "$WHATIF" -eq 0 ]; then
    azd "$@" -C "$ROOT/$folder" --no-prompt
  fi
}

get_azd_value() {
  # Prints the azd env value, or nothing when it is not set.
  local v
  if v="$(azd env get-value "$2" -C "$ROOT/$1" 2>/dev/null)"; then
    printf '%s' "$v" | tr -d '[:space:]'
  fi
}

get_project_id() {
  local id
  id="$(get_azd_value "$1" AZURE_AI_PROJECT_ID)"
  [ -n "$id" ] || { echo "No AZURE_AI_PROJECT_ID in $1" >&2; exit 1; }
  printf '%s' "$id"
}

project_endpoint_from_id() {
  # https://<account>.services.ai.azure.com/api/projects/<project>, derived
  # from /subscriptions/<s>/resourceGroups/<g>/providers/<p>/accounts/<a>/projects/<n>
  local id="$1"
  printf 'https://%s.services.ai.azure.com/api/projects/%s' \
    "$(printf '%s' "$id" | cut -d/ -f9)" "$(printf '%s' "$id" | cut -d/ -f11)"
}

attach_project() {
  # Newer azure.ai.agents extension versions (seen with 1.0.0-beta.19) expand
  # ${FOUNDRY_PROJECT_ENDPOINT} in the manifest before 'ai project add' runs,
  # so set it first from the shared project's ARM ID.
  local folder="$1"
  run_azd "$folder" env set FOUNDRY_PROJECT_ENDPOINT "$(project_endpoint_from_id "$SHARED_ID")"
  run_azd "$folder" ai project add --project-id "$SHARED_ID" --force
}

declared_models() {
  # Deployment names from the ai-project block of 01's azure.yaml.
  python3 - "$ROOT/$FIRST/azure.yaml" <<'PY'
import re, sys
yaml = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"(?ms)^\s+deployments:\s*$(.*?)^\s{4}\S", yaml)
for n in re.findall(r"(?m)^\s{14}name:\s*(\S+)", m.group(1) if m else ""):
    print(n)
PY
}

prompt_deploy() {
  # A prompt agent names its model in azure.yaml, and azd does not expand
  # env vars there, so swap the value for this deploy and restore it.
  local model="$1" yaml="$ROOT/$PROMPT/azure.yaml" backup
  if [ "$WHATIF" -eq 1 ]; then
    run_azd "$PROMPT" deploy
    return
  fi
  backup="$(mktemp)"
  cp "$yaml" "$backup"
  trap 'cp "$backup" "$yaml"; rm -f "$backup"' EXIT
  python3 - "$yaml" "$model" <<'PY'
import re, sys
path, model = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8", newline="").read()
text = re.sub(r"(?m)^(        model:) \S+", lambda m: m.group(1) + " " + model, text)
open(path, "w", encoding="utf-8", newline="").write(text)
PY
  run_azd "$PROMPT" deploy
  cp "$backup" "$yaml"; rm -f "$backup"; trap - EXIT
}

assert_az_context() {
  # Default to what 01's azd environment already targets, so later runs
  # cannot drift to another subscription.
  [ -n "$SUBSCRIPTION" ] || SUBSCRIPTION="$(get_azd_value "$FIRST" AZURE_SUBSCRIPTION_ID)"
  [ -n "$TENANT_ID" ]    || TENANT_ID="$(get_azd_value "$FIRST" AZURE_TENANT_ID)"

  local active_id active_tenant active_user
  active_id="$(az account show --query id -o tsv 2>/dev/null)" || { echo "Not signed in. Run: az login" >&2; exit 1; }
  if [ -n "$SUBSCRIPTION" ] && [ "$active_id" != "$SUBSCRIPTION" ]; then
    az account set --subscription "$SUBSCRIPTION" 2>/dev/null || true
    active_id="$(az account show --query id -o tsv)"
  fi
  active_tenant="$(az account show --query tenantId -o tsv)"
  active_user="$(az account show --query user.name -o tsv)"
  [ -n "$SUBSCRIPTION" ] || SUBSCRIPTION="$active_id"
  [ -n "$TENANT_ID" ]    || TENANT_ID="$active_tenant"
  if [ "$active_id" != "$SUBSCRIPTION" ] || [ "$active_tenant" != "$TENANT_ID" ]; then
    echo "Azure CLI is on $active_id ($active_user), expected $SUBSCRIPTION in tenant $TENANT_ID. Run: az login --tenant $TENANT_ID; az account set --subscription $SUBSCRIPTION" >&2
    exit 1
  fi
  green "Deploying as $active_user to $SUBSCRIPTION"
}

ensure_project_env() {
  # azd names the Foundry project and resource group after the environment,
  # so give 01 an environment named for the demo. Reuse it on re-runs.
  [ -z "$PROJECT_ID" ] || return 0
  [ "$SKIP_PROVISION" -eq 0 ] || return 0
  if azd env list -C "$ROOT/$FIRST" --no-prompt 2>/dev/null | grep -qw -- "$PROJECT_NAME"; then
    run_azd "$FIRST" env select "$PROJECT_NAME"
  else
    run_azd "$FIRST" env new "$PROJECT_NAME"
  fi
}

# Validate the requested models against the manifest.
DECLARED="$(declared_models)"
for m in "${MODELS[@]}"; do
  if ! printf '%s\n' "$DECLARED" | grep -qx -- "$m"; then
    echo "Unknown model '$m'. Declared: $(printf '%s' "$DECLARED" | tr '\n' ',' | sed 's/,$//; s/,/, /g')" >&2
    exit 1
  fi
done

assert_az_context
"$ROOT/scripts/sync-shared.sh"
ensure_project_env

for folder in "${AGENTS[@]}"; do
  run_azd "$folder" env set AZURE_SUBSCRIPTION_ID "$SUBSCRIPTION"
  run_azd "$folder" env set AZURE_TENANT_ID "$TENANT_ID"
  run_azd "$folder" env set AZURE_LOCATION "$LOCATION"
done

SHARED_ID="$PROJECT_ID"
FIRST_PASS=1
[ "$SKIP_PROVISION" -eq 1 ] && FIRST_PASS=0
for m in "${MODELS[@]}"; do
  green "Model: $m"
  for folder in "${AGENTS[@]}"; do
    run_azd "$folder" env set AZURE_AI_MODEL_DEPLOYMENT_NAME "$m"
    if [ "$folder" = "$PROMPT" ]; then
      if [ "$FIRST_PASS" -eq 1 ] && [ -n "$SHARED_ID" ]; then
        attach_project "$folder"
      fi
      prompt_deploy "$m"
      continue
    fi
    if [ "$FIRST_PASS" -eq 0 ]; then
      # Project and model deployments exist; only a new agent version.
      run_azd "$folder" deploy
      continue
    fi

    if [ -n "$SHARED_ID" ]; then
      attach_project "$folder"
    fi

    run_azd "$folder" up

    if [ -z "$SHARED_ID" ] && [ "$WHATIF" -eq 0 ]; then
      SHARED_ID="$(get_project_id "$folder")"
      green "Shared project: $SHARED_ID"
    fi
  done
  FIRST_PASS=0
done

for folder in "${AGENTS[@]}"; do
  run_azd "$folder" ai agent show
done
