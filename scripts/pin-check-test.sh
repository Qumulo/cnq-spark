#!/usr/bin/env bash
# Tests pin-check.sh: each case copies this repository's README.md, RUNBOOK.md, azuredeploy.json and the two scripts
# into a scratch directory, changes one pin, and runs the check there. Run: bash scripts/pin-check-test.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fails=0

copy() { # copy <dir>: the files the check reads, as they are in this repository
  mkdir -p "$1/scripts"
  cp "$root/README.md" "$root/RUNBOOK.md" "$root/azuredeploy.json" "$1/"
  cp "$here/pin-check.sh" "$here/deploy-button.sh" "$1/scripts/"
}
run() { local d=$1; shift; out=$(cd "$d" && bash scripts/pin-check.sh "$@" 2>&1); rc=$?; }
check() { # check <name> <condition>
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; printf '%s\n' "$out" | sed 's/^/       /'; fails=1; fi
}
replace() { # replace <file> <sed expression>: portable, as BSD sed's -i takes a suffix
  sed -E "$2" "$1" > "$1.new" && mv "$1.new" "$1"
}
set_default() { # set_default <dir> <parameter> <value>: azuredeploy.json with that parameter's default changed
  jq --arg p "$2" --arg v "$3" '.parameters[$p].defaultValue = $v' "$1/azuredeploy.json" > "$1/t.json" && mv "$1/t.json" "$1/azuredeploy.json"
}
tag=$(jq -r .parameters.bundleUrl.defaultValue "$root/azuredeploy.json" | sed -E 's#.*/download/([^/]+)/.*#\1#')
other=v0.0.1

copy "$tmp/same"; run "$tmp/same"
check "this repository's pins agree" '[[ $rc == 0 && $out == *"ok ($tag)"* ]]'

copy "$tmp/button"; replace "$tmp/button/README.md" "s#cnq-spark%2F$tag%2F#cnq-spark%2F$other%2F#g"; run "$tmp/button"
check "a README button at another version fails" '[[ $rc != 0 && $out == *README.md* ]]'

copy "$tmp/runbook"; replace "$tmp/runbook/RUNBOOK.md" "s#cnq-spark/$tag/azuredeploy.json#cnq-spark/$other/azuredeploy.json#"; run "$tmp/runbook"
check "a RUNBOOK TEMPLATE_URL at another version fails" '[[ $rc != 0 && $out == *RUNBOOK.md* ]]'

copy "$tmp/stray"; printf '\nOlder: https://raw.githubusercontent.com/Qumulo/cnq-spark/%s/azuredeploy.json\n' "$other" >> "$tmp/stray/RUNBOOK.md"
run "$tmp/stray"
check "another link to this repository's files at another version fails" '[[ $rc != 0 && $out == *"$other"* ]]'

copy "$tmp/url-tag"; url=$(jq -r .parameters.bundleUrl.defaultValue "$tmp/url-tag/azuredeploy.json")
set_default "$tmp/url-tag" bundleUrl "${url/\/download\/$tag\//\/download\/$other\/}"; run "$tmp/url-tag"
check "a bundleUrl at another version fails" '[[ $rc != 0 && $out == *README.md* ]]'

copy "$tmp/upper"; printf '\nOlder: https://raw.githubusercontent.com/QUMULO/cnq-spark/%s/azuredeploy.json\n' "$other" >> "$tmp/upper/RUNBOOK.md"
run "$tmp/upper"
check "a link in other letter case at another version fails" '[[ $rc != 0 && $out == *"$other"* ]]'

for link in "https://portal.azure.com/x/raw.githubusercontent.com%2FQumulo%2Fcnq-spark%2F$other%2Fazuredeploy.json" \
  "https://portal.azure.com/x/raw.githubusercontent.com%2fqumulo%2fcnq-spark%2f$other%2fazuredeploy.json" \
  "https://github.com/Qumulo/cnq-spark/raw/$other/azuredeploy.json" \
  "https://github.com/Qumulo/cnq-spark/releases/download/$other/spark-bundle-0123456789ab.tar.gz"; do
  copy "$tmp/link"; printf '\nOlder: %s\n' "$link" >> "$tmp/link/README.md"; run "$tmp/link"
  check "a link at another version fails: ${link:0:60}" '[[ $rc != 0 && $out == *"$other"* ]]'
  rm -rf "$tmp/link"
done

out=$(cd "$tmp" && bash "$tmp/same/scripts/pin-check.sh" 2>&1); rc=$?
check "it runs from another directory" '[[ $rc == 0 && $out == *"ok ($tag)"* ]]'

# Once the pinned version's tag exists, the template and form must be that tag's: a change needs a new version.
copy "$tmp/tagged"; cp "$root/createUiDefinition.json" "$tmp/tagged/"
git -C "$tmp/tagged" init -q; git -C "$tmp/tagged" -c user.email=1+t@users.noreply.github.com -c user.name=t add -A
git -C "$tmp/tagged" -c user.email=1+t@users.noreply.github.com -c user.name=t commit -qm release; git -C "$tmp/tagged" tag "$tag"
run "$tmp/tagged"
check "the template and form at the published tag pass" '[[ $rc == 0 ]]'
jq '.metadata.changed = true' "$tmp/tagged/azuredeploy.json" > "$tmp/tagged/t.json" && mv "$tmp/tagged/t.json" "$tmp/tagged/azuredeploy.json"
run "$tmp/tagged"
check "a template changed after its version was published fails" '[[ $rc != 0 && $out == *azuredeploy.json* && $out == *"$tag"* ]]'
git -C "$tmp/tagged" checkout -q -- azuredeploy.json; echo '{}' > "$tmp/tagged/createUiDefinition.json"
run "$tmp/tagged"
check "a form changed after its version was published fails" '[[ $rc != 0 && $out == *createUiDefinition.json* ]]'

# A rollback reverts the release pull request: every pin back at the previous version together, which passes.
copy "$tmp/rollback"; url=$(jq -r .parameters.bundleUrl.defaultValue "$tmp/rollback/azuredeploy.json")
set_default "$tmp/rollback" bundleUrl "${url/\/download\/$tag\//\/download\/$other\/}"
replace "$tmp/rollback/README.md" "s#cnq-spark%2F$tag%2F#cnq-spark%2F$other%2F#g"
replace "$tmp/rollback/RUNBOOK.md" "s#cnq-spark/$tag/azuredeploy.json#cnq-spark/$other/azuredeploy.json#"
run "$tmp/rollback"
check "every pin back at the previous version passes (a rollback)" '[[ $rc == 0 && $out == *"ok ($other)"* ]]'

# Before publishing, the check is given the tag about to be made.
run "$tmp/same" "$tag"
check "the tag being published, when the pins name it, passes" '[[ $rc == 0 ]]'
run "$tmp/same" "$other"
check "a tag the pins don't name fails" '[[ $rc != 0 && $out == *"$other"* ]]'

copy "$tmp/url-host"; set_default "$tmp/url-host" bundleUrl "https://example.com/download/$tag/spark-bundle-0123456789ab.tar.gz"
run "$tmp/url-host"
check "a bundleUrl outside this repository's releases fails" '[[ $rc != 0 && $out == *bundleUrl* ]]'

copy "$tmp/url-name"; set_default "$tmp/url-name" bundleUrl "https://github.com/Qumulo/cnq-spark/releases/download/$tag/bundle.tar.gz"
run "$tmp/url-name"
check "a bundle name that isn't spark-bundle-<commit>.tar.gz fails" '[[ $rc != 0 && $out == *bundleUrl* ]]'

for bad in "" "157DD2BB238FB9CC837E630AF4224BAAA2FD6401A13E70EB88267F1D1A4DACF8" "157dd2bb"; do
  copy "$tmp/sha"; set_default "$tmp/sha" bundleSha256 "$bad"; run "$tmp/sha"
  check "a bundleSha256 of '${bad:0:12}' fails" '[[ $rc != 0 && $out == *bundleSha256* ]]'
  rm -rf "$tmp/sha"
done

exit "$fails"
