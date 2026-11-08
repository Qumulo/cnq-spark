#!/usr/bin/env bash
# Fails if anything internal, secret or private is about to go public.
#   scripts/scrub-check.sh            always-on checks
#   scripts/scrub-check.sh --release  also fails on unfinished placeholders, a missing LICENSE,
#                                     and binary files or images that have not been reviewed
#   scripts/scrub-check.sh --record-images
#                                     records the binary files and images as reviewed, in .github/image-review.sha256.
#                                     Run it only after checking each one.
#   scripts/scrub-check.sh --history  also scans every commit on every branch for keys, internal
#                                     files and internal names, and fails on any author or committer
#                                     email that is not a GitHub noreply address. Whatever is in
#                                     history is public too.
# CI runs it, then with --release --history, on every push, pull request and merge queue run.
set -uo pipefail
cd "$(dirname "$0")/.."
release=0; history=0; record=0
for a in "$@"; do case "$a" in --release) release=1;; --history) history=1;; --record-images) record=1;; esac; done

# Every file, NUL-separated and unquoted: git quotes a name with an accent or a space unless told not to,
# and a quoted name would slip past every check below.
if git rev-parse --git-dir >/dev/null 2>&1 && [[ -n $(git ls-files | head -1) ]]; then
  list0() { git -c core.quotePath=false ls-files -z; }
else
  list0() { find . -type f -not -path './.git/*' -printf '%P\0'; }
fi
# Text checks can't read a binary file or see what an image shows, even one stored as text, so every
# binary file and every image needs a recorded review.
review=.github/image-review.sha256
image_ext='\.(svgz?|xpm|xbm|p[bgpn]m|pam|eps|ps|pdf|png|jpe?g|gif|webp|bmp|tiff?|avif|hei[cf]|ico|icns)$'
needs_review() { # NUL-separated and sorted: every non-empty binary file and every image
  list0 | while IFS= read -r -d '' f; do
    [[ -s $f ]] || continue
    if grep -qiE "$image_ext" <<<"$f" || ! grep -Iq . "$f"; then printf '%s\0' "$f"; fi
  done | LC_ALL=C sort -z
}
review_sums() { needs_review | xargs -0 -r sha256sum; }
if (( record )); then
  mkdir -p "$(dirname "$review")" && review_sums > "$review" || exit 1
  echo "recorded $(grep -c . "$review") reviewed files in $review"; exit 0
fi

# Internal names are not listed here: this file is public, and the list would publish the names it keeps
# out. The list is an extended regex, matched in any case, in SCRUB_INTERNAL_RE: CI takes it from the
# repository secret of that name, and maintainers export it to run this script themselves. Without it the
# script fails, unless SCRUB_ALLOW_NO_INTERNAL=1 (CI sets that only for pull requests from forks, which
# get no secrets). Every message masks listed names as [internal], so a public CI log doesn't repeat them.
INTERNAL_RE=${SCRUB_INTERNAL_RE:-}
fail=0
mask() { if [[ -n $INTERNAL_RE ]]; then sed -E $'s\001'"$INTERNAL_RE"$'\001[internal]\001gI'; else cat; fi; }
say() { printf '%s\n' "$*" | mask >&2; }
show() { mask | sed 's/^/    /' >&2; } # lists hits under a FAIL or WARN line
bad() { say "FAIL: $*"; fail=1; }
if [[ -z $INTERNAL_RE ]]; then
  if [[ ${SCRUB_ALLOW_NO_INTERNAL:-0} == 1 ]]; then
    say "WARN: SCRUB_INTERNAL_RE is not set, so internal names were not checked"
  else
    bad "SCRUB_INTERNAL_RE is not set, so internal names can't be checked (see docs/MAINTAINING.md)"
  fi
elif [[ $INTERNAL_RE == *[\^\$]* ]]; then
  # Names match anywhere in a line, and messages add a location prefix, so an anchor would miss hits and masking.
  INTERNAL_RE=; bad "SCRUB_INTERNAL_RE uses ^ or \$; names are matched anywhere in a line, so it can't use anchors"
else
  echo | grep -qiE -e "$INTERNAL_RE" 2>/dev/null; rc=$?
  if (( rc != 1 )); then
    (( rc == 0 )) && why="matches an empty line, so it would match everything" || why="is not a valid extended regex"
    INTERNAL_RE=; bad "SCRUB_INTERNAL_RE $why"
  fi
fi

files=$(list0 | tr '\0' '\n')
# A name with a double quote, a backslash or a control character is one git still quotes; it can't be checked.
hits=$(list0 | LC_ALL=C grep -zaE '["\\[:cntrl:]]' | tr '\0' '\n' || true)
[[ -n $hits ]] && { bad "file names that git has to quote; rename them"; printf '%s\n' "$hits" | show; }

# 1. Forbidden paths: internal source, planning docs, secrets. The internal repository's own files and
# tooling are named in SCRUB_INTERNAL_RE, not here, and fail below as internal names in a file name.
path_msg() { # prints why a path must never be committed, or nothing
  case "$1" in
    cmd/*|internal/*|mockups/*|reference/*|deploy-logs/*|docs/issues/*|docs/plans/*|docs/specs/*) echo "internal path";;
    go.mod|go.sum) echo "internal file";;
    *.pem|*.key|*.pfx|*id_rsa*|*id_ed25519*|*.tfstate|*.tfstate.*) echo "key or state file";;
    *.env) echo "env file";;
  esac
}
while IFS= read -r f; do
  [[ -z $f ]] && continue
  m=$(path_msg "$f"); [[ -n $m ]] && bad "$m: $f"
  [[ -n $INTERNAL_RE ]] && grep -qiE -e "$INTERNAL_RE" <<<"$f" && bad "internal name in a file name: $f"
  [[ -f $f ]] && (( $(wc -c < "$f") > 5000000 )) && bad "file over 5 MB (binaries do not belong here): $f"
done <<< "$files"

# 2. Content: private keys, internal names, subscription/tenant IDs.
text=$(printf '%s\n' "$files" | while IFS= read -r f; do [[ -f $f ]] && grep -Iq . "$f" 2>/dev/null && echo "$f"; done)
scan() { # scan <label> <regex> [grep flags]
  local label=$1 re=$2; shift 2
  local hits
  hits=$(printf '%s\n' "$text" | xargs -r -d '\n' grep -HnE "$@" -e "$re" 2>/dev/null || true)
  [[ -n $hits ]] && { bad "$label"; printf '%s\n' "$hits" | head -20 | show; }
}
scan "private key material" '-----BEGIN [A-Z ]*PRIVATE KEY-----'
[[ -n $INTERNAL_RE ]] && scan "internal name" "$INTERNAL_RE" -i
guid='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
hits=$(printf '%s\n' "$text" | xargs -r -d '\n' grep -HnE "$guid" 2>/dev/null | grep -v '00000000-0000-0000-0000-000000000000' || true)
[[ -n $hits ]] && { bad "GUID (subscription, tenant or object ID?)"; printf '%s\n' "$hits" | head -20 | show; }
hits=$(printf '%s\n' "$text" | xargs -r -d '\n' grep -HnE '[A-Za-z0-9._-]+@qumulo\.com' 2>/dev/null || true)
[[ -n $hits ]] && say "WARN: a Qumulo email address is in the repo; confirm it is a role address, not a person:" && printf '%s\n' "$hits" | head -5 | show

# 2b. History: every commit on every branch.
if (( history )); then
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    bad "--history needs a git repository"
  else
    while IFS= read -r f; do
      [[ -z $f ]] && continue
      m=$(path_msg "$f"); [[ -n $m ]] && bad "in history, $m: $f"
    done < <(git -c core.quotePath=false log --all --name-only --pretty=format: | sort -u)
    # Every commit's author, committer, message and patch, each line prefixed with its commit and file.
    log=$(git -c core.quotePath=false log --all -p --no-color --format='%x01%h%nAuthor: %an <%ae>%nCommitter: %cn <%ce>%n%B' |
      awk 'substr($0, 1, 1) == "\001" { c = substr($0, 2); f = ""; next }
           /^diff --git / { f = $NF; sub(/^b\//, "", f) }
           { print "commit " c (f == "" ? "" : " " f) ": " $0 }')
    hits=$(grep -E -e '-----BEGIN [A-Z ]*PRIVATE KEY-----' <<<"$log" | head -5 || true)
    [[ -n $hits ]] && { bad "private key material in history"; printf '%s\n' "$hits" | show; }
    if [[ -n $INTERNAL_RE ]]; then
      hits=$(grep -iE -e "$INTERNAL_RE" <<<"$log" | head -10 || true)
      [[ -n $hits ]] && { bad "internal name in history"; printf '%s\n' "$hits" | show; }
    fi
    hits=$(grep -E "$guid" <<<"$log" | grep -v '00000000-0000-0000-0000-000000000000' | head -10 || true)
    [[ -n $hits ]] && { bad "GUID in history (subscription, tenant or object ID?)"; printf '%s\n' "$hits" | show; }
    # Any other address would publish a person's email. The message names the commit, not the address.
    # The whole address must be one: git allows spaces in an email, so check the field, not its first word.
    hits=$(git log --all --format='%h%x09%ae%n%h%x09%ce' |
      awk -F '\t' '{
        e = tolower(substr($0, length($1) + 2))
        if (e !~ /^([0-9]+\+)?[a-z0-9-]+(\[bot\])?@users\.noreply\.github\.com$/ && e != "noreply@github.com") print "commit " $1
      }' | sort -u | head -10)
    [[ -n $hits ]] && { bad "author or committer email that is not a GitHub noreply address (set git's user.email to the noreply address in your GitHub email settings, and rewrite these commits)"; printf '%s\n' "$hits" | show; }
  fi
fi

# 3. Release gate.
if (( release )); then
  [[ -f LICENSE ]] || bad "no LICENSE file (add the license file for these files)"
  text=$(printf '%s\n' "$text" | grep -v '^scripts/scrub-check\.sh$' || true) # it names the placeholders it looks for
  scan "unfinished placeholder" 'TODO|FIXME|TBD|<RELEASE_TAG>'
  sums=$(review_sums)
  if [[ -n $sums && ! -f $review ]]; then
    bad "binary files or images have not been reviewed. Check each for lab hostnames, cluster UUIDs, IPs and performance numbers, then run: bash scripts/scrub-check.sh --record-images"
    needs_review | tr '\0' '\n' | show
  elif [[ -n $sums && $sums != "$(cat "$review")" ]]; then
    bad "binary files or images changed since the last review; check them again, then run: bash scripts/scrub-check.sh --record-images"
    diff <(cat "$review") <(printf '%s\n' "$sums") | grep '^[<>]' | show
  fi
fi

if (( fail )); then say "scrub-check: FAILED"; exit 1; fi
echo "scrub-check: ok$( (( release )) && echo ' (release gate)')$( (( history )) && echo ' (history)')"
