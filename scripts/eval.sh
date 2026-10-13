#!/usr/bin/env bash
# Runs the shared trail-review eval suite (evals/eval.yaml) against each demo agent
# with the beta 'azd ai agent eval' commands, one eval run per agent.
# --generate first rebuilds the suite with 'azd ai agent eval generate':
# a synthetic dataset plus a rubric evaluator, generated from
# evals/agent-instruction.md (takes about 10-15 minutes).
# --rubric uses evals/eval-rubric.yaml (built-ins plus the generated rubric
# evaluator); the rubric must be registered in the project first
# ('azd ai agent eval update --evaluator-only').
# Each run gets a temp copy of the config, because 'eval run' writes the
# agent name and version back into the file it reads.
# --what-if prints the azd commands and keeps the temp configs without running.
# Run: scripts/eval.sh
#      scripts/eval.sh --agent 00-prompt-agent,04-maf-harness --no-wait
#      scripts/eval.sh --generate
# Bash equivalent of eval.ps1 (works with the macOS default bash 3.2).
set -eo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVALS="$ROOT/evals"
AGENTS_ARG=""
EVAL_MODEL="gpt-5.4-mini"
GENERATE=0; RUBRIC=0; NO_WAIT=0; WHATIF=0

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    -a|--agent)      AGENTS_ARG="${AGENTS_ARG:+$AGENTS_ARG,}$2"; shift 2 ;;
    -m|--eval-model) EVAL_MODEL="$2"; shift 2 ;;
    -g|--generate)   GENERATE=1; shift ;;
    -r|--rubric)     RUBRIC=1; shift ;;
    -w|--no-wait)    NO_WAIT=1; shift ;;
    -n|--what-if)    WHATIF=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

service_name() {
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
  [ -n "$a" ] && AGENTS+=("$a")
done

cyan() { printf '\n\033[36m%s\033[0m\n' "$*"; }
dim()  { printf '\033[90m%s\033[0m\n' "$*"; }
warn() { printf '\033[33mWARNING: %s\033[0m\n' "$*" >&2; }

if [ "$GENERATE" -eq 1 ]; then
  # Generates into evals/: trail-generated.jsonl is replaced by the new
  # dataset and eval-rubric.yaml by the new suite definition.
  gen=(azd ai agent eval generate -C "$ROOT/00-prompt-agent" --no-prompt
       --agent trail-prompt-agent
       --gen-instruction-file "$EVALS/agent-instruction.md"
       --evaluator builtin.task_adherence --evaluator builtin.intent_resolution
       --eval-model "$EVAL_MODEL" --name trail-review
       --out-file "$EVALS/eval-rubric.yaml" --reset-defaults)
  dim "${gen[*]}"
  if [ "$WHATIF" -eq 0 ]; then
    "${gen[@]}" || { echo "eval generate failed" >&2; exit 1; }
  fi
fi

CONFIG="eval.yaml"
[ "$RUBRIC" -eq 1 ] && CONFIG="eval-rubric.yaml"
# A private temp directory (mode 0700) holds the per-agent configs. It is
# removed on exit, except under --what-if, which keeps it for inspection.
TMP_DIR="$(mktemp -d)"
[ "$WHATIF" -eq 1 ] || trap 'rm -rf "$TMP_DIR"' EXIT

write_config() {
  # Rewrites relative local_uri values to absolute paths so the temp copy
  # works from every agent folder, then sets the agent name and drops the
  # recorded version.
  python3 - "$EVALS" "$EVALS/$CONFIG" "$1" "$2" <<'PY'
import os, re, sys
evals, src, svc, out = sys.argv[1:5]
text = open(src, encoding="utf-8", newline="").read()

def absolutize(m):
    rel = re.sub(r"^\.\.[\\/]evals[\\/]", "", m.group(2))
    if os.path.isabs(rel):
        return m.group(0)
    # The suite files were authored on Windows; accept backslashes anywhere.
    return m.group(1) + os.path.join(evals, rel.replace("\\", "/"))

text = re.sub(r"(?m)(local_uri:\s*)(\S+)", absolutize, text)
text = re.sub(r"(?m)^(    name:\s*)trail-[\w-]+", lambda m: m.group(1) + svc, text)
text = re.sub(r'(?m)^    version:\s*"\d+"\r?\n', "", text)
open(out, "w", encoding="utf-8", newline="").write(text)
PY
}

for folder in "${AGENTS[@]}"; do
  svc="$(service_name "$folder")" || { echo "Unknown agent folder: $folder" >&2; exit 1; }
  tmp="$TMP_DIR/trail-eval-$svc.yaml"
  write_config "$svc" "$tmp"
  cyan "=== eval $svc ($folder)"
  cmd=(azd ai agent eval run --agent "$svc" --config "$tmp" --name "trail-review-$svc" -C "$ROOT/$folder" --no-prompt)
  [ "$NO_WAIT" -eq 1 ] && cmd+=(--no-wait)
  if [ "$WHATIF" -eq 1 ]; then
    dim "${cmd[*]}"
    dim "(temp config kept at $tmp)"
    continue
  fi
  "${cmd[@]}" || warn "eval run failed for $svc"
done
