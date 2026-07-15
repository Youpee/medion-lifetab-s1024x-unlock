#!/usr/bin/env bash
# fetch-apps.sh — download the curated open-source app suite that build-image.sh bakes
# into /system as SYSTEM apps. The root branch also fetches the microG signature-spoofing
# chain (GmsCore + FakeStore + LSPosed + FakeGApps).
#
# Every app is an OFFICIAL build pulled straight from its own source over https:
#   * F-Droid apps  -> f-droid.org (signed, reproducible)
#   * Cromite / microG / LSPosed / FakeGApps -> the projects' own GitHub releases
# This repo redistributes NONE of them — it only fetches.
#
# Versions are PINNED (below) to the exact builds this project was tested against, so everyone
# gets a known-good set. Pass --latest to float to each project's newest release instead.
#
# Usage:
#   scripts/fetch-apps.sh            # download the PINNED set into apps/
#   scripts/fetch-apps.sh --latest   # ignore pins, fetch each project's newest
#   scripts/fetch-apps.sh --check    # only RESOLVE + probe URLs (no big downloads)
set -euo pipefail
B=$'\033[1m'; Y=$'\033[1;33m'; G=$'\033[1;32m'; R=$'\033[1;31m'; C=$'\033[1;36m'; N=$'\033[0m'
cd "$(dirname "$0")/.."
CHECK=0; LATEST=0
for a in "$@"; do
  case "$a" in
    --check)  CHECK=1;;
    --latest) LATEST=1;;
    *) echo "unknown arg: $a (use --check and/or --latest)"; exit 2;;
  esac
done
APPS="apps"
mkdir -p "$APPS/system" "$APPS/microg/priv-app" "$APPS/microg/system"
: > "$APPS/VERSIONS.txt"

die(){ printf '%sERROR: %s%s\n' "$R" "$*" "$N" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
have curl    || die "need curl"
have python3 || die "need python3"
note(){ printf '%s%s%s\n' "$C" "$*" "$N"; }
rec(){ printf '%-16s %s\n' "$1" "$2" >> "$APPS/VERSIONS.txt"; }

# ============================ PINNED VERSIONS (tested known-good) =============================
# F-Droid apps are pinned by versionCode; GitHub apps by release tag + asset name.
PIN_FDROID=1023052                        # org.fdroid.fdroid            1.23.2
PIN_AURORA=75                             # com.aurora.store            4.8.3
PIN_FOSSIFY_CAMERA=11                     # org.fossify.camera          1.5.0
PIN_FOSSIFY_GALLERY=28                    # org.fossify.gallery         1.13.1
PIN_MATERIAL_FILES=39                     # me.zhanghai.android.files   1.7.4
PIN_HELIBOARD=4005                        # helium314.keyboard          4.0
PIN_CROMITE_TAG="v148.0.7778.168-cb3baf14f52eb4365d017f640f85310735c19b79"
PIN_CROMITE_ASSET="arm64_ChromePublic.apk"
PIN_MICROG_TAG="v0.3.15.250932"           # microg/GmsCore
PIN_GMS_ASSET="com.google.android.gms-250932030.apk"
PIN_VENDING_ASSET="com.android.vending-84022630.apk"
PIN_FAKEGAPPS_TAG="6.6"; PIN_FAKEGAPPS_ASSET="app-release.apk"
PIN_LSPOSED_TAG="v2.0";  PIN_LSPOSED_ASSET="Vector-v2.0-3021-Release.zip"
# =============================================================================================

# probe (--check) or download a URL to a destination file
dl(){ # $1=url  $2=dest
  [ -n "$1" ] || die "empty URL for $2"
  if [ "$CHECK" = 1 ]; then
    curl -fsSL -r 0-0 -o /dev/null "$1" \
      && printf '   %sok%s   %s\n' "$G" "$N" "$1" \
      || die "unreachable: $1"
  else
    curl -fSL --retry 3 --retry-delay 2 -o "$2.part" "$1" || die "download failed: $1"
    mv -f "$2.part" "$2"
    printf '   %ssaved%s %s (%s)\n' "$G" "$N" "$2" "$(du -h "$2" | cut -f1)"
  fi
}

# resolve an F-Droid package's suggested build (for --latest) -> "versionCode<TAB>versionName"
fdroid_latest(){ # $1=pkgid
  curl -fsSL "https://f-droid.org/api/v1/packages/$1" | python3 -c '
import sys,json
d=json.load(sys.stdin); c=d["suggestedVersionCode"]
ver=next((p["versionName"] for p in d["packages"] if p["versionCode"]==c), str(c))
print("%s\t%s" % (c,ver))'
}
# resolve a GitHub "latest" release asset by regex (for --latest) -> "asset<TAB>tag"
gh_latest(){ # $1=repo  $2=asset-regex
  local tmp; tmp=$(mktemp)
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" -o "$tmp" || { rm -f "$tmp"; die "GitHub API: $1"; }
  python3 -c '
import sys,json,re
d=json.load(open(sys.argv[1])); pat=re.compile(sys.argv[2])
a=next((a for a in d.get("assets",[]) if pat.search(a["name"])), None)
print("%s\t%s" % (a["name"] if a else "", d.get("tag_name",""))) ' "$tmp" "$2"
  rm -f "$tmp"
}

get_fdroid(){ # $1=pkgid  $2=destsubdir/name  $3=pinned versionCode
  local pkg="$1" dest="$2" code="$3" ver="pinned"
  if [ "$LATEST" = 1 ]; then IFS=$'\t' read -r code ver < <(fdroid_latest "$pkg"); fi
  rec "$(basename "$dest")" "$pkg  code=$code${ver:+  $ver}"
  note "  $(basename "$dest")  <-  $pkg  (code $code${ver:+, $ver})"
  dl "https://f-droid.org/repo/${pkg}_${code}.apk" "$APPS/$dest.apk"
}
get_github(){ # $1=repo  $2=asset-regex  $3=destsubdir/name  $4=ext  $5=pinned tag  $6=pinned asset
  local repo="$1" rx="$2" dest="$3" ext="${4:-apk}" tag="$5" asset="$6"
  if [ "$LATEST" = 1 ]; then IFS=$'\t' read -r asset tag < <(gh_latest "$repo" "$rx"); fi
  [ -n "$asset" ] && [ -n "$tag" ] || die "cannot resolve asset for $repo"
  rec "$(basename "$dest")" "$repo  $tag  ($asset)"
  note "  $(basename "$dest")  <-  $repo  ($tag)"
  dl "https://github.com/$repo/releases/download/$tag/$asset" "$APPS/$dest.$ext"
}

[ "$LATEST" = 1 ] && printf '%s--latest: ignoring pins, fetching newest of each project%s\n' "$Y" "$N"
echo "${B}== FOSS system-app suite (all branches) ==${N}"
get_github uazo/cromite '^arm64_ChromePublic\.apk$' system/Cromite apk "$PIN_CROMITE_TAG" "$PIN_CROMITE_ASSET"
get_fdroid org.fdroid.fdroid              system/FDroid         "$PIN_FDROID"
get_fdroid com.aurora.store               system/AuroraStore    "$PIN_AURORA"
get_fdroid org.fossify.camera             system/FossifyCamera  "$PIN_FOSSIFY_CAMERA"
get_fdroid org.fossify.gallery            system/FossifyGallery "$PIN_FOSSIFY_GALLERY"
get_fdroid me.zhanghai.android.files      system/MaterialFiles  "$PIN_MATERIAL_FILES"
get_fdroid helium314.keyboard             system/HeliBoard      "$PIN_HELIBOARD"

echo
echo "${B}== microG chain (root branch only — needs signature spoofing) ==${N}"
get_github microg/GmsCore '^com\.google\.android\.gms-[0-9]+\.apk$' microg/priv-app/GmsCore apk "$PIN_MICROG_TAG" "$PIN_GMS_ASSET"
get_github microg/GmsCore '^com\.android\.vending-[0-9]+\.apk$'      microg/system/FakeStore  apk "$PIN_MICROG_TAG" "$PIN_VENDING_ASSET"
get_github whew-inc/FakeGApps '^app-release\.apk$'                   microg/system/FakeGApps  apk "$PIN_FAKEGAPPS_TAG" "$PIN_FAKEGAPPS_ASSET"
get_github JingMatrix/LSPosed 'Release\.zip$'                        microg/LSPosed           zip "$PIN_LSPOSED_TAG" "$PIN_LSPOSED_ASSET"

echo
printf '%sDONE.%s versions recorded in %sapps/VERSIONS.txt%s\n' "$G$B" "$N" "$C" "$N"
[ "$CHECK" = 1 ] && printf '%s(--check: only probed URLs, nothing downloaded)%s\n' "$Y" "$N" || true
echo "Next: scripts/build-image.sh   (it auto-bakes everything under apps/)"
