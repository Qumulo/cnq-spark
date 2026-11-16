# Maintaining this repository

This repository is public. Anything committed here, including in history, is public for good. Treat every commit as a publication.

## What belongs here

Only the files that a person deploying Spark needs: the deployment template, the portal form, the runbook and the scripts that check them. The Spark source code, the Qumulo Core tarball, and Qumulo's internal tooling and planning documents never go here. Only the compiled Spark program is published, as a release attachment. Core is served from private Azure Blob storage through the registration endpoint.

`scripts/scrub-check.sh` enforces this on every push. It fails on private keys, key and state files, subscription or tenant IDs, internal names, and internal folders. Do not weaken it to get a change through.

The internal names it looks for are not in this repository, because listing them here would publish them. They are an extended regular expression in the repository secret `SCRUB_INTERNAL_RE`, which CI passes to the check. To run the check yourself, get the expression from a code owner and set it first: `SCRUB_INTERNAL_RE='...' bash scripts/scrub-check.sh`. Without it the check fails. Pull requests from forks get no secrets, so their pull request check skips the internal-name part. Changes merge only through the merge queue, which runs the full check with the secret on the exact commit that would land on `main`, so nothing merges unchecked. A new copy of this repository needs the secret before its first push.

CI also runs `bash scripts/scrub-check.sh --release --history` on every push, pull request and merge queue run. It fails on any commit whose author or committer email is not a GitHub noreply address, so before you commit here, set `git config user.email` to the noreply address shown in your GitHub email settings, and turn on "Keep my email addresses private" there so GitHub's web merges use it too. A commit made with another address has to be rewritten before it can merge.

## Source of truth

The internal repository is authoritative. Changes reach this repository by manual curation: copy the specific files, run `scripts/scrub-check.sh`, review the diff, merge. There is no automated mirror, because one wrong filter would publish something internal.

## Releasing

A release is one pull request and one release, so the files at the tag are the ones the button and the runbook point at.

1. Open one pull request, reviewed by a code owner, with the change and the version pin: the output of `scripts/deploy-button.sh vX.Y.Z` in `README.md`, and `RUNBOOK.md`'s `TEMPLATE_URL` at `vX.Y.Z`. CI's pin check (`scripts/pin-check.sh`) fails the pull request unless these and `azuredeploy.json`'s `bundleUrl` all name the same version. The pinned links answer 404 until step 3.
2. Before it merges, create the release as a draft with the bundle named in `bundleUrl` and its `.sha256`: `gh release create vX.Y.Z --draft --prerelease --target main --title vX.Y.Z --notes-file <notes> <bundle> <bundle>.sha256`. Every release attaches them, because `bundleUrl` names the release's own tag: a release that changes only the template attaches the previous bundle again, unchanged. Check each file's digest with `gh release view vX.Y.Z --json assets`. The bundle's digest must equal `bundleSha256` in the pull request's `azuredeploy.json`, and `bundleUrl` must be exactly `https://github.com/Qumulo/cnq-spark/releases/download/vX.Y.Z/<the bundle's file name>`: the VM downloads the bundle from that address and checks its digest, so a mismatch in either fails every deploy. Releases before 1.0 are pre-releases on purpose, so they never become Latest.
3. Merge the pull request through the merge queue. Just before publishing, check out the merge commit and run `bash scripts/pin-check.sh vX.Y.Z`, which fails unless every pin names vX.Y.Z, and check the draft's bundle digest once more against `bundleSha256` in `azuredeploy.json` there, in case a later push or a re-uploaded file changed either. Then publish the draft at once on the merge commit: `gh release edit vX.Y.Z --target <merge commit> --draft=false`. Publishing creates the tag. Merge nothing else in between: until then, the button on `main` answers 404. If publishing fails, revert the release pull request (`git revert -m 1 <merge commit>`) in a new pull request: that puts the template, the form, the button and `RUNBOOK.md` back at the previous release together, as the pin check requires.
4. Straight after publishing, check that the button opens the form and that the release's download matches its `.sha256`. Then deploy end to end from a subscription that is not Qumulo's, using `RUNBOOK.md`, before announcing the tag.

The button can only deploy a published release, so the gate before publishing is in the internal repository: the same template, form and bundle are deployed end to end from a private copy before the pull request. If a published release is broken, a pull request that reverts its release pull request withdraws it the same way.

Releases are immutable: this repository has GitHub's immutable releases setting on, so once published, a release's tag and files can't change, and its tag name can never be used again, even after the release is deleted. A new copy of this repository needs the setting on before its first release. A mistake needs a new version.

The Deploy to Azure button and the runbook point at a tag, not at `main`. People who deployed an earlier tag are not affected by a later change.

## Releasing a new Spark or Core version

1. Build the release pieces in the internal repository: the Spark bundle and its `.sha256`, `azuredeploy.json` with that bundle's URL and sha256 as defaults, and `createUiDefinition.json`. Nothing there pushes here.
2. If Core changed, upload the new tarball to the private Azure Blob storage. The bundle pins the Core version it installs, so a Core change needs a new bundle.
3. Release as above: the two JSON files go in the pull request, and the bundle and its `.sha256` are the draft release's files.

## Withdrawing Spark

To withdraw the offer, make this repository private or delete it, and take down the registration endpoint. New deployments are expected to stop working and existing VMs to keep running; this has not been verified.

## Issues

Issues are turned off: Spark has no support. Qumulo tracks defects in these files in the internal repository. Security problems go to the address in `SECURITY.md`.
