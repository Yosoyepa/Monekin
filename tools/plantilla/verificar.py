"""Compara los totales de Finanzas.xlsx con los del CSV de ejemplo.

Calcula en Python, con las reglas de la plantilla, el año, los ingresos, gastos y neto
de cada mes, y el top de gastos del mes elegido. Después lee lo que calcula el libro:
con LibreOffice (soffice en modo headless) si está instalado; si no, con el motor de
fórmulas `formulas` (pip install formulas en el venv).

Uso: python verificar.py [ruta_del_csv] [ruta_del_xlsx]
Sale con código 1 si algún valor no coincide.
"""

import contextlib
import csv
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import defaultdict
from datetime import datetime
from pathlib import Path

import openpyxl

CARPETA = Path(__file__).resolve().parent
MESES = ['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
         'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre']
TOP = 10
TOLERANCIA = 0.005
SOFFICE_RUTAS = [
    r'C:\Program Files\LibreOffice\program\soffice.exe',
    r'C:\Program Files (x86)\LibreOffice\program\soffice.exe',
]


class Cuenta:
    def __init__(self):
        self.total = 0
        self.fallos = 0

    def registrar(self, ok):
        self.total += 1
        self.fallos += 0 if ok else 1
        return ok

    def igual(self, esperado, obtenido, tol=TOLERANCIA):
        if esperado is None or isinstance(esperado, str):
            esperado = esperado or ''
            obtenido = '' if obtenido is None else obtenido
            return self.registrar(obtenido == esperado)
        return self.registrar(isinstance(obtenido, float) and abs(obtenido - esperado) <= tol)


def cop(valor):
    if valor is None or isinstance(valor, str):
        return valor or ''
    if abs(valor) < TOLERANCIA:
        valor = 0.0
    return f'{valor:,.2f}'.translate(str.maketrans(',.', '.,'))


def porcentaje(valor):
    if valor is None or isinstance(valor, str):
        return valor or ''
    return f'{valor * 100:.1f} %'.replace('.', ',')


def entero(valor):
    if valor is None or isinstance(valor, str):
        return valor or ''
    return str(int(valor))


def texto(valor):
    return '' if valor is None else str(valor)


def leer_transacciones(ruta):
    with open(ruta, newline='', encoding='utf-8') as archivo:
        return [
            {
                'fecha': datetime.strptime(fila['Date'], '%Y-%m-%d %H:%M:%S'),
                'monto': float(fila['Amount']),
                'categoria': fila['Category'],
            }
            for fila in csv.DictReader(archivo)
        ]


def esperado(transacciones):
    """Mismas reglas que la plantilla: traspasos e inversiones fuera; gasto = monto negativo."""
    ultima = max(t['fecha'] for t in transacciones)
    ingresos = defaultdict(float)
    gastos = defaultdict(float)
    por_categoria = defaultdict(lambda: defaultdict(float))
    orden = {}  # primera aparición de cada categoría de gasto: desempate del top, como en la hoja
    for t in transacciones:
        if t['categoria'] in ('TRANSFER', 'INVESTMENT'):
            continue
        clave = (t['fecha'].year, t['fecha'].month)
        if t['monto'] < 0:
            categoria = t['categoria'] or '(sin categoría)'
            orden.setdefault(categoria, len(orden))
            gastos[clave] += -t['monto']
            por_categoria[clave][categoria] += -t['monto']
        else:
            ingresos[clave] += t['monto']

    anio = ultima.year
    meses = {}
    for m in range(1, 13):
        ing, gas = ingresos[(anio, m)], gastos[(anio, m)]
        meses[m] = (ing, gas, ing - gas)
    gasto_mes = gastos[(anio, ultima.month)]
    ranking = sorted(
        ((cat, tot) for cat, tot in por_categoria[(anio, ultima.month)].items() if tot > 0),
        key=lambda ct: (-round(ct[1], 2), orden[ct[0]]),
    )[:TOP]
    return {
        'anio': anio,
        'mes': ultima.month,
        'meses': meses,
        'anual': tuple(sum(meses[m][i] for m in meses) for i in range(3)),
        'gasto_mes': gasto_mes,
        'top': [(cat, tot, tot / gasto_mes) for cat, tot in ranking],
        'categorias': len(orden),
    }


def normalizar(valor):
    if valor is None or isinstance(valor, str):
        return valor
    try:
        return float(valor)
    except (TypeError, ValueError):
        return str(valor)


def valores_con_libreoffice(soffice, ruta):
    with tempfile.TemporaryDirectory() as carpeta:
        subprocess.run(
            [soffice, '--headless', '--calc', '--convert-to', 'xlsx', '--outdir', carpeta, str(ruta)],
            check=True, capture_output=True, timeout=300,
        )
        libro = openpyxl.load_workbook(Path(carpeta) / ruta.name, data_only=True)
        valores = {
            (hoja.title.upper(), celda.coordinate): normalizar(celda.value)
            for hoja in libro.worksheets
            for fila in hoja.iter_rows()
            for celda in fila
        }
    return valores, 'LibreOffice (soffice en modo headless)'


def valores_con_formulas(ruta):
    try:
        import formulas
    except ImportError:
        raise SystemExit('Falta el motor de fórmulas: pip install formulas (o instala LibreOffice).')
    with open(os.devnull, 'w') as nulo, contextlib.redirect_stderr(nulo):
        modelo = formulas.ExcelModel().loads(str(ruta)).finish()
        solucion = modelo.calculate()
    patron = re.compile(r"'\[[^\]]*\](.+)'!([A-Z]+[0-9]+)$")
    valores = {}
    for clave, valor in solucion.items():
        m = patron.match(str(clave))
        if m:
            bruto = valor.value[0][0] if hasattr(valor, 'value') else valor
            valores[(m.group(1).upper(), m.group(2))] = normalizar(bruto)
    return valores, f'formulas {formulas.__version__} (LibreOffice no encontrado)'


def main():
    csv_ruta = Path(sys.argv[1]) if len(sys.argv) > 1 else CARPETA / 'ejemplo.csv'
    xlsx_ruta = Path(sys.argv[2]) if len(sys.argv) > 2 else CARPETA / 'Finanzas.xlsx'
    transacciones = leer_transacciones(csv_ruta)
    esp = esperado(transacciones)

    soffice = next((r for r in SOFFICE_RUTAS if Path(r).exists()), None) or shutil.which('soffice')
    valores = motor = None
    if soffice:
        try:
            valores, motor = valores_con_libreoffice(soffice, xlsx_ruta)
        except (OSError, subprocess.SubprocessError) as error:
            print(f'LibreOffice no pudo recalcular ({error}); se usa el motor formulas.')
    if valores is None:
        valores, motor = valores_con_formulas(xlsx_ruta)

    def v(celda):
        return valores.get(('RESUMEN', celda))

    cuenta = Cuenta()
    lineas = [
        f'Libro: {xlsx_ruta}',
        f'CSV:   {csv_ruta} ({len(transacciones)} filas de transacciones)',
        f'Motor: {motor}',
        '',
        'Año y mes del top (CSV = libro):',
    ]

    def linea(etiqueta, pares):
        oks, partes = [], []
        for nombre, esperado_, obtenido, formato, tol in pares:
            ok = cuenta.igual(esperado_, obtenido, tol)
            oks.append(ok)
            signo = '=' if ok else '!='
            prefijo = f'{nombre} ' if nombre else ''
            partes.append(f'{prefijo}{formato(esperado_)} {signo} {formato(obtenido)}')
        estado = 'OK' if all(oks) else 'DIFERENCIA'
        lineas.append(f'  {etiqueta:<24}{" | ".join(partes)}  {estado}')

    linea('Año', [('', esp['anio'], v('C4'), entero, 0)])
    linea('Mes', [('', MESES[esp['mes'] - 1], v('C5'), texto, 0)])

    lineas += ['', 'Totales por mes (CSV = libro):']
    for m in range(1, 13):
        ingresos, gastos, neto = esp['meses'][m]
        r = 8 + m
        linea(MESES[m - 1], [
            ('ing', ingresos, v(f'C{r}'), cop, TOLERANCIA),
            ('gas', gastos, v(f'D{r}'), cop, TOLERANCIA),
            ('neto', neto, v(f'E{r}'), cop, TOLERANCIA),
        ])
    ingresos, gastos, neto = esp['anual']
    linea('Total año', [
        ('ing', ingresos, v('C21'), cop, TOLERANCIA),
        ('gas', gastos, v('D21'), cop, TOLERANCIA),
        ('neto', neto, v('E21'), cop, TOLERANCIA),
    ])

    nombre_mes, anio = MESES[esp['mes'] - 1], esp['anio']
    lineas += ['', f'Top de gastos de {nombre_mes} {anio} (CSV = libro):']
    linea('Total del mes', [('gasto', esp['gasto_mes'], v('C35'), cop, TOLERANCIA)])
    linea('Categorías', [('de gasto', esp['categorias'], v('C36'), entero, 0)])
    for k in range(1, TOP + 1):
        r = 24 + k
        if k <= len(esp['top']):
            categoria, total_cat, parte = esp['top'][k - 1]
            linea(f'{k}. {categoria}', [
                ('cat', categoria, v(f'B{r}'), texto, 0),
                ('gasto', total_cat, v(f'C{r}'), cop, TOLERANCIA),
                ('%', parte, v(f'D{r}'), porcentaje, 1e-9),
            ])
    libres = range(25 + len(esp['top']), 35)
    if libres:
        vacias = [cuenta.igual('', v(f'{c}{r}'), 0) for r in libres for c in 'BCD']
        estado = 'OK' if all(vacias) else 'DIFERENCIA'
        lineas.append(f'  {len(esp["top"]) + 1}-{TOP}. (filas vacías del libro)  {estado}')
    aviso = cuenta.igual('', v('D36'), 0)
    lineas.append(f'  Aviso de más de 30 categorías: {"no hay" if aviso else "HAY AVISO"}')

    hoja = openpyxl.load_workbook(xlsx_ruta)['Resumen']
    etiquetas = [hoja.cell(row=8 + m, column=1).value for m in range(1, 13)]
    estado = 'OK' if cuenta.registrar(etiquetas == MESES) else 'DIFERENCIA'
    lineas += ['', f'Etiquetas de meses A9:A20: {estado}']

    resultado = 'OK' if cuenta.fallos == 0 else 'DIFERENCIAS'
    lineas.append(f'Resultado: {resultado} ({cuenta.total} comprobaciones, {cuenta.fallos} con diferencia)')
    print('\n'.join(lineas))
    return 0 if cuenta.fallos == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
