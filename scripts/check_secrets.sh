#!/usr/bin/env bash
#
# Guard de secretos (SCRUM-204, IA-3): la llave de la IA vive sólo en la Mac del
# desarrollador (variable `NVIDIA_API_KEY` o `.env` ignorado por git), nunca en el repo.
# Falla si un archivo versionado (o nuevo y no ignorado):
#   - contiene algo con forma de llave de NVIDIA (`nvapi-…`);
#   - asigna un valor literal a `NVIDIA_API_KEY` (los docs usan `<tu llave>`); los tests
#     usan valores falsos cortos y sólo se revisan con la forma de llave;
#   - es un scheme de Xcode que menciona `NVIDIA_API_KEY` (los schemes compartidos se
#     versionan; la llave para dispositivo va en un scheme local no compartido).
# Sólo imprime archivo:línea, nunca el contenido, para no filtrar la llave en los logs.
#
# Uso: ./scripts/check_secrets.sh [raíz del repo]
# Salida: 0 si no hay llaves en el repo.
set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

KEY_SHAPE='nvapi-[A-Za-z0-9_-]{20,}'
KEY_ASSIGNMENT='NVIDIA_API_KEY[[:space:]]*[=:][[:space:]]*["'"'"']?[A-Za-z0-9_-]{8,}'

found=0
report() {
  echo "ERROR: $1: $2" >&2
  found=1
}

while IFS= read -r -d '' file; do
  path="$REPO_ROOT/$file"
  [[ -f "$path" ]] || continue
  while IFS= read -r location; do
    report "posible llave de NVIDIA" "$file:$location"
  done < <(grep -nIE "$KEY_SHAPE" "$path" | cut -d: -f1 || true)
  if [[ "$file" != */Tests/* ]]; then
    while IFS= read -r location; do
      report "NVIDIA_API_KEY con valor literal" "$file:$location"
    done < <(grep -nIE "$KEY_ASSIGNMENT" "$path" | cut -d: -f1 || true)
  fi
  if [[ "$file" == *.xcscheme ]]; then
    while IFS= read -r location; do
      report "scheme versionado con NVIDIA_API_KEY (usa un scheme local no compartido)" "$file:$location"
    done < <(grep -nI "NVIDIA_API_KEY" "$path" | cut -d: -f1 || true)
  fi
done < <(git -C "$REPO_ROOT" ls-files -z --cached --others --exclude-standard)

if [[ $found -ne 0 ]]; then
  exit 1
fi
echo "OK: ninguna llave de la IA en el repo."
