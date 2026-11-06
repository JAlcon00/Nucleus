"""Pruebas de scripts/install_iphone.sh (PR-F009, SCRUM-262).

Corren con un `xcrun` y un `xcodebuild` falsos: no compilan ni tocan ningún iPhone.
"""

import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "install_iphone.sh"
ENTITLEMENTS = REPO_ROOT / "scripts" / "device" / "PR.device.entitlements"

FAKE_XCRUN = """#!/bin/bash
echo "xcrun $*" >> "$FAKE_CALLS"
if [[ "$1 $2 $3" == "devicectl list devices" ]]; then
  [[ "${FAKE_LIST_FAILS:-}" == "1" ]] && exit 1
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "--json-output" ]]; then cp "$FAKE_DEVICES" "$2"; fi
    shift
  done
  exit 0
fi
exit "${FAKE_INSTALL_EXIT:-0}"
"""

FAKE_XCODEBUILD = """#!/bin/bash
echo "xcodebuild $*" >> "$FAKE_CALLS"
printf '%s\\n' "${FAKE_BUILD_OUTPUT:-}"
if [[ "${FAKE_BUILD_EXIT:-0}" == "0" ]]; then
  mkdir -p "$PR_DEVICE_DERIVED_DATA/Build/Products/Debug-iphoneos/PR.app"
fi
exit "${FAKE_BUILD_EXIT:-0}"
"""


def device(name, udid, *, reality="physical", device_type="iPhone", paired="paired",
           connection="disconnected", developer_mode=None):
    state = {"name": name}
    state["developerModeStatus"] = developer_mode or {"enabled": {"mode": 1}}
    return {
        "properties": {
            "connection": {"pairingState": paired, "state": connection},
            "hardware": {"reality": reality, "deviceType": device_type, "udid": udid},
            "state": state,
        }
    }


class InstallIPhoneTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        for name, body in (("xcrun", FAKE_XCRUN), ("xcodebuild", FAKE_XCODEBUILD)):
            tool = bin_dir / name
            tool.write_text(body, encoding="utf-8")
            tool.chmod(tool.stat().st_mode | stat.S_IEXEC)
        self.calls = self.root / "calls.log"
        self.calls.touch()
        self.devices = self.root / "devices.json"
        self.env = {
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            "FAKE_CALLS": str(self.calls),
            "FAKE_DEVICES": str(self.devices),
            "PR_DEVICE_DERIVED_DATA": str(self.root / "derived"),
            "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer",
        }

    def run_script(self, devices, **env):
        self.devices.write_text(json.dumps({"result": {"devices": devices}}), encoding="utf-8")
        return subprocess.run(
            [str(SCRIPT)],
            env={**self.env, **env},
            capture_output=True,
            text=True,
            check=False,
        )

    def call_lines(self):
        return self.calls.read_text(encoding="utf-8").splitlines()

    def build_line(self):
        return next(line for line in self.call_lines() if line.startswith("xcodebuild"))

    def assert_nothing_built(self):
        self.assertFalse([line for line in self.call_lines() if line.startswith("xcodebuild")])

    def test_sin_iphone_falla_con_mensaje_claro(self):
        result = self.run_script([])

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no hay ningún iPhone conectado", result.stderr)
        self.assert_nothing_built()

    def test_simuladores_y_otros_dispositivos_no_cuentan(self):
        result = self.run_script([
            device("Simulado", "SIM", reality="simulated"),
            device("Reloj", "WATCH", device_type="appleWatch"),
            device("iPad", "IPAD", device_type="iPad"),
        ])

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no hay ningún iPhone conectado", result.stderr)

    def test_iphone_recordado_pero_fuera_de_alcance_no_cuenta(self):
        result = self.run_script([device("Lejos", "FAR", connection="unavailable")])

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no hay ningún iPhone conectado", result.stderr)

    def test_sin_poder_listar_falla_con_mensaje(self):
        result = self.run_script([], FAKE_LIST_FAILS="1")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no pude listar", result.stderr)

    def test_un_iphone_compila_debug_firma_solo_salud_e_instala(self):
        result = self.run_script([device("Mi iPhone", "UDID-1")])

        self.assertEqual(result.returncode, 0, result.stderr)
        build = self.build_line()
        self.assertIn("-configuration Debug", build)
        self.assertIn("-scheme PR", build)
        self.assertIn("-destination id=UDID-1", build)
        self.assertIn("-allowProvisioningUpdates", build)
        self.assertIn("CODE_SIGN_ENTITLEMENTS=scripts/device/PR.device.entitlements", build)
        self.assertIn("SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) PR_DEVICE_TEST", build)
        install = self.call_lines()[-1]
        self.assertIn("devicectl device install app --device UDID-1", install)
        self.assertIn("Debug-iphoneos/PR.app", install)
        self.assertIn("7 días", result.stderr)

    def test_varios_iphone_sin_device_piden_elegir(self):
        result = self.run_script([device("Uno", "U1"), device("Dos", "U2")])

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("varios iPhone", result.stderr)
        self.assertIn("Dos, Uno", result.stderr)
        self.assert_nothing_built()

    def test_device_elige_por_nombre(self):
        result = self.run_script([device("Uno", "U1"), device("Dos", "U2")], DEVICE="dos")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("-destination id=U2", self.build_line())

    def test_device_desconocido_falla_y_dice_cuales_hay(self):
        result = self.run_script([device("Uno", "U1")], DEVICE="Tres")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn('no encontré el iPhone "Tres"', result.stderr)
        self.assertIn("Uno", result.stderr)
        self.assert_nothing_built()

    def test_iphone_sin_confiar_lo_dice(self):
        result = self.run_script([device("Uno", "U1", paired="unpaired")])

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no confía en esta Mac", result.stderr)
        self.assert_nothing_built()

    def test_modo_desarrollador_apagado_lo_dice(self):
        result = self.run_script([device("Uno", "U1", developer_mode={"disabled": {"mode": 0}})])

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("modo desarrollador", result.stderr)
        self.assert_nothing_built()

    def test_cuenta_sin_sesion_lo_explica_y_no_instala(self):
        result = self.run_script(
            [device("Uno", "U1")],
            FAKE_BUILD_EXIT="65",
            FAKE_BUILD_OUTPUT='error: No Account for Team "ABC".',
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Apple Accounts", result.stderr)
        self.assertFalse([line for line in self.call_lines() if "install app" in line])

    def test_limite_de_app_ids_lo_explica(self):
        result = self.run_script(
            [device("Uno", "U1")],
            FAKE_BUILD_EXIT="65",
            FAKE_BUILD_OUTPUT="error: Your maximum App ID limit has been reached.",
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("límite de App IDs", result.stderr)

    def test_si_falla_la_instalacion_el_codigo_no_es_cero(self):
        result = self.run_script([device("Uno", "U1")], FAKE_INSTALL_EXIT="1")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no se pudo instalar", result.stderr)

    def test_entitlements_solo_traen_salud(self):
        text = ENTITLEMENTS.read_text(encoding="utf-8")

        self.assertIn("com.apple.developer.healthkit", text)
        self.assertNotIn("applesignin", text)


if __name__ == "__main__":
    unittest.main()
