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
- [x] Prueba 2: la restauración vuelve a los datos de la copia, en el mismo dispositivo y en instalación limpia con contraseña. Ver «Prueba 2». El tiempo de creación de la contraseña no se midió con precisión (ver «PREGUNTA» 4).
- [x] `docs/e2e/E005_report.md` commiteado y `git status --porcelain` vacío. Ver «Cierre».

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

qemu murió seis veces. En cada caso, el registro de aplicaciones de Windows (evento 1000) registra `qemu-system-x86_64-headless.exe` con código `0xc0000005` y módulo `unknown`:

| Caída (host) | Arranque del emulador | GPU | Dónde pasó |
|---|---|---|---|
| 23:35:46 | 23:24:20 | `swangle_indirect` | primer toque en la app |
| 23:37:18 | 23:36:13 | `swangle_indirect` | primer toque en la app |
| 23:47:43 | 23:46:39 | `swiftshader_indirect` | primer toque en la app |
| 23:50:23 | 23:49:20 | `swiftshader_indirect` | primer toque en la app |
| 00:02:14 | 23:51:58 | `angle_indirect` | pestaña «Activity», tras la actualización |
| 00:24:56 | 00:02:49 | `angle_indirect` | pestaña «Activity», al reabrir tras restaurar con contraseña en instalación limpia |

Tras cada caída se reinició en frío (`-no-snapshot`). La primera caída perdió la app instalada y hubo que reinstalarla. Con `angle_indirect` hubo dos caídas más, ambas al abrir «Activity». En el resto de pasos de las pruebas 1 y 2 (onboarding, datos, actualización y restauraciones) no hubo caídas con ese modo. Tras cada reinicio los datos seguían ahí: dashboard -$16.00 y los dos gastos.

## Prueba 2 — Copia local cifrada y restauración en el release arm64

**Resultado: cumplida.** Commit probado: `20302359`. Dos puntos del brief no se cumplieron tal cual, y van explicados abajo y en «PREGUNTA» 3 y 4: en el mismo dispositivo la restauración no pidió la contraseña, y el tiempo de creación de la contraseña no se midió con precisión.

### Exportar la copia completa

| Paso | Resultado | Evidencia |
|---|---|---|
| Ajustes → Data → Export your data → «Full backup» → Download | Hecho | Diálogo «Create a backup password» (`docs/e2e/E005/E005_07_backup_password.png`; el texto va enmascarado) |
| Contraseña de prueba `E2E-Arm-Clave-2026` en «Password» y «Confirm password» | Hecho | 18 caracteres en cada campo, leídos con uiautomator |
| Guardar con el selector SAF: «Usar esta carpeta» y «Permitir» | Pasa en `Documents` | En `Download` aparece «Can't use this folder — To protect your privacy, choose another folder» y USE THIS FOLDER no hace nada. En `Documents` no aparece el aviso; USE THIS FOLDER → «Allow Finanzas IA to access files in Documents?» → ALLOW |
| Archivo creado | Pasa | `/sdcard/Documents/finanzas-20261105-51515.fia`, 19.967 bytes, cabecera `46 49 41 33` («FIA3»), sin texto SQLite. Copia fuera del repo: `D:\Dev\e2e-build\e005\finanzas-20261105-51515.fia`, SHA-256 `F2F4E896B4E578A8D7A1AD741FD33909DF25A97B6693C2196DA17A8811802264` |
| Tiempo de creación de la contraseña | **No medido con precisión** | Nota 1 |

Nota 1. El primer sondeo del selector no leyó el foco de la ventana y no dejó marca de tiempo. El selector ya estaba abierto en la captura tomada después de 150 s desde el toque en «Save password». Cota superior: esos 150 s más el tiempo entre comandos, que no se midió. Bajo traducción ARM no es representativo del hardware real.

### Cambiar los datos

- Gasto «ARM-E2E Después»: 4.00, categoría Others, cuenta «ARM-E2E Ahorros». `input text` no escribe «é», así que la tilde se eligió en el menú de la tecla «e» del teclado, con `input motionevent DOWN` y `UP`. El título quedó «ARM-E2E Después» (15 caracteres).
- Saldo de la cuenta después del gasto: -$20.00 (`E005_09_before_restore.png`).

### Restaurar en el mismo dispositivo

| Paso | Resultado | Evidencia |
|---|---|---|
| Data → Restore Backup → aviso «Overwrite all data» → Understood | Hecho | Texto del diálogo con uiautomator |
| Selector → `finanzas-20261105-51515.fia` | Hecho | Carpeta `Documents` |
| Pide la contraseña | **No** | `restorePackage` usa la clave guardada cuando no recibe contraseña (`lib/core/database/backup/backup_database_service.dart:241-247`). La clave se guardó al crear la contraseña en este dispositivo |
| Pantalla de copia restaurada: «Backup restored», «The app needs to close to finish the restore» | Pasa | `E005_10_backup_restored.png` |
| «Close the app» | Observación | No terminó el proceso: el pid fue 2751 antes y después. Se hizo `am force-stop` y se reabrió (pid 6699) |
| Tras reabrir: «ARM-E2E Después» no está; «ARM-E2E Mercado» (-$12.50) y «ARM-E2E Bus» (-$3.50) sí; total -$16.00 | **Pasa** | Lista de la pestaña Activity con uiautomator: 2 transacciones, balance -$16.00 |

### Restaurar en instalación limpia, con contraseña

Para probar la ruta que pide la contraseña:

- `adb uninstall com.yosoyepa.finanzas` (borra datos y la clave guardada) y `adb install` del APK final. SHA-256 comprobado de nuevo: `E089492C…A316A0251B4`. Versión instalada: `versionCode=1004005`, `versionName=10.2.2`.
- Onboarding de esta versión: «Get started», tres páginas («Next», «Continue») e inicio vacío («No accounts created yet»).
- Data → Restore Backup → Understood → selector → `.fia`. Aparece «Backup password — Enter the password this backup was made with». Contraseña `E2E-Arm-Clave-2026` (18 caracteres) → **Restore**.
- «Backup restored» a los **3,3 s** del toque en Restore (cronómetro del host). Ese tiempo incluye derivar la clave con la contraseña, descifrar y preparar la restauración. Es la misma derivación que la de crear la contraseña, pero no mide la creación.
- Close the app → `force-stop` → reabrir. Dashboard: «ARM-E2E Ahorros» -$16.00. Lista de Activity: «ARM-E2E Bus» -$3.50 y «ARM-E2E Mercado» -$12.50. «ARM-E2E Después» no aparece, porque la copia se hizo antes de crearlo. Capturas: `E005_11_restore_password_restored.png` y `E005_12_restored_activity.png`.

El emulador cayó otra vez al abrir «Activity» después de esta restauración (caída 6 en «Entorno de la prueba 1»). Tras reiniciarlo con `angle_indirect`, el dashboard y la lista de Activity seguían mostrando los datos de la copia; `E005_12` es esa lista tras el reinicio.

Notas:

- No se pulsó «Google Drive backup» y no se inició sesión con ninguna cuenta. No se usó IA.

## Reapertura sin forzar

Tarea extra pedida por el arquitecto: el camino real del responsable. Se restaura, se pulsa «Close the app» y se reabre desde el lanzador, sin `am force-stop`.

Preparación:

- Emulador `Medium_Phone_API_36.0` arrancado con `-gpu angle_indirect` (mismos flags de la prueba 2) y `-no-snapshot`.
- Instalación limpia del APK final: SHA-256 `E089492CAF6ACA326DFC42C48601BAF1FE37251D98258481C5C657316A0251B4`, igual a `docs/release/SHA256SUMS`. `dumpsys`: `versionCode=1004005`, `versionName=10.2.2`.
- Copia `D:\Dev\e2e-build\e005\finanzas-20261105-51515.fia`, en `/sdcard/Documents/` del emulador. SHA-256 en el dispositivo igual al del host (`F2F4E896…1802264`).

| Paso | Resultado | Evidencia |
|---|---|---|
| Onboarding, luego restauración con contraseña `E2E-Arm-Clave-2026` | Pasa | «Backup restored» antes de cerrar: `docs/e2e/E005/E005_13_restored_before_close.png` |
| Pid antes de «Close the app» | `3654` | `pidof com.yosoyepa.finanzas` |
| Pila de actividades antes de cerrar | Pasa: `Task #59` con `com.yosoyepa.finanzas/com.monekin.app.MainActivity` como `topResumedActivity` | `dumpsys activity activities` (`dumpsys_before_close.txt`, fuera del repo) |
| «Close the app», sin `force-stop` | Pasa: la actividad sale de la pila | `dumpsys` después: 0 líneas con `com.yosoyepa.finanzas`. Pid después: `3654` |
| Reapertura desde el lanzador: `monkey -p com.yosoyepa.finanzas -c android.intent.category.LAUNCHER 1` | Pasa | Pid después de reabrir: `3654` |
| Dashboard: «ARM-E2E Ahorros» -$16.00, sin «Backup restored» | Pasa | `docs/e2e/E005/E005_14_reopen_dashboard.png` |
| Pestaña Activity: «ARM-E2E Bus» -$3.50 y «ARM-E2E Mercado» -$12.50 | Pasa | `docs/e2e/E005/E005_15_reopen_activity.png` |
| Logcat desde la reapertura hasta después de abrir Activity (3.845 líneas, todos los procesos): `E/flutter`, `FATAL EXCEPTION`, `Unhandled Exception` | 0 coincidencias | `logcat_reopen_after_activity_run8.txt` (fuera del repo); nivel E del pid 3654: 0 |

`dumpsys` antes de cerrar, recortado:

```
* Task{c28c5c2 #59 type=standard I=com.yosoyepa.finanzas/com.monekin.app.MainActivity U=0 visible=true ...}
topResumedActivity=ActivityRecord{189317645 u0 com.yosoyepa.finanzas/com.monekin.app.MainActivity t59}
app=ProcessRecord{9b4643c 3654:com.yosoyepa.finanzas/u0a219}
```

Tras cerrar, `dumpsys` no muestra ninguna línea con `com.yosoyepa.finanzas`.

Nota: «Close the app» quita la actividad, pero no termina el proceso: el pid 3654 se mantiene antes y después. Al reabrir, la app arranca una actividad nueva en ese mismo proceso y muestra la copia restaurada. El comentario de `restorePackage` (`lib/core/database/backup/backup_database_service.dart:229-230`) dice que la app debe reiniciarse después de restaurar («the app must restart afterwards»). Aquí el proceso no se reinició y los datos ya se ven restaurados. Esta prueba no comprueba qué cambia con un reinicio real del proceso.

## BUG-NN

Ninguno. Las caídas del emulador son del entorno (qemu), no de la app; ver «Entorno de la prueba 1».

## No probado

- Tiempo de creación de la contraseña medido con precisión (ver «Prueba 2», nota 1).
- Todo se probó en el emulador `Medium_Phone_API_36.0` con traducción ARM. No se probó en un celular real.
- «Google Drive backup»: no se probó, por la regla del brief de no tocar Drive ni iniciar sesión con Google.

## Cierre

- Commits de esta sesión, desde `4d570ed3`: `7cbf92ff` (prueba 0), `fcc4886e` y `6a408bf4` (build de la versión vieja), `98836caf` (prueba 1) y `93398036` (prueba 2). El commit que marca la última casilla es `a267aead`. La sección «Reapertura sin forzar» va en un commit posterior; tras él, `git status --porcelain` queda vacío.
- Cambios en el repo: solo `docs/e2e/E005_report.md` y 11 capturas en `docs/e2e/E005/`. `lib/**` sin cambios. No hubo push: la rama no tiene upstream configurado.
- Worktree temporal de `38ca6cca` (`D:\Dev\e2e-build\e005-v15`) borrado con `git worktree remove --force`, incluida su copia de `key.properties`. Comprobado: la carpeta ya no existe.
- Emulador `emulator-5554` apagado con `adb emu kill`. Al terminar no queda ningún proceso `emulator` ni `qemu-system-x86_64`.
- Fuera del repo y sin commitear, en `D:\Dev\e2e-build\e005\`: APKs de compilación, la copia `finanzas-20261105-51515.fia` y el logcat completo de la actualización.
- Preguntas: `## PREGUNTA` 1 a 4, todas respondidas por el arquitecto. No queda ninguna abierta.

## PREGUNTA

1. El criterio «la migración en el logcat» no se puede cumplir con un APK release, porque el log de migración solo imprime con `kDebugMode` (`lib/core/utils/logger.dart:4-7`). Propuesta de evidencia equivalente: actualización con `adb install -r` sin error de firma, `versionCode=1004005`, logcat sin `FATAL EXCEPTION`, `E/flutter` ni `Unhandled Exception` durante 60 s, y la cuenta y los dos gastos visibles tras abrir. ¿La aceptas, o quieres además un build debug del mismo commit para ver el log de migración? Un debug no sería el APK final.
   **Respondida (arquitecto):** aceptada la evidencia equivalente propuesta. No hace falta build debug.
2. La versión vieja se compila con `--split-per-abi --target-platform android-arm64`, el mismo flujo que el APK final, para que tenga `versionCode=1004002` como dice el brief. El comando literal del brief da `1002002`. Mismo commit (`38ca6cca`), mismas definiciones y misma clave. ¿Lo confirmas?
   **Respondida (arquitecto):** confirmado, como `tools/build_release.ps1`.
3. En el mismo dispositivo, «Restore Backup» no pide la contraseña si existe la clave guardada (`lib/core/database/backup/backup_database_service.dart:241-247`). El brief dice «restaurar con el selector y la contraseña». Probé las dos rutas: mismo dispositivo, sin contraseña (pasa), e instalación limpia, con contraseña (pasa). ¿Es el comportamiento que quieres, o la restauración en el mismo dispositivo debe pedir la contraseña también?
   **Respondida (arquitecto):** sí, es el diseño. En el mismo teléfono la clave derivada está en el almacenamiento seguro y no se vuelve a pedir la contraseña.
4. No pude medir con precisión cuánto tarda crear la contraseña, porque el primer sondeo del selector falló (ver «Prueba 2», nota 1). Como referencia, la restauración con contraseña tardó 3,3 s bajo traducción ARM, desde «Restore» hasta «Backup restored», e incluye derivar la clave. ¿Te sirve esa referencia, o quieres que repita la creación en una instalación limpia?
   **Respondida (arquitecto):** los 3,3 s bastan como referencia. No hace falta repetir.
