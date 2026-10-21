#!/usr/bin/env bash
#
# Guard de empaquetado de la app (CI gate 1/5).
#
# `PR/` y `PRWatch/` son carpetas sincronizadas de Xcode: TODO archivo que viva ahí entra
# al target y se empaqueta en el .app. La documentación (spec, ADRs, scripts) vive en
# `docs/` y no debe aparecer dentro de esas carpetas. Este guard falla si encuentra
# documentos o scripts dentro de ellas.
#
# Historia: la spec vivía en `PR/PR-agentic-fitness-spec` y dependía de una excepción de
# membresía en project.pbxproj que Xcode perdía al editar el target (se empaquetaban los
# .md). Se movió a `docs/spec` para eliminar esa fragilidad.
#
# Uso: ./scripts/check_pbxproj_exception.sh [ruta/al/project.pbxproj]
# Salida: 0 si no hay documentación dentro de las carpetas de app.
set -euo pipefail

PBX="${1:-PR.xcodeproj/project.pbxproj}"
REPO_ROOT="$(cd "$(dirname "$PBX")/.." && pwd)"

found=0
for app_dir in "$REPO_ROOT/PR" "$REPO_ROOT/PRWatch"; do
  [[ -d "$app_dir" ]] || continue
  while IFS= read -r -d '' file; do
    echo "ERROR: documento dentro de una carpeta de app (se empaquetaría): ${file#"$REPO_ROOT"/}" >&2
    found=1
  done < <(find "$app_dir" -type f \( -name "*.md" -o -name "*.sh" \) -print0)
done

if [[ -d "$REPO_ROOT/PR/PR-agentic-fitness-spec" ]]; then
  echo "ERROR: la spec volvió a PR/PR-agentic-fitness-spec; debe vivir en docs/spec." >&2
  found=1
fi

if [[ $found -ne 0 ]]; then
  echo "  Mueve la documentación a docs/ (fuera de PR/ y PRWatch/)." >&2
  exit 1
fi

echo "OK: sin documentación dentro de PR/ ni PRWatch/ (spec en docs/spec)." >&2
