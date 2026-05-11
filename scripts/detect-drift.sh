#!/usr/bin/env sh
# detect-drift.sh [--scope scope]
#
# Scans INDEX.md + feature docs + the git repo, emits a TSV drift report
# to stdout so the calling LLM can act on it without re-reading every file.
#
# Output format: one record per line, TAB-separated.
#   <kind>\t<feature-id|->\t<path|->\t<extra1|->\t<extra2|->
#
# Kinds:
#   HASH_MISMATCH    feature  path  recorded-hash  disk-hash
#   SHARED_DIVERGE   -        path  disk-hash      feat:hash,feat:hash
#   MISSING_FILE     feature  path  -              -                  (listed but not on disk)
#   UNTRACKED_SRC    -        path  -              -                  (on disk, not in any feature)
#   MISSING_TEST     feature  path  -              -
#   ORPHAN_TEST      -        path  -              -
#   ORPHAN_DOC       -        path  -              -                  (doc/features/*.md without INDEX entry)
#   MISSING_DOC      feature  -     -              -                  (INDEX entry without doc)
#   DUP_ID           -        id    -              -
#
# Exit codes:
#   0 = clean (no records)
#   10 = drift found (records printed)
#   2 = fatal (missing INDEX, malformed YAML, git failure)

set -eu

INDEX="docs/INDEX.md"
FEATURES_DIR="docs/features"

if [ ! -f "$INDEX" ]; then
  echo "detect-drift: $INDEX not found" >&2
  exit 2
fi

tmp=$(mktemp -d -t docflow-drift-XXXXXX) || { echo "detect-drift: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$tmp"' EXIT

# ---- 1. Parse INDEX.md YAML frontmatter ----
# Extract lines between the first two `---` markers, pull `id:` and `status:` pairs.
awk '
  BEGIN { in_fm = 0; count = 0 }
  /^---[[:space:]]*$/ {
    count++
    if (count == 1) { in_fm = 1; next }
    if (count == 2) { in_fm = 0; exit }
  }
  in_fm == 1 { print }
' "$INDEX" > "$tmp/frontmatter" || { echo "detect-drift: failed to read INDEX frontmatter" >&2; exit 2; }

if [ ! -s "$tmp/frontmatter" ]; then
  echo "detect-drift: $INDEX has no YAML frontmatter" >&2
  exit 2
fi

# Parse feature list — each feature block starts with `- id:`
awk '
  /^[[:space:]]*-[[:space:]]*id:[[:space:]]*/ {
    sub(/^[[:space:]]*-[[:space:]]*id:[[:space:]]*/, "")
    gsub(/["\047]/, "")
    sub(/[[:space:]]+$/, "")
    print
  }
' "$tmp/frontmatter" > "$tmp/index_ids"

# ---- 2. Duplicate IDs ----
sort "$tmp/index_ids" | uniq -d > "$tmp/dup_ids"
while IFS= read -r dup; do
  [ -n "$dup" ] && printf 'DUP_ID\t-\t%s\t-\t-\n' "$dup"
done < "$tmp/dup_ids"

# ---- 3. Orphan docs / Missing docs ----
if [ -d "$FEATURES_DIR" ]; then
  ls "$FEATURES_DIR" 2>/dev/null | awk '/\.md$/ { sub(/\.md$/, ""); print }' | sort -u > "$tmp/doc_ids"
else
  : > "$tmp/doc_ids"
fi
sort -u "$tmp/index_ids" > "$tmp/index_ids_sorted"

comm -23 "$tmp/doc_ids" "$tmp/index_ids_sorted" > "$tmp/orphan_docs"
while IFS= read -r id; do
  [ -n "$id" ] && printf 'ORPHAN_DOC\t-\t%s/%s.md\t-\t-\n' "$FEATURES_DIR" "$id"
done < "$tmp/orphan_docs"

comm -13 "$tmp/doc_ids" "$tmp/index_ids_sorted" > "$tmp/missing_docs"
while IFS= read -r id; do
  [ -n "$id" ] && printf 'MISSING_DOC\t%s\t-\t-\t-\n' "$id"
done < "$tmp/missing_docs"

# ---- 4. Extract associations from each feature doc ----
# Produces two files:
#   assoc.tsv  — feature \t path \t recorded-hash
#   tests.tsv  — feature \t path
: > "$tmp/assoc.tsv"
: > "$tmp/tests.tsv"

for docfile in "$FEATURES_DIR"/*.md; do
  [ -f "$docfile" ] || continue
  fid=$(basename "$docfile" .md)
  awk -v fid="$fid" '
    BEGIN { section = "" }
    /^##[[:space:]]+Associated Files[[:space:]]*$/ { section = "assoc"; next }
    /^##[[:space:]]+Tests[[:space:]]*$/           { section = "tests"; next }
    /^##[[:space:]]+/                             { section = "";      next }
    section == "assoc" && /^[[:space:]]*-[[:space:]]+/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]+/, "", line)
      # Expect: <path> | <hash>
      n = split(line, a, /[[:space:]]*\|[[:space:]]*/)
      if (n >= 2) {
        path = a[1]; hash = a[2]
        sub(/[[:space:]]+$/, "", path)
        sub(/[[:space:]]+$/, "", hash)
        printf "%s\t%s\t%s\n", fid, path, hash >> "'"$tmp"'/assoc.tsv"
      }
      next
    }
    section == "tests" && /^[[:space:]]*-[[:space:]]+/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line != "") {
        printf "%s\t%s\n", fid, line >> "'"$tmp"'/tests.tsv"
      }
      next
    }
  ' "$docfile"
done

# ---- 5. Hash mismatches + missing files (production) ----
while IFS="$(printf '\t')" read -r fid path recorded; do
  [ -n "$path" ] || continue
  if [ ! -e "$path" ]; then
    printf 'MISSING_FILE\t%s\t%s\t-\t-\n' "$fid" "$path"
    continue
  fi
  # Hash from HEAD (conventions.md rule: always read from HEAD, not working tree)
  disk=$(git rev-parse --short=7 "HEAD:$path" 2>/dev/null || echo "")
  if [ -z "$disk" ]; then
    # path exists on disk but not in HEAD — treat as hash mismatch with empty disk hash
    printf 'HASH_MISMATCH\t%s\t%s\t%s\t(not-in-HEAD)\n' "$fid" "$path" "$recorded"
    continue
  fi
  if [ "$recorded" != "$disk" ]; then
    printf 'HASH_MISMATCH\t%s\t%s\t%s\t%s\n' "$fid" "$path" "$recorded" "$disk"
  fi
done < "$tmp/assoc.tsv"

# ---- 6. Shared-file hash divergence ----
# For paths listed in >1 features, if their recorded hashes differ -> SHARED_DIVERGE.
awk -F'\t' '
  { paths[$2] = paths[$2] ? paths[$2] "," $1 ":" $3 : $1 ":" $3; count[$2]++ }
  END {
    for (p in paths) if (count[p] > 1) print p "\t" paths[p]
  }
' "$tmp/assoc.tsv" > "$tmp/shared"

while IFS="$(printf '\t')" read -r path feats; do
  # Are all recorded hashes identical?
  uniq_hashes=$(printf '%s\n' "$feats" | tr ',' '\n' | awk -F: '{print $2}' | sort -u | wc -l | tr -d ' ')
  if [ "$uniq_hashes" -gt 1 ]; then
    disk=""
    [ -e "$path" ] && disk=$(git rev-parse --short=7 "HEAD:$path" 2>/dev/null || echo "")
    printf 'SHARED_DIVERGE\t-\t%s\t%s\t%s\n' "$path" "${disk:--}" "$feats"
  fi
done < "$tmp/shared"

# ---- 7. Missing tests ----
while IFS="$(printf '\t')" read -r fid tpath; do
  [ -n "$tpath" ] || continue
  if [ ! -e "$tpath" ]; then
    printf 'MISSING_TEST\t%s\t%s\t-\t-\n' "$fid" "$tpath"
  fi
done < "$tmp/tests.tsv"

# ---- 8. Untracked source + orphan tests ----
# All tracked + untracked-but-not-ignored files:
git ls-files --cached --others --exclude-standard 2>/dev/null > "$tmp/all_files" || {
  echo "detect-drift: git ls-files failed" >&2
  exit 2
}

# Non-source / docflow / boilerplate exclusions (conventions.md rule)
grep -Ev '^(docs/|\.docflow/|\.git/)|\.lock$|-lock\.json$|^go\.sum$|^LICENSE|^CLAUDE\.md$|^README\.md$' "$tmp/all_files" > "$tmp/candidate_src" || true

# Test patterns (conventions.md)
grep -E '(^|/)tests/|(^|/)__tests__/|\.test\.|_test\.|(^|/)test_[^/]+$' "$tmp/candidate_src" | sort -u > "$tmp/disk_tests" || true
grep -Ev '(^|/)tests/|(^|/)__tests__/|\.test\.|_test\.|(^|/)test_[^/]+$' "$tmp/candidate_src" | sort -u > "$tmp/disk_src" || true

awk -F'\t' '{print $2}' "$tmp/assoc.tsv" | sort -u > "$tmp/assoc_paths"
awk -F'\t' '{print $2}' "$tmp/tests.tsv" | sort -u > "$tmp/test_paths"

comm -23 "$tmp/disk_src" "$tmp/assoc_paths" > "$tmp/untracked_src"
while IFS= read -r p; do
  [ -n "$p" ] && printf 'UNTRACKED_SRC\t-\t%s\t-\t-\n' "$p"
done < "$tmp/untracked_src"

comm -23 "$tmp/disk_tests" "$tmp/test_paths" > "$tmp/orphan_tests"
while IFS= read -r p; do
  [ -n "$p" ] && printf 'ORPHAN_TEST\t-\t%s\t-\t-\n' "$p"
done < "$tmp/orphan_tests"

# ---- 9. Exit code ----
# Count records printed. We tee'd to stdout directly; detect by running again with -c.
# Simpler: mark a sentinel in a file whenever we print.
# Re-do with a counter: actually, recompute quickly — if any of the intermediate files have content.
clean=1
for f in dup_ids orphan_docs missing_docs; do
  [ -s "$tmp/$f" ] && clean=0
done
[ -s "$tmp/assoc.tsv" ] && {
  # Any HASH_MISMATCH or MISSING_FILE would have been emitted; we detect via a quick rescan.
  while IFS="$(printf '\t')" read -r fid path recorded; do
    if [ ! -e "$path" ]; then clean=0; break; fi
    disk=$(git rev-parse --short=7 "HEAD:$path" 2>/dev/null || echo "")
    if [ -z "$disk" ] || [ "$recorded" != "$disk" ]; then clean=0; break; fi
  done < "$tmp/assoc.tsv"
}
[ -s "$tmp/shared" ] && {
  while IFS="$(printf '\t')" read -r path feats; do
    u=$(printf '%s\n' "$feats" | tr ',' '\n' | awk -F: '{print $2}' | sort -u | wc -l | tr -d ' ')
    [ "$u" -gt 1 ] && { clean=0; break; }
  done < "$tmp/shared"
}
[ -s "$tmp/untracked_src" ] && clean=0
[ -s "$tmp/orphan_tests" ] && clean=0
# Missing tests:
while IFS="$(printf '\t')" read -r fid tpath; do
  if [ -n "$tpath" ] && [ ! -e "$tpath" ]; then clean=0; break; fi
done < "$tmp/tests.tsv"

if [ "$clean" -eq 1 ]; then
  exit 0
else
  exit 10
fi
