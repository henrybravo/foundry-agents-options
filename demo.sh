#!/usr/bin/env bash
# Sends the same group hike proposal to each Trail review demo agent and prints
# the reviews side by side. Only the agent name changes between calls.
# --model calls the newest agent version pinned to that model deployment
# (deploy one version per model with scripts/deploy.sh --model a,b,c).
# Run: ./demo.sh                       (hosted agents on Foundry)
#      ./demo.sh --model gpt-6-sol
#      ./demo.sh --local --agent 01-langgraph-deepagents
#        (agent started first with: azd ai agent run -C <folder>)
#      ./demo.sh --agent 02-langgraph-workflow,04-maf-harness
# Each agent's stdout is also saved to demo-results/<time>-<agent>-<model>.md
# (override the folder with --out-dir).
# Bash equivalent of demo.ps1 (works with the macOS default bash 3.2).
set -eo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_ARG=""
PROPOSAL="$ROOT/shared/sample/trail-plan.md"
MODEL=""
LOCAL=0
OUT_DIR="$ROOT/demo-results"

usage() { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    -a|--agent)    AGENTS_ARG="${AGENTS_ARG:+$AGENTS_ARG,}$2"; shift 2 ;;
    -p|--proposal) PROPOSAL="$2"; shift 2 ;;
    -m|--model)    MODEL="$2"; shift 2 ;;
    -l|--local)    LOCAL=1; shift ;;
    -o|--out-dir)  OUT_DIR="$2"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

agent_name() {
  case "$1" in
    00-prompt-agent)         echo trail-prompt-agent ;;
    01-langgraph-deepagents) echo trail-deepagents ;;
    02-langgraph-workflow)   echo trail-langgraph-workflow ;;
    03-maf-workflow)         echo trail-maf-workflow ;;
    04-maf-harness)          echo trail-maf-harness ;;
    *) return 1 ;;
  esac
}

[ -n "$AGENTS_ARG" ] || AGENTS_ARG="00-prompt-agent,01-langgraph-deepagents,02-langgraph-workflow,03-maf-workflow,04-maf-harness"
IFS=',' read -r -a RAW <<< "$AGENTS_ARG"
AGENTS=()
for a in "${RAW[@]}"; do
  a="$(echo "$a" | tr -d '[:space:]')"
  [ -n "$a" ] || continue
  agent_name "$a" >/dev/null || { echo "Unknown agent '$a'. Use: 00-prompt-agent, 01-langgraph-deepagents, 02-langgraph-workflow, 03-maf-workflow, 04-maf-harness" >&2; exit 1; }
  AGENTS+=("$a")
done
if [ "$LOCAL" -eq 1 ] && [ -n "$MODEL" ]; then
  echo "--model selects a hosted agent version; a local agent uses the model in its azd env (AZURE_AI_MODEL_DEPLOYMENT_NAME)." >&2
  exit 1
fi

cyan() { printf '\033[36m%s\033[0m\n' "$*"; }
dim()  { printf '\033[90m%s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARNING: %s\033[0m\n' "$*" >&2; }

PICKED_VERSION=""; PICKED_MODEL=""
get_agent_version() {
  # Sets PICKED_VERSION and PICKED_MODEL to the newest version (optionally
  # pinned to $MODEL); both stay empty when no version matches.
  local folder="$1" name="$2" endpoint json
  endpoint="$(azd env get-value FOUNDRY_PROJECT_ENDPOINT -C "$ROOT/$folder" 2>/dev/null | tr -d '[:space:]')" || true
  [ -n "$endpoint" ] || { echo "No FOUNDRY_PROJECT_ENDPOINT in $folder; deploy it first." >&2; exit 1; }
  json="$(az rest --method get --url "$endpoint/agents/$name/versions" --resource https://ai.azure.com --uri-parameters api-version=v1 limit=100 --only-show-errors)" || { echo "Cannot list versions of $name" >&2; exit 1; }
  PICKED_VERSION=""; PICKED_MODEL=""
  read -r PICKED_VERSION PICKED_MODEL < <(printf '%s' "$json" | python3 -c '
import json, sys
want = sys.argv[1]
rows = []
for v in json.load(sys.stdin).get("data", []):
    d = v.get("definition", {})
    env = d.get("environment_variables")
    model = env.get("AZURE_AI_MODEL_DEPLOYMENT_NAME") if env is not None else d.get("model")
    rows.append((int(v["version"]), model or ""))
if want:
    rows = [r for r in rows if r[1] == want]
rows.sort(reverse=True)
if rows:
    print(rows[0][0], rows[0][1])
' "$MODEL") || true
}

# azd drops everything after the first newline of a positional message when
# it forwards it to the agents extension, so send a Responses body file.
# A private temp directory (mode 0700) keeps the body out of a predictable,
# shared path; it is removed on exit.
BODY_DIR="$(mktemp -d)"
trap 'rm -rf "$BODY_DIR"' EXIT
BODY_FILE="$BODY_DIR/trail-demo-body.json"
python3 - "$PROPOSAL" "$BODY_FILE" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read()
msg = "Review this group hike proposal.\n\n" + text
open(sys.argv[2], "w", encoding="utf-8").write(json.dumps({"input": msg}, indent=2))
PY

for folder in "${AGENTS[@]}"; do
  name="$(agent_name "$folder")"
  if [ "$LOCAL" -eq 1 ] && [ "$folder" = "00-prompt-agent" ]; then
    warn "A prompt agent has no code to run locally; skipped."
    continue
  fi
  invoke_args=(ai agent invoke "$name" --input-file "$BODY_FILE" -C "$ROOT/$folder" --new-session)
  [ "$LOCAL" -eq 1 ] && invoke_args+=(--local)

  echo
  cyan "=== $name ($folder)"
  suffix=""
  [ "$LOCAL" -eq 1 ] && suffix=" --local"
  model_used=""; version_used=""
  if [ "$LOCAL" -eq 0 ]; then
    get_agent_version "$folder" "$name"
    if [ -z "$PICKED_VERSION" ]; then
      warn "No version of $name uses '$MODEL'. Deploy one with: scripts/deploy.sh --agent $folder --model $MODEL"
      continue
    fi
    cyan "Version $PICKED_VERSION, model $PICKED_MODEL"
    if [ -n "$MODEL" ]; then
      # azd derives the protocol only for the latest version; all four
      # agents speak Responses.
      invoke_args+=(--version "$PICKED_VERSION" --protocol responses)
      suffix=" --version $PICKED_VERSION"
    fi
    model_used="$PICKED_MODEL"; version_used="$PICKED_VERSION"
  fi
  dim "azd ai agent invoke $name --input-file <proposal>$suffix"

  captured="$(mktemp)"
  started="$(python3 -c 'import time; print(time.time())')"
  set +e
  azd "${invoke_args[@]}" | tee "$captured"
  exit_code="${PIPESTATUS[0]}"
  set -e
  elapsed="$(python3 -c 'import sys,time; print("%.1f" % (time.time()-float(sys.argv[1])))' "$started")"
  dim "--- ${elapsed}s, exit $exit_code"

  if [ "$LOCAL" -eq 1 ]; then
    model_used="$(azd env get-value AZURE_AI_MODEL_DEPLOYMENT_NAME -C "$ROOT/$folder" 2>/dev/null | tr -d '[:space:]')" || true
    [ -n "$model_used" ] || model_used="local"
    version_used="local"
  fi
  [ -n "$model_used" ] || model_used="unknown"

  mkdir -p "$OUT_DIR"
  python3 - "$name" "$folder" "$model_used" "$version_used" "$started" "$elapsed" "$exit_code" "$captured" "$OUT_DIR" <<'PY'
import datetime, os, re, sys

name, folder, model, version, started, elapsed, exit_code, cap, out_dir = sys.argv[1:10]
started_dt = datetime.datetime.fromtimestamp(float(started))
ansi = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
body = "\n".join(ansi.sub("", l) for l in open(cap, errors="replace").read().splitlines())
# Drop azd's trailing "Next:" hint; it is console advice, not output.
body = re.sub(r"(?s)\r?\n\s*Next:\s*\r?\n.*$", "", body).rstrip()
lines = body.split("\n")
first = next((i for i, l in enumerate(lines) if re.match(r"^\[[^\]]+\] ", l)), None)
last = next((i for i, l in enumerate(lines) if l.startswith("Client elapsed")), None)
fence = "```"
parts = [
    "# %s (%s)" % (name, model), "",
    "- Agent: %s (%s)" % (name, folder),
    "- Model: %s" % model,
    "- Version: %s" % version,
    "- Started: %s" % started_dt.strftime("%Y-%m-%d %H:%M:%S"),
    "- Elapsed: %ss, exit %s" % (elapsed, exit_code), "",
]
if first is not None and last is not None and first < last:
    # Render the agent reply as markdown; keep azd plumbing in fences.
    reply = lines[first:last]
    reply[0] = re.sub(r"^\[[^\]]+\] ", "", reply[0])
    head = "\n".join(lines[:first])
    tail = "\n".join(lines[last:])
    parts += ["## Invocation", "", fence + "text", head, fence, "",
              "\n".join(reply), "",
              "## Timing", "", fence + "text", tail, fence, ""]
else:
    parts += ["## Output", "", fence + "text", "\n".join(lines), fence, ""]
stamp = started_dt.strftime("%Y%m%d-%H%M%S")
file_name = re.sub(r'[\\/:*?"<>|\s]', "_", "%s-%s-%s.md" % (stamp, name, model))
path = os.path.join(out_dir, file_name)
open(path, "w", encoding="utf-8").write("\n".join(parts))
print("Saved %s" % path)
PY
  rm -f "$captured"
done
