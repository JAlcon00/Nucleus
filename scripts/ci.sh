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
#   ./scripts/ci.sh test-ui      # todas las pruebas de UI (XCUIAutomation), por recorrido
#   ./scripts/ci.sh test-ui-smoke             # 3 recorridos: cuestionario, entrenamiento, exportar
#   ./scripts/ci.sh test-ui-build             # sólo compila las pruebas de UI (simulador apagado)
#   ./scripts/ci.sh test-ui-journey <Clase>…  # los recorridos elegidos, sin recompilar
#   ./scripts/ci.sh test-ui-erase             # borra el simulador de pruebas de UI a propósito
#   ./scripts/ci.sh guards       # solo los guards
#
# Tareas de compilación (SCRUM-228): `PR_BUILD_JOBS=N` limita las que corren a la vez en
# `swift build`/`swift test` y `xcodebuild`. El default (`DEFAULT_BUILD_JOBS`) es sin
# límite: se midió y ningún límite mejoró.
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

# Tareas de compilación simultáneas (SCRUM-228). Vacío = sin límite. Medido el 2026-10-30
# (`make ci` desde cero, MacBook Air M5 de 16 GB): sin límite, 65–66 s y el swap no crece;
# con 6, 81 s; con 4, 109 s. Ningún límite tarda igual o menos con menos swap, así que el
# default es sin límite. Lo que llenaba la memoria era arrancar el simulador mientras se
# compilaba (ahora se compila antes de arrancarlo).
DEFAULT_BUILD_JOBS=""
BUILD_JOBS="${PR_BUILD_JOBS-$DEFAULT_BUILD_JOBS}"
XCODEBUILD_JOBS=()
SWIFTPM_JOBS=()
if [[ -n "$BUILD_JOBS" ]]; then
  if [[ ! "$BUILD_JOBS" =~ ^[1-9][0-9]*$ ]]; then
    log "ERROR: PR_BUILD_JOBS debe ser un entero positivo, o vacío para no limitar (llegó '$BUILD_JOBS')."
    exit 2
  fi
  XCODEBUILD_JOBS=(-jobs "$BUILD_JOBS")
  SWIFTPM_JOBS=(--jobs "$BUILD_JOBS")
fi

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

# `${arr[@]+…}`: con bash 3.2 (el de macOS) y `set -u`, un arreglo vacío no se puede expandir.
run_package_build() {
  ( cd "$PACKAGE_DIR" && run_step "build-core" swift build \
      --build-system "$SWIFTPM_BUILD_SYSTEM" --scratch-path "$SCRATCH_DIR" ${SWIFTPM_JOBS[@]+"${SWIFTPM_JOBS[@]}"} )
}

run_package_tests() {
  ( cd "$PACKAGE_DIR" && run_step "test-core" swift test \
      --build-system "$SWIFTPM_BUILD_SYSTEM" --scratch-path "$SCRATCH_DIR" ${SWIFTPM_JOBS[@]+"${SWIFTPM_JOBS[@]}"} )
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
      ${XCODEBUILD_JOBS[@]+"${XCODEBUILD_JOBS[@]}"} \
      build )
}

# Pruebas de UI (XCUIAutomation), por recorrido (SCRUM-228): una clase de `PRUITests` por
# recorrido. Aparte de `all`: necesitan simulador (el CI de GitHub no las corre).
# Lo de SCRUM-217 se conserva, para que sean confiables desde la terminal:
# - Corren en un simulador PROPIO, `PR UI Tests` (iPhone; se crea la primera vez). Ningún
#   otro uso lo toca. `PR_UI_SIMULATOR=<udid>` usa otro simulador tal cual: nunca lo borra
#   y, si ya estaba arrancado, lo deja arrancado.
# - `-collect-test-diagnostics never`: con una prueba fallida, xcodebuild ya no se queda
#   esperando a `simctl diagnose` (se colgaba al terminar).
# - El resultado queda en `.ci/test-ui.xcresult` y se imprime prueba por prueba.
# SCRUM-228, para no llenar la memoria de una Mac de 16 GB:
# - Compila primero con el simulador APAGADO (`build-for-testing`) y después lo arranca y
#   corre lo ya compilado (`test-without-building`): el primer arranque de iOS (decenas de
#   procesos del sistema) ya no coincide con la compilación.
# - Sólo borra el simulador si iOS lo marcó con teclado físico: un simulador que "vio" uno
#   minimiza el teclado en pantalla y el texto que escriben las pruebas no llega (así
#   fallaba todo en "Sobre ti", SCRUM-217). La marca es `HardwareKeyboardLastSeen = true` en
#   `Library/Preferences/com.apple.keyboard.preferences.plist` de los datos del simulador.
#   Sin la marca se reutiliza. `test-ui-erase` lo borra a propósito.
# - Lo apaga al terminar, también si una prueba falla o se interrumpe con Ctrl+C.
# - Un solo simulador: nunca pruebas en paralelo (`-parallel-testing-enabled NO`).
UI_SIMULATOR_NAME="PR UI Tests"
UI_SIMULATOR_PREFERRED_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"
UI_RESULT_BUNDLE="$CI_LOG_DIR/test-ui.xcresult"
UI_JOURNEYS_DIR="$REPO_ROOT/PRUITests/Journeys"
# El smoke: cuestionario, entrenamiento con cierre forzado y primer entrenamiento → Exportar.
UI_SMOKE_JOURNEYS=(IntermediateQuestionnaireJourney WorkoutRecoveryJourney FirstWorkoutJourney)
# Simulador de la corrida y si hay que apagarlo al terminar (los fija `ui_prepare_simulator`).
UI_UDID=""
UI_SHUTDOWN_AT_END=true

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

# Carpeta de datos del simulador $1, según simctl (por lo común
# ~/Library/Developer/CoreSimulator/Devices/<udid>/data).
ui_simulator_data_path() {
  xcrun simctl list devices --json | python3 -I -c '
import json, sys
for devices in json.load(sys.stdin).get("devices", {}).values():
    for device in devices:
        if device.get("udid") == sys.argv[1]:
            print(device.get("dataPath", ""))
' "$1"
}

# ¿iOS marcó el simulador $1 con teclado físico? (ver arriba). Sólo cuenta
# `HardwareKeyboardLastSeen`: `AutomaticMinimizationEnabled = true` aparece también en un
# simulador limpio después de una corrida normal (visto el 2026-10-30), así que no distingue.
ui_keyboard_flagged() {
  local data prefs
  data="$(ui_simulator_data_path "$1")"
  prefs="$data/Library/Preferences/com.apple.keyboard.preferences.plist"
  [[ -n "$data" && -f "$prefs" ]] || return 1
  [[ "$(plutil -extract HardwareKeyboardLastSeen raw -o - "$prefs" 2>/dev/null)" == "true" ]]
}

ui_is_booted() {
  xcrun simctl list devices | grep -q "($1) (Booted)"
}

# Apaga el simulador $1 (si ya estaba apagado no es un error).
ui_shutdown() {
  xcrun simctl shutdown "$1" >/dev/null 2>&1 || true
  log "[ci] test-ui: simulador $1 apagado"
}

# Deja listo el simulador de la corrida: apagado mientras se compila y borrado sólo si quedó
# marcado con teclado físico. Fija UI_UDID y UI_SHUTDOWN_AT_END.
ui_prepare_simulator() {
  if [[ -n "${PR_UI_SIMULATOR:-}" ]]; then
    UI_UDID="$PR_UI_SIMULATOR"
    if ui_is_booted "$UI_UDID"; then
      UI_SHUTDOWN_AT_END=false
      log "[ci] test-ui: simulador indicado $UI_UDID, ya arrancado: se usa tal cual y se deja así"
    else
      log "[ci] test-ui: simulador indicado $UI_UDID (sin borrarlo)"
    fi
    return 0
  fi
  UI_UDID="$(ui_simulator)"
  xcrun simctl shutdown "$UI_UDID" >/dev/null 2>&1 || true
  if ui_keyboard_flagged "$UI_UDID"; then
    log "[ci] test-ui: $UI_SIMULATOR_NAME ($UI_UDID) quedó marcado con teclado físico: se borra"
    xcrun simctl erase "$UI_UDID"
  else
    log "[ci] test-ui: $UI_SIMULATOR_NAME ($UI_UDID) se reutiliza (sin marca de teclado físico)"
  fi
}

# Imprime cada prueba del result bundle con su resultado y duración y, si falló, el paso del
# recorrido donde falló (la actividad de `step(...)`) y el mensaje.
print_ui_results() {
  [[ -d "$UI_RESULT_BUNDLE" ]] || return 0
  xcrun xcresulttool get test-results tests --path "$UI_RESULT_BUNDLE" 2>/dev/null \
    | python3 -I -c '
import json, subprocess, sys
bundle = sys.argv[1]
marks = {"Passed": "OK  ", "Failed": "FAIL", "Skipped": "SKIP", "Expected Failure": "XF  "}
def failed_step(identifier):
    try:
        out = subprocess.run(
            ["xcrun", "xcresulttool", "get", "test-results", "activities", "--test-id", identifier, "--path", bundle],
            capture_output=True, text=True, timeout=120,
        ).stdout
        for run in json.loads(out).get("testRuns", []):
            for activity in run.get("activities", []):
                if activity.get("isAssociatedWithFailure"):
                    return activity.get("title")
    except (OSError, ValueError, subprocess.SubprocessError):
        return None
    return None
def walk(node):
    if node.get("nodeType") == "Test Case":
        mark = marks.get(node.get("result"), "?   ")
        print("  " + mark + " " + str(node.get("name")) + " (" + str(node.get("duration", "?")) + ")")
        if node.get("result") == "Failed" and node.get("nodeIdentifier"):
            step = failed_step(node["nodeIdentifier"])
            if step:
                print("         paso: " + step)
        for child in node.get("children", []):
            if child.get("nodeType") == "Failure Message":
                print("         " + str(child.get("name")))
        return
    for child in node.get("children", []):
        walk(child)
for node in json.load(sys.stdin).get("testNodes", []):
    walk(node)
' "$UI_RESULT_BUNDLE" >&2 || log "  (no se pudo leer $UI_RESULT_BUNDLE)"
}

# Compila la app y las pruebas de UI para el simulador de la corrida, sin arrancarlo.
run_ui_build() {
  log "[ci] test-ui: compilando con el simulador apagado (build-for-testing; tareas: ${BUILD_JOBS:-sin límite})"
  ( cd "$REPO_ROOT" && run_step "test-ui-build" xcodebuild \
      -scheme PR -destination "id=$UI_UDID" \
      ${XCODEBUILD_JOBS[@]+"${XCODEBUILD_JOBS[@]}"} \
      build-for-testing )
}

# Después de `bootstatus`, iOS sigue levantando sus servicios (PosterBoard, intelligenceflowd,
# ScreenTimeAgent, remindd…) con la CPU al 100% unos 110 s, aun con el simulador reutilizado.
# Si las pruebas arrancan encima, en 16 GB se dispara todo (medido el 2026-10-30: carga de
# 1 min de 145 a 337 y el swap +1.1 GB en el primer recorrido, que tardó el doble). Se espera
# a que la CPU de la Mac quede libre en dos lecturas seguidas, como mucho
# UI_SETTLE_MAX_SECONDS; si no, se corre igual.
# - En la E2E completa se espera: el primer recorrido ya no corre al doble de lento, así que
#   la espera se recupera (7 min 8 s con ella, 7 min 11 s sin ella) y la carga máxima baja
#   de 337 a 74–117.
# - En el smoke y los recorridos sueltos no: la espera casi duplicaría la corrida (el smoke
#   pasaría de 4 min); sin ella la carga máxima fue 151 y el swap no creció.
# `PR_UI_SETTLE=1` (o `0`) lo fuerza en cualquier modo.
UI_SETTLE_IDLE_PERCENT=50
UI_SETTLE_MAX_SECONDS=120
UI_SETTLE=0

ui_wait_until_settled() {
  local start idle calm=0
  start="$(date +%s)"
  while (( $(date +%s) - start < UI_SETTLE_MAX_SECONDS )); do
    # La segunda muestra de `top` es la CPU de los últimos 2 s.
    idle="$(top -l 2 -s 2 -n 0 | awk '/^CPU usage/ {value = $7} END {sub("%", "", value); print int(value)}')"
    if (( idle >= UI_SETTLE_IDLE_PERCENT )); then
      calm=$((calm + 1))
      if (( calm >= 2 )); then
        log "[ci] test-ui: simulador en calma tras $(( $(date +%s) - start )) s (CPU libre ${idle}%)"
        return 0
      fi
    else
      calm=0
    fi
  done
  log "[ci] test-ui: la CPU sigue ocupada tras ${UI_SETTLE_MAX_SECONDS} s; se corre igual"
}

# Arranca el simulador y corre lo ya compilado. $1 = nombre del log; el resto, los
# `-only-testing:` de lo que se corre.
run_ui_test_without_building() {
  local log_name="$1" code=0
  shift
  log "[ci] test-ui: arrancando el simulador"
  # Si ya estaba arrancado no es un error; `bootstatus` espera a que esté listo.
  xcrun simctl boot "$UI_UDID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$UI_UDID" -b >/dev/null
  if [[ "$UI_SETTLE" == 1 ]]; then
    ui_wait_until_settled
  fi
  # xcodebuild no sobrescribe un result bundle existente.
  rm -rf "$UI_RESULT_BUNDLE"
  ( cd "$REPO_ROOT" && run_step "$log_name" xcodebuild \
      -scheme PR -destination "id=$UI_UDID" \
      -parallel-testing-enabled NO \
      -collect-test-diagnostics never \
      -resultBundlePath "$UI_RESULT_BUNDLE" \
      "$@" test-without-building ) || code=$?
  log "[ci] test-ui: resultado por prueba"
  print_ui_results
  return "$code"
}

# $1 = all (todos los recorridos) | smoke | journey (sin recompilar; luego, las clases).
run_ui_tests() {
  local mode="$1" journey code=0 log_name="test-ui" settle=0
  local only=()
  shift
  case "$mode" in
    all)
      only=(-only-testing:PRUITests)
      settle=1
      ;;
    smoke)
      log_name="test-ui-smoke"
      for journey in "${UI_SMOKE_JOURNEYS[@]}"; do only+=("-only-testing:PRUITests/$journey"); done
      ;;
    journey)
      log_name="test-ui-journey"
      if [[ $# -eq 0 ]]; then
        log "ERROR: falta el recorrido. Uso: make test-ui-journey RECORRIDO=\"TodayJourney ProfileJourney\""
        log "  Recorridos: $(cd "$UI_JOURNEYS_DIR" && ls ./*.swift | sed 's|^\./||; s|\.swift$||' | tr '\n' ' ')"
        exit 2
      fi
      for journey in "$@"; do
        if [[ ! -f "$UI_JOURNEYS_DIR/$journey.swift" ]]; then
          log "ERROR: no existe el recorrido '$journey'."
          log "  Recorridos: $(cd "$UI_JOURNEYS_DIR" && ls ./*.swift | sed 's|^\./||; s|\.swift$||' | tr '\n' ' ')"
          exit 2
        fi
        only+=("-only-testing:PRUITests/$journey")
      done
      ;;
    *)
      log "ERROR: modo de pruebas de UI desconocido '$mode'."
      exit 2
      ;;
  esac
  UI_SETTLE="${PR_UI_SETTLE:-$settle}"
  if [[ "$UI_SETTLE" != 0 && "$UI_SETTLE" != 1 ]]; then
    log "ERROR: PR_UI_SETTLE debe ser 1 (esperar la calma tras arrancar) o 0 (llegó '$UI_SETTLE')."
    exit 2
  fi
  ui_prepare_simulator
  # Apagarlo al terminar, también si algo falla o se interrumpe (Ctrl+C).
  if [[ "$UI_SHUTDOWN_AT_END" == true ]]; then
    trap 'ui_shutdown "$UI_UDID"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
  fi
  if [[ "$mode" != journey ]]; then
    run_ui_build
  else
    log "[ci] test-ui: sin recompilar (usa lo último de test-ui, test-ui-smoke o test-ui-build)"
  fi
  run_ui_test_without_building "$log_name" "${only[@]}" || code=$?
  if [[ $code -ne 0 ]]; then
    exit "$code"
  fi
}

# Sólo compila las pruebas de UI (para después correr recorridos con test-ui-journey).
run_ui_build_only() {
  ui_prepare_simulator
  run_ui_build
}

# Borra el simulador de pruebas de UI a propósito (queda apagado y limpio).
run_ui_erase() {
  local udid
  udid="$(ui_simulator)"
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  xcrun simctl erase "$udid"
  log "[ci] test-ui-erase: $UI_SIMULATOR_NAME ($udid) borrado y apagado"
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
      run_ui_tests all
      ;;
    test-ui-smoke)
      run_ui_tests smoke
      ;;
    test-ui-build)
      run_ui_build_only
      ;;
    test-ui-journey)
      shift
      run_ui_tests journey "$@"
      ;;
    test-ui-erase)
      run_ui_erase
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
      log "  Uso: $(basename "${BASH_SOURCE[0]}") [all|test|build-ios|build-watch|test-ui|test-ui-smoke|test-ui-build|test-ui-journey <Clase>…|test-ui-erase|guards]" >&2
      exit 2
      ;;
  esac
  log ""
  log "[ci] OK"
}

main "$@"