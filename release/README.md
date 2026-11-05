# Releasing Hypermed desktop

1. Bump nothing by hand — the version comes from the tag.
2. Tag and push, with release notes as the tag message (shown in the app's
   "What's new"):

       git tag -a v1.4.0 -m "Faster machine list. New vendor fee receipts."
       git push origin v1.4.0

3. `.github/workflows/release.yml` builds the Windows installer (Inno Setup,
   on a Windows runner) and the Linux tarball, writes `latest.json`, uploads
   all three to the VPS updates folder, and attaches them to a GitHub Release.
4. Every running app picks it up within 15 minutes (or at next start / via
   Settings → Preferences → App updates → Check for updates).

**Forcing an update**: set `release/min_version.txt` to the new version before
tagging. Any app older than that shows a blocking "Update required" screen
(use this after breaking API changes).

**Building locally (Linux)**:

    flutter build linux --release --build-name=1.4.0
    tool/package_linux.sh 1.4.0

## One-time setup

GitHub repo → Settings → Secrets and variables → Actions:

| Name | Kind | Value |
|---|---|---|
| `VPS_HOST` | secret | VPS IP |
| `VPS_KNOWN_HOSTS` | secret | pinned SSH host key line for the VPS |
| `VPS_UPDATES_KEY` | secret | upload-only key for `hmdeploy` (forced command `hypermed-publish-update`) |
| `UPDATE_BASE_URL` | variable | e.g. `https://app.hypermed.co.tz/updates` |
| `API_BASE_URL` | variable | optional; baked into builds (else the default in `api_client.dart`) |
| `UPDATE_SIGNING_KEY` | secret | Ed25519 private key (PEM) that signs `latest.json` — **required** |

## Update signing

`latest.json` is signed (`latest.json.sig`, Ed25519) by the pipeline, and the
app refuses any feed that doesn't verify against the public key compiled into
`UpdateService.trustedKeys`. Since the feed carries each package's SHA-256,
this protects the installers too: someone who takes over the download server
still can't push an update.

The private key was generated on the release machine at
`~/.config/hypermed/update-signing-key.pem` (mode 600) and copied into the
`UPDATE_SIGNING_KEY` secret. **Back it up somewhere offline** (e.g. the external
backup drive). If it's lost, installed apps can only be moved to a new key by
reinstalling. To rotate, see the comment on `trustedKeys`.

Sign by hand (e.g. an emergency re-publish):

    tool/sign_update_manifest.py dist/latest.json --key-file ~/.config/hypermed/update-signing-key.pem

All of these are already set. Without the VPS secrets the workflow still builds and creates the GitHub
Release, it just skips the VPS upload.
