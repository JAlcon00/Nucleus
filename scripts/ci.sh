#!/usr/bin/env bash
#
# PR-0002 — CI local reproducible.
#
# Pipeline reproducible de build + unit tests para el repo PR. Pensado para ejecutarse
# localmente o en CI tras un `git clone`; NO depende de la ruta absoluta de un
# desarrollador (se resuelve relativo a este script) y falla con exit code != 0 ante
# cualquier fallo de los gates obligatorios.
#
# Gates obligatorios (fail-fast, exit != 0 ante fallo):
#   1. Guard del pbxproj (no empaqueta la carpeta de spec).
#   2. `swift build` del paquete PRCore.
#   3. `swift test` del paquete PRCore (tests de dominio/app-core).
#
# Gate adicional (integración iOS): build del scheme real con el primer destination de
# iOS Simulator detectado en la máquina. Si NO hay ningún destination de iOS Simulator
# disponible no es un fallo de CI (el core ya quedó validado); si hay destination y el
# build falla, el pipeline falla.
#
# Uso:
#   ./scripts/ci.sh            # todo el pipeline
#   ./scripts/ci.sh test       # solo unit tests del paquete
#   ./scripts/ci.sh build-ios  # solo el build del scheme iOS
#   ./scripts/ci.sh guards     # solo los guards
#
# Salida: 0 = éxito; != 0 = algún gate falló (ver mensaje en stderr).
set -euo pipefail

# Resolver el root del repo relativo a este script (sin rutas absolutas de dev).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$REPO_ROOT/Packages/PRCore"
PBX="$REPO_ROOT/PR.xcodeproj/project.pbxproj"
# Logs reproducibles del pipeline (se ignoran via .gitignore).
CI_LOG_DIR="$REPO_ROOT/.ci"
mkdir -p "$CI_LOG_DIR"

log() { printf '%s\n' "$*" >&2; }

# Ejecuta un comando (opcionalmente por fase, con su log) y propaga el exit code real.
# Nota: se vierte la salida a un archivo con `tee` y se fuerza la salida de `swift`/
# `xcodebuild` a archivo para que el exit code del gate sea fiable independientemente
# del stdout de la terminal (issue: `swift test` a `/dev/null` devuelve no-cero).
run_step() {
  local name="$1"
  local logfile="$CI_LOG_DIR/$name.log"
  shift
  local code
  log ""
  log "[ci] $name"
  "$@" >"$logfile" 2>&1
  code=$?
  if [[ $code -ne 0 ]]; then
    log "ERROR: $name falló (exit $code); log: $logfile" >&2
    exit "$code"
  fi
  log "OK: $name"
}

run_pbxproj_guard() {
  log ""
  log "[ci] 1/4 guard: excepción PR-agentic-fitness-spec en pbxproj"
  "$REPO_ROOT/scripts/check_pbxproj_exception.sh" "$PBX"
}

run_package_build() {
  ( cd "$PACKAGE_DIR" && run_step "build-core" swift build )
}

run_package_tests() {
  ( cd "$PACKAGE_DIR" && run_step "test-core" swift test )
}

run_ios_build() {
  local destination_id
  destination_id="$(
    xcodebuild -scheme PR -showdestinations 2>/dev/null \
      | sed -n 's/.*{ platform:iOS Simulator,[^}]*id:\([0-9A-F-]\{36\}\)[^}]*}.*/\1/p' \
      | head -n 1
  )"
  if [[ -z "$destination_id" ]]; then
    log ""
    log "[ci] 4/4 iOS scheme build: sin destination de iOS Simulator — se omite (core ya validado)"
    return 0
  fi
  log ""
  log "[ci] 4/4 xcodebuild -scheme PR (iOS Simulator, id=$destination_id)"
  ( cd "$REPO_ROOT" && run_step "build-ios" xcodebuild \
      -scheme PR \
      -destination "id=$destination_id" \
      build )
}

main() {
  local phase="${1:-all}"
  case "$phase" in
    test)
      run_package_tests
      ;;
    build-ios)
      run_ios_build
      ;;
    guards)
      run_pbxproj_guard
      ;;
    all|"")
      run_pbxproj_guard
      run_package_build
      run_package_tests
      run_ios_build
      ;;
    *)
      log "ERROR: fase desconocida '$phase'." >&2
      log "  Uso: $(basename "${BASH_SOURCE[0]}") [all|test|build-ios|guards]" >&2
      exit 2
      ;;
  esac
  log ""
  log "[ci] OK"
}

main "$@"