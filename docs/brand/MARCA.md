# Marca de Finanzas IA: «Durazno cálido»

La eligió el responsable el 2026-11-04 entre tres propuestas. Lo que pidió: «pulida, elegante, minimalista, pero con un estilo animado, fluido, como con
un toque caricaturesco pero sin abusar», y «con mejores SVGs».

## Principios
- **Minimalista y cálida.** Mucho espacio, superficies planas y sin sombras. El color dice algo: gasto, ingreso, acción. No decora.
- **Animada y fluida, con un toque caricaturesco medido.** La mascota, Chanchi, solo aparece en la bienvenida, en las pantallas vacías, mientras la IA trabaja,
  al confirmar y cuando algo falla. Nunca en listas ni formularios, ni como adorno fijo.
- **Todo va dentro del APK.** Las fuentes y las ilustraciones no se descargan al usar la app: funciona sin red y no le avisa a nadie que la abriste.

## Color
Los tokens son la única fuente de color. Ningún widget usa un hex suelto.

| Token | Claro | Oscuro | Uso |
|---|---|---|---|
| `background` | `#FFF7F0` | `#1C1612` | Fondo de página |
| `surface` | `#FFFFFF` | `#261E19` | Tarjetas, hojas |
| `surfaceLow` | `#FFF3EA` | `#211A15` | Secciones |
| `soft` | `#FFE3D3` | `#3A2A22` | Chips, avatares, contenedores |
| `primary` / `onPrimary` | `#BC4626` / `#FFFFFF` | `#FF9F7A` / `#3A1406` | Acción principal |
| `primaryContainer` / `onPrimaryContainer` | `#FFE3D3` / `#7A2E16` | `#5A2A18` / `#FFDCCB` | Elementos seleccionados |
| `text` | `#2B2118` | `#F6EDE6` | Texto |
| `textSecondary` | `#6F6259` | `#CDBDB2` | Texto de apoyo |
| `outline` | `#F0DCCD` | `#3D2F27` | Bordes finos, solo si hace falta separar |
| `expense` | `#C43D3D` | `#FF8A80` | Gastos, errores |
| `income` | `#2A7A52` | `#7DD3A8` | Ingresos, éxito |
| `warning` | `#A15C07` | `#F5B85C` | Avisos |

Contraste medido: `primary` sobre blanco 5,2:1; `textSecondary` sobre `background` 5,6:1; `expense` 5,1:1; `income` 5,2:1. En oscuro, `primary` sobre
`onPrimary` 8,2:1. Una prueba automática debe comprobar que cada par texto/fondo de esta tabla da al menos 4,5:1.

La mascota tiene colores fijos, iguales en claro y oscuro: cuerpo `#FFB4A2`, sombra `#F59C88`, brillo `#FFD3C7`, patas `#FFA48F`, fondo `#F08F7A`,
hocico `#FF9F8A`, ranura y boca `#BC4626`, moneda `#F2B544`.

## Tipografía
Nunito, que ya viene en el APK y no suma peso.

| Rol | Tamaño | Peso | Notas |
|---|---|---|---|
| Saldo (display) | 36 sp | 800 | Cifras tabulares, interletra −0,5 |
| Título de página | 24 sp | 800 | |
| Título de sección o tarjeta | 18 sp | 700 | |
| Texto | 16 sp | 400 | Interlineado 1,45 |
| Botones y chips | 14 sp | 700 | |
| Leyenda | 12,5 sp | 600 | Color `textSecondary` |

Todo número de dinero usa `FontFeature.tabularFigures()`. Ningún texto baja de 12 sp.

## Forma y espacio
- **Radios:** tarjetas 20, campos 16, botones y chips en píldora, hojas inferiores 28 en las esquinas de arriba.
- **Espaciado:** 4, 8, 12, 16, 24 y 32. Margen lateral de página: 20.
- **Elevación:** sin sombras. Las capas se distinguen por el tono (`surface` sobre `background`).
- **Toque:** área mínima de 48 × 48 dp.

## Movimiento
- **Duraciones:**
  - 120 ms al tocar
  - 200 ms en cambios de estado
  - 320 ms en tarjetas y hojas
  - 450 ms al cambiar de página
  - de 600 a 1200 ms para Chanchi
- **Curvas:**
  - Entrada: `Cubic(0.22, 1, 0.36, 1)`.
  - Rebote (`Curves.easeOutBack`): solo en elementos pequeños, como el botón de escanear, los chips y Chanchi.
  - Salida: dura el 70 % de la entrada y usa `Curves.easeInCubic`.
- **Patrones:**
  - Las listas entran escalonadas, 40 ms entre elementos y como mucho 8 elementos animados.
  - El saldo cuenta hasta su valor nuevo en 700 ms con `easeOutCubic`.
  - Al presionar, botones y tarjetas bajan a escala 0,97 en 120 ms.
  - La foto del recibo hace Hero entre la bandeja y su vista.
  - Las páginas cambian con fundido y escala de 0,98 a 1.
- **Reducir movimiento:** si `MediaQuery.disableAnimations` es verdadero, se quitan el escalonado, los rebotes, los saltos y el conteo. Quedan solo fundidos de
  150 ms o menos.

## Chanchi
- **Archivos:** `assets/brand/`.
  - `chanchi_<estado>.svg`: cinco estados completos (`idle`, `happy`, `thinking`, `sleepy`, `worried`).
  - `layers/`: el cuerpo, los ojos, las bocas y los extras (moneda, puntos, z, gota), todos con el mismo `viewBox` 160 × 140 para poder apilarlos.
  - `scenes/`: las tres escenas de bienvenida (`intro_local`, `intro_receipt`, `intro_check`).
  - `icon/`: el ícono.
- **Todo sale de `tools/brand/gen_chanchi.py`.** El arte se cambia ahí y se regenera con `python tools/brand/gen_chanchi.py assets/brand`. Los SVG no se editan
  a mano.
- **Widget `ChanchiMascot(mood, size, animate)`:** apila las capas con flutter_svg y anima cada parte.
  - Parpadeo: cada 3,5 a 5 s, al azar, con los ojos a escala vertical 0,1 durante 120 ms.
  - Salto con aplastamiento y estiramiento: al aparecer y al celebrar.
  - En `happy`, la moneda cae a la ranura. En `thinking`, los puntos laten. En `sleepy`, las z suben. En `worried`, la gota baja.
  - Solo el parpadeo es continuo: nada salta en bucle.
- **Dónde aparece:**
  - Bienvenida: las tres escenas.
  - Bandeja vacía y listas vacías: `sleepy`.
  - Mientras la IA lee un recibo o un extracto, o prepara un análisis: `thinking`.
  - Al confirmar en la bandeja: `happy` durante 1,2 s.
  - Errores de la IA: `worried`.
  - Saludo del inicio: `idle` a 36 dp, salta una vez al abrir.
- **Accesibilidad:** Chanchi es decorativo (`ExcludeSemantics`). El texto que lo acompaña lleva el mensaje.

## Ícono y pantalla de arranque
- **Ícono adaptativo:**
  - Fondo `#BC4626` y primer plano Chanchi (`icon/ic_foreground.svg`), dentro de la zona segura de 66 dp.
  - Versión monocroma para los íconos temáticos de Android 13 (`icon/ic_monochrome.svg`).
  - Versión heredada para Android 7 (`icon/ic_legacy.svg`).
- **Generación:** los PNG se sacan de los SVG con Chrome o Edge en modo headless. Después `flutter_launcher_icons`, que ya está en `dev_dependencies`, genera los
  mipmaps.
- **Pantalla de arranque (Android 12+):** fondo `#FFF7F0`, o `#1C1612` en oscuro, con el ícono. En versiones anteriores, el mismo fondo con el primer plano
  centrado.
- **Nombre visible:** «Finanzas IA», sin cambios. También es el que aparece en el consentimiento de Google.

## Pantallas, en orden
1. **Tema global:** `ThemeData` claro y oscuro a partir de los tokens, en `lib/core/presentation/theme.dart`. El acento por defecto es el de la marca y los colores
   dinámicos (Material You) vienen apagados.
2. **Inicio:**
   - Saludo en español según la hora («Buenos días», «Buenas tardes», «Buenas noches»), en vez de «You're back! / User».
   - Saldo con conteo y períodos como chips.
   - Tarjetas de gasto e ingreso.
   - Cuentas con su ícono o su inicial en un círculo `soft`, en vez de hexágonos vacíos.
3. **Navegación inferior:** Inicio, Movimientos, botón central «Escanear recibo», Bandeja (con el número de pendientes) y Más.
4. **Bienvenida:** las tres escenas, con textos cortos.
5. **Páginas de IA** (bandeja, revisión, ajustes de IA, avisos, extractos y análisis):
   - La revisión muestra la miniatura del recibo y el comercio, en vez del nombre de archivo con uuid.
   - Los montos van con formato.
   - Las pantallas vacías y de carga llevan a Chanchi.
6. **Formularios y hojas:** campos, botones y selectores con los tokens nuevos.
7. **Textos de upstream en español:** corregir las tildes que faltan, como «Donde», «Cuanto», «identica», «estadisticas», «Estas», «Que» y «cafe»
   (`lib/i18n/json/es.json`).

## Restricciones
- **Peso:** el APK arm64 no pasa de 40 MB (hoy pesa 39,4). Nada de Lottie, Rive ni fuentes nuevas. Si falta espacio, se quitan las fuentes Exo que no se usen.
- **Contraste:** al menos 4,5:1 en todo texto, con prueba automática de los tokens.
- **Upstream:** los cambios a los archivos de upstream se limitan al tema y a pocas pantallas, y cada uno se anota en el anexo de `docs/tasks/T002_apk-finanzas-ia.md`.
