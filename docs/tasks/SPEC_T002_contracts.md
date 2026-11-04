# SPEC T002 — Contratos del esqueleto de Finanzas IA

Base: `feat/finanzas-ia`. Todo el código nuevo vive en `lib/features_ia/**` y sus pruebas en `test/features_ia/**`.
El esqueleto ya trae las dependencias de todas las fases (`pubspec.yaml`), las páginas vacías enganchadas en la interfaz y las
secciones de traducción. **Nadie más toca `pubspec.yaml`, `lib/main.dart`, `lib/features_ia/features_ia.dart` ni los archivos de
upstream**, salvo los que su fila de abajo le asigna.

## 1. Contratos (no cambies firmas; si una no te sirve, escríbelo bajo `## PREGUNTA`)

| Archivo | Qué define | Dueño de la implementación |
|---|---|---|
| `core/ai/ai_client.dart` | `AiClient` (`chat`, `listModels`), `AiService.instance`, `AiService.debugClientOverride` para pruebas, `AiException`/`AiErrorKind`, `AiResult.json()` | w-ai |
| `core/ai/ai_service_factory.dart` | `createAiService()` | w-ai |
| `core/money/amount_parser.dart` | `parseLocalizedAmount(String) → double?` | w-utils |
| `core/dedupe/dedupe.dart` | `DedupeCandidate`, `DedupeMatch`, `normalizeTitle`, `findDuplicates` | w-utils |
| `core/catalog/ai_catalog.dart` | `loadAiCatalog()`, `AiCatalog.toPromptJson()` | w-utils |
| `core/cards/card_map.dart` (+ `card_map_page.dart`) | `CardMapService` (últimos 4 dígitos → cuenta) | w-utils |
| `inbox/inbox_models.dart`, `inbox/inbox_service.dart` | `InboxDraft`, `InboxItem`, `ProposedTransaction`, `ConfirmResult`, `InboxService.instance` | w-inbox |
| `inbox/inbox_navigation.dart` | `openInboxReview(context, itemId)`, `openInbox(context)` | w-inbox |
| `receipts/receipt_capture.dart` | `startReceiptCapture(context)` (botón de cámara del inicio) | w-recibos |
| `statements/statement_import_page.dart` | `StatementImportPage` | w-extractos |
| `insights/insights_service.dart` | `InsightsService.instance.weeklySummary()` | w-insights |
| `google/google_backup_service.dart` | `GoogleBackupService.instance` (`backupNow`, `isSignedIn`, `lastBackup`) | w-google |
| `core/background/background_tasks.dart` | `initBackgroundTasks`, `schedulePeriodicTask`, `cancelBackgroundTask`, despachador por nombre de tarea | w-avisos |
| `notifications/*` | `initNotificationsFeature`, tareas de recordatorio, presupuesto y resumen semanal | w-avisos |
| `google/google_background.dart` | `runDriveBackupTask` | w-google |

Las páginas vacías (`ComingSoonPage`) se reemplazan conservando el nombre de la clase y el constructor sin parámetros.

## 2. Reglas de datos (heredadas de T001)
- La IA y los avisos **nunca** crean transacciones: añaden un `InboxDraft`; solo `InboxService.confirm` escribe, después de que el usuario revisa.
- Antes de escribir, `confirm` deduplica con `findDuplicates` contra las transacciones existentes (ventana ±1 día) y dentro del lote.
- Cada transacción creada lleva la etiqueta `ia` (se crea si no existe) y sus notas terminan en `[origen: recibo:<archivo>]`,
  `[origen: extracto:<etiqueta>]` o `[origen: aviso:<paquete>]`.
- Si una fila falla, el ítem sigue `pending` y guarda los ids ya creados; reintentar no duplica.
- Si la fecha es anterior al saldo inicial de la cuenta, la revisión lo advierte antes de confirmar.
- Las ids de cuenta y categoría que proponga la IA deben existir en `loadAiCatalog()`; si no, quedan en null para que el usuario elija.

## 3. Traducciones
`lib/i18n/json/en.json` (base) y `es.json` traen una sección por función: `IA-COMMON`, `IA-SETTINGS`, `IA-CARDS`, `IA-NOTIFICATIONS`,
`IA-INBOX`, `IA-RECEIPTS`, `IA-STATEMENTS`, `IA-INSIGHTS`, `IA-GOOGLE` (en Dart: `t.ia_settings.title`, etc.).
**Cada worker añade claves solo dentro de su sección**, en inglés y en español. Los demás idiomas usan el inglés por defecto.
Después: `dart run slang` (el código generado no se versiona).

## 4. IA
- API compatible con OpenAI. Gemini: `https://generativelanguage.googleapis.com/v1beta/openai/`, modelos `gemini-flash-lite-latest`
  (por defecto) y `gemini-flash-latest`. DeepSeek: `https://api.deepseek.com`, `deepseek-flash` (acepta imágenes).
- Las imágenes van como `{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,..."}}`. Verificado con la key de prueba
  (recibo sintético: total y últimos 4 dígitos correctos, 1.137 tokens, 3 s).
- Pide `response_format: {"type":"json_object"}` y valida el JSON con tu propio esquema; nunca confíes en montos sin `parseLocalizedAmount`.

## 5. Pruebas y secretos
- Pruebas unitarias y de widgets con un cliente falso (`AiService.debugClientOverride`), sin red.
- Pruebas reales opcionales con la key de prueba del responsable: léela de `D:\Dev\secrets\gemini_test_key.txt` en la prueba
  (o de la variable `GEMINI_TEST_API_KEY`), sáltala si no existe y **nunca** la copies al repo, a un log ni al informe. Máximo 20 llamadas por worker.
- Antes de cada commit: `git grep -nE "AQ\.Ab8|AIza[0-9A-Za-z_-]{20,}"` debe salir vacío.
- El emulador lo usa solo `w-e2e`. Los demás no lo arrancan.

## 6. Entorno
Carga el entorno antes de cualquier comando: `source /d/Dev/dev-env.sh` (Git Bash) o `. D:\Dev\dev-env.ps1` (PowerShell).
Flutter 3.44.1 en `D:\Dev\flutter`, SDK en `D:\Dev\Android\Sdk`. Comandos de verificación:
`flutter pub get`, `dart run slang`, `flutter analyze --no-pub` (0 errores y ningún aviso nuevo en tus rutas) y `flutter test --no-pub test/features_ia/<tu carpeta>`.
Si tocas el esquema de la base (solo w-inbox): `dart run build_runner build --delete-conflicting-outputs` y commitea `app_db.g.dart`.
