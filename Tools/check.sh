#!/usr/bin/env bash
#
# Tools/check.sh — vérifie tout ce qui se vérifie sans simulateur.
#
# Écrit son journal complet dans check.log à la racine du dépôt, pour qu'il
# puisse être relu sans copier-coller. check.log n'est pas versionné.

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
LOG="$PWD/check.log"

PACKAGES=(Packages/PanoramaxKit Packages/ImageMetadataKit Packages/GeoKit)
TOOLS=(Tools/panoramax-probe)

# Le verdict doit nommer l'étape fautive. Sans cela, une section vide juste
# avant « RESULTAT: ECHEC » se lit comme la coupable — c'est arrivé.
failures=()

step() {
  local label="$1"
  shift
  echo
  echo "### $label"
  if ! ( "$@" ); then
    failures+=("$label")
  fi
}

swift_in() {
  local directory="$1"
  shift
  cd "$directory" && swift "$@"
}

{
  echo "=== iPanoramax — vérification locale ==="
  date '+%Y-%m-%d %H:%M:%S'

  step "swift --version" swift --version

  for package in "${PACKAGES[@]}"; do
    name="$(basename "$package")"
    step "$name — build" swift_in "$package" build
    step "$name — tests" swift_in "$package" test
  done

  for tool in "${TOOLS[@]}"; do
    step "$(basename "$tool") — build" swift_in "$tool" build
  done

  echo
  echo "### SwiftLint"
  if command -v swiftlint >/dev/null 2>&1; then
    # --strict comme en CI : un avertissement y est bloquant.
    if ! swiftlint lint --strict --quiet; then
      failures+=("SwiftLint")
    fi
  else
    echo "(swiftlint absent — brew install swiftlint)"
  fi

  echo
  if [ "${#failures[@]}" -eq 0 ]; then
    echo "RESULTAT: OK"
  else
    echo "RESULTAT: ECHEC"
    for failed in "${failures[@]}"; do
      echo "  ✗ $failed"
    done
  fi
} 2>&1 | tee "$LOG"

echo
echo "Journal complet : $LOG"
