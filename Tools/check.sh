#!/usr/bin/env bash
#
# Tools/check.sh — vérifie tout ce qui se vérifie sans simulateur.
#
# Écrit son journal complet dans check.log à la racine du dépôt, pour qu'il
# puisse être relu sans copier-coller. check.log n'est pas versionné.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
LOG="$PWD/check.log"

{
  echo "=== iPanoramax — vérification locale ==="
  date '+%Y-%m-%d %H:%M:%S'
  status=0

  echo
  echo "### swift --version"
  swift --version || status=1

  echo
  echo "### PanoramaxKit — build"
  (cd Packages/PanoramaxKit && swift build) || status=1

  echo
  echo "### PanoramaxKit — tests"
  (cd Packages/PanoramaxKit && swift test) || status=1

  echo
  echo "### panoramax-probe — build"
  (cd Tools/panoramax-probe && swift build) || status=1

  echo
  echo "### SwiftLint"
  if command -v swiftlint >/dev/null 2>&1; then
    # --strict comme en CI : un avertissement y est bloquant.
    swiftlint lint --strict --quiet || status=1
  else
    echo "(swiftlint absent — brew install swiftlint)"
  fi

  echo
  if [ "$status" -eq 0 ]; then
    echo "RESULTAT: OK"
  else
    echo "RESULTAT: ECHEC"
  fi
} 2>&1 | tee "$LOG"

echo
echo "Journal complet : $LOG"
