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
#   1. Guards: empaquetado (no hay documentación dentro de PR/ ni PRWatch/), colores sólo
#      desde DesignTokens.swift y ningún log con datos personales de "Sobre ti".
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
  log "[ci] 1/5 guard: colores sólo desde DesignTokens.swift (SCRUM-194)"
  "$REPO_ROOT/scripts/check_color_tokens.sh" "$REPO_ROOT"
  log "[ci] 1/5 guard: ningún log con datos de \"Sobre ti\" (SCRUM-198)"
  "$REPO_ROOT/scripts/check_privacy_logs.sh" "$REPO_ROOT"
  log "[ci] 1/5 guard: ninguna llave de la IA en el repo (SCRUM-204)"
  "$REPO_ROOT/scripts/check_secrets.sh" "$REPO_ROOT"
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

# Pruebas de UI (XCUIAutomation). Aparte de `all`: tardan ~20 min y necesitan simulador
# (el CI de GitHub no las corre). SCRUM-217, para que sean confiables desde la terminal:
# - Corren en un simulador PROPIO, `PR UI Tests` (iPhone; se crea la primera vez), que se
#   borra y arranca limpio en cada corrida. Ningún otro uso lo toca: un simulador que
#   "vio" un teclado físico minimiza el teclado en pantalla y el texto que escriben las
#   pruebas no llega (así fallaba todo en "Sobre ti"). `PR_UI_SIMULATOR=<udid>` usa otro
#   simulador tal cual, sin borrarlo.
# - `-collect-test-diagnostics never`: con una prueba fallida, xcodebuild ya no se queda
#   esperando a `simctl diagnose` (se colgaba al terminar).
# - El resultado queda en `.ci/test-ui.xcresult` y se imprime prueba por prueba.
UI_SIMULATOR_NAME="PR UI Tests"
UI_SIMULATOR_PREFERRED_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"
UI_RESULT_BUNDLE="$CI_LOG_DIR/test-ui.xcresult"

# UDID del simulador de pruebas de UI; lo crea si no existe.
ui_simulator() {
  local udid device_type
  udid="$(xcrun simctl list devices available \
    | sed -n "s/^ *$UI_SIMULATOR_NAME (\([0-9A-F-]\{36\}\)).*/\1/p" | head -n 1)"
  if [[ -z "$udid" ]]; then
    device_type="$(xcrun simctl list devicetypes \
      | sed -n "s/.*(\($UI_SIMULATOR_PREFERRED_TYPE\))\$/\1/p" | head -n 1)"
    if [[ -z "$device_type" ]]; then
      # Sin el modelo preferido: el primer iPhone que traiga este Xcode.
      device_type="$(xcrun simctl list devicetypes \
        | sed -n 's/^iPhone .*(\(com\.apple\.CoreSimulator\.SimDeviceType\.iPhone-[^)]*\))$/\1/p' | head -n 1)"
    fi
    udid="$(xcrun simctl create "$UI_SIMULATOR_NAME" "$device_type")"
    log "[ci] test-ui: simulador $UI_SIMULATOR_NAME creado ($device_type)"
  fi
  printf '%s\n' "$udid"
}

# Imprime cada prueba del result bundle con su resultado y duración.
print_ui_results() {
  [[ -d "$UI_RESULT_BUNDLE" ]] || return 0
  xcrun xcresulttool get test-results tests --path "$UI_RESULT_BUNDLE" 2>/dev/null \
    | python3 -I -c '
import json, sys
marks = {"Passed": "OK  ", "Failed": "FAIL", "Skipped": "SKIP", "Expected Failure": "XF  "}
def walk(node):
    if node.get("nodeType") == "Test Case":
        mark = marks.get(node.get("result"), "?   ")
        print("  " + mark + " " + str(node.get("name")) + " (" + str(node.get("duration", "?")) + ")")
        return
    for child in node.get("children", []):
        walk(child)
for node in json.load(sys.stdin).get("testNodes", []):
    walk(node)
' >&2 || log "  (no se pudo leer $UI_RESULT_BUNDLE)"
}

run_ui_tests() {
  local udid code=0
  if [[ -n "${PR_UI_SIMULATOR:-}" ]]; then
    udid="$PR_UI_SIMULATOR"
    log "[ci] test-ui: simulador indicado $udid (sin borrarlo)"
  else
    udid="$(ui_simulator)"
    log "[ci] test-ui: simulador $UI_SIMULATOR_NAME ($udid), borrado y arrancado limpio"
    # Apagado previo: si ya estaba apagado no es un error.
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    xcrun simctl erase "$udid"
  fi
  # Arranque: si ya estaba arrancado no es un error; `bootstatus` espera a que esté listo.
  xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$udid" -b >/dev/null
  # xcodebuild no sobrescribe un result bundle existente.
  rm -rf "$UI_RESULT_BUNDLE"
  ( cd "$REPO_ROOT" && run_step "test-ui" xcodebuild \
      -scheme PR -destination "id=$udid" \
      -collect-test-diagnostics never \
      -resultBundlePath "$UI_RESULT_BUNDLE" \
      -only-testing:PRUITests test ) || code=$?
  log "[ci] test-ui: resultado por prueba"
  print_ui_results
  if [[ $code -ne 0 ]]; then
    exit "$code"
  fi
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