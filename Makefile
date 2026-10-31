# PR-0002 — CI local reproducible.
#
# Atajos convencionales que delegan en `scripts/ci.sh` (pipeline reproducible de
# build + unit tests). Ejecutar siempre desde la raíz del repo con rutas relativas
# (sin dependencia de rutas absolutas de un desarrollador). Cualquier gate que falle
# hace que `make` devuelva exit code != 0.

.PHONY: ci test build test-ios test-watch test-ui test-ui-smoke test-ui-build test-ui-journey test-ui-erase guards

# Pipeline completo: guards + swift build + swift test + build schemes iOS y watchOS.
ci:
	./scripts/ci.sh all

# Solo unit tests del paquete PRCore.
test:
	./scripts/ci.sh test

# Guard del pbxproj.
guards:
	./scripts/ci.sh guards

# Build Debug del scheme iOS (destination concreto o genérico de Simulator).
test-ios:
	./scripts/ci.sh build-ios

# Build Debug del scheme watchOS (destination concreto o genérico de Simulator).
test-watch:
	./scripts/ci.sh build-watch

# Pruebas de UI (XCUIAutomation) por recorrido, en el simulador "PR UI Tests" (SCRUM-228).
# Fuera de `make ci` (y del CI de GitHub). Compilan con el simulador apagado, lo arrancan,
# corren y lo apagan al terminar. Cada historia corre `make ci`, el smoke y los recorridos
# que toca; todos los recorridos, al cerrar una fase (AGENTS.md §4).

# Todos los recorridos.
test-ui:
	./scripts/ci.sh test-ui

# 3 recorridos: cuestionario, entrenamiento con cierre forzado y primer entrenamiento → Exportar.
test-ui-smoke:
	./scripts/ci.sh test-ui-smoke

# Sólo compila las pruebas de UI (para después correr recorridos sin recompilar).
test-ui-build:
	./scripts/ci.sh test-ui-build

# Uno o varios recorridos, sin recompilar: make test-ui-journey RECORRIDO="TodayJourney ProfileJourney"
test-ui-journey:
	./scripts/ci.sh test-ui-journey $(RECORRIDO)

# Borra el simulador de pruebas de UI a propósito (el script sólo lo borra si quedó marcado
# con teclado físico).
test-ui-erase:
	./scripts/ci.sh test-ui-erase
