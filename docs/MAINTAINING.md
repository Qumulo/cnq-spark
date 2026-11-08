# Maintaining this repository

This repository is public. Anything committed here, including in history, is public for good. Treat every commit as a publication.

## What belongs here

Only the files that a person deploying Spark needs: the deployment template, the portal form, the runbook and the scripts that check them. The Spark source code, the Qumulo Core tarball, and Qumulo's internal tooling and planning documents never go here. Only the compiled Spark program is published, as a release attachment. Core is served from private Azure Blob storage through the registration endpoint.

`scripts/scrub-check.sh` enforces this on every push. It fails on private keys, key and state files, subscription or tenant IDs, internal names, and internal folders. Do not weaken it to get a change through.

The internal names it looks for are not in this repository, because listing them here would publish them. They are an extended regular expression in the repository secret `SCRUB_INTERNAL_RE`, which CI passes to the check. To run the check yourself, get the expression from a code owner and set it first: `SCRUB_INTERNAL_RE='...' bash scripts/scrub-check.sh`. Without it the check fails. Pull requests from forks get no secrets, so their pull request check skips the internal-name part. Changes merge only through the merge queue, which runs the full check with the secret on the exact commit that would land on `main`, so nothing merges unchecked. A new copy of this repository needs the secret before its first push.

CI also runs `bash scripts/scrub-check.sh --release --history` on every push, pull request and merge queue run. It fails on any commit whose author or committer email is not a GitHub noreply address, so turn on "Keep my email addresses private" in your GitHub email settings before you commit here.

## Source of truth

The internal repository is authoritative. Changes reach this repository by manual curation: copy the specific files, run `scripts/scrub-check.sh`, review the diff, merge. There is no automated mirror, because one wrong filter would publish something internal.

## Releasing a change to the template

1. Merge the change to `main` through a pull request reviewed by a code owner.
2. Deploy it end to end from a subscription that is not Qumulo's, using `RUNBOOK.md`.
3. Tag a release (for example `v1.0.1`).
4. Run `scripts/deploy-button.sh v1.0.1` and put the output in `README.md`. Update the tag in `RUNBOOK.md` the same way.

The Deploy to Azure button and the runbook point at a tag, not at `main`. People who deployed an earlier tag are not affected by a later change.

## Releasing a new Spark or Core version

1. Build the release pieces in the internal repository: the Spark bundle and its `.sha256`, `azuredeploy.json` with that bundle's URL and sha256 as defaults, and `createUiDefinition.json`. Nothing there pushes here.
2. If Core changed, upload the new tarball to the private Azure Blob storage. The bundle pins the Core version it installs, so a Core change needs a new bundle.
3. Bring the two JSON files here in a pull request, merge, tag, and attach the bundle and its `.sha256` to that tag's release.
4. Run the runbook end to end from a non-Qumulo subscription before announcing the tag.

## Withdrawing Spark

To withdraw the offer, make this repository private or delete it, and take down the registration endpoint. New deployments are expected to stop working and existing VMs to keep running; this has not been verified.

## Issues

Issues are turned off: Spark has no support. Qumulo tracks defects in these files in the internal repository. Security problems go to the address in `SECURITY.md`.
