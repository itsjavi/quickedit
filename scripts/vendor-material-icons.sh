#!/usr/bin/env bash
# Vendors a subset of the Material Icon Theme (https://github.com/material-extensions/vscode-material-icon-theme, MIT)
# into Resources/MaterialIcons for the folder sidebar and Quick Open.
#
# Resources/MaterialIcons/subset.json lists the file extensions, file names, folder names and languages QuickEdit
# wants icons for. They're resolved against the release's icon theme (dist/material-icons.json); only those icons are
# copied (with their light and open-folder variants), and material-icons.json is written back keeping just the
# associations that point to them, so every other name upstream maps to a kept icon still gets it. QuickEdit's own
# icons (icons/quickedit-*.svg, mapped by quickedit-icons.json; the Lumiose orbs) are kept as they are.
#
#   scripts/vendor-material-icons.sh          re-vendor the pinned release (Resources/MaterialIcons/VERSION)
#   scripts/vendor-material-icons.sh 5.39.0   update to that release and pin it
#
# The release's VSIX must match the SHA-256 pinned with its version; a new version pins its own. Needs curl, unzip, jq.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST=Resources/MaterialIcons
PIN="$DEST/VERSION"
REPO=material-extensions/vscode-material-icon-theme

PINNED_VERSION="" PINNED_SHA=""
[[ -f "$PIN" ]] && read -r PINNED_VERSION PINNED_SHA < "$PIN"
VERSION="${1:-$PINNED_VERSION}"
[[ -n "$VERSION" ]] || { echo "usage: $0 [version]" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
curl -fsSL "https://github.com/$REPO/releases/download/v$VERSION/material-icon-theme-$VERSION.vsix" -o "$WORK/theme.vsix"
SHA="$(shasum -a 256 "$WORK/theme.vsix" | cut -d' ' -f1)"
if [[ "$VERSION" == "$PINNED_VERSION" && -n "$PINNED_SHA" && "$SHA" != "$PINNED_SHA" ]]; then
  echo "error: the v$VERSION VSIX changed upstream (sha256 $SHA, pinned $PINNED_SHA)" >&2
  exit 1
fi
unzip -q "$WORK/theme.vsix" 'extension/icons/*' 'extension/dist/material-icons.json' 'extension/LICENSE*' -d "$WORK/x"
ICONS="$WORK/x/extension/icons"

jq --slurpfile subset "$DEST/subset.json" '
  $subset[0] as $wanted | . as $theme
  | [ ($wanted.fileExtensions[] as $k | $theme.fileExtensions[$k], $theme.light.fileExtensions[$k]),
      ($wanted.fileNames[] as $k | $theme.fileNames[$k], $theme.light.fileNames[$k]),
      ($wanted.languageIds[] as $k | $theme.languageIds[$k], $theme.light.languageIds[$k]),
      ($wanted.folderNames[] as $k | $theme.folderNames[$k], $theme.folderNamesExpanded[$k],
        $theme.light.folderNames[$k], $theme.light.folderNamesExpanded[$k]),
      $theme.file, $theme.folder, $theme.folderExpanded ]
  | map(select(. != null)) | map({(.): true}) | add as $keep
  | def kept: with_entries(select($keep[.value] == true));
  { iconDefinitions: ($theme.iconDefinitions | with_entries(select($keep[.key] == true))),
    file: $theme.file, folder: $theme.folder, folderExpanded: $theme.folderExpanded,
    fileExtensions: ($theme.fileExtensions | kept), fileNames: ($theme.fileNames | kept),
    languageIds: ($theme.languageIds | kept),
    folderNames: ($theme.folderNames | kept), folderNamesExpanded: ($theme.folderNamesExpanded | kept),
    light: ($theme.light | with_entries(.value |= kept)) }
' "$WORK/x/extension/dist/material-icons.json" > "$WORK/material-icons.json"

# Replace everything but QuickEdit's own files: the subset list, its mapping and its icons (icons/quickedit-*.svg).
find "$DEST" -mindepth 1 -maxdepth 1 ! -name subset.json ! -name quickedit-icons.json ! -name icons -exec rm -rf {} +
mkdir -p "$DEST/icons"
find "$DEST/icons" -type f ! -name 'quickedit-*' -delete
jq -r '.iconDefinitions[].iconPath' "$WORK/material-icons.json" | while read -r path; do
  cp "$ICONS/$(basename "$path")" "$DEST/icons/"
done
jq . "$WORK/material-icons.json" > "$DEST/material-icons.json"
cp "$WORK"/x/extension/LICENSE* "$DEST/LICENSE.txt"
echo "$VERSION $SHA" > "$PIN"

echo "Material Icon Theme $VERSION: $(ls "$DEST/icons" | wc -l | tr -d ' ') icons ($(( $(cat "$DEST"/icons/*.svg | wc -c) / 1024 )) KB), sha256 $SHA"
