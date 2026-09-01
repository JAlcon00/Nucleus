#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESTINATION="${1:-/Volumes/YisusSSD/Develop/Swift/PR/PR}"

if [[ ! -d "$DESTINATION" ]]; then
  echo "Destination does not exist: $DESTINATION" >&2
  echo "Create/mount the repository first or pass another path as the first argument." >&2
  exit 1
fi

mkdir -p "$DESTINATION/.agents/skills/swift-elite-coach" "$DESTINATION/docs"

for file in promptMaster.md backlog.md plan.md README.md AGENTS.md; do
  cp "$SOURCE_DIR/$file" "$DESTINATION/$file"
done

cp "$SOURCE_DIR/.agents/skills/swift-elite-coach/SKILL.md" \
   "$DESTINATION/.agents/skills/swift-elite-coach/SKILL.md"
cp "$SOURCE_DIR/docs/requirements-traceability.md" \
   "$DESTINATION/docs/requirements-traceability.md"

echo "PR specification installed into: $DESTINATION"
