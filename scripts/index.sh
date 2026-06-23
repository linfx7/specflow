#!/usr/bin/env sh
# index.sh <verb> [args]
#
# Tiny awk wrappers over specs/INDEX. Mutating verbs rewrite the file
# atomically via a temp file + mv. Rows are always written sorted by path.
#
# INDEX shape:
#   # specflow index v1
#   # lang: <code>    baseline: <commit>
#   <path>\t<spec-id-list>\t<hash>
#
# <spec-id-list> is a comma-separated, alphabetically-sorted list of spec IDs.
# <hash> is the 7-char git-short-hash for production files, "-" for test files.
# Comment lines (^#) and blank lines are ignored by all readers.
#
# Verbs:
#   list-by-spec <spec-id>         paths covered by <spec-id>, one per line
#   list-by-path <path>            spec-id list for <path>, one id per line
#   header <key>                   print lang or baseline header value
#   set-baseline <commit>          rewrite header baseline
#   set-lang <code>                rewrite header lang
#   upsert <path> <spec-id> <hash> add/refresh row; merges spec-id into list
#   remove <path> [spec-id]        drop row; or remove spec-id from list
#   next-id                        print next spec-NNN (zero-padded)

set -eu

# Operate from the repo root so the relative INDEX path resolves regardless of
# the caller's CWD. In a git worktree this is the worktree's own root (which has
# its own specs/), so parallel per-spec worktrees stay independent.
root=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$root" ] && cd "$root"

INDEX="specs/INDEX"
TAB=$(printf '\t')

die() { printf '%s\n' "$1" >&2; exit 1; }
need_index() { [ -f "$INDEX" ] || die "index.sh: $INDEX not found"; }
# Temp file lives in INDEX's own directory so the final mv is a same-filesystem
# atomic rename (mktemp -t lands in $TMPDIR, often a different fs -> mv degrades to
# copy+unlink, not atomic). make_tmp sets TMPFILE in *this* shell (NOT via a $(...)
# subshell, whose assignment wouldn't survive) so the EXIT trap can delete a
# half-written temp if we die mid-write -- otherwise it lingers in the tracked
# specs/ dir and could get committed.
TMPFILE=""
trap '[ -n "$TMPFILE" ] && rm -f "$TMPFILE"' EXIT
make_tmp() { TMPFILE=$(mktemp "$(dirname "$INDEX")/.INDEX.XXXXXX"); }
atomic_write() { mv "$TMPFILE" "$INDEX"; TMPFILE=""; }

# Print the value of header key (lang|baseline) from INDEX, or nothing.
# Used by the `header` verb and by set-baseline/set-lang, so the latter no longer
# self-invoke via "$0" (which required the file to be +x and broke after cd).
header_value() {
  awk -v k="$1" '
    /^#/ {
      line = $0
      sub(/^#[[:space:]]*/, "", line)
      n = split(line, t, /[[:space:]]+/)
      for (i=1; i<=n; i++) {
        idx = index(t[i], ":")
        if (idx < 1) continue
        if (substr(t[i], 1, idx-1) != k) continue
        val = substr(t[i], idx+1)
        if (val != "") { print val; exit }
        if ((i+1) <= n) { print t[i+1]; exit }
      }
    }
  ' "$INDEX"
}

verb="${1:-}"
[ -n "$verb" ] || die "index.sh: missing verb"
shift || true

case "$verb" in
  list-by-spec)
    need_index
    sid="${1:-}"; [ -n "$sid" ] || die "index.sh list-by-spec: missing spec-id"
    awk -F"$TAB" -v s="$sid" '
      $1 !~ /^#/ && NF==3 {
        n = split($2, a, ",")
        for (i=1; i<=n; i++) if (a[i] == s) { print $1; break }
      }
    ' "$INDEX"
    ;;

  list-by-path)
    need_index
    p="${1:-}"; [ -n "$p" ] || die "index.sh list-by-path: missing path"
    awk -F"$TAB" -v p="$p" '
      $1 !~ /^#/ && NF==3 && $1 == p {
        n = split($2, a, ",")
        for (i=1; i<=n; i++) print a[i]
        exit
      }
    ' "$INDEX"
    ;;

  header)
    need_index
    key="${1:-}"; [ -n "$key" ] || die "index.sh header: missing key"
    header_value "$key"
    ;;

  set-baseline|set-lang)
    need_index
    val="${1:-}"; [ -n "$val" ] || die "index.sh $verb: missing value"
    case "$verb" in set-lang) new_lang="$val"; new_baseline="";; *) new_baseline="$val"; new_lang="";; esac
    cur_lang=$(header_value lang)
    cur_baseline=$(header_value baseline)
    [ -n "$new_lang" ] || new_lang="${cur_lang:--}"
    [ -n "$new_baseline" ] || new_baseline="${cur_baseline:--}"
    make_tmp
    {
      printf '# specflow index v1\n'
      printf '# lang: %s    baseline: %s\n' "$new_lang" "$new_baseline"
      # Rewrite the two managed header lines, but preserve any extra comment
      # lines the user added (3rd onward) and all body rows -- upsert preserves
      # comments too, so the two verbs stay consistent.
      awk -F"$TAB" '/^#/ { c++; if (c > 2) print; next } NF >= 1 { print }' "$INDEX"
    } > "$TMPFILE"
    atomic_write
    ;;

  upsert)
    need_index
    p="${1:-}"; sid="${2:-}"; hash="${3:-}"
    [ -n "$p" ] && [ -n "$sid" ] && [ -n "$hash" ] \
      || die "index.sh upsert: need <path> <spec-id> <hash>"
    make_tmp
    awk -F"$TAB" -v OFS="$TAB" -v p="$p" -v s="$sid" -v h="$hash" '
      function merge(list, newid,    a, n, i, j, t, have, out) {
        n = split(list, a, ",")
        have = 0
        for (i=1; i<=n; i++) if (a[i] == newid) have = 1
        if (!have) { n++; a[n] = newid }
        for (i=1; i<=n; i++) for (j=i+1; j<=n; j++)
          if (a[i] > a[j]) { t=a[i]; a[i]=a[j]; a[j]=t }
        out = a[1]
        for (i=2; i<=n; i++) out = out "," a[i]
        return out
      }
      /^#/ { headers[++hn] = $0; next }
      NF < 3 { next }
      {
        if ($1 == p) { rows[$1] = $1 OFS merge($2, s) OFS h; seen = 1 }
        else { rows[$1] = $0 }
      }
      END {
        if (!seen) rows[p] = p OFS s OFS h
        for (i=1; i<=hn; i++) print headers[i]
        n = 0
        for (k in rows) { n++; ks[n] = k }
        for (i=1; i<=n; i++) for (j=i+1; j<=n; j++)
          if (ks[i] > ks[j]) { t=ks[i]; ks[i]=ks[j]; ks[j]=t }
        for (i=1; i<=n; i++) print rows[ks[i]]
      }
    ' "$INDEX" > "$TMPFILE"
    atomic_write
    ;;

  remove)
    need_index
    p="${1:-}"; sid="${2:-}"
    [ -n "$p" ] || die "index.sh remove: missing path"
    make_tmp
    awk -F"$TAB" -v OFS="$TAB" -v p="$p" -v s="$sid" '
      /^#/ { print; next }
      NF < 3 { next }
      $1 != p { print; next }
      {
        if (s == "") next
        n = split($2, a, ",")
        m = 0
        for (i=1; i<=n; i++) if (a[i] != s) { m++; b[m] = a[i] }
        if (m == 0) next
        list = b[1]
        for (i=2; i<=m; i++) list = list "," b[i]
        print $1, list, $3
      }
    ' "$INDEX" > "$TMPFILE"
    atomic_write
    ;;

  next-id)
    # Scan specs/spec-*.md filenames AND INDEX column 2 for the max NNN.
    # Width grows naturally: spec-099 → spec-100 keeps working.
    max=0
    width=3
    if [ -d specs ]; then
      for f in specs/spec-*.md; do
        [ -e "$f" ] || continue
        base=$(basename "$f" .md)
        num=$(printf '%s' "$base" | awk -F- '{print $2}')
        case "$num" in ''|*[!0-9]*) continue ;; esac
        len=${#num}
        [ "$len" -gt "$width" ] && width=$len
        # Strip leading zeros before any arithmetic: $((008)) / $((009)) are
        # parsed as octal and blow up on the 8/9 digit. dec is plain decimal.
        dec=$(printf '%s' "$num" | sed 's/^0*//'); [ -n "$dec" ] || dec=0
        [ "$dec" -gt "$max" ] && max=$dec
      done
    fi
    if [ -f "$INDEX" ]; then
      idx_max=$(awk -F"$TAB" '
        $1 !~ /^#/ && NF==3 {
          n = split($2, a, ",")
          for (i=1; i<=n; i++) if (match(a[i], /^spec-[0-9]+/)) {
            num = substr(a[i], 6, RLENGTH-5) + 0
            if (num > m) m = num
          }
        }
        END { print m+0 }
      ' "$INDEX")
      idx_width=$(awk -F"$TAB" '
        $1 !~ /^#/ && NF==3 {
          n = split($2, a, ",")
          for (i=1; i<=n; i++) if (match(a[i], /^spec-[0-9]+/)) {
            len = RLENGTH - 5
            if (len > w) w = len
          }
        }
        END { print w+0 }
      ' "$INDEX")
      [ "$idx_width" -gt "$width" ] && width=$idx_width
      [ "$idx_max" -gt "$max" ] && max=$idx_max
    fi
    next=$((max + 1))
    printf "spec-%0${width}d\n" "$next"
    ;;

  *)
    die "index.sh: unknown verb \`$verb\`"
    ;;
esac
