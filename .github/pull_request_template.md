<!--
Plantilla de PR de Nucleus (PR-X003). El formato sale de AGENTS.md §7.
Pega las líneas reales de cada comando. "Los tests pasan" sin la línea no cuenta.
Lo que no aplique se borra o se marca "no aplica" con la razón.
-->

## Historia

- **Jira:** SCRUM-XX (o PR-X00N del plan de aceleración)
- **Modo:** lógica / UI / vertical
- **Carril:** 🟢 verde (no toca rutas de `.github/CODEOWNERS`) / 🟡 amarillo (toca alguna; lo aprueba Jesús, sin auto-merge)

## Criterios de aceptación

| Criterio | Prueba que lo demuestra | Resultado |
|---|---|---|
| Dado …, cuando …, entonces … | `Suite.prueba` | ✅ / ❌ / 👤 pendiente |

## Cambios

- `Ruta/Archivo.swift` → qué y por qué

## Evidencia

- **Línea base:** `make test` → …
- **Final:** `make ci` → …
- **Guard del agente:** `OK: ninguna prueba se borra, desactiva ni reduce (base …, N → M pruebas).`
- **E2E:** `make test-ui-smoke` y los recorridos que toca → …
- **Warnings nuevos:** ninguno / lista
- Si algo no se pudo correr: **no verificado por ejecución**, y por qué.

## Invariantes y riesgos

- **Invariantes que toca:** …
- **Riesgos:** …
- **Pendientes 👤 (Jesús en el iPhone o el reloj):** …
