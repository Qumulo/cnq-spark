#!/usr/bin/env bash
# Checks that the version pins agree, so the files at a release's tag are the ones its button and runbook deploy:
# - azuredeploy.json's bundleUrl is https://github.com/Qumulo/cnq-spark/releases/download/vX.Y.Z/spark-bundle-<commit>.tar.gz,
#   and its bundleSha256 is 64 lowercase hex digits;
# - README.md's Deploy to Azure button is what scripts/deploy-button.sh vX.Y.Z prints;
# - RUNBOOK.md's TEMPLATE_URL, and every other link to this repository's files in README.md and RUNBOOK.md, names vX.Y.Z.
# Run from the repository root: bash scripts/pin-check.sh
set -euo pipefail
fail() { echo "pin-check: $*" >&2; exit 1; }

url=$(jq -r '.parameters.bundleUrl.defaultValue // ""' azuredeploy.json)
sha=$(jq -r '.parameters.bundleSha256.defaultValue // ""' azuredeploy.json)
re='^https://github\.com/Qumulo/cnq-spark/releases/download/(v[0-9]+\.[0-9]+\.[0-9]+)/spark-bundle-[0-9a-f]{12}\.tar\.gz$'
[[ $url =~ $re ]] ||
  fail "azuredeploy.json's bundleUrl is not https://github.com/Qumulo/cnq-spark/releases/download/vX.Y.Z/spark-bundle-<12 hex digits>.tar.gz: $url"
tag=${BASH_REMATCH[1]}
[[ $sha =~ ^[0-9a-f]{64}$ ]] || fail "azuredeploy.json's bundleSha256 is not 64 lowercase hex digits"

button=$(bash scripts/deploy-button.sh "$tag")
grep -qxF -- "$button" README.md || fail "README.md's Deploy to Azure button is not what scripts/deploy-button.sh $tag prints"
grep -qxF -- "TEMPLATE_URL=https://raw.githubusercontent.com/Qumulo/cnq-spark/$tag/azuredeploy.json" RUNBOOK.md ||
  fail "RUNBOOK.md's TEMPLATE_URL is not https://raw.githubusercontent.com/Qumulo/cnq-spark/$tag/azuredeploy.json"

# Every link to this repository's files, plain or URL-encoded as in the button, names the same version.
links=$(grep -ohE 'raw\.githubusercontent\.com/Qumulo/cnq-spark/[^/[:space:]]+/|raw\.githubusercontent\.com%2FQumulo%2Fcnq-spark%2F[^%[:space:]]+%2F' \
  README.md RUNBOOK.md || true)
others=$(grep -vxF -e "raw.githubusercontent.com/Qumulo/cnq-spark/$tag/" -e "raw.githubusercontent.com%2FQumulo%2Fcnq-spark%2F$tag%2F" \
  <<<"$links" | sort -u || true)
[[ -z $others ]] || fail "README.md or RUNBOOK.md links to this repository's files at another version: $(paste -sd' ' <<<"$others")"
echo "pin-check: ok ($tag)"
