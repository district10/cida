#!/bin/zsh
# Packs a locally built app into a DMG for another Mac of one's own. Upstream's
# scripts/build-dmg.sh wants a Developer ID, a notarization ticket and a Finder layout; a
# personal fork has none of those, and does not need them: an Apple Development signature is
# enough to run the app on a Mac that trusts the same developer, after 右键 →「打开」 once.
#
#   scripts/package-fork-dmg.sh <app> <output .dmg>
#
# The volume holds the app and an /Applications link, named after the app (so 辞达 Dev).
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <app> <output .dmg>" >&2
  exit 64
fi

app_path=${1:A}
dmg_path=${2:A}

if [[ ! -d "$app_path" ]]; then
  echo "No app at $app_path" >&2
  exit 66
fi
if [[ "${dmg_path:e}" != dmg ]]; then
  echo "The output must end in .dmg, got $dmg_path" >&2
  exit 64
fi
/usr/bin/codesign --verify --deep --strict "$app_path"

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/cida-fork-dmg.XXXXXX")
trap '/bin/rm -rf "$work_dir"' EXIT

/bin/cp -R "$app_path" "$work_dir/"
/bin/ln -s /Applications "$work_dir/应用程序"

mkdir -p "${dmg_path:h}"
/bin/rm -f "$dmg_path"
# ULFO (lzfse, read-only) is the format upstream ships; the volume name Finder shows comes from
# -volname, and the app inside keeps its own name.
/usr/bin/hdiutil create -volname "${app_path:t:r}" -srcfolder "$work_dir" -fs HFS+ \
  -format ULFO -ov "$dmg_path" >/dev/null
echo "$dmg_path"
