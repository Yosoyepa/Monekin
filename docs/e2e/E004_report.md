# E004 — Verificación en Android (emulador) de la versión final antes de actualizar el celular

Fecha: 2026-11-04. Emulador `Medium_Phone_API_36.0` (Android 16, x86_64, sin ventana), paquete `com.yosoyepa.finanzas`.
Versión final: `feat/finanzas-ia` en `d895fe75` (schema v16). Versión instalada en el celular: APK de `38ca6cca` (schema v15).
Sin IA real (la key de Gemini de prueba ya no existe): la key que se usa es ficticia.

## Resumen contra «Hecho cuando»

| Casilla | Estado |
|---|---|
| Prueba 1: conteos iguales, `user_version` 16, la app abre | **Cumplida** (3/12/1/1 antes y después; 15 → 16) |
| Prueba 2: el release abre sin crash y no es depurable | **Cumplida** |
| Prueba 3: tras `force-stop` a mitad la app abre con datos, y la tarea de fondo no interfiere | **Mitad cumplida**: `force-stop` en 3 puntos recupera la base anterior; la tarea de fondo sí abrió la base con el candado retenido (BUG-11) |
| Prueba 4: ms de Argon2id en profile | **Cumplida** (máx. 965 ms en el emulador; no vale para un teléfono ARM) |
| Prueba 5: flujos 5b, 12, 13 y 14 en la versión final | **Mitad cumplida**: 5b, 12 (IA falsa) y 14 pasan; 13 restaura bien pero deja 1 error de pintura bajo la pantalla de reinicio (BUG-12); «Ayúdanos» sin tarjeta de calificar, pero «Monekin» sigue en 2 textos (BUG-13) |
| `docs/e2e/E004_report.md` commiteado y `git status --porcelain` vacío | **Cumplida** con el commit que cierra la sesión (el informe de `orca_prompts` lleva además `<!-- DONE -->`) |

BUG nuevos: BUG-11, BUG-12, BUG-13 (ninguno corregido; no se tocó `lib/**`).
## Prueba 1 — Actualización con datos, de v15 a la final

| Paso | Resultado | Evidencia |
|---|---|---|
| Debug x86_64 de `38ca6cca` (worktree temporal `D:\Dev\e2e-build\v15`) instalado y sembrado | Hecho | `docs/e2e/seed_v15_test.dart.txt` (prueba de integración que se corrió en ese worktree; no se añade a `integration_test/` porque solo compila contra v15) |
| Datos creados con la versión vieja | 3 cuentas, 12 transacciones, 1 foto de recibo adjunta (JPEG), 1 ítem en la bandeja, ajustes de IA Gemini con key ficticia | salida del sembrado: `SEED user_version=15`, `accounts=3`, `transactions=12`, `attachments=1`, `inbox=1` |
| Conteos antes (base extraída con `run-as`, leída con `sqlite3` en el host) | `user_version 15`; accounts 3; transactions 12; transactionAttachments 1; aiInboxItems 1; categories 44; sin tabla `ai_notice_claims`; `accentColor = auto`; `dbVersion = 15` | `D:\Dev\e2e-build\evidence\before.*` |
| `adb install -r` del debug de la final encima (misma clave debug) y abrir | **Pasa**: abre sin errores | logcat del proceso: `DB found! Version 16 (previous was 15)`, `Executing migrations from previous version [15]...`, `Pre-migration backup created at .../database.pre_migration_v15.db`, `Migrating database to v16...`, `Migration completed!`, `DB Opened!`. Sin `FATAL`, buffer `crash` vacío |
| `PRAGMA user_version` y `ai_notice_claims` | **Pasa**: 16; la tabla existe (0 filas); `dbVersion = 16` | `D:\Dev\e2e-build\evidence\after.*` |
| Mismos conteos | **Pasa**: accounts 3, transactions 12, transactionAttachments 1, aiInboxItems 1, categories 44; la ruta del adjunto no cambió | idem |
| La foto abre | **Pasa**: el archivo sigue siendo un JPEG (`ff d8 ff e0`) y la miniatura se ve en «Adjuntos» de la transacción | `screens/E004_t1_tx_detail.png` |
| La key ficticia queda «por confirmar» | **Pasa**: en Ajustes → Inteligencia artificial: «Hay aquí una key de una versión anterior. Pégala una vez para confirmarla.»; el almacén guarda `ai_key_pending:gemini:https://generativelanguage.googleapis.com:443` y ya no `ai_api_key` | `screens/E004_t1_ai_settings.png` |
| La migración de marca puso el acento | **Pasa**: `accentColor` pasó de `auto` a `BC4626`; la pantalla de inicio usa el acento de marca | `screens/E004_t1_home.png` |

Además: la versión final deja `database.pre_migration_v15.db` con la copia previa a la migración.
Nota del entorno: el emulador se cayó una vez (qemu) tras la actualización; se reinició con los datos intactos y se repitieron las comprobaciones de la interfaz.

Commit probado: `d895fe75`.

## Prueba 2 — APK release en Android

| Comprobación | Resultado | Evidencia |
|---|---|---|
| Compilar el release x86_64 con la clave release | **Pasa** | `flutter build apk --release --target-platform android-x64 --split-debug-info=... --dart-define-from-file=D:\Dev\keys\release-defines.json` en `d895fe75` con `android/keys/key.properties` copiado del repo principal (ignorado por git, no commiteado). `app-release.apk` 43.187.389 bytes (41,2 MiB; SHA-256 `73386F46721AD5B584C419A6F42160E33E561D1F8B405EB00E8A2FD958847363`) |
| Firmado con la clave release | **Pasa** | `apksigner verify --print-certs`: `CN=Finanzas IA, O=Yosoyepa, C=CO`, SHA-256 `44b46fe1ff2aed97987d035531f682d7844211ac87d7b12b10bfbed5478a1d23`, igual que `docs/release/CERT_SHA256` |
| Emulador limpio: desinstalar la debug, instalar, abrir, esperar 35 s | **Pasa** | la app sigue viva tras 35 s (`pidof` = 4876) y después de otros 5 s |
| logcat sin crashes | **Pasa** | buffer `crash` vacío; 0 coincidencias de `FATAL EXCEPTION`, `AndroidRuntime`, `Unhandled` o `Exception` en el proceso; `screens/E004_t2_release_first_run.png` (pantalla de bienvenida) |
| No es `DEBUGGABLE` | **Pasa** | `dumpsys package` (recortado): `versionCode=1002003 versionName=10.2.2 minSdk=24 targetSdk=36`, `pkgFlags=[ HAS_CODE ALLOW_CLEAR_USER_DATA ]` (sin `DEBUGGABLE`) |
| `allowBackup` es false | **Pasa** | `pkgFlags` sin `ALLOW_BACKUP`; manifiesto del APK (`aapt2 dump xmltree`): `android:allowBackup(0x01010280)=false` |

Nota del entorno: un primer intento de compilar con `--no-pub` tras borrar el `GeneratedPluginRegistrant.java` obsoleto (ignorado por git, generado por mi `flutter pub get` con `integration_test`) produjo un APK sin el registrador y se cerró con «No JNI instance is available». No es un fallo de la app: la compilación normal (sin `--no-pub`, como `tools/build_release.ps1`) regenera el registrador sin dependencias de desarrollo y el APK arranca bien. El resultado anterior se descartó.

Commit probado: `d895fe75`.
## Prueba 3 — Restauración interrumpida y candado

Prueba: `integration_test/finanzas_ia/restore_interrupt_test.dart`, lanzada por `docs/e2e/run_restore_e2e.ps1` (build debug, emulador). La prueba crea una cuenta y 3 transacciones («Base 1..3»), exporta una copia local cifrada (`createBackupKey` + `exportEncryptedBackup`, 19.970 bytes), añade 2 transacciones más («Extra 1..2», la base viva queda con **5**) y restaura la copia con `BackupRestorer(onStage: …)`, el mismo restaurador que usa la app. En cada etapa imprime `E2E_MARKER restore-stage <etapa>`; en la etapa elegida espera 120 s y el script del host mata primero `flutter test` (si no, desinstala la app y se llevan los datos) y después hace `adb shell am force-stop com.yosoyepa.finanzas`.
Como el APK que instala `flutter test` tiene la prueba como punto de entrada, tras el `force-stop` el script instala encima el APK debug normal de la misma versión (`adb install -r`, misma clave, los datos se conservan) y abre la app. Evidencia en `docs/e2e/E004_t3/`.

### 3a. `force-stop` en mitad de la restauración

| Corte (marcador `hold <etapa>`) | Estado en disco al matar | Tras reabrir la app (30 s) | Resultado |
|---|---|---|---|
| `swap`: el diario ya existe y la base viva está apartada | `database.db.restore_marker`, `database.db.restore_bak`, `database.db.restore_tmp.*`, `database.pre_restore_backup.*.db`; **no hay `database.db`** | `database.db` de vuelta; sin marcador ni `.restore_bak`; `user_version 16`, **5 transacciones** («Base 1..3» y «Extra 1..2»), 1 cuenta; la pantalla de inicio muestra 425.000,00 $ y gasto 75.000 $ (`screens/E004_t3_after_kill_swap.png`); `DB found! Version 16 … DB Opened!`; 0 `FATAL`/`AndroidRuntime` en el proceso | **Pasa**: la base es la anterior, no vacía |
| `commit`: la base restaurada ya está en su sitio, el marcador sigue en fase `swap` | `database.db` (la restaurada, 3 transacciones), `database.db.restore_bak`, `database.db.restore_marker` | `database.db` es la anterior; marcador y `.restore_bak` borrados; **5 transacciones** | **Pasa**: la base es la anterior (la restauración sin confirmar se deshizo) |
| `bringPhotos`: tras `journal.begin`, antes de cerrar la conexión | `database.db` viva intacta, `database.db.restore_marker`, `database.db.restore_tmp.*` | `database.db` con **5 transacciones**; marcador borrado | **Pasa** |

Marcadores de cada corrida: `docs/e2e/E004_t3/kill-swap.markers.txt`, `kill-commit.markers.txt`, `kill-bringPhotos.markers.txt` (`… restore-stage swap` → `hold swap`, etc.). Listados `*.before-kill-*`, `*.after-kill-*` y `*.after-reopen.txt`; conteos en `*.after-reopen.counts.txt` (leídos con `sqlite3` del host sobre la base extraída con `run-as`).
Observación: tras recuperar, `database.db.restore_tmp.*` (temporal de la restauración) sigue en la carpeta; el diseño solo borra huérfanos de más de 10 minutos (`kOrphanTempAge`).

### 3b. Tarea de fondo (WorkManager) durante una restauración

La prueba retiene el candado de la restauración en la etapa `validate` durante 45 s, y en ese tiempo encola una tarea con `Workmanager().registerOneOffTask('e2e-bg-locked', kTaskNoticeScan)`; WorkManager la arranca al instante (el `initialDelay` de 30 min no se respeta) en su propio aislamiento. Cuando el script consultó `jobscheduler` ya no había un trabajo pendiente que forzar con `cmd jobscheduler run -f` (el volcado mostraba el trabajo `#u0aNNN/0` ya terminado: `app called jobFinished`), así que el mecanismo es la propia cola de WorkManager.

Resultado: **NO pasa** — la tarea de fondo abrió la base con el candado retenido.

- Marcadores (`docs/e2e/E004_t3/lock.markers.txt`): `lock-held` → `bg-scheduled e2e-bg-locked` → `isHeld from another isolate (lock held by the restore): true` → `lock-hold-ended` → … → `restore returned: done=true failure=null`.
- logcat del proceso de la app (`docs/e2e/E004_t3/lock.job-e2e-bg-locked.logcat.txt`), dentro de esos 45 s:
  ```
  00:45:38.364 WM-WorkerWrapper: Starting work for dev.fluttercommunity.workmanager.BackgroundWorker
  00:45:49.749 flutter : DB found! Version 16 (previous was 16). Path to DB -> /data/user/0/com.yosoyepa.finanzas/app_flutter/database.db
  00:45:50.403 flutter : DB Opened!
  00:45:51.030 WM-WorkerWrapper: Worker result SUCCESS for Work [ … BackgroundWorker ]
  ```
  No aparece `Background task finanzas.noticeScan skipped: a restore is running` (el mensaje de `executeBackgroundTask`) y el resultado es `SUCCESS`, no un reintento.
- Control sin tarea de fondo (`lock-nobg`, mismo candado retenido 45 s): una sola apertura de la base en todo el proceso (la del arranque). La segunda apertura de la corrida `lock` es, por tanto, de la tarea de fondo.
- `RestoreLock.isHeld` llamado desde otro aislamiento (`Isolate.run`) del mismo proceso con el candado retenido da `true`; el aislamiento del motor de WorkManager, en cambio, no lo respetó. No se averiguó la causa (no se toca `lib/**`).
- Lo que la tarea sí dejó intacto: los listados de la carpeta antes y después del trabajo (`lock.before-job-e2e-bg-locked.txt` y `lock.after-job-e2e-bg-locked.txt`) son idénticos (mismos archivos, tamaños y minutos; sin cambios en `restore.lock*`, `database.db` ni `database.db.restore_tmp.*`); la restauración que seguía terminó bien (`done=true`). No hay corrupción observada, pero la tarea llegó a abrir la base y a ejecutarse.

Tras la restauración (candado libre) se encoló otra tarea (`e2e-bg-free`); el registro del script no capturó su ejecución, así que no hay evidencia del caso «con el candado libre».

Commit probado: `d895fe75` + el arnés de esta prueba (`restore_interrupt_test.dart`, `run_restore_e2e.ps1`).

## Prueba 4 — Argon2id en Android (profile)

Medida: `createBackupKey('…')` (la derivación de la contraseña de las copias, en otro aislamiento) con los parámetros de producción `kDefaultKdfParams`: 19 MiB (`memoryKiB=19456`), 2 iteraciones, 1 hilo. Programa de medición: `integration_test/finanzas_ia/argon2_profile_main.dart`, compilado con `flutter build apk --profile --target-platform android-x64 -t integration_test/finanzas_ia/argon2_profile_main.dart` (AOT), instalado en el emulador y leído de logcat (`docs/e2e/E004_t4/argon2_profile_logcat.txt`).

| Ejecución | ms |
|---|---|
| 1 (incluye arrancar el aislamiento) | 965 |
| 2 | 278 |
| 3 | 306 |
| 4 | 432 |
| 5 | 238 |
| 6 | 190 |

Resultado: **máximo 965 ms**, por debajo del umbral de 3 s; en régimen estable 190 a 432 ms.

Alcance: se midió en el emulador `sdk_gphone64_x86_64` (CPU virtual x86_64 sobre el PC del anfitrión), no en un teléfono ARM. Un teléfono de gama media será más lento; esta cifra no demuestra que se cumpla el umbral de 3 s en el celular del responsable.

Commit probado: `d895fe75` + el programa de medición.

## Prueba 5 — Ronda 6 sobre la versión final

Pruebas de `integration_test/finanzas_ia/` lanzadas con `docs/e2e/run_e2e.ps1` sobre el build debug de `d895fe75` en el emulador, sin key de IA (defines vacíos): el cliente de IA es `FakeNoticeAiClient` (nuevo en `support/e2e_support.dart`), que contesta el JSON de «LIBRERIA NACIONAL 87.300»; `CountingAiClient` cuenta las llamadas. Marcadores y salidas: `docs/e2e/E004_t5/*.txt`; capturas de esta corrida en `docs/e2e/screens/E004_t5/`.
Cambios del arnés para esta prueba: `bank_notices_test.dart` espera 15 s y exige exactamente 2 ítems y 1 por aviso (antes `>= 2`); `notice_ai_test.dart` exige 1 ítem para el aviso desconocido; `encrypted_backup_test.dart` exige la pantalla «Copia restaurada» con el botón «Cerrar la app» y cuenta los errores de pintura antes y después de mostrarla.

| Flujo | Resultado | Evidencia |
|---|---|---|
| 5b: avisos del banco → bandeja → la notificación local abre la revisión (un aviso = un ítem) | **Pasa** | `before=0 after=2`; `items per notice after 15 s: {UBER: 1, EXITO: 1}, total new: 2`; `local notification opened the review: true` (`E004_t5/bank_notices_test.txt`) |
| 12: aviso que la app no entiende, con la IA de avisos encendida | **Pasa** (con IA falsa) | `items for the one unknown notice, before any tap: 1`; la frase muestra la tarjeta oculta (`*****`); rechazar el consentimiento: 0 llamadas; aceptar: `calls=1`, el ítem queda con propuesta y la fila se titula `LIBRERIA NACIONAL` (`E004_t5/notice_ai_test.txt`) |
| 13: copia cifrada, contraseña equivocada, contraseña buena | **Pasa la restauración; NO pasa «sin errores»** | contraseña equivocada: error y se conservan las 4 transacciones; contraseña buena: títulos restaurados `[E2E-BAK Arriendo, E2E-BAK Mercado, E2E-BAK Transporte]`; la pantalla de reinicio dice «Copia restaurada» con el botón «Cerrar la app»; pero **1 error de pintura después de mostrarla**: `Null check operator used on a null value @ UserProfileBuilder.build (user_profile_builder.dart:25:46)`; antes de mostrarla 0 errores (`E004_t5/encrypted_backup_test.txt`). BUG-12 |
| 14: migración de marca | **Pasa** | antes `accentColor=auto`; después `BC4626`, marcador creado, `theme primary=ffbc4626`; una elección posterior de «auto» se conserva; la pantalla de bienvenida (14b) también (`E004_t5/brand_test.txt`) |
| «Ayúdanos» y «Información de la app» (vistazo, app normal, idioma inglés del emulador) | **Parcial** | sin tarjeta de calificar la app en «Ayúdanos» (solo el agradecimiento, informar de errores y donar). «Monekin» sigue visible en 2 textos: «Your contributions to Monekin and other open source projects…» (Ayúdanos) y «All the developers who have made Monekin grow» (Información de la app, créditos). «Finanzas ia» y «v10.2.2 (1002003)» en la cabecera. Textos y capturas: `E004_t5/help_us.txt`, `E004_t5/app_info.txt`, `E004_t5/mas_menu.txt`, `screens/E004_t5/E004_t5_help_us.png`, `E004_t5_app_info.png`. Las mismas dos cadenas existen en las 10 lenguas (`thanks_long`, `contributors.descr`); el español es «Tus contribuciones a Monekin…» y «…que han hecho que Monekin crezca» |

Nota: «Reinicia la app» del encargo es, en la app, «Copia restaurada» con la descripción «La app debe cerrarse para terminar la restauración. Ábrela de nuevo para ver tus datos.» y el botón «Cerrar la app». No se pulsó el botón (cierra el proceso de la prueba).
Observación sin número: en inglés, la descripción de «Información de la app» dice «Find the terms of Finanzas IA,, important info…» (coma doble).

Commit probado: `d895fe75` + los cambios del arnés de esta prueba.
## BUG-NN nuevos

| Id | Gravedad | Resumen | Evidencia / archivo probable |
|---|---|---|---|
| BUG-11 | Media (por confirmar) | La tarea de fondo de WorkManager abre la base mientras una restauración retiene `restore.lock`: `executeBackgroundTask` debería saltarla con «skipped: a restore is running» y devolver `false`, pero la tarea arrancó, abrió la base (`DB found!`, `DB Opened!`) y terminó en `SUCCESS` | Prueba 3b; `docs/e2e/E004_t3/lock.job-e2e-bg-locked.logcat.txt`, `lock.markers.txt`, `lock-nobg.markers.txt`. Código: `lib/features_ia/core/background/background_tasks.dart` `executeBackgroundTask`, `lib/core/database/backup/restore_lock.dart` `isHeld`. `isHeld` desde un `Isolate.run` del mismo proceso sí devuelve `true`; falta averiguar por qué no en el motor de WorkManager. No se corrigió |
| BUG-12 | Baja | Tras restaurar, ya con la pantalla propia de reinicio mostrada, un `UserProfileBuilder` sigue vivo debajo y falla una vez con `Null check operator used on a null value` (el BUG-08 de E003 no queda cerrado del todo) | Prueba 5, flujo 13: `E004_t5/encrypted_backup_test.txt`, marcadores `BUG-08 errors under the restart page: 1 [... @ user_profile_builder.dart:25:46]` y `errors before the restart page: 0, after it: 1`. Código: `lib/core/presentation/widgets/user_profile_builder.dart:25`. No se corrigió |
| BUG-13 | Baja | «Monekin» sigue visible en los textos `thanks_long` (Ayúdanos) y `contributors.descr` (Información de la app) en las 10 lenguas, aunque el cambio `ab6c916f` declara que ningún texto visible lo dice; `contributors.descr` es un crédito, `thanks_long` no es claramente un crédito | Prueba 5; `lib/i18n/json/en.json:1531,1541`, `es.json:1520,1530`. No se corrigió |

## Lo no probado
- Teléfono real y CPU ARM: todo corrió en el emulador x86_64. Los tiempos de Argon2id y el arranque del release en un teléfono de gama media no están medidos; los APK `arm64-v8a` y `armeabi-v7a` que instalará el responsable no se probaron.
- La actualización real es release sobre release con la clave release; la prueba 1 usó debug sobre debug (misma clave debug) y datos sembrados por los servicios de la app, no datos reales. Un `adb install -r` de release sobre el release anterior no se ejecutó.
- Release: solo se comprobó que abre, que vive 30 s sin crash y que no es depurable. No se recorrieron sus pantallas.
- IA real: la key de Gemini ya no existe. El flujo 12 se probó con un cliente falso; no se repitieron recibos, extractos ni insights con IA, ni los consentimientos de esas funciones.
- Prueba 3b, caso con el candado libre: se encoló la tarea, pero el registro no capturó su ejecución. La causa de BUG-11 no se investigó.
- El botón «Cerrar la app» de la pantalla de reinicio no se pulsó (cierra el proceso de la prueba); no se probó reabrir la app tras una restauración completa hecha por la interfaz (sí tras los cortes de la prueba 3).
- La interfaz de restaurar desde los ajustes (selector de archivos nativo) no se manejó; las pruebas llaman a las mismas funciones que la página.
- Google Drive real, Davivienda/Daviplata/Nu/BBVA, tareas de fondo reales de recordatorios (solo la tarea `noticeScan` de la prueba 3b) y copia con cámara real: no probados.


## Ronda 7 — BUG-11, BUG-12 y BUG-13

Emulador `sdk_gphone64_x86_64` (Android 16), build debug del árbol de trabajo de la ronda 7. Evidencia en `docs/e2e/E004_r7/`.

### BUG-11: la tarea de fondo no toca la base durante una restauración

**Lo que se corrigió.**
- `executeBackgroundTask` calcula la ruta con `appDatabasePath()` (nueva función de `app_db.dart`, la misma que usan `AppDB.databasePath` y `openConnection`), sin tocar `AppDB`.
- Antes de abrir nada salta la ejecución (devuelve `false`, WorkManager reintenta) si hay marcador de restauración (`database.db.restore_marker`, `.restore_marker.new`), o una base apartada (`.restore_bak`) sin `database.db`, o el candado ocupado.
- `openConnection` lanza `RestoreBusyException` desde el isolate de fondo (bandera `isBackgroundIsolate`, que pone `backgroundDispatcher`) si encuentra uno de esos archivos: nunca recupera ni crea una base desde ahí.
- `RestoreLock` deja además `restore.lock.held`, un archivo que el titular refresca cada 5 s y que `isHeld` lee (cuenta si tiene menos de 30 s). Sirve para el tramo de la restauración anterior al marcador (hasta `validate`), donde sólo existe el candado.

**Sobre el diagnóstico de E004.** La evidencia de E004 para BUG-11 no era válida. En `E004_t3/lock.job-e2e-bg-locked.logcat.txt` el trabajo que abrió la base (`Starting work` → `DB found!` → `SUCCESS`) era la tarea periódica `finanzas.budgetCheck` que la app programa al arrancar, y corrió **antes** de que la restauración tomara el candado. La tarea `noticeScan` de la prueba nunca se ejecutó: el script del host no encontraba el trabajo (el formato de `dumpsys jobscheduler` de Android 16 es `JOB <tag>:u0a217/1`, no `JOB #u0a217/1`) y, forzado a mano, `cmd jobscheduler run -f` no la arrancó. Esta ronda lo comprobó con timestamps (ver abajo). Lo que sigue sin probar es si el candado sin el archivo `.held` bastaba entre motores de Flutter del mismo proceso: no se ejecutó ese caso sin el archivo. El `isHeld` desde un `Isolate.run` ya daba `true` en E004.

**Arnés.** `restore_interrupt_test.dart` encola `noticeScan` sin retraso (antes 30 min, a la espera de que el host la forzara) en el instante en que la restauración retiene el candado, y otra vez con el candado libre. `run_restore_e2e.ps1` reconoce el formato de jobs de Android 16 e imprime la hora del dispositivo en los marcadores del candado.

**Prueba 3b, candado retenido 45 s** (`E004_r7/lock.markers-timed.txt`, `E004_r7/lock.bg-trimmed.logcat.txt`):

```
[marker] lock-held                      [host] device time: 11-05 02:02:27
[marker] lock-hold-ended                [host] device time: 11-05 02:03:12
02:02:27.567 WM-WorkerWrapper: Starting work for dev.fluttercommunity.workmanager.BackgroundWorker
02:02:28.202 flutter : Background task finanzas.noticeScan checking for a restore
02:02:28.207 flutter : Background task finanzas.noticeScan skipped: a restore is running
02:02:28.213 WM-WorkerWrapper: Worker result RETRY
02:02:58.234 WM-WorkerWrapper: Starting work for dev.fluttercommunity.workmanager.BackgroundWorker
02:02:59.701 flutter : Background task finanzas.noticeScan checking for a restore
02:02:59.706 flutter : Background task finanzas.noticeScan skipped: a restore is running
02:02:59.715 WM-WorkerWrapper: Worker result RETRY
```

Entre las 02:02:27 y las 02:03:12 no hay `DB found!` ni `DB Opened!`. En `lock.before-job-e2e-bg-locked.txt` se ve `restore.lock.held` en la carpeta de la base.

**Mismo caso con el candado libre** (la restauración terminó a las 02:03:13):

```
02:03:13.030 WM-WorkerWrapper: Starting work for dev.fluttercommunity.workmanager.BackgroundWorker
02:03:13.641 flutter : Background task finanzas.noticeScan checking for a restore
02:03:13.875 flutter : DB found! Version 16 (previous was 16). ...
02:03:13.959 flutter : DB Opened!
02:03:14.006 WM-WorkerWrapper: Worker result SUCCESS
```

La restauración terminó con `done=true failure=null` y 3 transacciones (las de la copia).

**Pruebas unitarias** (`test/features_ia/core/background_tasks_test.dart`, `test/core/database/backup/open_connection_recovery_test.dart`, `restore_lock_test.dart`): con marcador, o con `.restore_bak` sin base, `executeBackgroundTask` no llama a `prepare` (0 aperturas) ni crea `database.db`; con `.restore_bak` junto a una base viva sí corre; `openConnection` desde el isolate de fondo lanza `RestoreBusyException` sin tocar el marcador ni crear base; el archivo `.held` fresco cuenta, el viejo no, y `isHeld` no deja rastro.

### BUG-12: `UserProfileBuilder` bajo la pantalla de reinicio

`UserProfileBuilder` usaba `snapshot.data!`. Al cerrarse la base el flujo falla y el `StreamBuilder` queda sin dato. Ahora usa `snapshot.data?` y pasa `null` al constructor, que ya acepta `String?`. Por qué sigue montado: `showRestartRequiredPage` hace `pushAndRemoveUntil` sobre el navegador raíz, y Flutter no desmonta las rutas retiradas hasta que termina la animación de la nueva; en ese lapso las pantallas viejas se reconstruyen con la base cerrada. No se comprobó la secuencia exacta de fotogramas, sólo el efecto.

Flujo 13 (`E004_r7/encrypted_backup_test.txt`):

```
E2E_MARKER wrong password: nothing changed, 4 transactions
E2E_MARKER BUG-08 errors under the restart page: 0 []
E2E_MARKER errors before the restart page: 0, after it: 0
E2E_MARKER restored titles: [E2E-BAK Arriendo, E2E-BAK Mercado, E2E-BAK Transporte]
00:54 +1: All tests passed!
```

Captura de la pantalla de reinicio: `E004_r7/flow13_restore_done.png`.

### BUG-13: textos

`thanks_long` (Ayúdanos) se reescribió en las 10 lenguas para decir que la app está basada en Monekin; `contributors.descr` queda como crédito. La coma doble de «Información de la app» en inglés se corrigió (`Finanzas IA, important info`). `git grep -nF ",," -- lib/i18n/json` sale vacío.

### No probado en esta ronda
- Qué hace el candado sin el archivo `.held` entre motores de Flutter (ver BUG-11).
- La tarea de fondo con la restauración en las etapas `swap`/`commit` en el emulador: sólo se cubre con pruebas unitarias (marcador y `.restore_bak`).
- Teléfono real y CPU ARM.
