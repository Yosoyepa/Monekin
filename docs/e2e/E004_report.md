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
Pendiente.

## Prueba 4 — Argon2id en Android (profile)
Pendiente.

## Prueba 5 — Ronda 6 sobre la versión final
Pendiente.

## BUG-NN nuevos
Ninguno hasta ahora.

## Lo no probado
Pendiente.

