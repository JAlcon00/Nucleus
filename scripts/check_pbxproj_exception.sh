#!/usr/bin/env bash
#
# Guard del pbxproj (PR.xcodeproj/project.pbxproj).
#
# Verifica que la excepción de la carpeta `PR-agentic-fitness-spec` siga presente y
# correctamente apuntada al target `PR` (no a `PRWatch`, no perdida, no a nivel de
# archivo). Esa carpeta es documentación de spec y NO debe compilarse/empaquetarse.
#
# Uso: se recomienda ejecutar como pre-commit; devuelve 0 si está correcta.
set -euo pipefail

PBX="${1:-PR.xcodeproj/project.pbxproj}"

if [[ ! -f "$PBX" ]]; then
  echo "OK: no hay pbxproj ($PBX) — no aplica." >&2
  exit 0
fi

# 1) Debe existir una excepción con la carpeta (no un archivo individual).
if ! grep -q "PR-agentic-fitness-spec," "$PBX"; then
  echo "ERROR: falta la excepción 'PR-agentic-fitness-spec,' en $PBX." >&2
  echo "  La carpeta de spec quedó como miembro del target PR (se empaqueta .md)." >&2
  echo "  Restaura con: git checkout -- $PBX  (o restaura la excepción para el target PR)." >&2
  exit 1
fi

# 2) No debe apuntar al target equivocado (PRWatch) — el drift común.
if grep -q 'Exceptions for "PR" folder in "PRWatch" target' "$PBX"; then
  echo "ERROR: la excepción quedó re-apuntada a PRWatch en $PBX." >&2
  echo "  Restaura con: git checkout -- $PBX" >&2
  exit 1
fi

# 3) La excepción debe existir como tal en la sección de excepciones del synced group.
if ! grep -q "PBXFileSystemSynchronizedBuildFileExceptionSet" "$PBX"; then
  echo "ERROR: no existe la sección de excepciones de grupo en $PBX." >&2
  exit 1
fi

echo "OK: excepción de PR-agentic-fitness-spec correcta en $PBX." >&2
