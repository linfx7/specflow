#!/usr/bin/env sh
# detect-drift.sh
#
# Scans specs/INDEX + specs/*.md frontmatter + the git repo, emits a TSV
# drift report to stdout so the calling LLM can act on it.
#
# Output format: one record per line, TAB-separated.
#   <kind>\t<spec-id-list|->\t<path|->\t<extra1|->\t<extra2|->
#
# Kinds:
#   HASH_MISMATCH    spec-list  path  recorded-hash  disk-hash
#   MISSING_FILE     spec-list  path  -              -
#   UNTRACKED_SRC    -          path  -              -
#   MISSING_SPEC     spec-id    -     -              -    (INDEX ref, no spec file)
#   ORPHAN_SPEC      -          path  -              -    (spec file, not in INDEX, not draft)
#   DUP_ID           -          id    -              -    (duplicate spec ID)
#
# Exit codes:
#   0  = clean (no records)
#   10 = drift found (records printed)
#   2  = fatal (missing INDEX, git failure)

set -eu

INDEX="specs/INDEX"
SPECS_DIR="specs"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TAB=$(printf '\t')

# Operate from the repo root (the worktree's own root when run inside a worktree)
# so relative paths like specs/INDEX resolve regardless of the caller's CWD.
root=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$root" ] && cd "$root"

if [ ! -f "$INDEX" ]; then
  echo "detect-drift: $INDEX not found" >&2
  exit 2
fi

tmp=$(mktemp -d -t specflow-drift-XXXXXX) || { echo "detect-drift: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$tmp"' EXIT

# ---- 1. Partition INDEX into prod / test rows + flatten spec IDs ----
awk -F"$TAB" -v OFS="$TAB" -v assoc="$tmp/assoc.tsv" -v tests="$tmp/tests.tsv" '
  $1 ~ /^#/ || NF != 3 { next }
  $3 == "-" { print $1, $2 > tests; next }
  { print $1, $2, $3 > assoc }
' "$INDEX"
touch "$tmp/assoc.tsv" "$tmp/tests.tsv"

awk -F"$TAB" '
  $1 ~ /^#/ || NF != 3 { next }
  { n = split($2, a, ","); for (i=1; i<=n; i++) print a[i] }
' "$INDEX" | sort -u > "$tmp/index_spec_ids"

# ---- 2. Resolve baseline + scan set ----
baseline=$("$SCRIPT_DIR/index.sh" header baseline)

if [ -n "$baseline" ] && git cat-file -e "$baseline^{commit}" 2>/dev/null; then
  # Fast path: scan only files changed since baseline + newly-untracked.
  # Caveat: `git diff` applies .gitattributes clean filters while the later
  # HASH_MISMATCH check uses raw `git hash-object`. In a repo with clean filters
  # (e.g. autocrlf), a file whose normalized content equals baseline but whose
  # raw bytes changed won't appear here, so its raw-hash drift is skipped on the
  # fast path (the slow path below would still catch it). Acceptable: such
  # changes are cosmetic, and a baseline-less run reconciles them.
  (
    git diff --name-only "$baseline" 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
  ) | sort -u > "$tmp/scan_paths"
else
  git ls-files --cached --others --exclude-standard 2>/dev/null > "$tmp/scan_paths" || {
    echo "detect-drift: git ls-files failed" >&2
    exit 2
  }
fi

# ---- 3. Spec-file frontmatter (id + status) ----
: > "$tmp/fm_status"
if [ -d "$SPECS_DIR" ]; then
  for f in "$SPECS_DIR"/spec-*.md; do
    [ -f "$f" ] || continue
    awk '
      /^---[[:space:]]*$/ { fences++; if (fences >= 2) exit; next }
      fences == 1 && /^id:[[:space:]]*/ {
        v = $0; sub(/^id:[[:space:]]*/, "", v); gsub(/["\047]/, "", v); sub(/[[:space:]]+$/, "", v); id = v
      }
      fences == 1 && /^status:[[:space:]]*/ {
        v = $0; sub(/^status:[[:space:]]*/, "", v); gsub(/["\047]/, "", v); sub(/[[:space:]]+$/, "", v); status = v
      }
      END { if (id != "") printf "%s\t%s\n", id, (status == "" ? "unknown" : status) }
    ' "$f" >> "$tmp/fm_status"
  done
fi
awk -F"$TAB" '{print $1}' "$tmp/fm_status" | sort -u > "$tmp/fm_ids_sorted"

# ---- 4. Pre-compute scan set (production rows inside scan_paths) ----
awk -F"$TAB" '{print $1}' "$tmp/assoc.tsv" | sort -u > "$tmp/assoc_paths"
awk -F"$TAB" '
  NR == FNR { scan[$0] = 1; next }
  ($1 in scan)
' "$tmp/scan_paths" "$tmp/assoc.tsv" > "$tmp/assoc_scan.tsv"

# ---- 5. Emit drift records (everything in this group goes to records + stdout) ----
{
  # DUP_ID: same frontmatter id in two files.
  awk -F"$TAB" '{print $1}' "$tmp/fm_status" | sort | uniq -d | while IFS= read -r dup; do
    [ -n "$dup" ] && printf 'DUP_ID\t-\t%s\t-\t-\n' "$dup"
  done

  # ORPHAN_SPEC: frontmatter id present, not in INDEX, status != draft.
  comm -23 "$tmp/fm_ids_sorted" "$tmp/index_spec_ids" > "$tmp/fm_orphans" || true
  while IFS= read -r orphan_id; do
    [ -n "$orphan_id" ] || continue
    status=$(awk -F"$TAB" -v id="$orphan_id" '$1==id {print $2; exit}' "$tmp/fm_status")
    # draft: code not written yet. deprecated: coverage intentionally emptied.
    # Neither is an orphan -- only a non-draft, non-deprecated spec with no rows is.
    case "$status" in draft|deprecated) continue ;; esac
    printf 'ORPHAN_SPEC\t-\t%s/%s.md\t-\t-\n' "$SPECS_DIR" "$orphan_id"
  done < "$tmp/fm_orphans"

  # MISSING_SPEC: INDEX references an id with no spec file.
  comm -13 "$tmp/fm_ids_sorted" "$tmp/index_spec_ids" | while IFS= read -r miss_id; do
    [ -n "$miss_id" ] && printf 'MISSING_SPEC\t%s\t-\t-\t-\n' "$miss_id"
  done

  # MISSING_FILE: every INDEX path absent from disk (intentionally NOT scoped to
  # scan_paths — a deletion before baseline can still leave a stale INDEX row).
  while IFS="$TAB" read -r path slist hash; do
    [ -n "$path" ] || continue
    [ -e "$path" ] || printf 'MISSING_FILE\t%s\t%s\t-\t-\n' "$slist" "$path"
  done < "$tmp/assoc.tsv"
  while IFS="$TAB" read -r path slist; do
    [ -n "$path" ] || continue
    [ -e "$path" ] || printf 'MISSING_FILE\t%s\t%s\t-\t-\n' "$slist" "$path"
  done < "$tmp/tests.tsv"

  # HASH_MISMATCH: hash each scan-set production file once.
  while IFS="$TAB" read -r path slist recorded; do
    [ -n "$path" ] || continue
    [ -e "$path" ] || continue
    disk=$(git hash-object "$path" 2>/dev/null | cut -c1-7)
    if [ -z "$disk" ]; then
      printf 'HASH_MISMATCH\t%s\t%s\t%s\t(unhashable)\n' "$slist" "$path" "$recorded"
    elif [ "$recorded" != "$disk" ]; then
      printf 'HASH_MISMATCH\t%s\t%s\t%s\t%s\n' "$slist" "$path" "$recorded" "$disk"
    fi
  done < "$tmp/assoc_scan.tsv"

  # UNTRACKED_SRC: scan-set source files not covered by INDEX.
  # Exclusion list mirrors conventions.md "Non-source files" (authoritative there).
  # ^LICENSE matches the LICENSE* glob; (^|/)CLAUDE\.md$ also excludes nested
  # CLAUDE.md (Claude Code reads those as config, not source); README.md root-only.
  grep -Ev '^(specs/|\.git/)|\.lock$|-lock\.json$|^go\.sum$|^LICENSE|(^|/)CLAUDE\.md$|^README\.md$' "$tmp/scan_paths" > "$tmp/candidate_src" || true
  awk -F"$TAB" '{print $1}' "$tmp/tests.tsv" | sort -u > "$tmp/index_test_paths"
  sort -u "$tmp/candidate_src" > "$tmp/candidate_sorted"
  comm -23 "$tmp/candidate_sorted" "$tmp/assoc_paths" \
    | comm -23 - "$tmp/index_test_paths" > "$tmp/unknown_paths"
  while IFS= read -r p; do
    [ -n "$p" ] && [ -e "$p" ] && printf 'UNTRACKED_SRC\t-\t%s\t-\t-\n' "$p"
  done < "$tmp/unknown_paths"
} | tee "$tmp/records"

# ---- 6. Exit ----
[ -s "$tmp/records" ] && exit 10 || exit 0
