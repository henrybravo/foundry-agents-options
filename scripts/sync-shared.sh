#!/usr/bin/env bash
# Copies the canonical shared/skills tree and shared/toolbox_skills.py into
# every hosted agent's source folder so each code-deploy package ships the
# same SKILL.md and toolbox loader. 04 loads toolbox skills natively and
# gets only the skills; folders without src (the prompt agent) are skipped.
# --check verifies the copies match without writing.
# Run: scripts/sync-shared.sh [--check]
# Bash equivalent of sync-shared.ps1 (works with the macOS default bash 3.2).
set -eo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/shared/skills"
LOADER="$ROOT/shared/toolbox_skills.py"
NATIVE_TOOLBOX="04-maf-harness"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

DRIFT=""
add_drift() { DRIFT="${DRIFT:+$DRIFT, }$1"; }

for agent_dir in "$ROOT"/0*/; do
  agent="$(basename "$agent_dir")"
  [ -d "$agent_dir/src" ] || continue
  src="$(find "$agent_dir/src" -mindepth 1 -maxdepth 1 -type d | sort | head -n 1)"
  [ -n "$src" ] || continue
  target="$src/skills"
  loader_target="$src/toolbox_skills.py"
  want_loader=1
  [ "$agent" = "$NATIVE_TOOLBOX" ] && want_loader=0

  if [ "$CHECK" -eq 1 ]; then
    if [ ! -d "$target" ] || ! diff -r -q "$SOURCE" "$target" >/dev/null 2>&1; then
      add_drift "$agent"
    fi
    if [ "$want_loader" -eq 1 ]; then
      if [ ! -f "$loader_target" ] || ! cmp -s "$LOADER" "$loader_target"; then
        add_drift "$agent (toolbox_skills.py)"
      fi
    fi
    continue
  fi

  [ "$want_loader" -eq 1 ] && cp -f "$LOADER" "$loader_target"
  rm -rf "$target"
  mkdir -p "$target"
  cp -R "$SOURCE"/. "$target"/
  echo "Synced skills -> $agent"
done

# A prompt agent has no code package, so its azure.yaml carries the skill
# and its reference files inline in the instructions.
PROMPT_YAML="$ROOT/00-prompt-agent/azure.yaml"
if [ -f "$PROMPT_YAML" ]; then
  rc=0
  python3 - "$SOURCE" "$PROMPT_YAML" "$CHECK" <<'PY' || rc=$?
import os, re, sys

source, yaml_path, check = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
skill_dir = os.path.join(source, "trail-review")

def read(path):
    with open(path, encoding="utf-8", newline="") as f:
        return f.read()

skill = read(os.path.join(skill_dir, "SKILL.md"))
body = re.sub(r"(?s)^---.*?\r?\n---\r?\n", "", skill, count=1).strip()
parts = [
    "You review group hike proposals. Follow the trail-review skill below "
    "for every review request. Its reference files follow the skill. Follow "
    "its steps and its output format exactly. Return only the review result.",
    "# Skill: trail-review\n\n" + body,
]
ref_dir = os.path.join(skill_dir, "references")
for name in sorted(os.listdir(ref_dir)):
    path = os.path.join(ref_dir, name)
    if os.path.isfile(path):
        parts.append("# File: references/%s\n\n%s" % (name, read(path).strip()))

lines = "\n\n".join(parts).replace("\r\n", "\n").split("\n")
indented = [(" " * 12 + l) if l else "" for l in lines]
block = "        instructions: |-\n" + "\n".join(indented) + "\n"

current = read(yaml_path).replace("\r\n", "\n")
pattern = re.compile(r"^        instructions:.*?\n(?=[ ]{0,8}\S)", re.M | re.S)
wanted = pattern.sub(lambda m: block, current, count=1)

if check:
    sys.exit(0 if current == wanted else 3)
with open(yaml_path, "w", encoding="utf-8", newline="") as f:
    f.write(wanted)
print("Synced skills -> 00-prompt-agent (instructions)")
PY
  if [ "$CHECK" -eq 1 ] && [ "$rc" -eq 3 ]; then add_drift "00-prompt-agent (azure.yaml)"; fi
fi

if [ "$CHECK" -eq 1 ]; then
  if [ -n "$DRIFT" ]; then
    echo "Skill copies differ from shared: $DRIFT" >&2
    exit 1
  fi
  echo "All agent skill copies match shared/skills."
fi
