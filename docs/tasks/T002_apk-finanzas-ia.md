# T002 — APK de finanzas con IA sobre Monekin (local, sin servidor)

Fecha: 2026-11-04 · Arquitecto: Opus 5.5 · Base: fork de [Monekin](https://github.com/enrique-lozano/Monekin) 10.2.2 (Flutter 3.44.1, SQLite con drift, AGPL-3.0)

## 0. Decisión

T001 (ezBookkeeping + MCP) funciona, pero exige un servidor y un PC. Este producto es un **APK que cualquiera instala**: todo vive en el
celular (SQLite local), la IA se llama directamente desde el teléfono con **la API key del usuario** y la copia de seguridad va a **su Google Drive**.
Monekin ya trae cuentas, categorías de dos niveles, presupuestos, metas, gráficas, español, CSV de entrada y salida y copias locales.
Le añadimos lo que hizo valioso a T001: recibos con la cámara, extractos, insights y recategorización con IA, más el registro automático desde
las notificaciones del banco.

Lecciones de T001 que se mantienen: nada se escribe sin una tabla de revisión (equivalente al `dry_run`), deduplicación antes de crear,
etiqueta `ia` y origen en cada transacción creada por IA, formatos colombianos (`1.234.567`, `45.900`, `12,34`, `dd/mm/aaaa`), y la regla de
upstream de no crear movimientos anteriores al saldo inicial (avisar antes de fallar).

## 1. Ítems críticos

| # | Ítem | Por qué no puede salir mal |
|---|---|---|
| C1 | **Ligero y local** | Si necesita servidor o pesa mucho, no lo usa una persona normal |
| C2 | **IA con la key del usuario, varios proveedores** | Gemini gratis (AI Studio) por defecto; DeepSeek y cualquier API compatible con OpenAI como alternativa. La key no puede filtrarse |
| C3 | **Nada se registra sin confirmar ni se duplica** | Un modelo puede inventar montos o repetir un extracto |
| C4 | **Recibo con la cámara en 2 toques** | Si cuesta más, no se usa |
| C5 | **Avisos del banco → gasto pendiente** | Es el registro sin esfuerzo; tiene que acertar con Bancolombia, Nequi y Davivienda |
| C6 | **Google: inicio de sesión y copia en Drive** | Sin servidor, Drive es la única forma de no perder datos al cambiar de celular |
| C7 | **CSV + plantilla en el PC** | El usuario quiere ver sus datos bonitos en el computador |
| C8 | **Fork mantenible** | Upstream publica a menudo; los cambios deben vivir en carpetas nuevas |

## 2. Definición de hecho

**C1 — Ligero y local**
- [ ] `flutter build apk --release --split-per-abi`: el APK `arm64-v8a` pesa **≤ 40 MB** (medido y anotado).
- [ ] Sin conexión funciona todo salvo IA y copia en Drive (prueba en emulador en modo avión).
- [ ] `applicationId` propio (`com.yosoyepa.finanzas`) para instalarse junto a Monekin; nombre visible «Finanzas IA»; créditos a Monekin en «Acerca de».

**C2 — IA multiproveedor**
- [ ] Capa única compatible con OpenAI (`/chat/completions`, imágenes en `image_url` base64). Proveedores precargados: Gemini (AI Studio), DeepSeek,
      OpenRouter y «Personalizado» (URL + modelo). La lista de modelos se pide al proveedor (`/models`), no se fija en el código.
- [ ] La key se guarda con `flutter_secure_storage` (Keystore). Prueba: no aparece en la base, el backup, el CSV ni los logs (`grep` sobre los tres archivos).
- [ ] Botón «Probar conexión» con mensaje claro si la key falla o se acaba la cuota.
- [ ] Pruebas con un servidor falso compatible con OpenAI (sin keys reales en el repo ni en las pruebas).

**C3 — Integridad**
- [ ] Todo lo que propone la IA o un aviso del banco entra a una **bandeja** (tabla nueva) y solo crea transacciones al confirmar en la pantalla de revisión.
- [ ] Deduplicación (misma cuenta, ±1 día, mismo monto, título normalizado; reglas de comentario vacío de T001): reimportar el mismo extracto crea **0**.
- [ ] Cada transacción creada así lleva la etiqueta `ia` y en las notas `[origen: recibo|extracto|aviso:<app>]`.
- [ ] Parser de montos colombianos portado de `pkg/aiimport/amount.go` con sus casos de prueba (~39).

**C4 — Recibos**
- [ ] Botón «Recibo» en el inicio → cámara → propuesta (fecha, comercio, total, categoría del catálogo, cuenta) → confirmar: **2 toques + disparo**.
- [ ] La foto queda adjunta a la transacción (tabla nueva de adjuntos) y se ve en su detalle.
- [ ] Mapa opcional «últimos 4 dígitos → cuenta» en ajustes, usado en recibos y avisos.

**C5 — Avisos del banco y recordatorios**
- [ ] `NotificationListenerService` con permiso explícito y lista de apps elegibles. Plantillas locales (regex) para Bancolombia, Nequi y Davivienda con pruebas
      de ejemplos reales; si ninguna encaja y hay key, la IA interpreta el texto. Sin key, queda pendiente para revisión manual.
- [ ] Recordatorio diario configurable, aviso al pasar el 80 % y el 100 % de un presupuesto, y resumen semanal con recomendaciones si hay key.
- [ ] Prueba en emulador con `adb shell cmd notification post` → aparece en la bandeja.

**C6 — Google**
- [ ] Inicio de sesión con Google (`google_sign_in`) y copia/restauración de la base en la carpeta oculta de la app en Drive (`drive.appdata`), manual y automática diaria.
- [ ] Funciona sin iniciar sesión (Google es opcional).
- [ ] README con los pasos para crear el cliente OAuth de Android (paquete + SHA-1): lo hace el responsable, no se puede automatizar.

**C7 — CSV y plantilla**
- [ ] El CSV de exportación de Monekin, con columnas estables documentadas.
- [ ] `tools/plantilla/Finanzas.xlsx`: hoja «Datos» que recibe el CSV y hoja «Resumen» con totales por mes y categoría y gráficas. Prueba: totales de la plantilla = totales de la app.

**C8 — Mantenible**
- [ ] Código nuevo en `lib/features_ia/**` (y su prueba en `test/features_ia/**`). Archivos de upstream tocados: solo registro (rutas, menú, ajustes, esquema, manifiesto,
      `pubspec`, i18n) y listados en un anexo.
- [ ] `flutter analyze` sin errores nuevos y `flutter test` en verde.
- [ ] `git merge upstream/main` de prueba al cierre, con los conflictos anotados.

## 3. Delegación

| Fase | Qué | Quién | Modelo | Rutas |
|---|---|---|---|---|
| A | Cimientos: id y nombre de la app, tablas `ai_inbox` y `attachments`, capa de IA y ajustes, parser de montos y deduplicación, bandeja y pantalla de revisión, dependencias y permisos de todas las fases | `w-base` | Haiku 5.5 max | `lib/features_ia/core/**`, `lib/features_ia/inbox/**`, esquema, `pubspec`, manifiesto |
| B | Recibos con cámara y adjuntos | `w-recibos` | Haiku 5.5 max | `lib/features_ia/receipts/**` |
| B | Extractos CSV/PDF y conciliación | `w-extractos` | Haiku 5.5 max | `lib/features_ia/statements/**` |
| B | Avisos del banco, recordatorios, alertas y resumen semanal | `w-avisos` | Haiku 5.5 max | `lib/features_ia/notifications/**` |
| B | Insights, recategorización y Google Drive | `w-insights` | Haiku 5.5 max | `lib/features_ia/insights/**`, `lib/features_ia/google/**` |
| C | Plantilla `.xlsx`, APK release y E2E en emulador con IA falsa | `w-e2e` | Haiku 5.5 max | `tools/**`, `docs/e2e/**` |
| C | Revisión independiente | Codex `gpt-6.1-terra` xhigh (Orca visible) | — | solo lectura |
| C | Prueba ciega con el README | `w-blind` | Haiku 5.5 max | solo lectura |

Si Haiku no cierra una fase, se reintenta con Sonnet 5.5 high. Todo el entorno vive en D: `D:\Dev` (SDK, Flutter 3.44.1, Gradle, pub) y `D:\Proyectos\Monekin`.

Pendiente del responsable: su API key de Gemini (en la app, no en el repo), el cliente OAuth de Google y la prueba final en su celular.

## Cierre
_(se rellena al terminar: por ítem, cumplido / no cumplido / aceptado por alcance, con la evidencia)_
