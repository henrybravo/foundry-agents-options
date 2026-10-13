#!/usr/bin/env bash
# Parses every Mermaid block in a Markdown file with mermaid + jsdom under
# Node. Parsing catches syntax errors; it does not check layout. Needs node
# and npm; the first run installs mermaid and jsdom into ~/.cache/trail-mermaid.
# Run: scripts/validate-mermaid.sh [path/to/file.md]   (default: docs/demo-walkthrough.md)
# Bash equivalent of validate-mermaid.ps1, without the WSL layer the Windows
# script needs (works with the macOS default bash 3.2).
set -eo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="${1:-$ROOT/docs/demo-walkthrough.md}"
CACHE="${HOME}/.cache/trail-mermaid"

command -v node >/dev/null && command -v npm >/dev/null \
  || { echo "node and npm are required." >&2; exit 1; }
[ -f "$FILE" ] || { echo "No such file: $FILE" >&2; exit 1; }

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

COUNT="$(python3 - "$FILE" "$OUT" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
blocks = re.findall(r"```mermaid\r?\n(.*?)```", text, flags=re.S)
for i, b in enumerate(blocks, 1):
    open("%s/diagram-%d.mmd" % (sys.argv[2], i), "w", encoding="utf-8", newline="").write(b)
print(len(blocks))
PY
)"
[ "$COUNT" -gt 0 ] || { echo "No mermaid blocks in $FILE" >&2; exit 1; }

mkdir -p "$CACHE"
if [ ! -d "$CACHE/node_modules/mermaid" ]; then
  ( cd "$CACHE" && npm init -y >/dev/null && npm i --silent mermaid jsdom )
fi

cat > "$CACHE/check.cjs" <<'JS'
const fs = require("fs");
const { JSDOM } = require("jsdom");
const dom = new JSDOM("<!doctype html><body></body>");
global.window = dom.window;
global.document = dom.window.document;
global.DOMParser = dom.window.DOMParser;
(async () => {
  const mermaid = (await import("mermaid")).default;
  mermaid.initialize({ startOnLoad: false });
  let fail = 0;
  const files = fs.readdirSync(process.argv[2])
    .filter((f) => /^diagram-\d+\.mmd$/.test(f))
    .sort((a, b) => parseInt(a.match(/\d+/)[0]) - parseInt(b.match(/\d+/)[0]));
  for (const f of files) {
    const src = fs.readFileSync(`${process.argv[2]}/${f}`, "utf8");
    try {
      await mermaid.parse(src);
      console.log(`OK   ${f}`);
    } catch (e) {
      fail = 1;
      console.log(`FAIL ${f}\n${e.message}`);
    }
  }
  process.exit(fail);
})();
JS

( cd "$CACHE" && node check.cjs "$OUT" ) || { echo "Mermaid validation failed" >&2; exit 1; }
echo "All $COUNT diagrams parsed"
