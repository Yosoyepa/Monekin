# E005 — APK final arm64 (release) en Android: actualización con datos y copia cifrada local

Fecha: 2026-11-04 (la prueba cruzó la medianoche; hora del host UTC-5). Worker `fi-e2e4`, worktree `D:\Dev\orca-workspaces\Monekin\fi-e2e4` (rama `Yosoyepa/fi-e2e4`).

- APK probado: `D:\Dev\apk\FinanzasIA-arm64.apk`, versión `10.2.2+1002005`, versionCode `1004005`, SHA-256 `E089492CAF6ACA326DFC42C48601BAF1FE37251D98258481C5C657316A0251B4`. Coincide con `docs/release/SHA256SUMS`. Firmado con el certificado de `docs/release/CERT_SHA256` (`44b46fe1…8a1d23`).
- Versión vieja (la del celular): arm64 de `38ca6cca`, `10.2.2+1002002`, versionCode `1004002`, schema v15, compilada con `--split-per-abi` en un worktree temporal fuera del repo (`D:\Dev\e2e-build\e005-v15`).
- Código de la versión final: `20302359`. `4d570ed3` solo cambia `docs/release/SHA256SUMS` y `docs/tasks/T002_apk-finanzas-ia.md` respecto a `20302359`.
- Emulador: `Medium_Phone_API_36.0` (Android 16, API 36, x86_64 con traducción ARM `libndk_translation.so`), headless, `-no-snapshot`. GPU: `swangle_indirect` en la prueba 0 y `angle_indirect` desde la prueba 1 (ver «Entorno de la prueba 1»).
- Idioma de la interfaz: inglés (`en-US`). Las etiquetas del brief en español se buscan en su equivalente inglés.
- Paquete `com.yosoyepa.finanzas`. Sin cuentas de Google ni IA real: se usó «Start session offline».

## Hecho cuando

- [x] Prueba 0 con su salida. Ver «Prueba 0».
- [x] Prueba 1: la actualización conserva la cuenta y los dos gastos, sin crash. La migración no sale en el logcat de release; se usa la evidencia equivalente aceptada por el arquitecto (ver «PREGUNTA» 1). Ver «Prueba 1».
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

**Resultado: cumplida.** Commit probado: `38ca6cca` (versión vieja) y `20302359` (versión final).

### Versión vieja (la del celular)

| Paso | Resultado | Evidencia |
|---|---|---|
| Worktree temporal de `38ca6cca` fuera del repo, con `android/keys/key.properties` copiado | Hecho | `git status` del worktree vacío; `key.properties` ignorado por `android/.gitignore:11` |
| `flutter pub get` y `dart run slang` | Hecho (exit 0) | log de compilación en el scratchpad de la sesión |
| Comando literal del brief: `flutter build apk --release --target-platform android-arm64 --dart-define-from-file=D:\Dev\keys\release-defines.json` | Compilado, **no instalado** | APK de 43.641.982 bytes; `versionCode=1002002`; código nativo `arm64-v8a`, `armeabi-v7a`, `x86_64`. Guardado fuera del repo (`D:\Dev\e2e-build\e005\app-release-literal-1002002.apk`) |
| `flutter build apk --release --split-per-abi --target-platform android-arm64 --dart-define-from-file=D:\Dev\keys\release-defines.json` | Hecho (exit 0) | `app-arm64-v8a-release.apk`, 43.401.710 bytes, SHA-256 `CF192801E46701157F2ABEB95BB2B26CA5FF45CBAC115C007312D47EA4C05E42`; `versionCode=1004002`, `versionName=10.2.2`; `native-code: 'arm64-v8a'`; firma `44b46fe1…8a1d23` |
| Instalación en el emulador limpio (`adb install`) | `Success` | `dumpsys package`: `versionCode=1004002 minSdk=24 targetSdk=36`, `versionName=10.2.2` |

Desviación: el comando del brief no lleva `--split-per-abi`, y sin él sale `versionCode 1002002`. El brief dice que el celular tiene `1004002`. Gradle no suma ningún offset (`android/app/build.gradle:36` usa `flutter.versionCode`); el +2000 de arm64 lo aplica el split por ABI, igual que en el APK final (`1002005` → `1004005`). `tools/build_release.ps1:39` usa `--split-per-abi`. Confirmado por el arquitecto («PREGUNTA» 2).

### Datos creados en la versión vieja

Con la interfaz (`uiautomator dump` y `adb shell input`):

- Introducción: «Start session offline», moneda por defecto USD, pantallas informativas y «Continue».
- Cuenta «ARM-E2E Ahorros» (Money account, saldo inicial 0).
- Gasto «ARM-E2E Mercado»: 12.50, categoría Food & Dining › Groceries, cuenta «ARM-E2E Ahorros».
- Gasto «ARM-E2E Bus»: 3.50, categoría Transportation › Public Transport, cuenta «ARM-E2E Ahorros».
- Antes de actualizar: saldo de la cuenta -$16.00; la lista de transacciones muestra los dos gastos.

Capturas: `docs/e2e/E005/E005_01_first_run.png` (primera pantalla), `E005_02_account_created.png` (cuenta creada), `E005_03_first_expense.png` (primer gasto), `E005_04_v15_transactions.png` (lista con los dos gastos, versión vieja).

### Actualización a la versión final

| Paso | Resultado | Evidencia |
|---|---|---|
| SHA-256 de `D:\Dev\apk\FinanzasIA-arm64.apk` contra `docs/release/SHA256SUMS` | Coincide | `E089492CAF6ACA326DFC42C48601BAF1FE37251D98258481C5C657316A0251B4` |
| `adb install -r D:\Dev\apk\FinanzasIA-arm64.apk` | `Success` | `Performing Streamed Install` / `Success` |
| `dumpsys package com.yosoyepa.finanzas \| grep -E "versionCode\|versionName"` | `versionCode=1004005`, `versionName=10.2.2` | salida pegada en la sesión |
| Logcat durante 60 s tras abrir (`logcat -c`, abrir, esperar 60 s, `logcat -d`) | **Pasa**: 0 coincidencias de `FATAL EXCEPTION`, `Unhandled Exception` o `E/flutter`; 0 líneas de nivel E del proceso de la app (pid 5323) | 974 líneas capturadas. Las 222 de nivel E son de otros procesos: AuthPII 188, rdv 26, Finsky 2 y 6 del sistema |
| Migración en logcat | No aparece (esperado en release, ver abajo) | Evidencia equivalente aceptada («PREGUNTA» 1) |
| Cuenta y dos gastos visibles tras abrir | **Pasa** | Dashboard: «ARM-E2E Ahorros» -$16.00. Pestaña «Activity»: «ARM-E2E Bus» -$3.50 y «ARM-E2E Mercado» -$12.50 |

Líneas recortadas del logcat del proceso de la app (`logcat -d` completo fuera del repo, en `D:\Dev\e2e-build\e005\logcat_update_60s.txt`):

```
05:00:52.152  5323 D nativeloader: Load …/base.apk!/lib/arm64-v8a/libflutter.so …
05:00:52.522  5323 I flutter : [IMPORTANT:flutter/shell/platform/android/android_context_gl_impeller.cc(104)] Using the Impeller rendering backend (OpenGLES).
05:00:55.380  5323 I Choreographer: Skipped 56 frames!  The application may be doing too much work on its main thread.
```

Capturas: `E005_05_v16_after_update.png` (dashboard tras la actualización) y `E005_06_v16_activity.png` (lista con los dos gastos).

Notas:

- La interfaz de la versión final es distinta de la vieja: pestañas `Dashboard · Activity · Scan receipt · Inbox · More` (la vieja tenía `Dashboard · Transactions · More`) y el rango `3M` en el dashboard.
- Los «Skipped frames» vienen de la traducción ARM y no son representativos del hardware.
- La migración no sale en release: los mensajes `DB found! Version 16 (previous was 15)` y `Migrating database…` se emiten con `Logger.printDebug` (`lib/core/database/app_db.dart:102-226`), que solo imprime con `kDebugMode` (`lib/core/utils/logger.dart:4-7`). Los datos de v15 visibles en la app final, sin error, son la evidencia equivalente aceptada.

### Entorno de la prueba 1: caídas del emulador

qemu murió cinco veces. En cada caso, el registro de aplicaciones de Windows (evento 1000) registra `qemu-system-x86_64-headless.exe` con código `0xc0000005` y módulo `unknown`:

| Caída (host) | Arranque del emulador | GPU | Dónde pasó |
|---|---|---|---|
| 23:35:46 | 23:24:20 | `swangle_indirect` | primer toque en la app |
| 23:37:18 | 23:36:13 | `swangle_indirect` | primer toque en la app |
| 23:47:43 | 23:46:39 | `swiftshader_indirect` | primer toque en la app |
| 23:50:23 | 23:49:20 | `swiftshader_indirect` | primer toque en la app |
| 00:02:14 | 23:51:58 | `angle_indirect` | pestaña «Activity», tras la actualización |

Tras cada caída se reinició en frío (`-no-snapshot`). La primera reinstalación fue necesaria porque la caída perdió la app instalada. Con `angle_indirect` no hubo más caídas en el onboarding, la creación de datos, la actualización ni al reabrir la pestaña «Activity» (arranque de 00:02:49). Tras el reinicio, los datos seguían ahí (dashboard -$16.00 y los dos gastos).

## Prueba 2 — Copia local cifrada y restauración en el release arm64

Pendiente. Siguiente paso: Ajustes → Copias de seguridad, con la contraseña de prueba `E2E-Arm-Clave-2026`.

## BUG-NN

Ninguno. Las caídas del emulador son del entorno (qemu), no de la app; ver «Entorno de la prueba 1».

## No probado

- Prueba 2: copia cifrada por SAF, cambio de datos, restauración y comprobación de «ARM-E2E Después».

## PREGUNTA

1. El criterio «la migración en el logcat» no se puede cumplir con un APK release, porque el log de migración solo imprime con `kDebugMode` (`lib/core/utils/logger.dart:4-7`). Propuesta de evidencia equivalente: actualización con `adb install -r` sin error de firma, `versionCode=1004005`, logcat sin `FATAL EXCEPTION`, `E/flutter` ni `Unhandled Exception` durante 60 s, y la cuenta y los dos gastos visibles tras abrir. ¿La aceptas, o quieres además un build debug del mismo commit para ver el log de migración? Un debug no sería el APK final.
   **Respondida (arquitecto):** aceptada la evidencia equivalente propuesta. No hace falta build debug.
2. La versión vieja se compila con `--split-per-abi --target-platform android-arm64`, el mismo flujo que el APK final, para que tenga `versionCode=1004002` como dice el brief. El comando literal del brief da `1002002`. Mismo commit (`38ca6cca`), mismas definiciones y misma clave. ¿Lo confirmas?
   **Respondida (arquitecto):** confirmado, como `tools/build_release.ps1`.
