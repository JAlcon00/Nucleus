#!/usr/bin/env bash
#
# Guard de privacidad de logs (SCRUM-198, U5): los datos de "Sobre ti" (nombre, edad/año de
# nacimiento, sexo, estatura y peso) nunca se loguean. Falla si una llamada de logging
# (print, NSLog, os_log, Logger/PRLogger, `log.`, `sink(`, dump) menciona alguno de esos
# campos en el paquete, la app o el reloj.
#
# Uso: ./scripts/check_privacy_logs.sh [raíz del repo]
# Salida: 0 si ningún log menciona datos personales de "Sobre ti".
set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

LOG_CALL='(\blog\.[a-zA-Z]+\(|\bprint\(|\bdebugPrint\(|\bdump\(|NSLog\(|os_log\(|Logger\(|PRLogger|\blogger\.|\.log\.|\bsink\()'
PERSONAL='(aboutYou|AboutYou|birthYear|heightCentimeters|DeclaredSex|givenName|displayName|restrictionNote|\.weight\b|\.sex\b)'

found=0
for dir in "$REPO_ROOT/Packages/PRCore/Sources" "$REPO_ROOT/PR/App" "$REPO_ROOT/PRWatch/App"; do
  [[ -d "$dir" ]] || continue
  while IFS= read -r match; do
    echo "ERROR: un log menciona datos de \"Sobre ti\": ${match#"$REPO_ROOT"/}" >&2
    found=1
  done < <(grep -rnE --include='*.swift' "$LOG_CALL" "$dir" | grep -E "$PERSONAL" || true)
done

if [[ $found -ne 0 ]]; then
  exit 1
fi
echo "OK: ningún log menciona datos de \"Sobre ti\"."
