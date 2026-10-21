# Checklist de revisión de UI

Marca cada punto como ✅ cumple, ❌ falla (con hallazgo y severidad) o ⚠️ no verificable aquí (qué hace falta: dispositivo, Instruments, VoiceOver real).

## Jerarquía y tarea
- [ ] Se identifica la acción principal en menos de 1 s.
- [ ] Hay una sola acción primaria visual por pantalla o sección.
- [ ] Contenido terciario está fuera de la vista principal (menú, detalle).
- [ ] El texto es concreto y en lenguaje del usuario (sin jerga técnica, sin códigos de error).

## Sistema y consistencia
- [ ] Todos los espaciados, radios, colores y fuentes salen de tokens.
- [ ] Radios concéntricos en elementos anidados.
- [ ] Componentes nativos usados donde existen.
- [ ] Mismo concepto = mismo icono, color y palabra en toda la app.

## Color y contraste
- [ ] Texto ≥ 4.5:1 (grande ≥ 3:1); iconos/controles informativos ≥ 3:1 (medido con `scripts/contrast_check.py`).
- [ ] Color nunca es el único portador de significado.
- [ ] Rojo/destructivo reservado y acompañado de icono/texto.
- [ ] Funciona en claro, oscuro y aumento de contraste.
- [ ] Legible sobre el peor fondo realista bajo vidrio o imágenes.

## Layout y toque
- [ ] Áreas de toque ≥ 44×44 pt (más en acciones críticas o contexto de movimiento).
- [ ] Acciones frecuentes al alcance del pulgar; destructivas separadas.
- [ ] Sin tamaños de pantalla ni idiom hardcodeados; adapta por size class.
- [ ] Soporta textos 40 % más largos (localización) y RTL.

## Estados
- [ ] Carga, vacío, error, sin conexión, parcial, deshabilitado y éxito diseñados.
- [ ] La recarga conserva el contenido anterior visible.
- [ ] Los errores dicen qué pasó y qué hacer, con acción de recuperación.
- [ ] Nada que el usuario escribió o registró se pierde por error o navegación.

## Interacción y movimiento
- [ ] Feedback visual inmediato en cada control.
- [ ] Hápticos solo en confirmaciones, límites y cambios de estado.
- [ ] Animaciones con springs del sistema y duración ≤ 0.5 s salvo momentos expresivos.
- [ ] Reduce Motion respetado.
- [ ] Cada gesto tiene alternativa visible y acción accesible.

## Liquid Glass (si aplica)
- [ ] Vidrio solo en la capa de navegación/controles, no en contenido.
- [ ] Sin vidrio sobre vidrio; elementos cercanos en un `GlassEffectContainer`.
- [ ] `.glassEffect()` aplicado después de los modificadores de layout.
- [ ] Tinte solo para prominencia.
- [ ] Gating `#available` con fallback si el target es < iOS 26.

## Accesibilidad
- [ ] Dynamic Type hasta accessibility5 sin truncar información crítica; layout se reorganiza.
- [ ] Etiquetas VoiceOver con significado; elementos agrupados; orden lógico.
- [ ] Reduce Transparency, Increase Contrast, Bold Text y Differentiate Without Color comprobados.

## Performance
- [ ] `body` sin trabajo pesado ni formateadores creados al vuelo.
- [ ] Colecciones grandes en `List`/lazy stacks con ids estables; sin `AnyView`.
- [ ] Imágenes reducidas al tamaño mostrado y con espacio reservado.
- [ ] Efectos caros (vidrio, blur, sombras grandes) limitados y fuera de filas repetidas.
- [ ] Medido en el dispositivo más lento soportado (o marcado ⚠️).

## Código
- [ ] Views sin reglas de negocio; estado de pantalla modelado como tipo.
- [ ] Previews por estado, modo oscuro y Dynamic Type grande.
- [ ] Ninguna API usada sin verificar disponibilidad para el target mínimo.
