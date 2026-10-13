# Releasing QuickEdit

For maintainers. Releases and the update feed live on GitHub Releases (decision-7).

```bash
make bump V=patch PUSH=1          # bump VERSION, tag vX.Y.Z on main, push → the Release workflow publishes it
make bump V=2.1.0-beta.1 PUSH=1   # a GitHub pre-release: no update feed, installed copies never get it
```

Pushing a `vX.Y.Z` tag runs `.github/workflows/release.yml`: it tests, builds for Apple silicon, signs with Developer
ID, notarizes and staples the app and the DMG, and publishes a GitHub Release named after the tag with
`QuickEdit-X.Y.Z.dmg`, `QuickEdit-X.Y.Z.zip`, `SHA256SUMS` and `appcast.xml`. The tag must match `./VERSION`.

A `vX.Y.Z-<pre-release>` tag publishes a GitHub pre-release with the same files except `appcast.xml`. GitHub never
marks a pre-release as the latest release, so the feed, the website and the README's download link skip it. After a
pre-release, name the next version (`make bump V=2.1.0` or `V=2.1.0-beta.2`): `major`, `minor` and `patch` need an
X.Y.Z `VERSION`.

## Update feed

Info.plist's `SUFeedURL` is `https://github.com/itsjavi/quickedit/releases/latest/download/appcast.xml`, the feed attached
to the newest release. `make appcast` (`scripts/appcast.sh`) downloads that feed, adds the new build and signs it, so
it lists every release; each item links to the zip in its own release (`releases/download/vX.Y.Z/`). It refuses
pre-releases and a key that doesn't match the app's public key.

Sparkle's private EdDSA key lives in the login Keychain under the account `quickedit` (never in the repo); the public
key is `Resources/SparklePublicKey.txt`. They were made once with:

```bash
.build/artifacts/sparkle/Sparkle/bin/generate_keys --account quickedit
```

Export the private key (`generate_keys --account quickedit -x quickedit-sparkle.key`) for the `SPARKLE_PRIVATE_KEY` secret
and keep a backup outside the repo. Losing it means installed copies can't accept updates signed with a new key.

## Website

The download links on https://itsjavi.com/quickedit/ point at `releases/latest`, so a release needs no site deploy.

## Credentials

The workflow's secrets live in the `release` environment, which only `v*` tags can use. Every one is optional: without
them the build is ad-hoc signed (other Macs need System Settings ▸ Privacy & Security ▸ Open Anyway on first launch)
and has no feed, and the release notes say so.

| Secret                      | What it is                                                                     |
| --------------------------- | ------------------------------------------------------------------------------ |
| `DEVELOPER_ID_P12`          | The Developer ID Application certificate and its private key, as a base64 .p12 |
| `DEVELOPER_ID_P12_PASSWORD` | The password the .p12 was exported with                                        |
| `APPLE_ID`                  | The Apple Account that notarizes                                               |
| `APPLE_APP_PASSWORD`        | An app-specific password for it (account.apple.com ▸ Sign-In and Security)     |
| `APPLE_TEAM_ID`             | The team that owns the certificate                                             |
| `SPARKLE_PRIVATE_KEY`       | The exported Sparkle private key                                               |

## Building a release locally

```bash
DEVELOPER_ID="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=lamina make release
```

`make release` (`scripts/release.sh`) writes `QuickEdit.app`, the zip, the DMG and `SHA256SUMS` to `build/release`. It
signs and notarizes when `DEVELOPER_ID` (from `security find-identity -v -p codesigning`) and `NOTARY_PROFILE` are
set; the profile is made once with `xcrun notarytool store-credentials <name> --apple-id … --team-id …`. Otherwise it
builds ad-hoc and lists what's missing. Check a build with `spctl -a -vv build/release/QuickEdit.app` and
`xcrun stapler validate build/release/QuickEdit-X.Y.Z.dmg`.

To publish such a build (while the workflow has no secrets), tag without pushing (`make bump V=X.Y.Z`), run
`make build-notarized` and `make appcast`, push main and the tag, and `gh release create vX.Y.Z` with the DMG, zip,
`SHA256SUMS` and `build/appcast/appcast.xml`. The workflow still runs for the tag but leaves an existing release alone.

`make build-notarized` does the same with the Keychain's Developer ID identity and the `lamina` profile (the same
Apple ID and team) (override
them with `DEVELOPER_ID` and `NOTARY_PROFILE`); without an identity it stops instead of building ad-hoc.
`make install-notarized` then installs that app to `/Applications` like `make install`.
