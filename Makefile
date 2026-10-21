# PR-0002 — CI local reproducible.
#
# Atajos convencionales que delegan en `scripts/ci.sh` (pipeline reproducible de
# build + unit tests). Ejecutar siempre desde la raíz del repo con rutas relativas
# (sin dependencia de rutas absolutas de un desarrollador). Cualquier gate que falle
# hace que `make` devuelva exit code != 0.

.PHONY: ci test build test-ios test-watch guards

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
