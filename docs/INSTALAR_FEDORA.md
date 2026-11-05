# Instalar Finanzas IA desde Fedora (por cable)

Esto instala o actualiza la app en tu celular desde un PC con Fedora, usando la depuración USB (`adb`). Una actualización conserva tus datos.

## Lo que necesitas
- **Este repo en Fedora:**
  ```sh
  git clone -b feat/finanzas-ia https://github.com/Yosoyepa/Monekin.git
  cd Monekin
  ```
  Si ya lo tienes, actualízalo con `git pull`.
- **Los APK de la versión:** `FinanzasIA-arm64.apk` y, para celulares viejos, `FinanzasIA-armv7.apk`.
  - Cópialos a `~/Descargas` desde el PC donde se compilan, por USB, Drive o como prefieras.
  - El script comprueba que cada archivo sea **exactamente** el publicado: compara su SHA‑256 con `docs/release/SHA256SUMS` del repo. Si no coincide, no instala nada.
  - Si en `~/Descargas` queda una copia vieja y la nueva se guardó como `FinanzasIA-arm64 (1).apk`, no pasa nada: el script usa la copia que coincide.
- **Un cable USB de datos.**

## Pasos
1. **En el celular:**
   - Activa las opciones de desarrollador: Ajustes → Información del teléfono → toca 7 veces **Número de compilación**.
   - Activa **Depuración USB** en las opciones de desarrollador.
2. **Conecta el cable y corre el script:**
   ```sh
   ./tools/instalar_celular.sh
   ```
   Si los APK están en otra carpeta: `./tools/instalar_celular.sh /ruta/a/la/carpeta`.
3. **Cuando el celular pregunte** «¿Permitir la depuración USB?», acepta solo si la huella es la de **este** PC.
4. **El script hace el resto:**
   - instala `adb` si falta (te pide permiso para `sudo dnf install android-tools`);
   - elige el APK según el procesador del celular;
   - verifica el SHA‑256;
   - instala o actualiza;
   - abre la app.

## Al terminar: cierra la puerta
En el celular, en las opciones de desarrollador:
1. **apaga Depuración USB**;
2. toca **Revocar autorizaciones de depuración USB**.

Si la dejas encendida, alguien con acceso a tu celular y a un PC autorizado podría leerlo.

## Si algo sale mal
| Mensaje | Qué hacer |
|---|---|
| «no veo ningún celular autorizado» | Revisa el cable (que sea de datos), la **Depuración USB** y el aviso de la huella en el celular. |
| «hay varios celulares conectados» | Deja solo uno, o corre `ANDROID_SERIAL=<serie> ./tools/instalar_celular.sh`. |
| «ninguna de estas copias coincide con el APK publicado» | Son de otra compilación o están dañadas. **No las instales**: haz `git pull`, borra las copias viejas y copia el APK nuevo. |
| «la app instalada tiene otra firma» | **No la desinstales** sin antes hacer una copia (Ajustes → Copias): desinstalar borra tus datos. |
| «el celular ya tiene una versión más nueva» | Pide el APK de la versión más reciente. |

## Después de instalar
- **IA:** en Ajustes → Inteligencia artificial, pega tu key de Gemini. Si la app dice «key por confirmar», pégala otra vez.
- **Copias:** en Copias de seguridad, crea tu **contraseña de copias** (12 caracteres o más, o una frase de 4 palabras). Guárdala fuera del celular: si la olvidas, esas
  copias no se pueden recuperar.
- **Drive:** si tenías copias antiguas sin cifrar, toca **Borrar copias sin cifrar**.
