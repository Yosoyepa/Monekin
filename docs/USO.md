# Finanzas IA: guía de uso

Esta guía es para cualquier persona que instale **Finanzas IA** en su celular Android. No necesitas saber de programación.

Finanzas IA es Monekin con funciones de inteligencia artificial (IA). Tus datos se guardan en el celular. Solo la IA y la copia en Google Drive usan internet.

Si un texto de la app es distinto al de esta guía, avisa a la persona que te dio la app.

## Qué necesitas

- Un celular Android.
- Para leer recibos, extractos y avisos del banco, y para las recomendaciones y la recategorización: una key gratis de Google Gemini, u otro proveedor de IA (sección 3).
- Para la copia en Google Drive: una cuenta de Google (opcional).

Sin IA ni Google la app también funciona: creas cuentas, registras movimientos a mano, importas extractos con columnas conocidas y haces copias locales.

---

## 1. Instalar la app

### Instalar por cable (recomendado)

Lo hacen dos personas: la persona dueña del celular y quien administra la app, que tiene el PC con el cable. La depuración USB deja que el PC instale apps en tu celular. Los nombres cambian según el celular.

Tú, en tu celular:

1. Activa las opciones de desarrollador: toca 7 veces **Número de compilación**. Suele estar en **Información del teléfono**, dentro de **Ajustes**.
2. Activa **Depuración USB** en las opciones de desarrollador y conecta el cable al PC. Si aparece un aviso con una huella, acepta solo si es el PC de quien administra la app y lo tienes delante.

Quien administra la app:

3. Instala la app o actualízala desde su PC.

Tú, al terminar:

4. **Apaga la Depuración USB** y toca **Revocar autorizaciones de depuración USB**. Si la dejas encendida, otra persona con acceso físico a tu celular y un PC autorizado podría leerlo.

Las actualizaciones por cable conservan tus datos. Nunca instales un APK de Finanzas IA que no venga de quien administra la app.

### Instalar el archivo APK (segunda opción)

1. Pide a la persona que te comparte la app el archivo `FinanzasIA-arm64.apk`. Sirve para casi todos los celulares Android de los últimos años.
2. Abre el archivo desde la app de archivos o de descargas de tu celular.
3. Si Android dice que no puede instalar apps de fuentes desconocidas, permítelo para la app con la que abriste el archivo (por ejemplo, Archivos, Drive, WhatsApp o Chrome). Los nombres de los menús cambian según el celular.
4. Toca **Instalar**.
5. Si aparece **Play Protect**, sigue la sección de abajo.
6. Abre **Finanzas IA**. Se instala aparte de Monekin: puedes tener las dos y sus datos no se mezclan.
7. En el primer uso, sigue la introducción de la app y crea tu primera cuenta (sección 2).

### Si aparece Play Protect

**Play Protect** es el sistema de seguridad de Google para las apps. Pasa porque la app no viene de una tienda y pide acceso a tus notificaciones, que es un permiso delicado. Los textos cambian según el celular.

- **Si pregunta si quieres analizar la app:** acepta. El análisis envía a Google el archivo de la app, no tus datos.
- **Si dice que la app no es segura o que está bloqueada:** toca **Más detalles** y luego **Instalar de todas formas**.
- **Si no te deja instalarla y no hay ninguna opción:** pausa Play Protect, instala la app y vuelve a activarlo.
  1. Abre **Google Play Store**, toca tu foto o tu inicial (arriba a la derecha) y entra en **Play Protect**.
  2. Toca el icono de ajustes y apaga **Analizar apps con Play Protect**.
  3. Vuelve al archivo y toca **Instalar**.
  4. Cuando la app esté instalada, vuelve a esos ajustes y enciende **Analizar apps con Play Protect**. No dejes esa opción apagada.

### Actualizar la app

Instala el archivo nuevo encima de la app que ya tienes. Tus datos se conservan, porque la versión nueva viene firmada igual que la anterior.

---

## 2. Crear cuentas y fijar el saldo inicial

**Regla importante:** la app no crea movimientos con fecha anterior a la **fecha de apertura** de su cuenta. Por eso, pon una fecha de apertura anterior al primer recibo, extracto o aviso que vas a registrar.

Crear una cuenta:

1. Toca **Crear cuenta** en **Inicio** o en la lista de cuentas.
2. Escribe el **Nombre de la cuenta**.
3. Escribe el **Balance inicial**: el saldo con el que empiezas.
4. En **Fecha de apertura \***, elige una fecha anterior a tus primeros movimientos. Por ejemplo, el 1 de enero del año en que empezaste a usar tus cuentas.
5. Toca **Crear cuenta** para guardar.

Cambiar la fecha de una cuenta que ya creaste:

1. Abre la cuenta y entra en su edición (el formulario se titula **Editar cuenta**).
2. Cambia **Fecha de apertura** por una fecha anterior.
3. Guarda.

Si un movimiento tiene fecha anterior a la fecha de apertura, la revisión muestra el aviso «No puedes crear una transacción cuya fecha es anterior a la fecha de creación de la cuenta a la que pertenece». Esa fila no se crea.

### El interruptor «Alcancía (solo transferencias)»

Este interruptor está en el formulario de la cuenta. Significa que la cuenta **solo admite transferencias**: no recibe gastos ni ingresos. Nequi, Daviplata y tus cuentas de ahorros sí reciben gastos e ingresos normales, así que el interruptor debe estar apagado en ellas.

- Al crear Nequi, Daviplata o tu cuenta de ahorros del banco, deja **apagado** «Alcancía (solo transferencias)». Enciéndelo solo para dinero que apartas.
- Si ya lo encendiste:
  1. Ve a **Cuentas**, abre la cuenta y entra en **Editar cuenta**.
  2. Apaga **Alcancía (solo transferencias)** y guarda.
- En la **Bandeja IA** también puedes tocar la cuenta y elegir **Quitar la marca y elegirla**. Si la cuenta sale con el texto «Alcancía: solo admite transferencias», tiene la marca.

---

## 3. La key de IA

La **key** (API key) es una clave personal que te da el proveedor de IA. No la compartas con nadie.

### Conseguir la key gratis de Gemini

1. Abre `https://aistudio.google.com/apikey` en tu navegador y entra con tu cuenta de Google.
2. Crea una API key y cópiala completa.

### Ponerla en la app

1. Toca **Más**, luego **Ajustes y Personalización** y luego **Inteligencia artificial**.
2. En **Proveedor**, deja **Gemini**. La **URL base** y el **Modelo** se llenan solos.
3. En **API key**, toca el icono de pegar.
4. Toca **Guardar**.
5. Toca **Probar conexión**. Si aparece **Conexión correcta**, ya puedes usar la IA.

**Probar conexión** guarda antes lo que escribiste en la pantalla.

### Otros proveedores

En **Proveedor**, elige:

- **DeepSeek**: el modelo viene por defecto.
- **OpenRouter**: elige un modelo con el icono de lupa (**Elegir modelo**) antes de probar.
- **Personalizado**: escribe la **URL base** y el **Modelo** de otro servicio compatible con OpenAI. Si no sabes cuál usar, pregunta a tu responsable.

### Qué cuesta

- **Gemini** tiene un plan gratis con un cupo diario. Si se agota, la app lo dice. Espera al día siguiente o cambia de proveedor.
- **DeepSeek** es de pago y muy económico. Revisa la tarifa actual en su web.
- Cada petición a la IA gasta cupo: una recomendación, un resumen semanal o un lote de 50 transacciones al recategorizar.

### Privacidad

- En el plan gratis de Gemini, Google puede usar tus datos para mejorar sus productos. DeepSeek procesa los datos en servidores de China.
- La app envía a la IA solo lo que cada función necesita:
  - **Recibos**: la foto del recibo.
  - **Avisos del banco**: el texto del aviso, solo si ninguna plantilla lo reconoce.
  - **Extractos**: el texto de los PDF y de los formatos que la app no reconoce.
  - **Recomendaciones y resumen semanal**: solo totales del periodo, la variación, los nombres y totales de tus categorías principales, y cuántos gastos recurrentes y atípicos hay. No envía movimientos individuales ni títulos.
  - **Recategorizar**: los títulos y los montos de las transacciones que revisas, y tus categorías y cuentas (nombres, identificadores, moneda y los últimos 4 dígitos de tus tarjetas).
- La key se guarda en el almacenamiento seguro de tu celular. No va a la base de datos, ni a las copias, ni al CSV.

Para quitar la key, toca **Borrar key** en la misma pantalla.

---

## 4. Mapa de tarjetas

Sirve para que la app sepa a qué cuenta pertenece cada tarjeta. Usa solo los últimos 4 dígitos; nunca guarda el número completo.

1. Toca **Más**, luego **Ajustes y Personalización** y luego **Tarjetas y cuentas**.
2. Toca **Añadir tarjeta**.
3. Escribe los **Últimos 4 dígitos** (exactamente 4).
4. Elige la cuenta.
5. Guarda.

Para quitar una tarjeta, toca su icono de basura. Cuando un recibo o un aviso muestra esos 4 dígitos, la app propone esa cuenta.

---

## 5. Recibos con la cámara

Necesitas la IA configurada (sección 3). Si no la tienes, la app te ofrece **Abrir ajustes de IA**.

Registrar un recibo (dos toques y la foto):

1. En **Inicio** o en **Transacciones**, toca el botón de cámara **Escanear recibo**. Está encima del botón de nueva transacción.
2. Toma la foto. Si cancelas la cámara, toca **Elegir fotos de la galería** y elige una o varias.
3. Espera a que termine **Leyendo recibo…**.
4. Se abre la revisión con el comercio, el total, la fecha, la categoría y la cuenta propuestos.
5. Revisa y toca **Confirmar**.

Qué debes saber:

- La app solo propone un gasto. No lo guarda hasta que confirmes.
- Si no lee un dato, la revisión lo avisa: «No se leyó la fecha; se usó hoy», «No se leyó el comercio» o «No se leyó el total. Agrega la transacción a mano».
- Si la IA falla (por ejemplo, sin conexión o con el cupo agotado), el recibo queda en la **Bandeja IA** con el motivo. Abre el elemento, toca **Añadir transacción** y escribe los datos.
- Al confirmar, la foto queda adjunta a la transacción. La ves en su detalle.
- Si no propone una categoría, la pantalla te pide elegir una: «Elige una categoría».

---

## 6. Bandeja IA: revisar, confirmar y descartar

La **Bandeja IA** reúne lo que proponen los recibos, los extractos y los avisos del banco. **Ningún elemento crea transacciones hasta que tú confirmas.**

Para entrar, toca **Más** y luego **Bandeja IA**. Tiene tres pestañas: **Pendientes** (con un número), **Procesados** y **Descartados**.

Revisar y confirmar:

1. Toca un elemento de **Pendientes**.
2. Arriba ves el origen (**Recibo**, **Extracto** o **Aviso del banco**), la referencia y, si existe, la foto o el texto original.
3. Revisa cada fila: **Gasto** o **Ingreso**, **Título**, **Monto**, fecha, **Categoría** y **Cuenta**.
4. Si falta la categoría o la cuenta, la fila dice **Elige una categoría** o **Elige una cuenta**. Toca la fila y elige.
5. Para quitar una fila, toca su icono de basura. Para añadir una, toca **Añadir transacción**.
6. Toca **Confirmar**.

Después de confirmar, verás un **Resultado** con tres números:

- **Creadas**: transacciones guardadas.
- **Omitidas por duplicadas**: filas que ya tenías.
- **Filas por corregir**: filas con un error. El elemento sigue en **Pendientes**. Corrige esas filas y vuelve a confirmar. Lo que ya se creó no se repite.

Si una fila parece repetida, aparece **Parece un duplicado**. Si es el mismo movimiento, quítala con el icono de basura. Marca **Crear de todos modos** solo si es otro movimiento.

Para descartar un elemento entero, toca **Descartar**. Pasa a **Descartados**.

Cada transacción creada así lleva la etiqueta **ia** y, en sus notas, dice de dónde viene: recibo, extracto o aviso.

---

## 7. Extractos del banco

Un extracto es el archivo con los movimientos de tu cuenta bancaria. Puede ser CSV, TXT o PDF. Descárgalo desde la app de tu banco.

1. Toca **Más** y luego **Importar extracto**.
2. Toca **Elegir CSV, TXT o PDF** y elige el archivo.
3. Revisa la **Etiqueta del extracto**. La app pone el nombre del archivo; puedes cambiarlo.
4. En **Cuenta de destino**, elige la cuenta.
5. Toca **Importar y revisar**. Se abre la revisión de la Bandeja IA. Elige la categoría de cada fila y toca **Confirmar** (sección 6).

Cómo lee la app el archivo:

- CSV o TXT con columnas de **Fecha**, **Descripción** (o **Concepto** o **Detalle**) y **Valor** (o **Monto** o **Importe**), o con **Débito** y **Crédito**: el celular lo lee solo. No necesita IA.
- Cualquier otro formato, y todos los PDF: el texto se envía a la IA. Necesitas la IA configurada.

Conciliación (comprobar el saldo):

- Si el extracto trae el saldo inicial y el saldo final, la revisión muestra «Neto: …; diferencia de conciliación: …». Si la diferencia es 0,00, las filas cuadran con el banco. Si no, revisa filas que falten o estén repetidas.
- Si no encuentra los dos saldos, la revisión dice «Conciliación no disponible: no se encontró el saldo inicial o final».

Si importas otra vez el mismo extracto, la app omite lo que ya tienes. Un movimiento se considera repetido si tiene la misma cuenta, el mismo monto, una fecha con un día de diferencia como máximo y un título parecido.

---

## 8. Avisos del banco y recordatorios

Para entrar, toca **Más**, luego **Ajustes y Personalización** y luego **Avisos del banco y recordatorios**.

### Leer los avisos del banco

1. Activa **Leer avisos del banco**.
2. Acepta el permiso para mostrar notificaciones.
3. Android te lleva a la lista de acceso a notificaciones. Activa **Finanzas IA** y vuelve a la app.
4. Si ves «No se dio el acceso. Activa Finanzas IA en la lista de acceso a notificaciones y vuelve.», activa la app en esa lista y toca **Dar acceso**.
5. Si el interruptor sale bloqueado o dice **Ajuste restringido**, haz esto:
   1. Toca **Abrir información de la app**.
   2. Toca ⋮ (arriba a la derecha) y luego **Permitir ajustes restringidos**. Confirma con tu PIN o tu huella.
   3. Vuelve aquí y toca **Dar acceso**.

   La opción ⋮ aparece solo después de haber intentado dar el acceso una vez. Los nombres cambian según el celular.

Si tocaste **Leer avisos del banco** y te faltó el acceso, al volver a la app con el acceso dado la lectura se activa sola. La tarjeta de ayuda desaparece.

### Elegir los bancos (Apps vigiladas)

- Vienen marcadas: Bancolombia, Bancolombia (app anterior), Nequi, Davivienda, Daviplata, Nu, BBVA y Banco de Bogotá.
- **Mensajes (SMS)** viene sin marcar. Márcala solo si tu banco te avisa por SMS.
- Para otra app, toca **Añadir app** y escribe su nombre de paquete (por ejemplo, `com.banco.app`). Si no lo sabes, pídelo a tu responsable.

### Qué pasa con cada aviso

- Compra, pago, transferencia, retiro o abono que la app entiende en el propio teléfono (por una plantilla de tu banco o por las palabras que usan todos los bancos: «compra», «pagaste», «retiro», «recibiste», «abono»...): la app crea una propuesta en la Bandeja IA y te avisa con «Nuevo gasto detectado» o «Nuevo ingreso detectado». Toca el aviso para revisarlo. Esto no usa la IA.
- Si la app no lo entiende y el interruptor **Usar la IA con los avisos que la app no entiende** está activado (viene apagado), la IA lo interpreta. Si dice que no es un movimiento (una promoción, un código, un saldo o una alerta de seguridad), la app lo ignora.
- Nada lo reconoce (o el interruptor está apagado): queda en la Bandeja como **Aviso del banco por revisar**, con el texto original. Escribe la transacción a mano.
- El mismo aviso no se registra dos veces.
- Nada entra a tus transacciones sin que lo confirmes en la Bandeja.

### Usar la IA con los avisos que la app no entiende

Por defecto los avisos se leen solo en tu teléfono y no se envía nada a ninguna IA. Si activas **Usar la IA con los avisos que la app no entiende**, los avisos que la app no logra leer se mandan a tu proveedor de IA, pero antes se reduce el texto:

- **Se envía:** la frase del movimiento (por ejemplo, «Compra por $45.900 en TIENDA»), con el monto y la fecha tal cual.
- **No se envía:** las frases de saldo, saldo disponible o cupo, ni ningún otro número (cuenta, tarjeta, teléfono, documento, hora). Esos números salen como `****`.
- Al no mandar los dígitos de la tarjeta, la propuesta que arma la IA no trae cuenta: elígela tú al revisarla.
- Para apagarlo, desactiva el interruptor. El cambio vale desde el siguiente aviso.

### Recordatorios y alertas

- **Recordatorio diario**: actívalo y elige la hora en **Hora del recordatorio**. Viene a las 20:00 y dice «Registra tus gastos».
- **Alertas de presupuesto**: vienen activadas. Te avisan al llegar al 80 % y al 100 % de un presupuesto. Para que funcionen, crea presupuestos en **Más** y luego **Presupuestos**. El aviso dice solo «Revisa tus presupuestos»: ni el nombre del presupuesto ni el porcentaje salen en la pantalla de bloqueo.
- **Resumen semanal**: si lo activas, el lunes a partir de las 9:00 recibes el aviso «Tu resumen semanal está listo». Las cifras de lo que gastaste y la recomendación no salen en la notificación, para que no se vean en la pantalla de bloqueo. Si no gastaste nada en los últimos 7 días, no te avisa. La app revisa cada 12 horas, así que el aviso puede llegar un poco después de las 9:00.

---

## 9. Análisis con IA y recategorización

Para entrar, toca **Más** y luego **Análisis con IA**.

### Ver tus gastos

Elige el periodo arriba: **Este mes**, **Mes anterior** o **Elegir fechas** (un rango de días hasta hoy).

- El importe grande es lo que gastaste en el periodo, en tu moneda principal. Solo cuentan los gastos ya registrados: no entran los pendientes ni las transferencias.
- Debajo aparece cuánto cambió frente al periodo anterior de la misma duración. Si el periodo anterior no tuvo gastos, dice «Sin gastos en el periodo anterior».
- **Categorías principales**: las 5 categorías que más pesan, con su importe y una barra con su porcentaje del total.
- **Gastos recurrentes**: títulos que aparecen en al menos dos meses distintos, mirando el periodo y los meses anteriores. Indica en cuántos meses aparecen.
- **Gastos inusuales**: gastos del periodo que superan el doble del promedio de su categoría.
- Si no hay gastos en el periodo, la pantalla solo muestra «No hay gastos en este periodo». Las secciones de gastos recurrentes e inusuales solo aparecen cuando hay algo que mostrar.

### Recomendaciones

Toca **Pedir recomendaciones**. La IA escribe tres recomendaciones en el idioma de la app, a partir de los totales y las categorías, no de tus movimientos. Quedan guardadas con su fecha hasta que pidas otras, y siguen ahí al volver a abrir la app.

- Sin proveedor de IA, la pantalla dice «Configura un proveedor de IA en los ajustes de IA para pedir recomendaciones».
- Si la IA falla, dice «La IA no pudo responder. Inténtalo más tarde.».

### Recategorizar

Desde **Análisis con IA**, toca **Recategorizar transacciones**. La IA propone una categoría para cada transacción, pero nada cambia hasta que lo confirmes.

1. Filtra la lista: elige el periodo, una categoría (**Todas** o un chip de categoría), o busca por título en **Buscar por título**. La lista incluye gastos e ingresos, también los pendientes.
2. Toca **Proponer categorías**. La app envía a la IA los títulos y los montos, en lotes de 50, junto con tus categorías y cuentas. Si no tienes proveedor de IA, la pantalla te avisa.
3. Revisa la lista. Cada transacción muestra la categoría propuesta (**→ Categoría**). Las que tienen propuesta vienen marcadas. **Sin propuesta** significa que la IA no encontró categoría, y su casilla queda desactivada.
4. Desmarca lo que no quieras y toca **Aplicar seleccionadas**. La app cambia solo la categoría: el título, la fecha y el monto no cambian. Verás «N transacciones actualizadas».

---

## 10. Copia en Google Drive

Requisito: el responsable de la app configuró el inicio de sesión con Google. Si no lo hizo, la página dice «Google no está configurado en esta versión de la app». La app funciona igual; usa la copia local (sección 11).

**Las copias van cifradas.** Se cifran en el teléfono antes de subirlas, con una contraseña que eliges tú. En Drive solo queda un archivo ilegible. **Si olvidas la contraseña, esas copias no se pueden restaurar: nadie, ni el desarrollador, puede recuperarlas.** Anótala en un lugar seguro.

1. Toca **Más**, luego **Ajustes y Personalización**, luego **Datos** y luego **Copia en Google Drive**.
2. Toca **Iniciar sesión con Google**, elige tu cuenta y acepta el permiso de Drive. Iniciar sesión es opcional.
3. La primera vez que copias o activas la copia diaria, la app pide **Crear contraseña de copias**: al menos 10 caracteres, escrita dos veces, con un indicador de fuerza. Lee la advertencia y toca **Guardar contraseña**. La app guarda en el teléfono solo una clave derivada de la contraseña, nunca la contraseña, para que la copia diaria siga funcionando sin pedírtela.
4. Toca **Copiar ahora**. Aparece «Copia guardada en tu Drive».
5. La copia incluye tus datos y las fotos de los recibos. La app guarda las 5 copias más recientes y borra las anteriores. Se guardan en una carpeta oculta de tu Drive que solo usa esta app.
6. Para volver a una copia, toca **Restaurar**, elige la fecha y hora, y confirma. **Tus datos actuales se reemplazarán por la copia elegida.** Antes de restaurar, toca **Copiar ahora** para no perder lo último que registraste.
7. Si la copia se hizo con la contraseña actual, se abre sola. Si se hizo con una anterior (o en otro teléfono), la app pide la contraseña con la que se hizo; si la escribes mal, lo dice y puedes intentarlo otra vez sin que se toque nada.
8. Al terminar, aparece «Copia restaurada». Toca **Cerrar la app** y vuelve a abrirla para ver tus datos.
9. **Copia diaria**: actívala para que la app guarde una copia cada día.
10. **Cambiar contraseña de copias**: las copias nuevas usan la contraseña nueva. **Las copias que ya hiciste siguen pidiendo la contraseña anterior**, así que no la pierdas mientras quieras poder restaurarlas.
11. **Cerrar sesión** desactiva la copia diaria.

Si la copia está dañada, fue modificada o está incompleta, la app no la restaura, dice por qué y tus datos no cambian. Lo mismo si la hizo una versión más nueva de la app. Las copias antiguas sin cifrar (de antes de esta versión) todavía se restauran, con un aviso de que cualquiera con acceso a tu cuenta de Google podría leerlas; las copias nuevas sí van cifradas. Sin contraseña creada, la app no sube nada.

Detalle técnico: formato `FIA3`, AES-256-GCM por bloques de 1 MiB (detecta cambios, bloques reordenados y archivos cortados) y clave derivada con Argon2id (19 MiB de memoria, 2 iteraciones, 1 hilo). Esos parámetros viajan en la cabecera de cada copia y la restauración los usa. Tiempo medido en el PC de desarrollo: unos 100 a 190 ms; en el teléfono puede tardar más.

---

## 11. Copia local (sin Google)

La copia local usa el mismo formato cifrado y la misma contraseña de copias que Drive. Aplica la misma advertencia: **si la olvidas, la copia no se puede restaurar.**

Guardar una copia:

1. Toca **Más**, luego **Ajustes y Personalización**, luego **Datos** y luego **Exportar datos**.
2. En **Tipo de exportación**, elige **Respaldo total**. Así sale un archivo `.fia` cifrado con toda la base de datos de Monekin (cuentas, transacciones, presupuestos y lo demás) **y las fotos de los recibos**. Si todavía no tienes contraseña de copias, la app la pide aquí.
3. Toca **Descargar** (guardar en una carpeta) o **Compartir** (correo, Drive u otra app).

Restaurar una copia:

1. Toca **Más**, luego **Ajustes y Personalización**, luego **Datos** y luego **Restaurar copia de seguridad**.
2. Confirma el aviso y elige el archivo `.fia` (o un `.db` antiguo). Si es un `.fia`, la app pide la contraseña con la que se hizo; con una contraseña equivocada o un archivo alterado no se toca nada. Al terminar, toca **Cerrar la app** y ábrela de nuevo.
3. Un `.db` antiguo, sin cifrar, se restaura como antes. Un zip antiguo sin cifrar se restaura con un aviso.

Las fotos de los recibos viajan dentro de la copia `.fia`: si la restauras en otro celular, los recibos aparecen con su foto.

---

## 12. Exportar el CSV y usar la plantilla en el PC

En el celular:

1. Toca **Más**, luego **Ajustes y Personalización**, luego **Datos** y luego **Exportar datos**.
2. En **Tipo de exportación**, elige **Respaldo de transacciones**. Así sale el CSV.
3. Si quieres solo algunas transacciones, abre **Opciones** y luego **Filtrar transacciones** antes de exportar.
4. Toca **Descargar** o **Compartir**.

En el PC:

1. Abre la plantilla `tools/plantilla/Finanzas.xlsx` del repositorio. Si no la tienes, pídela a tu responsable.
2. En la hoja **Datos**, borra las filas de ejemplo y deja el encabezado.
3. Abre tu CSV en Excel y copia las filas **sin el encabezado**. Pégalas en la hoja **Datos**, desde la celda A2. Para que se vean bien las tildes, ábrelo con **Datos → Obtener datos → Desde texto/CSV** y elige el origen **65001: Unicode (UTF-8)**.
4. Revisa que la columna **Monto (número)** muestre números.
5. Abre la hoja **Resumen**: verás ingresos, gastos y neto de cada mes, los gastos por categoría y las gráficas. Elige el mes en la celda C5.
6. Antes de confiar en los totales, compara un mes con los totales de la app.

Las transferencias y las inversiones no cuentan como ingresos ni gastos. Más detalle en `docs/plantilla.md`.

---

## 13. Problemas frecuentes

| Qué ves | Qué hacer |
|---|---|
| «Se agotó la cuota de la IA» | Gemini tiene un cupo diario. Espera al día siguiente o cambia de proveedor en **Inteligencia artificial** (dentro de **Ajustes y Personalización**). |
| «Sin conexión con el proveedor de IA» | Revisa tu internet. El recibo queda en la Bandeja: toca **Añadir transacción** y escribe los datos. |
| «La API key fue rechazada» | Copia la key de nuevo, completa y sin espacios, o crea una key nueva en AI Studio. |
| «La IA tardó demasiado en responder» | Vuelve a intentarlo más tarde, o escribe la transacción a mano. |
| **Aviso del banco por revisar** | La app no entendió el aviso. Abre el elemento en la Bandeja, lee el texto original y escribe la transacción a mano. |
| «No puedes crear una transacción cuya fecha es anterior a la fecha de creación de la cuenta…» | Cambia la fecha de la fila o la fecha de apertura de la cuenta (sección 2). |
| **Parece un duplicado** | Si es el mismo movimiento, quita esa fila. Si es otro, marca **Crear de todos modos**. |
| **Filas por corregir** | Corrige las filas marcadas (cuenta, categoría, monto o fecha) y vuelve a confirmar. |
| «Conciliación no disponible» | El extracto no trae el saldo inicial y el final. Revisa las filas a mano. |
| «No se pudo importar el extracto» | Revisa que el CSV tenga columnas de fecha, descripción y valor, o configura la IA para leerlo. |
| El inicio de sesión con Google da error | Puede que el responsable no haya configurado Google o que no aceptaras el permiso de Drive. Usa la copia local (sección 11). |
| «La IA no pudo responder. Inténtalo más tarde.» | Vuelve a intentarlo más tarde. Si el cupo se agotó, cambia de proveedor. |
| «Configura un proveedor de IA en los ajustes de IA para pedir recomendaciones» | Entra en **Inteligencia artificial** y pon tu key (sección 3). |
| «No se pudieron actualizar las transacciones» | Vuelve a abrir la pantalla, revisa las categorías y vuelve a aplicar. |
| «Esta copia está dañada y no se puede restaurar. Tus datos actuales no cambiaron.» | Elige otra copia. Tus datos siguen igual. |
| «Esta copia se hizo con una versión más nueva de la app. Actualiza la app para restaurarla. Tus datos actuales no cambiaron.» | Actualiza la app y vuelve a intentarlo. Tus datos siguen igual. |
| **Play Protect bloqueó la app** | Mira «Si aparece Play Protect» en la sección 1. Si ves **Más detalles**, tócalo y luego **Instalar de todas formas**. Si no hay ninguna opción, pausa **Analizar apps con Play Protect**, instala la app y vuelve a activarlo. |
| **Ajuste restringido** | Sigue los pasos de «Leer los avisos del banco» en la sección 8: **Abrir información de la app**, luego ⋮ y **Permitir ajustes restringidos**, y por último **Dar acceso**. |
