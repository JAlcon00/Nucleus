#!/usr/bin/env bash
#
# PR-F009 (SCRUM-262) — Build de prueba para iPhone con cuenta gratuita.
#
# Compila Debug, firma sólo con HealthKit e instala en el iPhone conectado. No toca
# `PR/PR.entitlements` ni el proyecto: las opciones van en la línea de `xcodebuild`.
# - `CODE_SIGN_ENTITLEMENTS`: la cuenta gratuita no admite Sign in with Apple.
# - `PR_DEVICE_TEST`: abre desde el ícono con el usuario simulado (`AuthLaunchMode`).
# - `-allowProvisioningUpdates`: pide o renueva el perfil, que dura 7 días.
#
# Instalar encima de la misma app conserva sus datos. Este build no sirve para TestFlight.
#
# Uso:
#   make install-iphone
#   make install-iphone DEVICE="Nombre del iPhone"   # con varios iPhone
#
# Salida: 0 = instalada; != 0 = no se instaló (el motivo va a stderr).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTITLEMENTS="scripts/device/PR.device.entitlements"
DERIVED_DATA="${PR_DEVICE_DERIVED_DATA:-${TMPDIR:-/tmp}/pr-device-build}"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphoneos/PR.app"
BUILD_LOG="$DERIVED_DATA/install-iphone.log"

log() { printf '%s\n' "$*" >&2; }

# Usa Xcode completo si el developer dir activo es CommandLineTools.
if [[ -z "${DEVELOPER_DIR:-}" ]] \
  && [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]] \
  && [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# Elige el iPhone. Imprime "<udid><tab><nombre>", o explica por qué no se puede y falla.
select_device() {
  local devices_json="$1"
  DEVICE="${DEVICE:-}" python3 -I -B - "$devices_json" <<'PY'
import json
import os
import sys


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def is_iphone(device):
    hardware = device.get("properties", {}).get("hardware", {})
    return hardware.get("reality") == "physical" and hardware.get("deviceType") == "iPhone"


def name_of(device):
    return device.get("properties", {}).get("state", {}).get("name", "")


def developer_mode_is_off(device):
    status = device.get("properties", {}).get("state", {}).get("developerModeStatus")
    return status is not None and "enabled" not in status


with open(sys.argv[1], encoding="utf-8") as devices_file:
    devices = json.load(devices_file).get("result", {}).get("devices", [])

reachable = [
    device for device in devices
    if is_iphone(device)
    and device.get("properties", {}).get("connection", {}).get("state") != "unavailable"
]
if not reachable:
    fail("no hay ningún iPhone conectado. Conéctalo a esta Mac, desbloquéalo y vuelve a correr el comando.")

wanted = os.environ.get("DEVICE", "").strip()
names = ", ".join(sorted(name_of(device) for device in reachable))
if wanted:
    chosen = [device for device in reachable if name_of(device).casefold() == wanted.casefold()]
    if not chosen:
        fail(f'no encontré el iPhone "{wanted}". Conectados: {names}.')
elif len(reachable) > 1:
    fail(f'hay varios iPhone conectados: {names}. Elige uno con make install-iphone DEVICE="<nombre>".')
else:
    chosen = reachable

device = chosen[0]
if device.get("properties", {}).get("connection", {}).get("pairingState") != "paired":
    fail(f'"{name_of(device)}" no confía en esta Mac. Desbloquéalo, toca Confiar y vuelve a correr el comando.')
if developer_mode_is_off(device):
    fail(f'"{name_of(device)}" tiene apagado el modo desarrollador. Actívalo en Ajustes › Privacidad y seguridad › Modo de desarrollador.')

print(f'{device["properties"]["hardware"]["udid"]}\t{name_of(device)}')
PY
}

# Explica los fallos de firma que tienen arreglo conocido.
explain_build_failure() {
  if grep -qiE "no account|requires a development team|not logged in|sign in to your apple" "$BUILD_LOG"; then
    log "Xcode no tiene la sesión de tu cuenta: revisa Xcode › Settings › Apple Accounts."
  elif grep -qiE "maximum (number of )?app id|app id limit|maximum app id" "$BUILD_LOG"; then
    log "La cuenta gratuita llegó a su límite de App IDs de la semana: espera a que venza o borra apps de prueba."
  elif grep -qiE "developer mode" "$BUILD_LOG"; then
    log "Revisa el modo desarrollador en Ajustes › Privacidad y seguridad › Modo de desarrollador."
  elif grep -qiE "locked|passcode" "$BUILD_LOG"; then
    log "Desbloquea el iPhone y vuelve a correr el comando."
  fi
  log "Log completo: $BUILD_LOG"
}

mkdir -p "$DERIVED_DATA"
devices_json="$DERIVED_DATA/devices.json"

if ! xcrun devicectl list devices --quiet --json-output "$devices_json" >/dev/null 2>&1; then
  log "ERROR: no pude listar los dispositivos con devicectl. Abre Xcode una vez y vuelve a correr el comando."
  exit 1
fi

selection="$(select_device "$devices_json")"
device_id="${selection%%$'\t'*}"
device_name="${selection#*$'\t'}"

log "[install-iphone] compilando Debug para \"$device_name\""
cd "$REPO_ROOT"
if ! xcodebuild \
  -project PR.xcodeproj \
  -scheme PR \
  -configuration Debug \
  -destination "id=$device_id" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) PR_DEVICE_TEST' \
  build >"$BUILD_LOG" 2>&1; then
  log "ERROR: no se pudo compilar o firmar el build de prueba."
  explain_build_failure
  exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
  log "ERROR: el build terminó pero no encontré la app en $APP_PATH."
  exit 1
fi

log "[install-iphone] instalando en \"$device_name\""
if ! xcrun devicectl device install app --device "$device_id" "$APP_PATH" >>"$BUILD_LOG" 2>&1; then
  log "ERROR: no se pudo instalar en \"$device_name\"."
  explain_build_failure
  exit 1
fi

log "[install-iphone] OK: instalada en \"$device_name\". Tus datos se conservan."
log "El perfil dura 7 días: al vencer, vuelve a correr este comando."
log "La primera vez, confía en tu cuenta en Ajustes › General › VPN y gestión de dispositivos."
