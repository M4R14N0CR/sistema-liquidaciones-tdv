"""Copia consistente de db.sqlite3 usando la API de respaldo de SQLite.

Se puede correr con el sistema encendido: SQLite arma una copia
coherente aunque el servidor web o los workers esten escribiendo.

Uso:
    .venv\\Scripts\\python.exe scripts\\backup_db.py <ruta_destino>

Codigos de salida: 0 = OK, 1 = error, 2 = uso incorrecto.
"""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("Uso: python scripts\\backup_db.py <ruta_destino>")
        return 2

    origen = Path(__file__).resolve().parents[1] / "db.sqlite3"
    destino = Path(sys.argv[1])

    if not origen.is_file():
        print(f"ERROR: no existe {origen}")
        return 1

    destino.parent.mkdir(parents=True, exist_ok=True)
    temporal = destino.with_name(destino.name + ".tmp")
    if temporal.exists():
        temporal.unlink()

    # 1) Copia con la API de respaldo (no un copy del archivo)
    fuente = sqlite3.connect(origen, timeout=30)
    copia = sqlite3.connect(temporal)
    try:
        fuente.backup(copia)
    finally:
        copia.close()
        fuente.close()

    # 2) Verificar que la copia este sana antes de darla por buena
    revision = sqlite3.connect(temporal)
    try:
        resultado = revision.execute("PRAGMA integrity_check").fetchone()[0]
    finally:
        revision.close()

    if resultado != "ok":
        temporal.unlink(missing_ok=True)
        print(f"ERROR: la copia no paso integrity_check: {resultado}")
        return 1

    # 3) Recien ahora reemplazar el destino
    temporal.replace(destino)
    tamano_kb = destino.stat().st_size / 1024
    print(f"OK base de datos -> {destino} ({tamano_kb:,.1f} KB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())