#!/bin/sh
# Applies patches/mush8/*.patch onto the pinned upstream Mush8 commit, on a
# local branch "splatnative". The submodule pointer in this repo always stays
# at the upstream commit; every SplatNative change to Mush8 lives in the
# patch series with its rationale in the commit message.
#
#   tools/apply-mush8-patches.sh          apply (refuses if the branch has local work)
#   tools/apply-mush8-patches.sh --export write the branch back into patches/mush8
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
M="$ROOT/third_party/mush8"
BASE="$(git -C "$ROOT" ls-tree HEAD third_party/mush8 | awk '{print $3}')"
[ -n "$BASE" ] || { echo "third_party/mush8 is not a submodule here"; exit 1; }

if [ "${1:-}" = "--export" ]; then
  rm -f "$ROOT"/patches/mush8/*.patch
  git -C "$M" format-patch -q "$BASE..splatnative" -o "$ROOT/patches/mush8"
  ls "$ROOT/patches/mush8"
  exit 0
fi

[ -z "$(git -C "$M" status --porcelain --untracked-files=no)" ] || { echo "third_party/mush8 has uncommitted changes"; exit 1; }
if git -C "$M" rev-parse -q --verify splatnative >/dev/null; then
  ahead="$(git -C "$M" rev-list --count "$BASE..splatnative")"
  have="$(ls "$ROOT"/patches/mush8/*.patch 2>/dev/null | wc -l | tr -d ' ')"
  [ "$ahead" = "$have" ] || { echo "branch splatnative has $ahead commits, the series has $have: export or reset it first"; exit 1; }
  git -C "$M" checkout -q splatnative
  echo "splatnative already has the $have patches"
  exit 0
fi
git -C "$M" checkout -q -b splatnative "$BASE"
git -C "$M" am -q "$ROOT"/patches/mush8/*.patch
git -C "$M" log --oneline "$BASE..splatnative"
