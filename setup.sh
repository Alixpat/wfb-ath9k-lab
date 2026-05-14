#!/usr/bin/env bash
# setup.sh — Clone les dépôts liés pour reproduire l'environnement de manip.
#
# Ce script est idempotent : il vérifie si chaque dépôt est déjà présent
# dans le dossier parent et ne reclone pas inutilement.
#
# Usage : ./setup.sh
# Pré-requis : git installé.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(dirname "$SCRIPT_DIR")"

# (dossier_cible, URL clone)
REPOS=(
    "wfb-ng|https://github.com/svpcom/wfb-ng.git"
    "open-ath9k-htc-firmware|https://github.com/alixpat/open-ath9k-htc-firmware.git"
    "rtl8812au|https://github.com/svpcom/rtl8812au.git"
)

cd "$WORKSPACE"
echo "Workspace : $WORKSPACE"
echo ""

for entry in "${REPOS[@]}"; do
    dir="${entry%%|*}"
    url="${entry##*|}"

    if [[ -d "$dir/.git" ]]; then
        echo "[OK]     $dir/ déjà cloné"
    elif [[ -e "$dir" ]]; then
        echo "[SKIP]   $dir/ existe mais pas un dépôt git — vérifier manuellement"
    else
        echo "[CLONE]  $dir/ depuis $url"
        git clone "$url" "$dir"
    fi
done

echo ""
echo "Workspace final :"
ls -d */ 2>/dev/null | sort
