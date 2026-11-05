#!/usr/bin/env bash
# Installs or updates Finanzas IA on an Android phone over USB (adb), from Linux (tested for Fedora).
#
#   ./tools/instalar_celular.sh                      # looks for the APKs next to the repo or in ~/Descargas, ~/Downloads
#   ./tools/instalar_celular.sh /ruta/a/la/carpeta   # folder that holds FinanzasIA-arm64.apk / FinanzasIA-armv7.apk
#   ./tools/instalar_celular.sh /ruta/FinanzasIA-arm64.apk
#
# Every APK is checked against docs/release/SHA256SUMS (committed with the release) before anything is installed.
# An update keeps the user's data because it is signed with the same key; the script never uninstalls anything.
set -euo pipefail

PKG="com.yosoyepa.finanzas"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUMS="$REPO_DIR/docs/release/SHA256SUMS"

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
fail() { printf '\n\033[31mNo se pudo continuar:\033[0m %s\n' "$*" >&2; exit 1; }

# 1. adb -------------------------------------------------------------------------------------------
say "1/6  Herramienta adb"
if ! command -v adb >/dev/null 2>&1; then
  info "No está instalada. En Fedora viene en el paquete android-tools."
  if command -v dnf >/dev/null 2>&1; then
    read -r -p "  ¿Instalarla ahora con 'sudo dnf install -y android-tools'? [s/N] " answer
    [[ "$answer" =~ ^[sSyY]$ ]] || fail "instala android-tools y vuelve a correr el script."
    sudo dnf install -y android-tools
  else
    fail "instala adb (paquete android-tools o platform-tools de Android) y vuelve a correr el script."
  fi
fi
info "$(adb version | head -1)"

# 2. APKs and checksums ----------------------------------------------------------------------------
say "2/6  Archivos de la app"
[ -f "$SUMS" ] || fail "falta $SUMS. Actualiza el repo (git pull)."
list_apks() {  # $1 = file name; prints every copy found, one per line, also «FinanzasIA-arm64 (1).apk»
  local base="${1%.apk}" dir f
  shopt -s nullglob
  if [ -n "${SOURCE:-}" ] && [ -f "$SOURCE" ]; then
    echo "$SOURCE"
  elif [ -n "${SOURCE:-}" ] && [ -d "$SOURCE" ]; then
    for f in "$SOURCE/$base"*.apk; do echo "$f"; done
  else
    for dir in "$REPO_DIR" "$REPO_DIR/.." "$HOME/Descargas" "$HOME/Downloads" "$PWD"; do
      for f in "$dir/$base"*.apk; do echo "$f"; done
    done
  fi
}
SOURCE="${1:-}"

# 3. Phone -----------------------------------------------------------------------------------------
say "3/6  Celular"
info "En el celular: Ajustes → Información del teléfono → toca 7 veces «Número de compilación»;"
info "luego Opciones de desarrollador → activa «Depuración USB» y conecta el cable."
info "Si aparece «¿Permitir la depuración USB?», acepta solo si la huella es la de este PC."
adb start-server >/dev/null
for _ in $(seq 1 60); do
  STATES="$(adb devices | sed '1d' | awk 'NF>=2 {print $1" "$2}')"
  if echo "$STATES" | grep -q ' device$'; then break; fi
  if echo "$STATES" | grep -q ' unauthorized$'; then info "Esperando que aceptes la huella en el celular…"; fi
  sleep 2
done
COUNT="$(echo "$STATES" | grep -c ' device$' || true)"
[ "$COUNT" -ge 1 ] || fail "no veo ningún celular autorizado. Revisa el cable, la «Depuración USB» y el aviso de la huella."
if [ "$COUNT" -gt 1 ] && [ -z "${ANDROID_SERIAL:-}" ]; then
  echo "$STATES" | grep ' device$'
  fail "hay varios celulares conectados. Deja solo uno o corre: ANDROID_SERIAL=<serie> $0"
fi
MODEL="$(adb shell getprop ro.product.model | tr -d '\r')"
ANDROID="$(adb shell getprop ro.build.version.release | tr -d '\r')"
ABI="$(adb shell getprop ro.product.cpu.abi | tr -d '\r')"
info "Conectado: $MODEL, Android $ANDROID, procesador $ABI"

case "$ABI" in
  arm64-v8a) NAME="FinanzasIA-arm64.apk" ;;
  armeabi-v7a|armeabi) NAME="FinanzasIA-armv7.apk" ;;
  *) fail "procesador $ABI no soportado por estos APK (solo arm64-v8a y armeabi-v7a)." ;;
esac
CANDIDATES="$(list_apks "$NAME")"
[ -n "$CANDIDATES" ] || fail "no encuentro $NAME. Cópialo a ~/Descargas o pasa la carpeta: $0 /ruta/a/la/carpeta"

# 4. Integrity -------------------------------------------------------------------------------------
say "4/6  Verificación del APK"
EXPECTED="$(awk -v n="$NAME" '$2==n || $2=="*"n {print $1}' "$SUMS")"
[ -n "$EXPECTED" ] || fail "$NAME no aparece en $SUMS."
# A second download may be saved as «FinanzasIA-arm64 (1).apk» next to an old copy: the copy that matches wins.
APK=""
while IFS= read -r f; do
  if [ "$(sha256sum "$f" | awk '{print $1}')" = "$EXPECTED" ]; then APK="$f"; break; fi
done <<< "$CANDIDATES"
if [ -z "$APK" ]; then
  printf '%s\n' "$CANDIDATES" | sed 's/^/     /'
  fail "ninguna de estas copias coincide con el APK publicado en el repo (SHA-256): son de otra compilación o están dañadas. No las instales: copia el APK nuevo y borra las viejas."
fi
info "APK: $APK"
info "SHA-256 correcto: $EXPECTED"
if command -v apksigner >/dev/null 2>&1 && [ -f "$REPO_DIR/docs/release/CERT_SHA256" ]; then
  CERT="$(apksigner verify --print-certs "$APK" | awk -F': ' '/certificate SHA-256/ {print $2; exit}')"
  [ "$CERT" = "$(tr -d ' \r\n' < "$REPO_DIR/docs/release/CERT_SHA256")" ] || fail "la firma del APK no es la de Finanzas IA."
  info "Firma correcta."
else
  info "(apksigner no está instalado: basta con el SHA-256; además Android rechaza una actualización con otra firma.)"
fi

# 5. Install or update -----------------------------------------------------------------------------
say "5/6  Instalación"
BEFORE="$( (adb shell dumpsys package "$PKG" 2>/dev/null || true) | awk -F= '/versionName/ {print $2; exit}' | tr -d '\r')"
if [ -n "$BEFORE" ]; then info "Ya está instalada la versión $BEFORE: se actualiza y tus datos se conservan."; else info "Instalación nueva."; fi
if ! OUT="$(adb install -r "$APK" 2>&1)"; then
  echo "$OUT"
  case "$OUT" in
    *INSTALL_FAILED_UPDATE_INCOMPATIBLE*)
      fail "la app instalada tiene otra firma. NO la desinstales sin antes hacer una copia (Ajustes → Copias): desinstalar borra tus datos." ;;
    *INSTALL_FAILED_VERSION_DOWNGRADE*)
      fail "el celular ya tiene una versión más nueva que este APK." ;;
    *) fail "adb no pudo instalar el APK (mira el mensaje de arriba)." ;;
  esac
fi
AFTER="$( (adb shell dumpsys package "$PKG" 2>/dev/null || true) | awk -F= '/versionName/ {print $2; exit}' | tr -d '\r')"
info "Instalada: Finanzas IA $AFTER"
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 && info "La app se abrió en el celular."

# 6. Close the door --------------------------------------------------------------------------------
say "6/6  Seguridad: cierra la puerta"
info "En el celular, Opciones de desarrollador:"
info "  • apaga «Depuración USB»;"
info "  • toca «Revocar autorizaciones de depuración USB»."
info "Si la dejas encendida, alguien con tu celular y un PC autorizado podría leerlo."
adb kill-server >/dev/null 2>&1 || true
say "Listo."
