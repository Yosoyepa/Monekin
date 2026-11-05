# Prueba en el celular de la versión final (10.2.2+1002005)

Esta lista cierra lo que solo se puede comprobar en un celular real con tu cuenta de Google. En el emulador ya pasaron la actualización con datos, la copia
cifrada local y su restauración, y la reapertura (`docs/e2e/E005_report.md`). Los pasos detallados están en `docs/USO.md`. Para cada fila, anota **sí** o **no**, y si
es no, el mensaje que viste o una captura.

## 1. Instalación (unos 5 minutos)
| # | Haz esto | Debe pasar | ¿Pasó? |
|---|---|---|---|
| 1.1 | En la app que tienes ahora: Más → Ajustes → Datos → exporta una copia local. | Se guarda un archivo de copia. | |
| 1.2 | En Fedora, corre `./tools/instalar_celular.sh` con el celular conectado ([INSTALAR_FEDORA.md](INSTALAR_FEDORA.md)). | «SHA-256 correcto», «se actualiza y tus datos se conservan» y «Listo». | |
| 1.3 | Abre la app. | Tus cuentas, movimientos y fotos de recibos siguen ahí. En Más → Ajustes → «Información de la app» dice `10.2.2`. | |
| 1.4 | Desactiva la depuración USB. | Lo pide el paso 6 del script. | |

## 2. IA con tu key (unos 5 minutos)
| # | Haz esto | Debe pasar | ¿Pasó? |
|---|---|---|---|
| 2.1 | Pega tu key de Gemini y toca «Probar conexión» ([USO.md](USO.md), sección 3). | La conexión funciona. Antes, la key aparecía «por confirmar». | |
| 2.2 | Escanea un recibo ([USO.md](USO.md), sección 5). | La primera vez pide el consentimiento. Sale una propuesta que confirmas, y la foto queda adjunta. | |
| 2.3 | Revoca en AI Studio la key de prueba que usamos en el PC. | Ya no aparece en AI Studio. | |

## 3. Avisos del banco (cuando te llegue uno real)
| # | Haz esto | Debe pasar | ¿Pasó? |
|---|---|---|---|
| 3.1 | Activa la lectura de avisos y elige tus bancos ([USO.md](USO.md), sección 8). | Android te pide el permiso de notificaciones. | |
| 3.2 | Espera un aviso real, por ejemplo de un pago con Nequi o con tu tarjeta. | Aparece **un** ítem en la Bandeja con el monto correcto, y nada se guarda hasta que confirmas. | |

## 4. Copia en Google Drive (unos 10 minutos)
| # | Haz esto | Debe pasar | ¿Pasó? |
|---|---|---|---|
| 4.1 | Datos → Copia en Google Drive → inicia sesión ([USO.md](USO.md), sección 10). | Aparece tu cuenta. | |
| 4.2 | «Copiar ahora». La primera vez crea la contraseña de copias: 12 caracteres o más, o 4 palabras. **Anótala fuera del teléfono.** | «Copia guardada en tu Drive», y la copia aparece en la lista. | |
| 4.3 | Toca «Borrar copias sin cifrar». | Desaparecen las copias viejas sin cifrar. | |
| 4.4 | Registra un gasto de prueba, «PRUEBA borrar». Luego restaura la copia del paso 4.2. | Sale «Copia restaurada». Al tocar «Cerrar la app» y volver a abrirla, «PRUEBA borrar» ya no está y lo demás sí. | |
| 4.5 | Activa la copia diaria. | Al día siguiente hay una copia nueva en la lista. | |

## 5. La segunda persona
| # | Haz esto | Debe pasar | ¿Pasó? |
|---|---|---|---|
| 5.1 | En Google Cloud, añade su correo como usuario de prueba del cliente OAuth ([google-oauth.md](google-oauth.md)). | Su correo aparece en la lista de usuarios de prueba. | |
| 5.2 | Instala la app en su celular con el mismo script, e inicia sesión en Drive. | Inicia sesión sin el error «app no verificada / acceso bloqueado». | |

## 6. Rendimiento en tu celular
| # | Observa | Referencia | Lo que viste |
|---|---|---|---|
| 6.1 | Cuánto tarda en guardarse la contraseña de copias (paso 4.2). | De 0,2 a 1 s en el emulador; en un celular de gama media, algo más. | |
| 6.2 | Si la app va fluida al moverte entre pestañas. | Sin saltos visibles. | |

Si algo no pasa, copia el mensaje o haz una captura: con eso se corrige y se vuelve a probar.
