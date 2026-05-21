#!/usr/bin/env bash
# memo-flow-doctor.sh — per-mutation drift report for a memo-flow managed project.
#
# Usage:
#   memo-flow-doctor.sh [--fix] [--project-dir <dir>] [--bundle-dir <dir>]
#   memo-flow-doctor.sh --survey [--registry <file>] [--bundle-dir <dir>]
#
# Flags:
#   --project-dir <dir>   project root (default: cwd)
#   --bundle-dir <dir>    bundle source directory (default: auto-detect)
#   --fix                 non-interactively restore all non-customized drifted/missing files
#   --survey              roll-up check across all projects in the user registry
#   --registry <file>     user registry file (default: ~/.claude/memo-flow/registry.json)
#
# Reports per-mutation status:
#   up-to-date      disk matches both manifest and bundle checksums
#   drifted-clean   bundle updated since install, disk still matches manifest
#   drifted-edited  user has modified the file (disk differs from manifest)
#   missing         manifest entry exists but file not on disk
#   customized      mutation has customized:true (opted out of updates)
#
# Read-only by default. Pass --fix to restore files non-interactively.
# Routes config-level decisions (doc_block, settings_entry) to /setup-memo-flow.
# Honors customized flag — never overwrites customized mutations.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_SH="$SKILL_DIR/modules/manifest.sh"
BUNDLE_INV_SH="$SKILL_DIR/modules/bundle-inventory.sh"
DRIFT_SH="$SKILL_DIR/modules/drift-detector.sh"

# ── arg parsing ───────────────────────────────────────────────────────────────

PROJECT_DIR="$(pwd)"
BUNDLE_DIR=""
FIX=false
SURVEY=false
REGISTRY_FILE="$HOME/.claude/memo-flow/registry.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --bundle-dir)  BUNDLE_DIR="$2";  shift 2 ;;
    --fix)         FIX=true;         shift ;;
    --survey)      SURVEY=true;      shift ;;
    --registry)    REGISTRY_FILE="$2"; shift 2 ;;
    *) echo "memo-flow-doctor: unknown flag: $1" >&2; exit 1 ;;
  esac
done

# ── survey mode ──────────────────────────────────────────────────────────────

if [ "$SURVEY" = true ]; then
  if [ ! -f "$REGISTRY_FILE" ]; then
    echo "memo-flow-doctor: no user registry found at $REGISTRY_FILE" >&2
    exit 1
  fi

  if [ -z "$BUNDLE_DIR" ]; then
    if [ -d "$HOME/.claude/skills/memo-flow" ]; then
      BUNDLE_DIR="$HOME/.claude/skills/memo-flow"
    else
      echo "memo-flow-doctor: bundle directory not found — pass --bundle-dir <dir>" >&2
      exit 1
    fi
  fi

  projects=$(python3 -c "
import json, sys
data = json.load(open('$REGISTRY_FILE'))
for p in data.get('projects', []):
    print(p['path'])
")

  if [ -z "$projects" ]; then
    echo "memo-flow-doctor: no projects registered in $REGISTRY_FILE"
    exit 0
  fi

  echo "memo-flow-doctor: survey across registered projects"
  echo ""
  printf "  %-50s  %s\n" "project" "status"
  printf "  %-50s  %s\n" "-------" "------"

  TMPDIR_SURVEY=$(mktemp -d)
  trap 'rm -rf "$TMPDIR_SURVEY"' EXIT

  while IFS= read -r proj_path; do
    if [ ! -d "$proj_path" ]; then
      printf "  %-50s  %s\n" "$proj_path" "(dead registry entry — skipped)"
      echo "  warning: dead registry entry: $proj_path" >&2
      continue
    fi

    proj_manifest="$proj_path/.claude/memo-flow/manifest.json"
    if [ ! -f "$proj_manifest" ]; then
      printf "  %-50s  %s\n" "$proj_path" "no manifest"
      continue
    fi

    inv_file="$TMPDIR_SURVEY/inventory.json"
    "$BUNDLE_INV_SH" scan "$BUNDLE_DIR" > "$inv_file"
    findings=$("$DRIFT_SH" check "$proj_manifest" "$inv_file" "$proj_path" 2>/dev/null || echo "[]")

    status=$(python3 -c "
import json, sys
items = json.loads(sys.argv[1])
if not items:
    print('clean')
    sys.exit(0)
statuses = [i['status'] for i in items]
bad = [s for s in statuses if s not in ('up-to-date', 'customized')]
if not bad:
    print('clean')
elif 'missing' in bad:
    missing_count = sum(1 for s in bad if s == 'missing')
    drift_count = sum(1 for s in bad if 'drift' in s)
    parts = []
    if missing_count:
        parts.append(str(missing_count) + ' missing')
    if drift_count:
        parts.append(str(drift_count) + ' drift')
    print(', '.join(parts))
else:
    drift_count = len(bad)
    print(str(drift_count) + ' drift')
" "$findings")

    printf "  %-50s  %s\n" "$proj_path" "$status"
  done <<< "$projects"

  echo ""
  exit 0
fi

MANIFEST="$PROJECT_DIR/.claude/memo-flow/manifest.json"

# ── pre-flight ────────────────────────────────────────────────────────────────

if [ ! -f "$MANIFEST" ]; then
  echo "memo-flow-doctor: no manifest found at $MANIFEST — is memo-flow installed in this project?" >&2
  exit 1
fi

"$MANIFEST_SH" validate "$MANIFEST" || exit 1

# ── locate bundle ─────────────────────────────────────────────────────────────

if [ -z "$BUNDLE_DIR" ]; then
  if [ -d "$HOME/.claude/skills/memo-flow" ]; then
    BUNDLE_DIR="$HOME/.claude/skills/memo-flow"
  elif [ -d "$PROJECT_DIR/.claude/skills/memo-flow" ]; then
    BUNDLE_DIR="$PROJECT_DIR/.claude/skills/memo-flow"
  else
    echo "memo-flow-doctor: bundle directory not found — pass --bundle-dir <dir>" >&2
    exit 1
  fi
fi

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "memo-flow-doctor: bundle directory not found: $BUNDLE_DIR" >&2
  exit 1
fi

# ── run inventory + drift detection ──────────────────────────────────────────

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "$TMPDIR_WORK"' EXIT

INVENTORY_FILE="$TMPDIR_WORK/inventory.json"
"$BUNDLE_INV_SH" scan "$BUNDLE_DIR" > "$INVENTORY_FILE"

FINDINGS=$("$DRIFT_SH" check "$MANIFEST" "$INVENTORY_FILE" "$PROJECT_DIR")

# ── report ────────────────────────────────────────────────────────────────────

total=$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])))" "$FINDINGS")
needs_attention=$(python3 -c "
import json, sys
items = json.loads(sys.argv[1])
count = sum(1 for i in items if i['status'] not in ('up-to-date', 'customized'))
print(count)
" "$FINDINGS")

echo "memo-flow-doctor: checking $PROJECT_DIR"
echo ""

if [ "$total" -eq 0 ]; then
  echo "  no managed mutations found in manifest"
  echo ""
  exit 0
fi

python3 -c "
import json, sys
items = json.loads(sys.argv[1])
for item in items:
    status = item['status']
    target = item['target']
    note = ''
    if status == 'drifted-edited':
        note = '  [user edits]'
    elif status == 'drifted-clean':
        note = '  [bundle updated]'
    elif status == 'customized':
        note = '  [opted out]'
    print(f'  {status:<18} {target}{note}')
" "$FINDINGS"

echo ""

if [ "$needs_attention" -eq 0 ]; then
  echo "  all managed files are up-to-date"
  exit 0
fi

echo "  $needs_attention item(s) need attention"

# ── fix ───────────────────────────────────────────────────────────────────────

if [ "$FIX" = false ]; then
  echo "  run with --fix to repair non-interactively"
  exit 0
fi

echo ""
echo "memo-flow-doctor: applying fixes..."

python3 -c "
import json, sys
items = json.loads(sys.argv[1])
for item in items:
    print(json.dumps(item))
" "$FINDINGS" | while IFS= read -r finding; do
  status=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['status'])" "$finding")
  target=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['target'])" "$finding")
  fid=$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['id'])" "$finding")

  case "$status" in
    up-to-date|customized)
      continue
      ;;
    missing|drifted-edited|drifted-clean)
      source_rel=$(python3 -c "
import json, sys
inv = json.load(open('$INVENTORY_FILE'))
target = '$target'
for item in inv:
    if item['target'] == target:
        print(item['source'])
        break
")
      if [ -z "$source_rel" ]; then
        echo "  skipped  $target  (source not found in bundle inventory)"
        continue
      fi
      src="$BUNDLE_DIR/$source_rel"
      dst="$PROJECT_DIR/$target"
      if [ ! -f "$src" ]; then
        echo "  skipped  $target  (bundle source missing: $src)"
        continue
      fi
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst"
      echo "  fixed    $target"
      ;;
    orphan)
      echo "  skipped  $target  (orphan — run /setup-memo-flow to reconcile)"
      ;;
    *)
      echo "  skipped  $target  (route to /setup-memo-flow for config-level changes)"
      ;;
  esac
done

echo ""
echo "memo-flow-doctor: done"
