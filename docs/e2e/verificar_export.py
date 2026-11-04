"""Pega un CSV exportado por la app en una copia de Finanzas.xlsx y lo pasa por tools/plantilla/verificar.py.

verificar.py compara el CSV con el libro tal cual (que trae el CSV de ejemplo), asi que para comprobar un
CSV propio hay que pegarlo antes en la hoja Datos, como indica docs/plantilla.md.

Uso: python verificar_export.py <csv_exportado> [salida.xlsx]
Sale con el codigo de verificar.py (0 = los totales del libro coinciden con los del CSV).
"""

import csv
import subprocess
import sys
import tempfile
from pathlib import Path

import openpyxl
from openpyxl.formula.translate import Translator

RAIZ = Path(__file__).resolve().parents[2]
PLANTILLA = RAIZ / 'tools' / 'plantilla' / 'Finanzas.xlsx'
VERIFICAR = RAIZ / 'tools' / 'plantilla' / 'verificar.py'
ULTIMA_COLUMNA_CSV = 10  # A..J son las columnas del CSV; K..O son formulas del libro
ULTIMA_COLUMNA = 15


def pegar(csv_ruta, destino):
    with open(csv_ruta, newline='', encoding='utf-8') as f:
        filas = list(csv.reader(f))[1:]

    libro = openpyxl.load_workbook(PLANTILLA)
    hoja = libro['Datos']
    tabla = hoja.tables['Transacciones']
    ultima_vieja = hoja.max_row
    formulas = [hoja.cell(row=2, column=c).value for c in range(ULTIMA_COLUMNA_CSV + 1, ULTIMA_COLUMNA + 1)]

    for fila in range(2, max(ultima_vieja, len(filas) + 1) + 1):
        for col in range(1, ULTIMA_COLUMNA + 1):
            hoja.cell(row=fila, column=col).value = None

    for i, valores in enumerate(filas):
        fila = i + 2
        for col, valor in enumerate(valores[:ULTIMA_COLUMNA_CSV], start=1):
            hoja.cell(row=fila, column=col).value = valor if valor != '' else None
        for j, formula in enumerate(formulas):
            col = ULTIMA_COLUMNA_CSV + 1 + j
            hoja.cell(row=fila, column=col).value = Translator(formula, origin=f'{openpyxl.utils.get_column_letter(col)}2').translate_formula(
                f'{openpyxl.utils.get_column_letter(col)}{fila}')

    tabla.ref = f'A1:O{len(filas) + 1}'
    libro.save(destino)
    return len(filas)


def main():
    csv_ruta = Path(sys.argv[1])
    destino = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(tempfile.gettempdir()) / 'Finanzas_con_export.xlsx'
    n = pegar(csv_ruta, destino)
    print(f'{n} filas del CSV pegadas en {destino}')
    sys.exit(subprocess.run([sys.executable, str(VERIFICAR), str(csv_ruta), str(destino)]).returncode)


if __name__ == '__main__':
    main()
