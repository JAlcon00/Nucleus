#!/usr/bin/env bash
#
# Guard de colores (SCRUM-194, U1): todos los colores de la app iOS salen de roles en
# `PR/App/DesignTokens.swift` (paleta Iron Energy). Falla si encuentra, fuera de ese
# archivo, colores del sistema, hex, `Color(red:…)`, materiales sobre contenido o
# `.borderedProminent` (pinta texto blanco sobre el acento: 3.22:1).
#
# Una línea puede excepcionarse con el comentario `color-guard: allow (motivo)`, p. ej. el
# estilo `.white` del botón oficial de Apple o una máscara donde sólo cuenta la opacidad.
# El reloj (PRWatch) queda fuera: su paleta es otra historia.
#
# Uso: ./scripts/check_color_tokens.sh [raíz del repo]
# Salida: 0 si no hay colores fuera de los tokens.
set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
APP_DIR="$REPO_ROOT/PR/App"

PATTERN='Color\.(red|green|blue|orange|yellow|pink|purple|indigo|teal|cyan|mint|brown|gray|grey|white|black)\b'
PATTERN+='|[(:, ]\.(red|green|blue|orange|yellow|pink|purple|indigo|teal|cyan|mint|brown|gray|white|black)\b'
PATTERN+='|Color\((red|white|hue|uiColor|\.)|UIColor\.|accentColor|systemBackground'
PATTERN+='|\((\.secondary|\.primary|\.tertiary|\.tint)\)|borderedProminent|(thin|ultraThin|regular|thick)Material'
PATTERN+='|#[0-9A-Fa-f]{6}\b'

found=0
while IFS= read -r -d '' file; do
  [[ "$(basename "$file")" == "DesignTokens.swift" ]] && continue
  while IFS= read -r match; do
    echo "ERROR: color fuera de DesignTokens.swift: ${file#"$REPO_ROOT"/}:$match" >&2
    found=1
  done < <(grep -nE "$PATTERN" "$file" | grep -v "color-guard: allow" || true)
done < <(find "$APP_DIR" -type f -name "*.swift" -print0)

if [[ $found -ne 0 ]]; then
  echo "Usa un rol de color de DesignTokens.swift (o agrega el rol que falte ahí)." >&2
  exit 1
fi
echo "OK: todos los colores de la app salen de DesignTokens.swift."
