# E004 — Verificación en Android (emulador) de la versión final antes de actualizar el celular

Fecha: 2026-11-04. Emulador `Medium_Phone_API_36.0` (Android 16, x86_64, sin ventana), paquete `com.yosoyepa.finanzas`.
Versión final: `feat/finanzas-ia` en `d895fe75` (schema v16). Versión instalada en el celular: APK de `38ca6cca` (schema v15).
Sin IA real (la key de Gemini de prueba ya no existe): la key que se usa es ficticia.

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
Pendiente.

## BUG-NN nuevos

| Id | Gravedad | Resumen | Evidencia / archivo probable |
|---|---|---|---|
| BUG-11 | Media (por confirmar) | La tarea de fondo de WorkManager abre la base mientras una restauración retiene `restore.lock`: `executeBackgroundTask` debería saltarla con «skipped: a restore is running» y devolver `false`, pero la tarea arrancó, abrió la base (`DB found!`, `DB Opened!`) y terminó en `SUCCESS` | Prueba 3b; `docs/e2e/E004_t3/lock.job-e2e-bg-locked.logcat.txt`, `lock.markers.txt`, `lock-nobg.markers.txt`. Código: `lib/features_ia/core/background/background_tasks.dart` `executeBackgroundTask`, `lib/core/database/backup/restore_lock.dart` `isHeld`. `isHeld` desde un `Isolate.run` del mismo proceso sí devuelve `true`; falta averiguar por qué no en el motor de WorkManager. No se corrigió |

## Lo no probado
Pendiente.

