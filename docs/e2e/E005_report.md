# E005 — APK final arm64 (release) en Android: actualización con datos y copia cifrada local

Fecha: 2026-11-04. Worker `fi-e2e4`, worktree `D:\Dev\orca-workspaces\Monekin\fi-e2e4` (rama `Yosoyepa/fi-e2e4`).

- APK probado: `D:\Dev\apk\FinanzasIA-arm64.apk`, versión `10.2.2+1002005`, SHA-256 `E089492CAF6ACA326DFC42C48601BAF1FE37251D98258481C5C657316A0251B4`. Coincide con `docs/release/SHA256SUMS`.
- Versión vieja (la del celular): release arm64 de `38ca6cca` (`10.2.2+1002002`, schema v15), compilada en un worktree temporal fuera del repo.
- Código de la versión final: `20302359`. `4d570ed3` solo cambia `docs/release/SHA256SUMS` y `docs/tasks/T002_apk-finanzas-ia.md` respecto a `20302359`.
- Emulador: `Medium_Phone_API_36.0` (Android 16, API 36, x86_64, headless, `-no-snapshot`), con traducción ARM.
- Paquete: `com.yosoyepa.finanzas`. Sin cuentas de Google ni IA real.

## Hecho cuando

- [x] Prueba 0 con su salida. Ver «Prueba 0».
- [ ] Prueba 1: la actualización conserva la cuenta y los dos gastos, sin crash, con la migración en el logcat. O queda un BUG-NN con evidencia.
- [ ] Prueba 2: la restauración vuelve a los datos de la copia. O queda «no se pudo» con la explicación.
- [ ] `docs/e2e/E005_report.md` commiteado y `git status --porcelain` vacío.

## Prueba 0 — Capacidad del emulador

**Resultado: cumplida.** Commit probado: `20302359`.

| Comprobación | Salida | Resultado |
|---|---|---|
| `adb shell getprop ro.product.cpu.abilist` | `x86_64,arm64-v8a` | Incluye `arm64-v8a` |
| `adb shell getprop ro.dalvik.vm.native.bridge` | `libndk_translation.so` | No es `0` |

Datos de contexto: `ro.product.cpu.abi=x86_64`, `ro.build.version.sdk=36`, `ro.build.version.release=16`. `/system/lib64/libndk_translation.so` presente (5.420.176 bytes). `/data` con 3.4G libres tras el arranque.

Arranque: `emulator -avd Medium_Phone_API_36.0 -no-window -no-audio -no-snapshot -no-boot-anim -gpu swangle_indirect -memory 3072`, con `ANDROID_AVD_HOME=D:\Dev\Android\user\avd`. `sys.boot_completed=1` a unos 30 s.

## Prueba 1 — Actualización release a release con datos

**Resultado: en curso.** Commit probado: `20302359` (versión final) y `38ca6cca` (versión vieja).

| Paso | Estado | Evidencia |
|---|---|---|
| Worktree temporal de `38ca6cca` fuera del repo (`D:\Dev\e2e-build\e005-v15`) con `android/keys/key.properties` copiado | Hecho | `git worktree add`; `git status` del worktree vacío; `key.properties` ignorado por `android/.gitignore:11` |
| `flutter pub get` y `dart run slang` en el worktree temporal | Hecho (exit 0) | log de compilación en el scratchpad |
| `flutter build apk --release --target-platform android-arm64 --dart-define-from-file=D:\Dev\keys\release-defines.json` (comando literal del brief) | Hecho (exit 0), **no instalado** | APK de 43.641.982 bytes, SHA-256 `9EE44CC6…`; `versionCode=1002002`; código nativo `arm64-v8a`, `armeabi-v7a` y `x86_64`; firma `44b46fe1…`. Guardado en `D:\Dev\e2e-build\e005\app-release-literal-1002002.apk` |
| `flutter build apk --release --split-per-abi --target-platform android-arm64 --dart-define-from-file=D:\Dev\keys\release-defines.json` (con `--split-per-abi`, como `tools/build_release.ps1:39`) | En curso | Versión vieja instalada, si sale `versionCode=1004002` y solo `arm64-v8a` |

Desviación: el comando literal del brief no reproduce el APK del celular. Sin `--split-per-abi` sale `versionCode 1002002`, mientras el brief dice que el celular tiene `1004002`. Gradle no suma ningún offset (`android/app/build.gradle:36` usa `flutter.versionCode`); el offset +2000 de arm64 lo aplica el split por ABI, igual que en el APK final (base `1002005` → `1004005`). Por eso la versión vieja se compila con `--split-per-abi`. Ver «PREGUNTA» 2.
| APK final: SHA-256 `E089492C…` = `docs/release/SHA256SUMS`; firma `44b46fe1…` = `docs/release/CERT_SHA256`; `versionCode=1004005`, `versionName=10.2.2` | Comprobado (se repite antes del `adb install -r`) | `apksigner verify --print-certs`; `aapt2 dump badging` |

Idioma de la interfaz: inglés. El emulador está en `en-US` y la app toma el idioma del dispositivo (`lib/main.dart`, `LocaleSettings.useDeviceLocale()`). Las etiquetas del brief en español se buscan en su equivalente inglés.

Límite de logcat en release: la migración (`DB found! Version 16 (previous was 15)`, `Migrating database…`) se emite con `Logger.printDebug` (`lib/core/database/app_db.dart:102-226`), y `Logger.printDebug` solo imprime con `kDebugMode` (`lib/core/utils/logger.dart:4-7`). Un APK release no la mostrará. Ver «PREGUNTA».

## Prueba 2 — Copia local cifrada y restauración en el release arm64

Pendiente.

## BUG-NN

Ninguno hasta ahora.

## No probado

- Pruebas 1 y 2: pendientes.

## PREGUNTA

1. El criterio «la migración en el logcat» no se puede cumplir con un APK release, porque el log de migración solo imprime con `kDebugMode` (`lib/core/utils/logger.dart:4-7`). Propuesta de evidencia equivalente: actualización con `adb install -r` sin error de firma, `versionCode=1004005`, logcat sin `FATAL EXCEPTION`, `E/flutter` ni `Unhandled Exception` durante 60 s, y la cuenta y los dos gastos visibles tras abrir. ¿La aceptas, o quieres además un build debug del mismo commit para ver el log de migración? Un debug no sería el APK final.
2. La versión vieja se compila con `--split-per-abi --target-platform android-arm64`, el mismo flujo que el APK final, para que tenga `versionCode=1004002` como dice el brief. El comando literal del brief da `1002002`. Mismo commit (`38ca6cca`), mismas definiciones y misma clave. ¿Lo confirmas?
