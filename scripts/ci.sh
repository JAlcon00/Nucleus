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
#   1. Guard de empaquetado (no hay documentación dentro de PR/ ni PRWatch/).
#   2. `swift build` del paquete PRCore.
#   3. `swift test` del paquete PRCore (tests de dominio/app-core).
#
#   4. Build del scheme iOS `PR` (Debug).
#   5. Build del scheme watchOS `PRWatch` (Debug).
#
# Los builds de scheme usan el primer destination concreto de Simulator detectado y, si
# no hay runtime instalado, el destination genérico `generic/platform=... Simulator`
# (sólo requiere el SDK). Nunca se omiten en silencio.
#
# Toolchain: si `xcode-select` apunta a CommandLineTools (sin XCTest), se usa
# `/Applications/Xcode.app` salvo que `DEVELOPER_DIR` ya esté definido.
# Los artefactos de SwiftPM van a `PR_CI_SCRATCH` (default: `$TMPDIR/prcore-ci-build`),
# fuera del repo: carpetas como ~/Documents añaden atributos extendidos que rompen el
# codesign ad-hoc del resource bundle de PRCore.
#
# Uso:
#   ./scripts/ci.sh              # todo el pipeline
#   ./scripts/ci.sh test         # solo unit tests del paquete
#   ./scripts/ci.sh build-ios    # solo el build del scheme iOS
#   ./scripts/ci.sh build-watch  # solo el build del scheme watchOS
#   ./scripts/ci.sh test-ui      # pruebas de UI (XCUIAutomation) en el simulador
#   ./scripts/ci.sh guards       # solo los guards
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
# Artefactos de SwiftPM fuera del repo (ver cabecera).
SCRATCH_DIR="${PR_CI_SCRATCH:-${TMPDIR:-/tmp}/prcore-ci-build}"
# Build system de SwiftPM fijo: el `native` (default hasta Swift 6.3 / Xcode 26.x) copia
# `Localizable.xcstrings` crudo al bundle sin compilar los `.lproj`, así que en runtime
# no hay inglés ni plurales y los tests de localización fallan. `swiftbuild` (default
# desde Swift 6.4 / Xcode 27) compila el catálogo igual que Xcode con ambas toolchains.
SWIFTPM_BUILD_SYSTEM="swiftbuild"

log() { printf '%s\n' "$*" >&2; }

# Usa Xcode completo si el developer dir activo es CommandLineTools (no trae XCTest).
if [[ -z "${DEVELOPER_DIR:-}" ]] \
  && [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]] \
  && [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# Ejecuta un comando (opcionalmente por fase, con su log) y propaga el exit code real.
# Nota: se vierte la salida a un archivo con `tee` y se fuerza la salida de `swift`/
# `xcodebuild` a archivo para que el exit code del gate sea fiable independientemente
# del stdout de la terminal (issue: `swift test` a `/dev/null` devuelve no-cero).
run_step() {
  local name="$1"
  local logfile="$CI_LOG_DIR/$name.log"
  shift
  local code=0
  log ""
  log "[ci] $name"
  # `|| code=$?` evita que `set -e` aborte antes de reportar qué gate falló.
  "$@" >"$logfile" 2>&1 || code=$?
  if [[ $code -ne 0 ]]; then
    log "ERROR: $name falló (exit $code); log: $logfile" >&2
    exit "$code"
  fi
  log "OK: $name"
}

run_pbxproj_guard() {
  log ""
  log "[ci] 1/5 guard: sin documentación dentro de PR/ ni PRWatch/"
  "$REPO_ROOT/scripts/check_pbxproj_exception.sh" "$PBX"
}

run_package_build() {
  ( cd "$PACKAGE_DIR" && run_step "build-core" swift build \
      --build-system "$SWIFTPM_BUILD_SYSTEM" --scratch-path "$SCRATCH_DIR" )
}

run_package_tests() {
  ( cd "$PACKAGE_DIR" && run_step "test-core" swift test \
      --build-system "$SWIFTPM_BUILD_SYSTEM" --scratch-path "$SCRATCH_DIR" )
}

# Build Debug de un scheme sobre Simulator. $1 = scheme, $2 = plataforma
# ("iOS" | "watchOS"), $3 = nombre de fase, $4 = índice de gate.
run_scheme_build() {
  local scheme="$1" platform="$2" phase="$3" gate="$4"
  local destination_id destination
  destination_id="$(
    cd "$REPO_ROOT" && xcodebuild -scheme "$scheme" -showdestinations 2>/dev/null \
      | sed -n "s/.*{ platform:$platform Simulator,[^}]*id:\([0-9A-F-]\{36\}\)[^}]*}.*/\1/p" \
      | head -n 1
  )"
  if [[ -n "$destination_id" ]]; then
    destination="id=$destination_id"
  else
    # Sin runtime instalado: el destination genérico compila con el SDK.
    destination="generic/platform=$platform Simulator"
  fi
  log ""
  log "[ci] $gate xcodebuild -scheme $scheme -configuration Debug ($destination)"
  ( cd "$REPO_ROOT" && run_step "$phase" xcodebuild \
      -scheme "$scheme" \
      -configuration Debug \
      -destination "$destination" \
      build )
}

# Pruebas de UI (XCUIAutomation) sobre el simulador. Aparte de `all`: tardan ~4 min y
# necesitan sesión gráfica con simulador (el CI de GitHub no las corre).
run_ui_tests() {
  local destination_id
  destination_id="$(
    cd "$REPO_ROOT" && xcodebuild -scheme PR -showdestinations 2>/dev/null \
      | sed -n 's/.*{ platform:iOS Simulator,[^}]*id:\([0-9A-F-]\{36\}\)[^}]*}.*/\1/p' \
      | head -n 1
  )"
  if [[ -z "$destination_id" ]]; then
    log "ERROR: no hay simulador de iOS para las pruebas de UI." >&2
    exit 1
  fi
  ( cd "$REPO_ROOT" && run_step "test-ui" xcodebuild \
      -scheme PR -destination "id=$destination_id" -only-testing:PRUITests test )
}

run_ios_build() {
  run_scheme_build PR iOS build-ios "4/5"
}

run_watch_build() {
  run_scheme_build PRWatch watchOS build-watch "5/5"
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
    build-watch)
      run_watch_build
      ;;
    test-ui)
      run_ui_tests
      ;;
    guards)
      run_pbxproj_guard
      ;;
    all|"")
      run_pbxproj_guard
      run_package_build
      run_package_tests
      run_ios_build
      run_watch_build
      ;;
    *)
      log "ERROR: fase desconocida '$phase'." >&2
      log "  Uso: $(basename "${BASH_SOURCE[0]}") [all|test|build-ios|build-watch|test-ui|guards]" >&2
      exit 2
      ;;
  esac
  log ""
  log "[ci] OK"
}

main "$@"