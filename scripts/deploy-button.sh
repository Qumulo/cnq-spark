#!/usr/bin/env bash
# Prints the "Deploy to Azure" button markdown for a release tag.
# Usage: scripts/deploy-button.sh v1.0.0 [owner/repo]
# The button is pinned to the tag, never to main, so a later commit cannot change what it deploys.
set -euo pipefail
tag=${1:?usage: deploy-button.sh <release-tag> [owner/repo]}
repo=${2:-Qumulo/cnq-spark}
raw="https://raw.githubusercontent.com/${repo}/${tag}"
enc() { jq -rn --arg u "$1" '$u|@uri'; }
t=$(enc "${raw}/azuredeploy.json")
u=$(enc "${raw}/createUiDefinition.json")
echo "[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/${t}/createUIDefinitionUri/${u})"
