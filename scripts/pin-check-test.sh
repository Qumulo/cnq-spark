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
run() { out=$(cd "$1" && bash scripts/pin-check.sh 2>&1); rc=$?; }
check() { # check <name> <condition>
  if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; printf '%s\n' "$out" | sed 's/^/       /'; fails=1; fi
}
set_default() { # set_default <dir> <parameter> <value>: azuredeploy.json with that parameter's default changed
  jq --arg p "$2" --arg v "$3" '.parameters[$p].defaultValue = $v' "$1/azuredeploy.json" > "$1/t.json" && mv "$1/t.json" "$1/azuredeploy.json"
}
tag=$(jq -r .parameters.bundleUrl.defaultValue "$root/azuredeploy.json" | sed -E 's#.*/download/([^/]+)/.*#\1#')
other=v0.0.1

copy "$tmp/same"; run "$tmp/same"
check "this repository's pins agree" '[[ $rc == 0 && $out == *"ok ($tag)"* ]]'

copy "$tmp/button"; sed -i "s#cnq-spark%2F$tag%2F#cnq-spark%2F$other%2F#g" "$tmp/button/README.md"; run "$tmp/button"
check "a README button at another version fails" '[[ $rc != 0 && $out == *README.md* ]]'

copy "$tmp/runbook"; sed -i "s#cnq-spark/$tag/azuredeploy.json#cnq-spark/$other/azuredeploy.json#" "$tmp/runbook/RUNBOOK.md"; run "$tmp/runbook"
check "a RUNBOOK TEMPLATE_URL at another version fails" '[[ $rc != 0 && $out == *RUNBOOK.md* ]]'

copy "$tmp/stray"; printf '\nOlder: https://raw.githubusercontent.com/Qumulo/cnq-spark/%s/azuredeploy.json\n' "$other" >> "$tmp/stray/RUNBOOK.md"
run "$tmp/stray"
check "another link to this repository's files at another version fails" '[[ $rc != 0 && $out == *"$other"* ]]'

copy "$tmp/url-tag"; url=$(jq -r .parameters.bundleUrl.defaultValue "$tmp/url-tag/azuredeploy.json")
set_default "$tmp/url-tag" bundleUrl "${url/\/download\/$tag\//\/download\/$other\/}"; run "$tmp/url-tag"
check "a bundleUrl at another version fails" '[[ $rc != 0 ]]'

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
