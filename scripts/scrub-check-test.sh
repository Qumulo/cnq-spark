#!/usr/bin/env bash
# Tests scrub-check.sh's internal-name check, whose list comes from SCRUB_INTERNAL_RE, not from the script.
# Each case copies the script into a scratch git repository. Run: bash scripts/scrub-check-test.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
term=zqx-private-name # stands in for a real internal name
g=12345678-1234-1234-1234 q=qumulo # a GUID and a Qumulo address are put together at run time: this file is scanned too
fails=0

repo() { # repo <dir>: a git repository holding the script and one clean file
  mkdir -p "$1/scripts"; cp "$here/scrub-check.sh" "$1/scripts/"
  git -C "$1" init -q; git -C "$1" config user.email test@example.invalid; git -C "$1" config user.name test
  echo "clean text" > "$1/README.md"; git -C "$1" add -A; git -C "$1" commit -qm init
}
run() { # run <dir> [args]: sets out and rc
  local d=$1; shift
  out=$(cd "$d" && bash scripts/scrub-check.sh "$@" 2>&1); rc=$?
}
check() { # check <name> <condition>
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; printf '%s\n' "$out" | sed 's/^/       /'; fails=1; fi
}
no_term() { ! grep -qi -- "$term" <<<"$out"; }

repo "$tmp/clean"
unset SCRUB_INTERNAL_RE SCRUB_ALLOW_NO_INTERNAL
run "$tmp/clean"
check "without the list, the check fails and names SCRUB_INTERNAL_RE" '[[ $rc != 0 && $out == *SCRUB_INTERNAL_RE* ]]'

export SCRUB_ALLOW_NO_INTERNAL=1
run "$tmp/clean"
check "without the list but allowed (a fork's pull request), it passes with a warning" '[[ $rc == 0 && $out == *WARN*SCRUB_INTERNAL_RE* ]]'
unset SCRUB_ALLOW_NO_INTERNAL

repo "$tmp/guid"
echo "id $g-123456789abc" >> "$tmp/guid/README.md"; git -C "$tmp/guid" commit -qam guid
run "$tmp/guid"
check "without the list, the other checks still run" '[[ $rc != 0 && $out == *SCRUB_INTERNAL_RE* && $out == *GUID* ]]'

export SCRUB_INTERNAL_RE='['
run "$tmp/clean"
check "a list that is not a valid regex fails" '[[ $rc != 0 && $out == *"not a valid"* ]]'
run "$tmp/clean" --history
check "... with --history too" '[[ $rc != 0 && $out == *"not a valid"* ]]'
export SCRUB_INTERNAL_RE="$term|"
run "$tmp/clean"
check "a list that matches an empty line (so everything) fails" '[[ $rc != 0 && $out == *"empty line"* ]]'
export SCRUB_INTERNAL_RE="^$term"
run "$tmp/clean"
check "a list with an anchor fails: names match anywhere in a line" '[[ $rc != 0 && $out == *anchor* ]]'
export SCRUB_INTERNAL_RE="$term\$"
run "$tmp/clean"
check "... at either end" '[[ $rc != 0 && $out == *anchor* ]]'

export SCRUB_INTERNAL_RE="other-name|$term"
run "$tmp/clean"
check "with the list, a clean repository passes" '[[ $rc == 0 ]]'

repo "$tmp/leak"
echo "see ${term^^} here" >> "$tmp/leak/README.md"; git -C "$tmp/leak" commit -qam leak
run "$tmp/leak"
check "a listed name in any case fails, located as file:line, the name masked" '[[ $rc != 0 && $out == *"README.md:2:see [internal] here"* ]]'
check "the failure does not print the name" no_term

repo "$tmp/mail"
echo "write to $term@$q.com" >> "$tmp/mail/README.md"; git -C "$tmp/mail" commit -qam mail
run "$tmp/mail"
check "a listed name in a Qumulo email fails" '[[ $rc != 0 ]]'
check "the email warning does not print the name either" no_term

repo "$tmp/filename"
echo "clean text" > "$tmp/filename/$term.txt"; git -C "$tmp/filename" add -A; git -C "$tmp/filename" commit -qm name
run "$tmp/filename"
check "a listed name in a file name fails" '[[ $rc != 0 && $out == *"[internal].txt"* ]]'
check "the file-name failure does not print the name" no_term

repo "$tmp/history"
echo "${term^^}" > "$tmp/history/notes.txt"; git -C "$tmp/history" add notes.txt; git -C "$tmp/history" commit -qm add
git -C "$tmp/history" rm -q notes.txt; git -C "$tmp/history" commit -qm remove
run "$tmp/history"
check "a name only in history passes the normal check" '[[ $rc == 0 ]]'
run "$tmp/history" --history
check "--history fails on it and names the file" '[[ $rc != 0 && $out == *notes.txt* ]]'
check "the history failure does not print the name" no_term

repo "$tmp/message"
git -C "$tmp/message" commit -q --allow-empty -m "fix for ${term^^}"
run "$tmp/message" --history
check "--history fails on a name in a commit message" '[[ $rc != 0 && $out == *"fix for [internal]"* ]]'
check "the message failure does not print the name" no_term

repo "$tmp/author"
git -C "$tmp/author" -c user.email="$term@example.invalid" commit -q --allow-empty -m change
run "$tmp/author" --history
check "--history fails on a name in an author's email" '[[ $rc != 0 && $out == *"Author: test <[internal]@example.invalid>"* ]]'
check "the author failure does not print the name" no_term

repo "$tmp/pathonly"
echo "clean text" > "$tmp/pathonly/$term.txt"; git -C "$tmp/pathonly" add -A; git -C "$tmp/pathonly" commit -qm add
git -C "$tmp/pathonly" rm -q "$term.txt"; git -C "$tmp/pathonly" commit -qm remove
run "$tmp/pathonly" --history
check "--history fails on a name that is only in a file's path" '[[ $rc != 0 ]]'
check "the path failure does not print the name" no_term

repo "$tmp/oldscript"
echo "# $term" >> "$tmp/oldscript/scripts/scrub-check.sh"; git -C "$tmp/oldscript" commit -qam list
git -C "$tmp/oldscript" checkout -q HEAD~1 -- scripts/scrub-check.sh; git -C "$tmp/oldscript" commit -qam "no list"
run "$tmp/oldscript" --history
check "--history fails on a name in an old copy of this script" '[[ $rc != 0 && $out == *scripts/scrub-check.sh* ]]'

repo "$tmp/paths"
mkdir -p "$tmp/paths/cmd"; touch "$tmp/paths/cmd/main.go" "$tmp/paths/go.mod" "$tmp/paths/deploy.pem" "$tmp/paths/local.env"
git -C "$tmp/paths" add -A; git -C "$tmp/paths" commit -qm paths
run "$tmp/paths"
check "source, key and env files fail" '[[ $rc != 0 && $out == *"internal path: cmd/main.go"* && $out == *"internal file: go.mod"*
  && $out == *"key or state file: deploy.pem"* && $out == *"env file: local.env"* ]]'

todo=TO; todo+=DO # put together at run time: --release scans this file too
repo "$tmp/todo"
echo "$todo: finish" >> "$tmp/todo/README.md"; touch "$tmp/todo/LICENSE"
git -C "$tmp/todo" add -A; git -C "$tmp/todo" commit -qm todo
run "$tmp/todo" --release
check "--release fails on an unfinished placeholder" '[[ $rc != 0 && $out == *"unfinished placeholder"* ]]'

repo "$tmp/image"
mkdir -p "$tmp/image/docs"; printf '\x89PNG\r\n\x1a\n\0' > "$tmp/image/docs/Shot.PNG"; touch "$tmp/image/LICENSE"
git -C "$tmp/image" add -A; git -C "$tmp/image" commit -qm image
run "$tmp/image" --release
check "--release fails on an image that has not been reviewed, wherever it is" '[[ $rc != 0 && $out == *"not been reviewed"* && $out == *docs/Shot.PNG* ]]'
run "$tmp/image" --record-images
check "--record-images records the review" '[[ $rc == 0 && -s $tmp/image/.github/image-review.sha256 ]]'
git -C "$tmp/image" add -A; git -C "$tmp/image" commit -qm reviewed
run "$tmp/image" --release
check "... and then --release passes" '[[ $rc == 0 ]]'
printf 'changed\0' >> "$tmp/image/docs/Shot.PNG"; git -C "$tmp/image" commit -qam changed
run "$tmp/image" --release
check "... and fails again when an image changes" '[[ $rc != 0 && $out == *"changed since"* ]]'

repo "$tmp/binary"
printf 'x\0y' > "$tmp/binary/diagram-é.avif"; touch "$tmp/binary/LICENSE"
git -C "$tmp/binary" add -A; git -C "$tmp/binary" commit -qm binary
run "$tmp/binary" --release
check "--release fails on any binary file, of any type or name, that has not been reviewed" '[[ $rc != 0 && $out == *"not been reviewed"* && $out == *"diagram-é.avif"* ]]'

repo "$tmp/textimage"
printf 'P3\n1 1\n255\n0 0 0\n' > "$tmp/textimage/pic.ppm"; touch "$tmp/textimage/LICENSE"
git -C "$tmp/textimage" add -A; git -C "$tmp/textimage" commit -qm textimage
run "$tmp/textimage" --release
check "--release fails on an image stored as text that has not been reviewed" '[[ $rc != 0 && $out == *"not been reviewed"* && $out == *pic.ppm* ]]'

repo "$tmp/accent"
echo "see $term" > "$tmp/accent/draft's notés.md"; touch "$tmp/accent/clé.pem"
git -C "$tmp/accent" add -A; git -C "$tmp/accent" commit -qm accent
run "$tmp/accent"
hit="draft's notés.md:1:see [internal]"
check "files with accents, spaces or apostrophes in their names are checked like any other" \
  '[[ $rc != 0 && $out == *"$hit"* && $out == *"key or state file: clé.pem"* ]]'

repo "$tmp/quoted"
touch "$tmp/quoted/a\"b.md"; git -C "$tmp/quoted" add -A; git -C "$tmp/quoted" commit -qm quoted
run "$tmp/quoted"
check "a file name that git has to quote fails" '[[ $rc != 0 && $out == *"git has to quote"* ]]'
printf 'x\0y' > "$tmp/quoted/shot.bin"; touch "$tmp/quoted/LICENSE"
git -C "$tmp/quoted" add -A; git -C "$tmp/quoted" commit -qm binary
run "$tmp/quoted" --release
check "... and the other checks still run after it" '[[ $rc != 0 && $out == *"git has to quote"* && $out == *"not been reviewed"* && $out == *shot.bin* ]]'

(( fails )) && { echo "scrub-check tests: FAILED"; exit 1; }
echo "scrub-check tests: ok"
