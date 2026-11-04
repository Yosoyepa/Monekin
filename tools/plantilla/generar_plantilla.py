"""Genera Finanzas.xlsx (hojas «Cómo usar», «Datos» y «Resumen») a partir del CSV de Monekin.

Uso: python generar_plantilla.py [ruta_del_csv]
Sin argumento lee ejemplo.csv de esta carpeta. Requiere openpyxl.
"""

import csv
import sys
from datetime import datetime
from pathlib import Path

from openpyxl import Workbook
from openpyxl.chart import BarChart, PieChart, Reference
from openpyxl.chart.label import DataLabelList
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter
from openpyxl.workbook.properties import CalcProperties
from openpyxl.worksheet.datavalidation import DataValidation
from openpyxl.worksheet.filters import AutoFilter
from openpyxl.worksheet.table import Table, TableColumn, TableFormula, TableStyleInfo

CARPETA = Path(__file__).resolve().parent
SALIDA = CARPETA / 'Finanzas.xlsx'
CSV_COLUMNAS = ['ID', 'Amount', 'Date', 'Title', 'Note', 'Account', 'Currency', 'Category', 'Subcategory', 'Tags']
CALC_COLUMNAS = ['Monto (número)', 'Mes', 'Tipo', 'Categoría (resumen)', 'Orden categoría']
MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']
ULTIMA = 20001  # última fila que leen las fórmulas de Resumen: 20 000 filas de datos
TOP = 10  # filas del top de gastos
SLOTS = 30  # categorías de gasto distintas que caben en el cálculo
COP = '"$ "#,##0;-"$ "#,##0'
COP_CENT = '"$ "#,##0.00;-"$ "#,##0.00'
FECHA = 'dd/mm/yyyy hh:mm'
AZUL = PatternFill('solid', fgColor='1F4E79')
AMARILLO = PatternFill('solid', fgColor='FFF2CC')
BLANCO = Font(bold=True, color='FFFFFF')
TITULO = Font(bold=True, size=16)
SUBTITULO = Font(bold=True, size=12)
AUXILIAR = Font(color='808080')


def rango(columna):
    return f'Datos!${columna}$2:${columna}${ULTIMA}'


def aux(columna):
    return f'${columna}$9:${columna}${8 + SLOTS}'


def formulas_fila(r):
    """Columnas calculadas K:O de la fila r de Datos, sin el signo '='."""
    return {
        'K': f'IF(ISNUMBER(B{r}),B{r},IFERROR(VALUE(SUBSTITUTE(B{r},".",MID(1/2,2,1))),""))',
        'L': f'IF(K{r}="","",IF(ISNUMBER(C{r}),DATE(YEAR(C{r}),MONTH(C{r}),1),IFERROR(DATE(VALUE(LEFT(C{r},4)),VALUE(MID(C{r},6,2)),1),"")))',
        'M': f'IF(K{r}="","",IF(OR(H{r}="TRANSFER",H{r}="INVESTMENT"),"Excluido",IF(K{r}<0,"Gasto","Ingreso")))',
        'N': f'IF(M{r}="Gasto",IF(H{r}="","(sin categoría)",H{r}),"")',
        'O': f'IF(N{r}="","",IF(COUNTIF(N$2:N{r},N{r})=1,MAX(O$1:O{r - 1})+1,""))',
    }


def leer_csv(ruta):
    with open(ruta, newline='', encoding='utf-8') as archivo:
        filas = list(csv.reader(archivo))
    if filas[0] != CSV_COLUMNAS:
        raise SystemExit(f'El encabezado de {ruta} no coincide con el CSV de Monekin: {filas[0]}')
    return filas[1:]


def encabezado(ws, fila, columna, textos):
    for i, texto in enumerate(textos):
        celda = ws.cell(row=fila, column=columna + i, value=texto)
        celda.font = BLANCO
        celda.fill = AZUL
        celda.alignment = Alignment(wrap_text=True, vertical='center')


def hoja_como_usar(ws, total_filas):
    ws.column_dimensions['A'].width = 120
    lineas = [
        ('Finanzas: tus datos de Monekin en el computador', TITULO),
        ('Lee el CSV que exporta Monekin y calcula ingresos, gastos y neto por mes, y los gastos por categoría.', None),
        ('', None),
        ('Cómo usar', SUBTITULO),
        ('1. Exporta desde Monekin: en la lista de transacciones toca el icono de descarga («Exportar datos»), elige «Respaldo de transacciones» y pulsa «Descargar» o «Compartir». Obtienes un archivo .csv.', None),
        ('2. Pasa ese archivo al computador (correo, Drive, cable USB u otra app).', None),
        ('3. En Excel, abre el CSV con Datos → Obtener datos → Desde texto/CSV. En «Origen del archivo» elige 65001: Unicode (UTF-8) para que las tildes se vean bien. Las etiquetas pueden variar según la versión de Excel.', None),
        ('4. En la hoja Datos, borra las filas de ejemplo (deja solo el encabezado) y pega en A2 las filas del CSV, sin el encabezado, en las columnas A a J.', None),
        ('5. Comprueba que la columna K («Monto (número)») muestre números. Las columnas K a O son fórmulas: no las pegues ni las borres.', None),
        ('6. Abre la hoja Resumen. El año (C4) y el mes (C5) se calculan con tus datos; para cambiarlos, escribe el año o elige el mes de la lista. El mes solo afecta al top de gastos y a la gráfica de torta.', None),
        ('', None),
        ('Reglas de cálculo', SUBTITULO),
        ('• Lo que entra a una cuenta es ingreso (monto positivo); lo que sale es gasto (monto negativo).', None),
        ('• Los traspasos y las inversiones (categorías TRANSFER e INVESTMENT) no cuentan como ingresos ni gastos.', None),
        ('• El CSV no indica si una transacción está pagada o pendiente: la plantilla suma todo lo exportado.', None),
        ('• Capacidad: hasta 20 000 filas de transacciones y 30 categorías de gasto distintas.', None),
        ('', None),
        ('Datos de ejemplo', SUBTITULO),
        (f'La hoja Datos trae {total_filas} filas inventadas de enero a marzo de 2026 para que veas cómo funciona. Bórralas antes de usar tus datos.', None),
    ]
    for r, (texto, fuente) in enumerate(lineas, start=1):
        celda = ws.cell(row=r, column=1, value=texto or None)
        celda.alignment = Alignment(wrap_text=True, vertical='top')
        if fuente:
            celda.font = fuente


def hoja_datos(wb, filas):
    ws = wb.create_sheet('Datos')
    ws.append(CSV_COLUMNAS + CALC_COLUMNAS)
    for id_, monto, fecha, titulo, nota, cuenta, moneda, categoria, sub, etiquetas in filas:
        ws.append([
            id_,
            float(monto),
            datetime.strptime(fecha, '%Y-%m-%d %H:%M:%S'),
            titulo or None,
            nota or None,
            cuenta or None,
            moneda or None,
            categoria or None,
            sub or None,
            etiquetas or None,
        ])

    ultima = len(filas) + 1
    for r in range(2, ultima + 1):
        for letra, formula in formulas_fila(r).items():
            ws[f'{letra}{r}'] = '=' + formula
        ws[f'B{r}'].number_format = COP_CENT
        ws[f'C{r}'].number_format = FECHA
        ws[f'K{r}'].number_format = COP_CENT
        ws[f'L{r}'].number_format = 'mmm yyyy'

    columnas = []
    for i, nombre in enumerate(CSV_COLUMNAS + CALC_COLUMNAS, start=1):
        columna = TableColumn(id=i, name=nombre)
        if i > len(CSV_COLUMNAS):
            columna.calculatedColumnFormula = TableFormula(attr_text=formulas_fila(2)[get_column_letter(i)])
        columnas.append(columna)
    tabla = Table(displayName='Transacciones', ref=f'A1:O{ultima}', tableColumns=columnas, autoFilter=AutoFilter(ref=f'A1:O{ultima}'))
    tabla.tableStyleInfo = TableStyleInfo(name='TableStyleMedium2', showRowStripes=True)
    ws.add_table(tabla)

    anchos = [38, 16, 18, 32, 30, 22, 10, 22, 24, 22, 18, 13, 12, 24, 16]
    for i, ancho in enumerate(anchos, start=1):
        ws.column_dimensions[get_column_letter(i)].width = ancho
    ws.freeze_panes = 'A2'


def hoja_resumen(wb):
    ws = wb.create_sheet('Resumen')
    ws['A1'] = 'Resumen de finanzas'
    ws['A1'].font = TITULO
    ws['A2'] = 'Se calcula solo desde la hoja Datos. Cambia únicamente las celdas amarillas (año y mes).'

    ws['A4'] = 'Año'
    ws['C4'] = f'=IF(COUNT({rango("L")})=0,YEAR(TODAY()),YEAR(MAX({rango("L")})))'
    ws['A5'] = 'Mes para el top de gastos'
    ws['C5'] = f'=IF(COUNT({rango("L")})=0,"Enero",INDEX($A$9:$A$20,MONTH(MAX({rango("L")}))))'
    ws['A6'] = 'Inicio del mes elegido (cálculo)'
    ws['C6'] = '=IFERROR(DATE($C$4,MATCH($C$5,$A$9:$A$20,0),1),DATE($C$4,1,1))'
    ws['C4'].fill = AMARILLO
    ws['C5'].fill = AMARILLO
    ws['C6'].number_format = 'mmmm yyyy'

    encabezado(ws, 8, 1, ['Mes', 'Inicio', 'Ingresos', 'Gastos', 'Neto'])
    for m, nombre in enumerate(MESES, start=1):
        r = 8 + m
        ws[f'A{r}'] = nombre
        ws[f'B{r}'] = f'=DATE($C$4,{m},1)'
        ws[f'C{r}'] = f'=SUMIFS({rango("K")},{rango("L")},$B{r},{rango("M")},"Ingreso")'
        ws[f'D{r}'] = f'=-SUMIFS({rango("K")},{rango("L")},$B{r},{rango("M")},"Gasto")'
        ws[f'E{r}'] = f'=C{r}-D{r}'
        ws[f'B{r}'].number_format = 'mmm yyyy'
    ws['A21'] = 'Total'
    for letra in 'CDE':
        ws[f'{letra}21'] = f'=SUM({letra}9:{letra}20)'
    for r in range(9, 22):
        for letra in 'CDE':
            ws[f'{letra}{r}'].number_format = COP

    ws['A23'] = '="Top de gastos de "&$C$5&" "&$C$4'
    ws['A23'].font = SUBTITULO
    encabezado(ws, 24, 1, ['Puesto', 'Categoría', 'Gasto', '% del gasto del mes'])
    for n in range(1, TOP + 1):
        r = 24 + n
        pos = f'MATCH(LARGE({aux("U")},A{r}),{aux("U")},0)'
        ws[f'A{r}'] = n
        ws[f'C{r}'] = f'=IF(LARGE({aux("U")},A{r})<=0,"",INDEX({aux("T")},{pos}))'
        ws[f'B{r}'] = f'=IF(C{r}="","",INDEX({aux("S")},{pos}))'
        ws[f'D{r}'] = f'=IF(OR(C{r}="",$C$35=0),"",C{r}/$C$35)'
        ws[f'C{r}'].number_format = COP
        ws[f'D{r}'].number_format = '0.0%'
    ws['A35'] = 'Total de gastos del mes'
    ws['C35'] = f'=-SUMIFS({rango("K")},{rango("L")},$C$6,{rango("M")},"Gasto")'
    ws['C35'].number_format = COP
    ws['A36'] = 'Categorías de gasto distintas en Datos'
    ws['C36'] = f'=MAX({rango("O")})'
    ws['D36'] = f'=IF(C36>{SLOTS},"Aviso: hay más de {SLOTS} categorías; el top solo revisa las {SLOTS} primeras","")'

    encabezado(ws, 8, 18, ['Nº', 'Categoría (auxiliar)', 'Gasto del mes (auxiliar)', 'Clave de orden (auxiliar)'])
    for k in range(1, SLOTS + 1):
        r = 8 + k
        ws[f'R{r}'] = k
        ws[f'S{r}'] = f'=IFERROR(INDEX({rango("N")},MATCH(R{r},{rango("O")},0)),"")'
        ws[f'T{r}'] = f'=IF(S{r}="",0,-SUMIFS({rango("K")},{rango("N")},S{r},{rango("L")},$C$6))'
        ws[f'U{r}'] = f'=T{r}-R{r}/1000000'
        ws[f'T{r}'].number_format = COP
        ws[f'U{r}'].number_format = '0.000000'
        for letra in 'RSTU':
            ws[f'{letra}{r}'].font = AUXILIAR

    validacion = DataValidation(type='list', formula1='"' + ','.join(MESES) + '"', allow_blank=False)
    validacion.errorTitle = 'Mes no válido'
    validacion.error = 'Elige un mes de la lista.'
    ws.add_data_validation(validacion)
    validacion.add('C5')

    barras = BarChart()
    barras.type = 'col'
    barras.grouping = 'clustered'
    barras.title = 'Ingresos y gastos por mes'
    barras.add_data(Reference(ws, min_col=3, max_col=4, min_row=8, max_row=20), titles_from_data=True)
    barras.set_categories(Reference(ws, min_col=1, min_row=9, max_row=20))
    barras.x_axis.delete = False
    barras.y_axis.delete = False
    barras.width, barras.height = 17, 8
    ws.add_chart(barras, 'G8')

    torta = PieChart()
    torta.title = 'Gastos por categoría (mes elegido)'
    torta.add_data(Reference(ws, min_col=3, min_row=24, max_row=24 + TOP), titles_from_data=True)
    torta.set_categories(Reference(ws, min_col=2, min_row=25, max_row=24 + TOP))
    torta.dataLabels = DataLabelList()
    torta.dataLabels.showPercent = True
    torta.width, torta.height = 17, 8
    ws.add_chart(torta, 'G25')

    anchos = {'A': 36, 'B': 22, 'C': 18, 'D': 22, 'E': 18, 'R': 8, 'S': 26, 'T': 24, 'U': 22}
    for letra, ancho in anchos.items():
        ws.column_dimensions[letra].width = ancho


def main():
    ruta = Path(sys.argv[1]) if len(sys.argv) > 1 else CARPETA / 'ejemplo.csv'
    filas = leer_csv(ruta)
    wb = Workbook()
    como = wb.active
    como.title = 'Cómo usar'
    hoja_como_usar(como, len(filas))
    hoja_datos(wb, filas)
    hoja_resumen(wb)
    wb.calculation = CalcProperties(fullCalcOnLoad=True)
    wb.save(SALIDA)
    print(f'{SALIDA}: {len(filas)} filas de transacciones')


if __name__ == '__main__':
    main()
