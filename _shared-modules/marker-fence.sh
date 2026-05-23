#!/usr/bin/env bash
# marker-fence.sh — parse and rewrite HTML-comment-fenced regions in markdown.
#
# Fence syntax:
#   <!-- BEGIN memo-flow:<section> -->
#   ...content...
#   <!-- END memo-flow:<section> -->
#
# Usage:
#   marker-fence.sh insert <file> <section> <content>
#     Insert content in a fence. If fence already exists, update inner content
#     when it differs (idempotent when content matches). Corruption (only BEGIN
#     without END) leaves the file alone and exits 2 with a warning on stderr.
#
#   marker-fence.sh remove <file> <section>
#     Remove the fence markers and inner content from the file.

set -euo pipefail

cmd="${1:-}"
if [ -z "$cmd" ]; then
  echo "usage: marker-fence.sh <insert|remove> <file> <section> [content]" >&2
  exit 1
fi

_begin_marker() { echo "<!-- BEGIN memo-flow:${1} -->"; }
_end_marker()   { echo "<!-- END memo-flow:${1} -->"; }

# fence_insert <file> <section> <content>
fence_insert() {
  local file="$1" section="$2" content="$3"
  local begin end

  begin="$(_begin_marker "$section")"
  end="$(_end_marker "$section")"

  if [ ! -f "$file" ]; then
    echo "marker-fence: file not found: $file" >&2
    return 1
  fi

  local has_begin has_end
  has_begin=$(grep -cF "$begin" "$file" 2>/dev/null || true)
  has_end=$(grep -cF "$end" "$file" 2>/dev/null || true)

  # Corruption: BEGIN without END
  if [ "${has_begin:-0}" -gt 0 ] && [ "${has_end:-0}" -eq 0 ]; then
    echo "marker-fence: corruption in '$file': BEGIN without END for section '$section' — leaving file alone" >&2
    return 2
  fi

  # Fence exists: check if update is needed
  if [ "${has_begin:-0}" -gt 0 ] && [ "${has_end:-0}" -gt 0 ]; then
    # Extract current inner content (lines between markers, exclusive)
    local current_content
    current_content=$(awk -v begin="$begin" -v end="$end" '
      $0 == begin { in_fence=1; next }
      in_fence && $0 == end { in_fence=0; next }
      in_fence { print }
    ' "$file")

    if [ "$current_content" = "$content" ]; then
      return 0  # no-op: content matches
    fi

    # Replace inner content. Write new content to a temp file so awk can read
    # it without hitting shell quoting limits on multiline strings.
    local tmpfile content_file
    tmpfile=$(mktemp)
    content_file=$(mktemp)
    printf '%s' "$content" > "$content_file"

    awk -v begin="$begin" -v end="$end" -v cf="$content_file" '
      $0 == begin {
        print
        while ((getline line < cf) > 0) print line
        close(cf)
        in_fence=1
        next
      }
      in_fence && $0 == end { in_fence=0; print; next }
      in_fence { next }
      { print }
    ' "$file" > "$tmpfile"
    mv "$tmpfile" "$file"
    rm -f "$content_file"
    return 0
  fi

  # No fence: append to file
  {
    printf '\n%s\n' "$begin"
    printf '%s\n' "$content"
    printf '%s\n' "$end"
  } >> "$file"
}

# fence_remove <file> <section>
fence_remove() {
  local file="$1" section="$2"
  local begin end

  begin="$(_begin_marker "$section")"
  end="$(_end_marker "$section")"

  if [ ! -f "$file" ]; then
    echo "marker-fence: file not found: $file" >&2
    return 1
  fi

  local tmpfile
  tmpfile=$(mktemp)
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { in_fence=1; next }
    in_fence && $0 == end { in_fence=0; next }
    in_fence { next }
    { print }
  ' "$file" > "$tmpfile"
  mv "$tmpfile" "$file"
}

# ── dispatch ──────────────────────────────────────────────────────────────────

case "$cmd" in
  insert)
    file="${2:-}"
    section="${3:-}"
    content="${4:-}"
    if [ -z "$file" ] || [ -z "$section" ]; then
      echo "usage: marker-fence.sh insert <file> <section> <content>" >&2
      exit 1
    fi
    fence_insert "$file" "$section" "$content"
    ;;
  remove)
    file="${2:-}"
    section="${3:-}"
    if [ -z "$file" ] || [ -z "$section" ]; then
      echo "usage: marker-fence.sh remove <file> <section>" >&2
      exit 1
    fi
    fence_remove "$file" "$section"
    ;;
  *)
    echo "marker-fence: unknown command '$cmd'" >&2
    exit 1
    ;;
esac
