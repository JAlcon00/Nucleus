#!/usr/bin/env bash
#
# SCRUM-228 — Cuánto le cuesta un comando a la Mac de desarrollo.
#
# Corre el comando y toma una muestra cada `PR_MEASURE_INTERVAL` segundos (default 5) de:
# carga promedio de 1, 5 y 15 minutos, swap usado, memoria comprimida, memoria usada (como
# el Monitor de Actividad: apps + wired + comprimida) y memoria libre. Al terminar imprime
# el resumen: duración, cargas máximas de 1 y 15 minutos, comprimida máxima, usada máxima,
# swap al empezar y al terminar, y libre mínima. Las muestras quedan en
# `.ci/resources-<fecha>.csv` (ignorado por git). Devuelve el exit code del comando, también
# si falla. Para comparar corridas, empieza con la Mac en calma (carga de 1 min baja).
#
# Uso:
#   ./scripts/measure_resources.sh make test-ui
#   ./scripts/measure_resources.sh make ci
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CI_LOG_DIR="$REPO_ROOT/.ci"
INTERVAL="${PR_MEASURE_INTERVAL:-5}"

if [[ $# -eq 0 ]]; then
  printf 'Uso: %s <comando> [argumentos…]\n' "$(basename "${BASH_SOURCE[0]}")" >&2
  exit 2
fi

mkdir -p "$CI_LOG_DIR"
CSV="$CI_LOG_DIR/resources-$(date +%Y%m%d-%H%M%S).csv"

# Una línea CSV: epoch, carga de 1 min, swap usado, comprimida, usada y libre (MB), y
# cargas de 5 y 15 min (al final, para que los CSV anteriores sigan leyéndose igual).
sample() {
  local load loads swap
  load="$(sysctl -n vm.loadavg | awk '{print $2}')"
  loads="$(sysctl -n vm.loadavg | awk '{print $3 "," $4}')"
  swap="$(sysctl -n vm.swapusage | sed -n 's/.*used = \([0-9.]*\)M.*/\1/p')"
  vm_stat | awk -v now="$(date +%s)" -v load="$load" -v loads="$loads" -v swap="$swap" '
    /page size of/ { for (i = 1; i <= NF; i++) if ($i == "of") size = $(i + 1) }
    { value = $NF; gsub(/\./, "", value) }
    /^Pages free:/ { free = value }
    /^Pages wired down:/ { wired = value }
    /^Pages purgeable:/ { purgeable = value }
    /^Anonymous pages:/ { anonymous = value }
    /^Pages occupied by compressor:/ { compressed = value }
    END {
      mb = size / 1048576
      printf "%s,%s,%s,%.0f,%.0f,%.0f,%s\n", now, load, swap, compressed * mb,
        (anonymous - purgeable + wired + compressed) * mb, free * mb, loads
    }'
}

printf 'epoch,load1,swap_used_mb,compressed_mb,used_mb,free_mb,load5,load15\n' >"$CSV"
sample >>"$CSV"
(
  while true; do
    sleep "$INTERVAL"
    sample >>"$CSV"
  done
) &
SAMPLER_PID=$!
trap 'kill "$SAMPLER_PID" 2>/dev/null || true' EXIT

START="$(date +%s)"
code=0
"$@" || code=$?
END="$(date +%s)"
kill "$SAMPLER_PID" 2>/dev/null || true
wait "$SAMPLER_PID" 2>/dev/null || true
sample >>"$CSV"

awk -F, -v seconds="$((END - START))" -v csv="${CSV#"$REPO_ROOT"/}" -v code="$code" '
  NR == 1 { next }
  NR == 2 { swapStart = $3; minFree = $6 }
  {
    if ($2 > maxLoad) maxLoad = $2
    if ($3 > maxSwap) maxSwap = $3
    if ($4 > maxCompressed) maxCompressed = $4
    if ($5 > maxUsed) maxUsed = $5
    if ($6 < minFree) minFree = $6
    if ($8 > maxLoad15) maxLoad15 = $8
    swapEnd = $3
  }
  END {
    printf "\n[medir] duración: %d s (%d min %d s), exit %s\n", seconds, seconds / 60, seconds % 60, code
    printf "[medir] carga promedio de 1 min: máxima %.2f\n", maxLoad
    printf "[medir] carga promedio de 15 min: máxima %.2f\n", maxLoad15
    printf "[medir] memoria comprimida: máxima %.1f GB\n", maxCompressed / 1024
    printf "[medir] memoria usada: máxima %.1f GB\n", maxUsed / 1024
    printf "[medir] swap usado: %.1f GB al empezar, %.1f GB al terminar (máximo %.1f GB)\n", swapStart / 1024, swapEnd / 1024, maxSwap / 1024
    printf "[medir] memoria libre: mínima %d MB\n", minFree
    printf "[medir] muestras: %s\n", csv
  }' "$CSV" >&2

exit "$code"
