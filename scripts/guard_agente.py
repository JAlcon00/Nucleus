#!/usr/bin/env python3
#
# Guard del agente (PR-X002 del plan de aceleración): un PR no puede debilitar las pruebas
# para ponerse en verde (AGENTS.md §3.1 y §8). Compara el árbol de trabajo con la base y
# falla si:
#   1. baja el número de pruebas (`@Test` de Swift Testing y `func test…` de XCTest; una
#      prueba parametrizada cuenta una vez);
#   2. se borra un archivo de pruebas;
#   3. una línea nueva de una prueba la desactiva o la salta (`.disabled(`,
#      `.enabled(if: false)`, `withKnownIssue`, `XCTSkip`);
#   4. cambia, se renombra o se borra una muestra de persistencia existente
#      (`Fixtures/Persistence/v<N>/`). Una versión nueva va en su propia carpeta (ADR-0003);
#      editar la muestra vieja escondería un cambio incompatible del modelo.
# 1 y 2 se permiten con la etiqueta `test-retirado` en el PR; 4, con `muestra-cambiada`.
# 3 no tiene excepción. Las etiquetas las pone Jesús, nunca el agente.
#
# Base: `GUARD_BASE` (en el CI de un PR, `HEAD^1`, el `main` del commit de merge que arma
# GitHub); si no está, el merge-base con `origin/main`. Sin base avisa y no revisa nada.
# Etiquetas: `GUARD_LABELS`, separadas por comas.
#
# Uso: python3 -I -B scripts/guard_agente.py [raíz del repo]
# Salida: 0 si nada debilita las pruebas; 1 si algo sí; 2 si la base no sirve.

import os
import re
import subprocess
import sys

TEST_ROOTS = ("Packages/PRCore/Tests/", "PRUITests/")
FIXTURE_ROOT = "Packages/PRCore/Tests/PRCoreTests/Fixtures/Persistence/"
RETIRED_TEST_LABEL = "test-retirado"
CHANGED_FIXTURE_LABEL = "muestra-cambiada"

# POSIX ERE para `git grep -E`: una línea por prueba.
SWIFT_TESTING_TEST = r"^[[:space:]]*@Test([[:space:](]|$)"
XCTEST_TEST = (
    r"^[[:space:]]*((@MainActor|override|final|public|internal|private|nonisolated)[[:space:]]+)*"
    r"func[[:space:]]+test[A-Za-z0-9_]*[[:space:]]*\("
)

WEAKENING = (
    (re.compile(r"(?<![A-Za-z0-9_])\.disabled\s*\("), "desactiva una prueba (`.disabled`)"),
    (re.compile(r"\.enabled\s*\(\s*if\s*:\s*false\s*\)"), "desactiva una prueba (`.enabled(if: false)`)"),
    (re.compile(r"\bwithKnownIssue\s*[({]"), "marca una falla como conocida (`withKnownIssue`)"),
    (re.compile(r"\bXCTSkip(?:If|Unless)?\b"), "salta una prueba (`XCTSkip`)"),
)


class BaseError(Exception):
    pass


def git(root, *args, check=True):
    result = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)
    if check and result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, ["git", *args], result.stdout, result.stderr)
    return result.stdout


def in_tests(path):
    return path.startswith(TEST_ROOTS)


def in_fixtures(path):
    return path.startswith(FIXTURE_ROOT)


def resolve_base(root):
    explicit = os.environ.get("GUARD_BASE", "").strip()
    if explicit:
        result = subprocess.run(
            ["git", "-C", root, "rev-parse", "--verify", "--quiet", explicit + "^{commit}"],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise BaseError("GUARD_BASE no es un commit de este repo: " + explicit)
        return result.stdout.strip()
    upstream = git(root, "rev-parse", "--verify", "--quiet", "origin/main^{commit}", check=False).strip()
    if not upstream:
        return None
    return git(root, "merge-base", upstream, "HEAD").strip()


def test_pathspecs():
    return [":(glob)" + root + "**/*.swift" for root in TEST_ROOTS]


def count_tests(root, rev):
    """Pruebas en `rev`, o en el árbol de trabajo (con archivos nuevos) si `rev` es None."""
    total = 0
    for pattern in (SWIFT_TESTING_TEST, XCTEST_TEST):
        # `git grep` sale con 1 si no encuentra nada; con 2 o más, falló de verdad.
        options = [] if rev else ["--untracked"]
        trees = [rev] if rev else []
        result = subprocess.run(
            ["git", "-C", root, "grep", "-c", *options, "-E", pattern, *trees, "--", *test_pathspecs()],
            capture_output=True, text=True,
        )
        if result.returncode > 1:
            raise subprocess.CalledProcessError(result.returncode, ["git", "grep"], result.stdout, result.stderr)
        for line in result.stdout.splitlines():
            total += int(line.rsplit(":", 1)[1])
    return total


def changed_paths(root, base):
    """(estado, ruta de antes, ruta de ahora) de lo que cambió en las carpetas de pruebas."""
    changes = []
    output = git(root, "diff", "--name-status", "-M", "--no-color", base, "--", *TEST_ROOTS)
    for line in output.splitlines():
        fields = line.split("\t")
        status = fields[0][0]
        old = fields[1]
        new = fields[2] if len(fields) > 2 else fields[1]
        changes.append((status, old, new))
    untracked = git(root, "ls-files", "--others", "--exclude-standard", "--", *TEST_ROOTS)
    for path in untracked.splitlines():
        changes.append(("A", path, path))
    return changes


def added_swift_lines(root, base, changes):
    """(ruta, número de línea, texto) de cada línea nueva en archivos `.swift` de pruebas."""
    added = []
    diff = git(root, "diff", "-U0", "-M", "--no-color", "--no-ext-diff", base, "--", *test_pathspecs())
    path = None
    number = 0
    hunk = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")
    for line in diff.splitlines():
        if line.startswith("+++ "):
            path = line[6:] if line.startswith("+++ b/") else None
            continue
        match = hunk.match(line)
        if match:
            number = int(match.group(1))
            continue
        if path and line.startswith("+"):
            added.append((path, number, line[1:]))
            number += 1
    untracked = {new for status, _, new in changes if status == "A"} - set(
        git(root, "ls-files", "--", *TEST_ROOTS).splitlines()
    )
    for path in sorted(untracked):
        if not path.endswith(".swift"):
            continue
        with open(os.path.join(root, path), encoding="utf-8", errors="replace") as handle:
            for index, text in enumerate(handle.read().splitlines(), start=1):
                added.append((path, index, text))
    return added


def weakening_reason(text):
    stripped = text.strip()
    if stripped.startswith("//") or stripped.startswith("*") or stripped.startswith("/*"):
        return None
    for pattern, reason in WEAKENING:
        if pattern.search(text):
            return reason
    return None


def main(argv):
    root = os.path.abspath(argv[1] if len(argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
    labels = {label.strip() for label in os.environ.get("GUARD_LABELS", "").split(",") if label.strip()}
    try:
        base = resolve_base(root)
    except BaseError as error:
        print("ERROR: " + str(error), file=sys.stderr)
        return 2
    if base is None:
        print("AVISO: sin GUARD_BASE ni origin/main; el guard del agente no revisa nada.")
        return 0

    errors = []
    allowed = []
    changes = changed_paths(root, base)

    before = count_tests(root, base)
    after = count_tests(root, None)
    if after < before:
        message = "baja el número de pruebas: {} → {}".format(before, after)
        (allowed if RETIRED_TEST_LABEL in labels else errors).append(message)

    for status, old, new in changes:
        if status == "D" and in_tests(old) and not in_fixtures(old):
            message = "se borra un archivo de pruebas: " + old
            (allowed if RETIRED_TEST_LABEL in labels else errors).append(message)
        if status in ("M", "D", "R", "T") and in_fixtures(old):
            message = "cambia una muestra de persistencia existente: " + old
            (allowed if CHANGED_FIXTURE_LABEL in labels else errors).append(message)

    for path, number, text in added_swift_lines(root, base, changes):
        reason = weakening_reason(text)
        if reason:
            errors.append("{}:{}: {}".format(path, number, reason))

    for message in allowed:
        label = CHANGED_FIXTURE_LABEL if "muestra" in message else RETIRED_TEST_LABEL
        print("AVISO: {} (permitido por la etiqueta `{}`)".format(message, label))
    if errors:
        for message in errors:
            print("ERROR: " + message, file=sys.stderr)
        print(
            "ERROR: el PR debilita las pruebas (base {}). Ver scripts/guard_agente.py.".format(base[:7]),
            file=sys.stderr,
        )
        return 1
    print("OK: ninguna prueba se borra, desactiva ni reduce (base {}, {} → {} pruebas).".format(base[:7], before, after))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
