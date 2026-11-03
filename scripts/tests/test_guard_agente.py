#
# Pruebas de `scripts/guard_agente.py` (PR-X002 del plan de aceleración).
#
# Cada prueba arma un repo de git temporal con pruebas de Swift Testing y XCTest, una vista
# de la app y una muestra de persistencia; lo guarda como base, cambia el árbol de trabajo
# como lo haría un PR y corre el guard de verdad (proceso aparte) contra esa base.
#
# Uso: python3 -I -B -m unittest discover -s scripts/tests
#

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

GUARD = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "guard_agente.py")

UNIT_TESTS = "Packages/PRCore/Tests/PRCoreTests/RestTests.swift"
XC_TESTS = "Packages/PRCore/Tests/PRCoreTests/LegacyTests.swift"
UI_TESTS = "PRUITests/Journeys/TodayJourney.swift"
APP_VIEW = "PR/App/TodayView.swift"
FIXTURE = "Packages/PRCore/Tests/PRCoreTests/Fixtures/Persistence/v1/workouts.json"

BASE_FILES = {
    UNIT_TESTS: """import Testing

@Suite("Descanso")
struct RestTests {
    @Test("Empieza en cero")
    func startsAtZero() {
        #expect(true)
    }

    @Test("Cuenta hacia atrás", arguments: [1, 2, 3])
    func countsDown(seconds: Int) {
        #expect(seconds > 0)
    }

    @Test("Sólo si se pide", .enabled(if: ProcessInfo.processInfo.environment["PR_WRITE"] == "1"))
    func writesFixtures() {}

    func helper() -> Int { 1 }
}
""",
    XC_TESTS: """import XCTest

final class LegacyTests: XCTestCase {
    func testSavesSet() {
        XCTAssertTrue(true)
    }

    @MainActor
    func testRestoresWorkout() async throws {
        XCTAssertTrue(true)
    }
}
""",
    UI_TESTS: """import XCTest

final class TodayJourney: XCTestCase {
    func testTodayShowsExercises() {
        XCTAssertTrue(true)
    }
}
""",
    APP_VIEW: """import SwiftUI

struct TodayView: View {
    var body: some View {
        Button("Empezar") {}
            .disabled(false)
    }
}
""",
    FIXTURE: '{"id":"A","sets":[]}\n',
}


class GuardRepo:
    """Repo temporal con la base ya guardada en un commit."""

    def __init__(self):
        self.root = tempfile.mkdtemp(prefix="guard-agente-")
        self.git("init", "-q")
        for path, content in BASE_FILES.items():
            self.write(path, content)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "base")
        self.base = self.git("rev-parse", "HEAD").strip()

    def git(self, *args):
        env = dict(os.environ)
        env.update({
            "GIT_AUTHOR_NAME": "Prueba", "GIT_AUTHOR_EMAIL": "prueba@example.com",
            "GIT_COMMITTER_NAME": "Prueba", "GIT_COMMITTER_EMAIL": "prueba@example.com",
        })
        result = subprocess.run(
            ["git", "-C", self.root, "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", *args],
            capture_output=True, text=True, env=env, check=True,
        )
        return result.stdout

    def path(self, relative):
        return os.path.join(self.root, relative)

    def read(self, relative):
        with open(self.path(relative), encoding="utf-8") as handle:
            return handle.read()

    def write(self, relative, content):
        os.makedirs(os.path.dirname(self.path(relative)), exist_ok=True)
        with open(self.path(relative), "w", encoding="utf-8") as handle:
            handle.write(content)

    def replace(self, relative, old, new):
        content = self.read(relative)
        if old not in content:
            raise AssertionError("no está en " + relative + ": " + old)
        self.write(relative, content.replace(old, new, 1))

    def remove(self, relative):
        os.remove(self.path(relative))

    def run_guard(self, labels="", base=None):
        env = dict(os.environ)
        env["GUARD_BASE"] = self.base if base is None else base
        env["GUARD_LABELS"] = labels
        return subprocess.run(
            [sys.executable, "-I", "-B", GUARD, self.root],
            capture_output=True, text=True, env=env,
        )

    def cleanup(self):
        shutil.rmtree(self.root, ignore_errors=True)


class GuardAgenteTests(unittest.TestCase):

    def setUp(self):
        self.repo = GuardRepo()
        self.addCleanup(self.repo.cleanup)

    def assertPasses(self, result):
        self.assertEqual(result.returncode, 0, msg=result.stdout + result.stderr)

    def assertFails(self, result, message):
        self.assertEqual(result.returncode, 1, msg=result.stdout + result.stderr)
        self.assertIn(message, result.stderr)

    # MARK: - Sin cambios y cambios sanos

    def test_sin_cambios_pasa_y_cuenta_las_pruebas(self):
        result = self.repo.run_guard()
        self.assertPasses(result)
        # 3 @Test (una parametrizada cuenta una vez) + 2 XCTest + 1 de UI; `helper` no cuenta.
        self.assertIn("6 → 6 pruebas", result.stdout)

    def test_agregar_una_prueba_pasa(self):
        self.repo.replace(UNIT_TESTS, "    func helper()", "    @Test func stopsAtZero() {}\n\n    func helper()")
        result = self.repo.run_guard()
        self.assertPasses(result)
        self.assertIn("6 → 7 pruebas", result.stdout)

    def test_mover_un_archivo_de_pruebas_pasa(self):
        os.makedirs(self.repo.path("Packages/PRCore/Tests/PRDomainTests"))
        self.repo.git("mv", UNIT_TESTS, "Packages/PRCore/Tests/PRDomainTests/RestTests.swift")
        self.assertPasses(self.repo.run_guard())

    def test_desactivar_algo_en_la_app_no_cuenta(self):
        self.repo.replace(APP_VIEW, ".disabled(false)", ".disabled(true)\n            .disabled(isSaving)")
        self.assertPasses(self.repo.run_guard())

    def test_disabledByFlag_en_una_prueba_no_es_desactivar(self):
        self.repo.replace(UNIT_TESTS, "#expect(true)", "#expect(status == .offline(.disabledByFlag))")
        self.assertPasses(self.repo.run_guard())

    def test_enabled_if_con_una_condicion_real_pasa(self):
        self.repo.replace(
            UNIT_TESTS, "    func helper()",
            '    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil)) func local() {}\n\n    func helper()',
        )
        self.assertPasses(self.repo.run_guard())

    def test_un_comentario_que_menciona_withKnownIssue_pasa(self):
        self.repo.replace(UNIT_TESTS, "import Testing", "import Testing\n// Antes iban en `withKnownIssue { }`; ya no.")
        self.assertPasses(self.repo.run_guard())

    def test_agregar_una_muestra_de_una_version_nueva_pasa(self):
        self.repo.write("Packages/PRCore/Tests/PRCoreTests/Fixtures/Persistence/v2/workouts.json", '{"id":"A"}\n')
        self.assertPasses(self.repo.run_guard())

    # MARK: - 1. Baja el número de pruebas

    def test_quitar_una_prueba_de_swift_testing_falla(self):
        self.repo.replace(UNIT_TESTS, '    @Test("Empieza en cero")\n    func startsAtZero() {\n        #expect(true)\n    }\n', "")
        self.assertFails(self.repo.run_guard(), "baja el número de pruebas: 6 → 5")

    def test_quitar_una_prueba_de_xctest_falla(self):
        self.repo.replace(XC_TESTS, "    func testSavesSet() {\n        XCTAssertTrue(true)\n    }\n", "")
        self.assertFails(self.repo.run_guard(), "baja el número de pruebas: 6 → 5")

    def test_quitar_una_prueba_con_la_etiqueta_test_retirado_pasa(self):
        self.repo.replace(XC_TESTS, "    func testSavesSet() {\n        XCTAssertTrue(true)\n    }\n", "")
        result = self.repo.run_guard(labels="ux, test-retirado")
        self.assertPasses(result)
        self.assertIn("test-retirado", result.stdout)

    # MARK: - 2. Se borra un archivo de pruebas

    def test_borrar_un_archivo_de_pruebas_falla(self):
        self.repo.remove(UI_TESTS)
        self.assertFails(self.repo.run_guard(), "se borra un archivo de pruebas: " + UI_TESTS)

    def test_borrar_un_archivo_de_pruebas_con_la_etiqueta_pasa(self):
        self.repo.remove(UI_TESTS)
        self.assertPasses(self.repo.run_guard(labels="test-retirado"))

    # MARK: - 3. Una línea nueva desactiva o salta una prueba

    def test_agregar_disabled_falla(self):
        self.repo.replace(UNIT_TESTS, '@Test("Empieza en cero")', '@Test("Empieza en cero", .disabled("falla en CI"))')
        self.assertFails(self.repo.run_guard(), "desactiva una prueba (`.disabled`)")

    def test_agregar_enabled_if_false_falla(self):
        self.repo.replace(UNIT_TESTS, '@Test("Empieza en cero")', '@Test("Empieza en cero", .enabled(if: false))')
        self.assertFails(self.repo.run_guard(), "desactiva una prueba (`.enabled(if: false)`)")

    def test_agregar_withKnownIssue_falla(self):
        self.repo.replace(UNIT_TESTS, "        #expect(true)", "        withKnownIssue {\n            #expect(false)\n        }")
        self.assertFails(self.repo.run_guard(), "marca una falla como conocida (`withKnownIssue`)")

    def test_agregar_XCTSkip_falla(self):
        self.repo.replace(XC_TESTS, "        XCTAssertTrue(true)\n    }\n\n    @MainActor", '        throw XCTSkip("luego")\n    }\n\n    @MainActor')
        self.assertFails(self.repo.run_guard(), "salta una prueba (`XCTSkip`)")

    def test_agregar_XCTSkipIf_en_una_prueba_de_ui_falla(self):
        self.repo.replace(UI_TESTS, "XCTAssertTrue(true)", "try XCTSkipIf(true)")
        self.assertFails(self.repo.run_guard(), "salta una prueba (`XCTSkip`)")

    def test_desactivar_no_se_permite_ni_con_la_etiqueta(self):
        self.repo.replace(UNIT_TESTS, '@Test("Empieza en cero")', '@Test("Empieza en cero", .disabled())')
        self.assertFails(self.repo.run_guard(labels="test-retirado,muestra-cambiada"), "desactiva una prueba")

    def test_un_archivo_nuevo_sin_commit_tambien_se_revisa(self):
        self.repo.write("Packages/PRCore/Tests/PRCoreTests/NewTests.swift", "import Testing\n\n@Test(.disabled()) func later() {}\n")
        self.assertFails(self.repo.run_guard(), "Packages/PRCore/Tests/PRCoreTests/NewTests.swift:3")

    def test_lo_que_ya_estaba_en_la_base_no_cuenta(self):
        self.repo.replace(UNIT_TESTS, '@Test("Empieza en cero")', '@Test("Empieza en cero", .disabled())')
        self.repo.git("commit", "-q", "-am", "otra base")
        self.repo.base = self.repo.git("rev-parse", "HEAD").strip()
        self.repo.replace(UNIT_TESTS, "func helper() -> Int { 1 }", "func helper() -> Int { 2 }")
        self.assertPasses(self.repo.run_guard())

    # MARK: - 4. Muestras de persistencia

    def test_editar_una_muestra_existente_falla(self):
        self.repo.write(FIXTURE, '{"identifier":"A","sets":[]}\n')
        self.assertFails(self.repo.run_guard(), "cambia una muestra de persistencia existente: " + FIXTURE)

    def test_borrar_una_muestra_existente_falla(self):
        self.repo.remove(FIXTURE)
        result = self.repo.run_guard(labels="test-retirado")
        self.assertFails(result, "cambia una muestra de persistencia existente: " + FIXTURE)

    def test_editar_una_muestra_con_la_etiqueta_muestra_cambiada_pasa(self):
        self.repo.write(FIXTURE, '{"identifier":"A","sets":[]}\n')
        self.assertPasses(self.repo.run_guard(labels="muestra-cambiada"))

    # MARK: - Base

    def test_una_base_que_no_existe_es_un_error(self):
        result = self.repo.run_guard(base="no-existe")
        self.assertEqual(result.returncode, 2, msg=result.stdout + result.stderr)
        self.assertIn("GUARD_BASE", result.stderr)

    def test_junta_todos_los_problemas_en_una_corrida(self):
        self.repo.remove(UI_TESTS)
        self.repo.write(FIXTURE, "{}\n")
        result = self.repo.run_guard()
        self.assertFails(result, "se borra un archivo de pruebas")
        self.assertIn("cambia una muestra de persistencia existente", result.stderr)
        self.assertIn("baja el número de pruebas", result.stderr)


if __name__ == "__main__":
    unittest.main()
