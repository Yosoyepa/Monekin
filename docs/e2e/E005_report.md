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

Pendiente.

## Prueba 2 — Copia local cifrada y restauración en el release arm64

Pendiente.

## BUG-NN

Ninguno hasta ahora.

## No probado

- Pruebas 1 y 2: pendientes.
