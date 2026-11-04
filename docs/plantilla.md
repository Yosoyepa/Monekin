# Plantilla de Finanzas: tus transacciones de Monekin en el computador

Convierte el CSV que exporta Monekin en un libro de Excel con los ingresos, los gastos y el neto de cada mes, y los gastos por categoría.

| Archivo | Para qué sirve |
|---|---|
| `tools/plantilla/Finanzas.xlsx` | La plantilla, con datos de ejemplo. |
| `tools/plantilla/ejemplo.csv` | Un CSV de ejemplo con el formato real de la exportación: datos inventados, de enero a marzo de 2026, 48 filas. |
| `tools/plantilla/generar_plantilla.py` | Genera `Finanzas.xlsx` a partir de un CSV. |
| `tools/plantilla/verificar.py` | Comprueba que los totales del libro coinciden con los que calcula Python. |

## 1. Exportar desde Monekin

Hay dos caminos:

- **Desde la lista de transacciones:** toca el icono de descarga de la barra superior (su nombre es «Exportar datos»).
- **Desde Ajustes:** Más → Ajustes y Personalización → Datos → Exportar datos.

Después:

1. En «Tipo de exportación», elige **Respaldo de transacciones**. Así sale el CSV. «Respaldo total» genera una copia de la base de datos (`.db`) y no sirve para la plantilla.
2. Si quieres solo algunas transacciones, abre «Opciones» → «Filtrar transacciones» antes de exportar.
3. Pulsa **Descargar** (guarda el archivo en la carpeta que elijas) o **Compartir** (correo, Drive u otra app).

## 2. Formato del CSV

Cabecera y orden de las columnas, según `createCsvFromTransactions` en `lib/core/database/backup/backup_database_service.dart`:

| Columna | Contenido | Ejemplo |
|---|---|---|
| `ID` | Identificador único de la transacción (UUID). Las dos filas de un traspaso tienen el mismo ID. | `24a9b529-600f-46eb-a1d6-b10c917e3f15` |
| `Amount` | Monto con signo, punto decimal y siempre dos decimales, sin separador de miles. Negativo = sale de la cuenta. | `-1200000.00` |
| `Date` | Fecha y hora locales, formato `yyyy-MM-dd HH:mm:ss` (24 horas). | `2026-01-05 09:10:00` |
| `Title` | Título. Vacío si no tiene. | `Arriendo enero` |
| `Note` | Nota. Puede tener comas, comillas o saltos de línea. | `Dijo "gracias" a la taquilla` |
| `Account` | Nombre de la cuenta. | `Cuenta de ahorros` |
| `Currency` | Código de la moneda de la cuenta. | `COP` |
| `Category` | Categoría principal. `TRANSFER` en traspasos; `INVESTMENT` en compras y ventas de inversiones; vacía si no tiene categoría. | `Hogar` |
| `Subcategory` | Subcategoría. Vacía si la categoría no tiene subcategorías. | `Alquiler` |
| `Tags` | Etiquetas separadas por `\|`. | `carro\|viaje` |

Formato del archivo:

- Separador: coma (`,`).
- Fin de línea: CRLF (`\r\n`). El archivo no termina con salto de línea.
- Codificación: UTF-8, sin BOM.
- Comillas: un campo va entre comillas dobles solo si tiene coma, salto de línea, comilla o espacio al principio o al final. Las comillas dentro del campo se duplican (`""`). Lo escribe el paquete `csv` 8.0.0 en su modo `necessary`.

Reglas de los datos:

- **Traspasos:** dos filas con el mismo ID. La fila de la cuenta de origen es negativa; la de la cuenta de destino, positiva, en la moneda de esa cuenta.
- **Inversiones:** `Category` = `INVESTMENT`. Compra = negativo; venta = positivo.
- **Lo que no trae:** el CSV no dice si una transacción está pagada o pendiente, y no incluye cuentas, presupuestos ni metas. Exporta solo las transacciones que cumplen el filtro.

Primeras filas de `tools/plantilla/ejemplo.csv`:

```
ID,Amount,Date,Title,Note,Account,Currency,Category,Subcategory,Tags
64e2dd02-3c2e-49f4-9d45-e1e98a0f5d31,3500000.00,2026-01-05 08:00:00,Salario enero,,Cuenta de ahorros,COP,Salario,,
ef330a8d-7de0-43b7-8dcb-f207b982b3cf,-1200000.00,2026-01-05 09:10:00,Arriendo enero,,Cuenta de ahorros,COP,Hogar,Alquiler,casa
24a9b529-600f-46eb-a1d6-b10c917e3f15,-300000.00,2026-01-06 10:00:00,Traspaso a billetera,,Cuenta de ahorros,COP,TRANSFER,,
24a9b529-600f-46eb-a1d6-b10c917e3f15,300000.00,2026-01-06 10:00:00,Traspaso a billetera,,Billetera digital,COP,TRANSFER,,
bdc8adcf-f29b-40d0-9c0e-2bfb7c863235,-185430.50,2026-01-07 18:30:00,"Mercado semanal, con aseo",Lista del hogar,Tarjeta de crédito,COP,Alimentación,Comestibles,hogar
```

## 3. Usar la plantilla en Excel

1. Abre `Finanzas.xlsx`. La hoja **Datos** trae 48 filas de ejemplo: bórralas antes de usar tus datos.
2. Abre el CSV de Monekin con **Datos → Obtener datos → Desde texto/CSV** (los nombres de los menús cambian según la versión de Excel). En «Origen del archivo» elige **65001: Unicode (UTF-8)** para que las tildes se vean bien.
3. En **Datos**, borra las filas de ejemplo (deja el encabezado) y pega en A2 las filas del CSV, sin el encabezado, en las columnas A a J.
4. Comprueba que la columna K («Monto (número)») muestre números.
5. Abre **Resumen**. El año (C4) toma la fecha más reciente de tus datos. El mes (C5) se elige de la lista y solo cambia el top de gastos y la gráfica de torta.

Si al pegar más filas las columnas K a O no se rellenan, copia las fórmulas de la última fila hacia abajo.

## 4. Hojas de la plantilla

### «Cómo usar»

Los pasos y las reglas en español, una línea por paso. Es la primera hoja.

### «Datos»

Tabla de Excel llamada `Transacciones` (A1:O49 con el ejemplo), con filtros en la cabecera y la fila 1 fija.

- **A a J:** las columnas del CSV, con el mismo nombre y orden, para pegar el archivo tal cual.
- **K a O (calculadas; no las pegues ni las borres):**
  - **K «Monto (número)»:** el monto como número. Acepta el texto del CSV (`-1200000.00`) o un número que Excel ya haya convertido.
  - **L «Mes»:** primer día del mes de la fecha.
  - **M «Tipo»:** `Ingreso` (monto ≥ 0), `Gasto` (monto < 0) o `Excluido` (`TRANSFER` o `INVESTMENT`).
  - **N «Categoría (resumen)»:** la categoría principal de cada gasto (`(sin categoría)` si está vacía). Vacía en el resto.
  - **O «Orden categoría»:** número de la primera aparición de cada categoría de gasto. Sirve para desempatar el top.

### «Resumen»

- **C4 «Año»:** el año de la fecha más reciente. Puedes escribir otro año.
- **C5 «Mes para el top de gastos»:** lista desplegable; por defecto, el mes más reciente.
- **C6:** inicio del mes elegido (cálculo).
- **A8:E21:** por mes del año de C4, ingresos, gastos (en positivo) y neto, con una fila de total.
- **A23:D36:** top 10 de gastos del mes elegido (categoría, gasto y porcentaje del gasto del mes), total del mes (C35), número de categorías de gasto (C36) y un aviso si hay más de 30 (D36).
- **Gráfica de barras (G8):** ingresos y gastos por mes.
- **Gráfica de torta (G25):** gastos por categoría del mes elegido.
- **R8:U38:** cálculos auxiliares. No los edites.

## 5. Reglas de cálculo

- **Ingreso:** monto ≥ 0. **Gasto:** monto < 0. Los traspasos y las inversiones no cuentan en ninguno de los dos.
- **Neto** = ingresos − gastos.
- **Mes:** el de la fecha de la transacción.
- **Top:** gastos del mes elegido agrupados por categoría principal (no por subcategoría). Solo entran categorías con gasto mayor que cero. En caso de empate, va primero la categoría que aparece antes en Datos.
- **Límites:** las fórmulas leen hasta la fila 20 001 de Datos (20 000 transacciones) y hasta 30 categorías de gasto distintas.

## 6. Verificación

`verificar.py` calcula en Python el año, los ingresos, gastos y neto de cada mes, el total del mes elegido y el top 10, con las mismas reglas. Después compara esos valores con los que calcula el libro:

- con LibreOffice en modo headless, si `soffice` está instalado;
- si no, con el motor de fórmulas `formulas`.

Para ejecutarlo, desde la raíz del repositorio:

```
D:\Dev\venvs\plantilla\Scripts\python.exe tools\plantilla\verificar.py
```

Requiere `openpyxl` y `formulas` en el venv (`pip install openpyxl formulas`). Sale con código 0 si todo coincide y con 1 si hay alguna diferencia. Con el ejemplo hace 75 comprobaciones.

Cómo se ha verificado la plantilla en este repositorio:

- Con `formulas` 1.3.4, el libro se calcula sin errores; los totales por mes y el top de marzo coinciden con el CSV.
- Con `Amount` y `Date` pegados como texto, los resultados son los mismos.
- Con un monto cambiado a propósito en una copia, `verificar.py` da diferencias y sale con código 1.
- No se ha abierto en Excel ni en LibreOffice.

## 7. Límites y pendientes

- **Excel y LibreOffice:** el libro no se ha abierto en ninguno de los dos, y las gráficas no se han visto.
- **Exportación real:** el ejemplo sigue el formato del código de la app, pero no se ha probado con una exportación de un teléfono. Antes de confiar en la plantilla, compara un mes con los totales de la app.
- **Pagado o pendiente:** el CSV no lo indica; la plantilla suma todo lo exportado.
- **Traspasos e inversiones:** no cuentan como ingresos ni gastos.
- **Formato COP:** la plantilla usa `"$ "#,##0`. Con la configuración de Colombia se ve como `$ 1.234.567`.
- **Otras aplicaciones:** fuera de Excel, las fórmulas de K a O hay que copiarlas hacia abajo al pegar más filas.

## 8. Regenerar la plantilla

```
D:\Dev\venvs\plantilla\Scripts\python.exe tools\plantilla\generar_plantilla.py [ruta_del_csv]
```

Sin argumento usa `tools\plantilla\ejemplo.csv`. Requiere `openpyxl`.
