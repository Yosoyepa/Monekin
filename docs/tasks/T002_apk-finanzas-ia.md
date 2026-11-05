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
Fecha: 2026-11-04. Rama `feat/finanzas-ia`, publicada en `Yosoyepa/Monekin` (último commit de código `20302359`). Versión `10.2.2+1002005`, APK release
firmado con la clave del responsable (SHA-1 `f05501fc…`, la registrada en Google). Las sumas SHA-256 de los APK están en `docs/release/SHA256SUMS`.

### Por ítem
| Ítem | Estado | Evidencia |
|---|---|---|
| **C1** Ligero y local | **Cumplido** | **Peso:** APK arm64 de 39,41 MiB (41.325.701 B) con `tools/build_release.ps1`, gracias a `--split-debug-info`. **Sin conexión:** E002 y E003, flujo 8 (modo avión: gasto manual, y la IA falla con un mensaje claro). **Identidad:** `aapt2 dump badging` da el paquete `com.yosoyepa.finanzas` y la etiqueta «Finanzas IA»; «Monekin» solo queda en créditos, licencia y URLs (`f6-pulido`). |
| **C2** IA multiproveedor | **Cumplido** | **Proveedores:** Gemini (AI Studio), DeepSeek, OpenRouter y Custom, con `/models` y «Probar conexión» (E003, flujo 2). **La key:** vive en el almacenamiento seguro, atada al origen (proveedor, esquema, host y puerto); solo https en release y sin redirecciones (`fs-ia`, `fs2-ia`). **Pruebas:** con un cliente o servidor falso; las de IA real son opcionales (`RUN_REAL_AI_TESTS`). |
| **C3** Integridad | **Cumplido** | **Bandeja:** nada se escribe sin confirmar. **Duplicados:** reimportar Nequi crea 0 (E003, flujo 4), y un aviso da un solo ítem gracias a la reclamación atómica en SQLite (BUG-09). **Origen:** la etiqueta `ia` y la nota de origen van en cada transacción (E003, flujo 3). **Montos:** el parser tiene sus pruebas. |
| **C4** Recibos | **Cumplido** | **Flujo:** botón central «Escanear recibo» → cámara → propuesta → confirmar. Son 2 toques más el disparo; la primera vez, uno más por el consentimiento. **Foto:** queda adjunta como PNG reconstruido, sin metadatos (`f5-fotos`). **Tarjetas:** el mapa es local (9911 → Bancolombia). Evidencia: E003, flujos 3 y 3b. |
| **C5** Avisos y recordatorios | **Cumplido, con un cambio de alcance aceptado** | **Lectura:** escucha con permiso explícito y lista de apps vigiladas. La extracción es local, con patrones colombianos; se probó con avisos sintéticos, y con avisos reales solo en la prueba del responsable con la versión anterior. **IA:** para los avisos que no se entienden, es manual y opcional («Leer con IA», con vista previa). Es una decisión del responsable, que pidió ver antes de enviar. **Recordatorios:** diario, alertas al 80 y al 100 % y resumen semanal, ahora calculado en el teléfono. Evidencia: E003, flujos 5a, 5b y 12. |
| **C6** Google | **Cumplido en el emulador. En el celular, cumplido con la versión anterior; con la final, pendiente** | **Drive:** inicio de sesión, copia y restauración en `appDataFolder`, manual y automática. Las copias van **cifradas** (v3: Argon2id, AES-256-GCM por bloques y una clave por copia), se hacen desde una instantánea `VACUUM INTO` y la restauración siempre vuelve atrás (`f3-cifrado`, `f4-datos`, `f5-restaurar`). **Sin Google** la app funciona igual. **Pasos de OAuth:** `docs/google-oauth.md`. **Android (E004, emulador API 36):** la actualización de v15 a v16 con datos conserva cuentas, transacciones, adjuntos, bandeja y categorías. Una restauración cortada con `force-stop` en `swap`, `commit` o `bringPhotos` siempre vuelve con los datos. Con la restauración en curso, la tarea de fondo se salta y no abre la base (ronda 7, `f7-fondo`). La restauración espera a que terminen las tareas de fondo de este proceso antes de tocar la base, y una tarea en curso la retiene (ronda 8, `f8-exclusion`, E004 3c). **El APK final exacto (E005):** `FinanzasIA-arm64.apk` (SHA-256 `e089492c…`), ejecutado en Android 16 con traducción ARM, actualiza sobre el release que tiene el celular (1004002 → 1004005) y conserva la cuenta y los gastos, sin errores. Exporta la copia local cifrada (cabecera `FIA3`, sin texto SQLite) y la restaura en el mismo dispositivo y en una instalación limpia con la contraseña (3,3 s). Tras «Cerrar la app» se reabre desde el ícono con los datos restaurados, sin forzar la detención. **Celular:** el responsable probó el inicio de sesión y Drive en su Motorola con la versión anterior, sin cifrado. **Pendiente:** la copia cifrada y su restauración en su celular con la versión final. |
| **C7** CSV y plantilla | **Cumplido** | **Plantilla:** E003, flujo 7, «Resultado: OK (75 comprobaciones, 0 con diferencia)». **CSV:** neutraliza fórmulas y va y vuelve exacto con los archivos propios. |
| **C8** Mantenible | **Parcial, aceptado por alcance** | **Código nuevo:** está en `lib/features_ia/**` y `lib/brand/**`. **Upstream:** el rebranding y las correcciones de seguridad que pidió el responsable tocaron más archivos de upstream que «solo registro»: 55 modificados, 40 agregados y 15 borrados (íconos viejos), listados en el anexo. **Calidad:** `flutter analyze` da 0 errores (170 infos heredados) y `flutter test` da 1190 en verde (9 de IA real saltadas). **Fusión con upstream:** `upstream/main` no tiene commits nuevos desde la base 10.2.2 (`35217411`), así que a la fecha no hay conflictos. |

### Lo que se añadió durante T002, a pedido del responsable
- **Seguridad:**
  - Auditoría `security-audit` de Cloudflare: 12 hallazgos, 6 bajos confirmados y 6 por validar.
  - Ocho rondas de corrección: `fs-*`, `fs2-*`, `f3-*`, `f4-*`, `f5-*`, `f6-pulido`, `f7-fondo` y `f8-exclusion`.
  - Siete verificaciones independientes:
    - `fv` a `fv3` con Codex `gpt-6.1-terra` xhigh;
    - `fv4` con Claude Sonnet 5.5 high, porque Codex llegó a su límite de uso. Su veredicto: no había bloqueantes para entregar a dos personas por ADB;
    - `fv5` con Codex `gpt-6.1-terra` xhigh, sobre la ronda 7. Encontró dos bloqueantes en la exclusión entre la restauración y la tarea de fondo: la ventana entre la
      comprobación y la apertura, y una tarea que ya tenía la base abierta. Reprodujo con SQLite un journal de la base vieja aplicado sobre la restaurada. Los corrige
      la ronda 8 (`f8-exclusion`);
    - `fv6` con Codex `gpt-6.1-terra` xhigh, sobre la primera versión de la ronda 8. Confirmó cerrados los dos de fv5, pero halló otro bloqueante: la frescura por
      `mtime` podía dar por huérfana la bandera de una tarea viva. El arquitecto decidió que la vida de las marcas la decida el proceso (`pid:starttime`) y no el
      reloj, y lo aplicó la misma ronda (`ae39ca05`);
    - `fv7` con Codex `gpt-6.1-terra` xhigh: comprobación corta de esa regla. Confirmó cerrado el caso de la marca envejecida o adelantada, también con una
      transacción SQLite abierta. Halló un caso más: una marca que existe pero no se puede leer contaba como ausente. Lo reprodujo en Windows bloqueando la lectura. El
      arquitecto lo corrigió en `20302359`: una marca presente e ilegible cuenta como viva, y `isHeld` ya no borra un aviso ajeno mientras una restauración puede estar
      escribiendo el suyo. Se probó con 116 pruebas de candado, restauración y fondo.
- **Rebranding «Durazno cálido»:** la mascota Chanchi, el ícono, la pantalla de arranque y todas las pantallas (`docs/brand/MARCA.md`).
- **Consentimiento por función de IA:** con vista previa exacta del extracto y de los avisos.
- **Verificación en Android (E004)** de la versión final en el emulador:
  - la actualización con datos;
  - el APK release;
  - la restauración interrumpida;
  - Argon2id;
  - los flujos de la ronda 6.
- **Verificación del APK final exacto (E005, `fi-e2e4`):** el `FinanzasIA-arm64.apk` publicado, en Android 16 con traducción ARM.
  - Actualiza desde el release del celular con datos.
  - Exporta la copia local cifrada y la restaura, en el mismo dispositivo y en una instalación limpia con la contraseña.
  - Se reabre sin forzar la detención.
- **Ronda 7 (`f7-fondo` y el arquitecto):** con una restauración en curso, la tarea de fondo no abre ni crea la base. Todas las conexiones esperan hasta 5 s a otra que
  esté escribiendo (`busy_timeout`), en vez de fallar con «database is locked».
- **Ronda 8 (`f8-exclusion`):** la restauración y las tareas de fondo se excluyen.
  - Cada ejecución de fondo deja una bandera con la identidad de su proceso antes de mirar nada, y la baja solo después de cerrar su conexión.
  - La restauración escribe su aviso antes de contar las banderas, y espera a que no quede ninguna de este proceso antes de tocar la base.
  - El motor de fondo nunca recupera ni crea la base.
  - Pruebas con isolates y SQLite reales: una tarea a punto de abrir, una con una escritura a medias y una bandera envejecida o adelantada. En el emulador: E004 3b,
    3c y flujo 13.
- **Instalación por cable:** en Windows y en Fedora (`tools/instalar_celular.sh`, que verifica el SHA-256 de `docs/release/SHA256SUMS`, y `docs/INSTALAR_FEDORA.md`).
- **Limpieza del disco C:** 31,3 GB liberados, aprobado por el responsable.

### Riesgos aceptados por alcance
- **La IA recibe lo que el usuario aprueba:** fotos, texto de extractos enmascarado y frases de avisos. El enmascarado es heurístico.
- **Transferencia a iOS (Android 16 QPR2):** no se puede excluir porque no existe app de iOS.
- **Android 13 o anterior:** otra app puede forzar una relectura de los avisos activos. No inyecta datos.
- **Bandeja:** la edad se cuenta desde `createdAt`.
- **CSV externo:** pierde el apóstrofo inicial si va seguido de `=`, `+`, `-` o `@`.
- **Aviso perdido:** si el proceso muere entre reclamar el aviso y crear el ítem, se pierde. Es una ventana de milisegundos.
- **Imágenes:** la esteganografía dentro de los píxeles sobrevive, y decodificar imágenes grandes consume memoria.
- **Contraseña de copias:** su fuerza depende del usuario (12 caracteres o 4 palabras). La clave derivada queda en el almacenamiento seguro del teléfono.
- **Tarea de fondo colgada:** si una tarea muere a mitad o su cierre falla, su bandera retiene las restauraciones hasta que termine el proceso. La app lo avisa: «Si
  vuelve a pasar, fuerza la detención de la app en Ajustes y ábrela de nuevo». Es la opción segura: no mueve la base bajo una conexión que podría seguir abierta.
  Pasa lo mismo con una marca que no se puede leer, con un aviso que no se pudo borrar al terminar o con un `pid` reutilizado sin `starttime` (fv7). En esos casos
  se retrasan tareas o restauraciones hasta que termina el proceso, pero nunca se toca la base.
- **Exclusión con una tarea real de WorkManager durante toda una restauración:** en el emulador, la 3c simula la tarea con una bandera del proceso. La carrera real
  se probó con isolates y SQLite reales en el PC.
- **Verificado en el emulador, no en un celular ARM:** E005 ejecutó el APK arm64 exacto con la traducción ARM del emulador, que no mide tiempos reales. El emulador
  (qemu) se cayó seis veces al dibujar, sin errores de la app y sin perder datos. Quedan sin medir en un celular real:
  - el candado contra la tarea de fondo;
  - el tiempo de Argon2id: de 190 a 965 ms en profile en el emulador; en un celular de gama media será algo más.

### Desviaciones dichas tal cual
- `fi-insights` se fusionó a medias al principio, tras una PREGUNTA, y el resto entró después.
- `fs-ia` hizo 17 llamadas reales a Gemini, por encima del tope de 5 de su encargo pero dentro de las 20 de las reglas comunes.
- Varias pruebas eran frágiles en Windows con la máquina cargada: el tiempo de las regex y el borrado de temporales. Se ajustaron (500 ms y reintento) y no eran
  fallos de la app.
- La prueba ciega la hizo el responsable en su celular, no un Haiku. La fricción que encontró fue la instalación, y se resolvió con ADB y la ayuda dentro de la app.
- **BUG-11 de E004 partió de una evidencia que no era válida.** La tarea que abrió la base fue la periódica `budgetCheck`, y corrió antes de que la restauración tomara
  el candado. La ronda 7 lo comprobó con las horas del dispositivo y endureció la tarea de fondo de todos modos.
- **`notice_claims_test` falló una vez con la suite completa bajo carga.** Dos conexiones escribían a la vez sin `busy_timeout`, y una recibió «database is locked».
  En la app, ese aviso esperaba al siguiente escaneo. Se corrigió en la conexión de la app (`configureConnection`).
- **La ronda 8 necesitó un segundo ajuste:** su primera versión decidía por la hora del último latido, y fv6 mostró que eso no garantiza la exclusión. El AVD se llama
  `Medium_Phone_API_36.0`, no `Medium_Phone` como decía el encargo.

### Pendiente del responsable
1. Antes de actualizar, exportar una copia local desde la app que ya tiene instalada.
2. Instalar la versión final desde Fedora con `git pull` y `./tools/instalar_celular.sh`. El script comprueba el APK contra `docs/release/SHA256SUMS`, así que los
   APK de compilaciones anteriores no pasan. Al terminar, desactivar la depuración USB y revocar las autorizaciones.
3. Pegar de nuevo la key de Gemini, porque ahora queda atada a su origen. Revocar en AI Studio la key de prueba, que ya se borró del PC.
4. Crear la contraseña de copias y tocar «Borrar copias sin cifrar» en Drive.
5. Añadir a la segunda persona como usuario de prueba del cliente OAuth en Google Cloud (modo Testing).
6. Probar en el celular la copia cifrada en Drive, su restauración y los avisos reales de sus bancos.

### Anexo: archivos de upstream tocados (respecto de `35217411`, sin `lib/features_ia`, `lib/brand`, `assets/brand`, `tools`, `docs` ni pruebas nuevas)
Modificados: `README.md`, `android/app/build.gradle`, `android/app/src/main/AndroidManifest.xml`, `res/drawable*/launch_background.xml`,
`res/mipmap-anydpi-v26/ic_launcher.xml`, `res/values/colors.xml`, `lib/app/home/dashboard.page.dart`, `lib/app/home/widgets/dashboard_account_list.dart`,
`lib/app/layout/{page_switcher,window_bar}.dart`, `lib/app/layout/indexed_stacks/fade_indexed_stack.dart`,
`lib/app/layout/widgets/{app_bottom_bar,app_navigation_drawer,app_navigation_sidebar}.dart`, `lib/app/onboarding/{intro.page,onboarding}.dart`,
`lib/app/securities/widgets/security_avatar.dart`, `lib/app/settings/{about.page,help_us_page,more_actions.page,settings_page}.dart`,
`lib/app/settings/pages/appareance_settings.page.dart`, `lib/app/settings/pages/backup/{backup_settings.page,export_page,import_csv.page}.dart`,
`lib/app/stats/widgets/movements_distribution/pie_chart_by_categories.dart`, `lib/app/transactions/details/transaction_details.page.dart`,
`lib/core/database/{app_db,app_db.g}.dart`, `lib/core/database/backup/backup_database_service.dart`, `lib/core/database/sql/initial/{seed.dart,tables.drift}`,
`lib/core/presentation/theme.dart`, `lib/core/presentation/widgets/html_text.dart`, `lib/core/routes/destinations.dart`,
`lib/core/services/market_data/{market_data_provider,market_data_service,yahoo_finance_provider}.dart`, `lib/i18n/json/*.json` (10 idiomas), `lib/main.dart`,
`pubspec.yaml`, `pubspec.lock` y `windows/flutter/generated_*` (plugins nuevos).
Agregados en carpetas de upstream: los widgets nuevos del inicio y de la barra (`lib/app/home/widgets/*`, `lib/app/layout/widgets/{inbox_pending,scan_receipt_button}.dart`),
`lib/core/database/backup/*` (instantánea, journal, candado y copias previas), `assets/sql/migrations/v15.sql` y `v16.sql`, las reglas `res/xml/*` y `res/values*-v31` y sus pruebas.
Borrados: los 15 PNG del ícono viejo de Monekin (`res/mipmap-*/ic_launcher_{background,foreground,monochrome}.png`).
