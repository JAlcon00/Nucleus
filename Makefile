# PR-0002 — CI local reproducible.
#
# Atajos convencionales que delegan en `scripts/ci.sh` (pipeline reproducible de
# build + unit tests). Ejecutar siempre desde la raíz del repo con rutas relativas
# (sin dependencia de rutas absolutas de un desarrollador). Cualquier gate que falle
# hace que `make` devuelva exit code != 0.

.PHONY: ci test build test-ios guards

# Pipeline completo: guards + swift build + swift test + build scheme iOS.
ci:
	./scripts/ci.sh all

# Solo unit tests del paquete PRCore.
test:
	./scripts/ci.sh test

# Guard del pbxproj.
guards:
	./scripts/ci.sh guards

# Build del scheme iOS real (integración, si hay destination disponible).
test-ios:
	./scripts/ci.sh build-ios