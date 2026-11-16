#!/usr/bin/env bash
# Checks that the version pins agree, so the files at a release's tag are the ones its button and runbook deploy:
# - azuredeploy.json's bundleUrl is https://github.com/Qumulo/cnq-spark/releases/download/vX.Y.Z/spark-bundle-<commit>.tar.gz,
#   and its bundleSha256 is 64 lowercase hex digits;
# - README.md's Deploy to Azure button is what scripts/deploy-button.sh vX.Y.Z prints;
# - RUNBOOK.md's TEMPLATE_URL, and every other link to this repository's files at a version in README.md and RUNBOOK.md
#   names vX.Y.Z, in any letter case. These are the forms checked: raw.githubusercontent.com (plain, or URL-encoded as in
#   the button), github.com/Qumulo/cnq-spark/raw/ and github.com/Qumulo/cnq-spark/releases/download/. Other forms
#   (blob, tree, releases/tag) are not checked.
# Given a tag (the one about to be published), it also fails unless the pins name that tag.
# Run from any directory: bash scripts/pin-check.sh [vX.Y.Z]
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "pin-check: $*" >&2; exit 1; }

url=$(jq -r '.parameters.bundleUrl.defaultValue // ""' azuredeploy.json)
sha=$(jq -r '.parameters.bundleSha256.defaultValue // ""' azuredeploy.json)
re='^https://github\.com/Qumulo/cnq-spark/releases/download/(v[0-9]+\.[0-9]+\.[0-9]+)/spark-bundle-[0-9a-f]{12}\.tar\.gz$'
[[ $url =~ $re ]] ||
  fail "azuredeploy.json's bundleUrl is not https://github.com/Qumulo/cnq-spark/releases/download/vX.Y.Z/spark-bundle-<12 hex digits>.tar.gz: $url"
tag=${BASH_REMATCH[1]}
if [[ -n ${1:-} && $1 != "$tag" ]]; then
  fail "the pins name $tag, not $1: azuredeploy.json's bundleUrl, README.md's button and RUNBOOK.md's TEMPLATE_URL must name the tag being published"
fi
[[ $sha =~ ^[0-9a-f]{64}$ ]] || fail "azuredeploy.json's bundleSha256 is not 64 lowercase hex digits"

button=$(bash scripts/deploy-button.sh "$tag")
grep -qxF -- "$button" README.md || fail "README.md's Deploy to Azure button is not what scripts/deploy-button.sh $tag prints"
grep -qxF -- "TEMPLATE_URL=https://raw.githubusercontent.com/Qumulo/cnq-spark/$tag/azuredeploy.json" RUNBOOK.md ||
  fail "RUNBOOK.md's TEMPLATE_URL is not https://raw.githubusercontent.com/Qumulo/cnq-spark/$tag/azuredeploy.json"

# Every link to this repository's files at a version names the same version.
refs=$(grep -ohiE 'raw\.githubusercontent\.com/Qumulo/cnq-spark/[^/[:space:]]+/|raw\.githubusercontent\.com%2FQumulo%2Fcnq-spark%2F[^%[:space:]]+%2F|github\.com/Qumulo/cnq-spark/(raw|releases/download)/[^/[:space:]]+/' \
  README.md RUNBOOK.md | sed -E 's#%2[Ff]#/#g; s#/$##; s#.*/##' || true)
others=$(grep -vxF -- "$tag" <<<"$refs" | sort -u || true)
[[ -z $others ]] || fail "README.md or RUNBOOK.md links to this repository's files at another version: $(paste -sd' ' - <<<"$others")"
echo "pin-check: ok ($tag)"
