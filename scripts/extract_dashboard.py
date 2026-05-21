#!/usr/bin/env python3
"""
extract_dashboard.py
---------------------
Extrai o HTML embutido em `src/rs50h_thermal/dashboard.h` (PROGMEM raw string)
e salva como `dist/dashboard.html` para preview no navegador.

Suporta qualquer delimitador de raw string C++ (RSHTML, rawliteral, etc.).

Uso:
    python scripts/extract_dashboard.py
    python scripts/extract_dashboard.py --watch    # modo watch (auto re-extract)
    python scripts/extract_dashboard.py --open     # abre no navegador após extrair
"""

import re
import sys
import argparse
import webbrowser
from pathlib import Path
from time import sleep

ROOT = Path(__file__).resolve().parent.parent
HEADER = ROOT / "src" / "rs50h_thermal" / "dashboard.h"
OUT_DIR = ROOT / "dist"
OUT_FILE = OUT_DIR / "dashboard.html"

# Captura conteúdo entre R"DELIM( ... )DELIM" — aceita qualquer delimitador
RAW_PATTERN = re.compile(
    r'R"(\w+)\((.*?)\)\1"',
    re.DOTALL
)


def extract(header_path: Path) -> str:
    if not header_path.exists():
        raise FileNotFoundError(f"Arquivo não encontrado: {header_path}")

    content = header_path.read_text(encoding="utf-8")
    match = RAW_PATTERN.search(content)

    if not match:
        raise ValueError(
            f"Nenhum bloco R\"DELIM(...)DELIM\" encontrado em {header_path.name}.\n"
            f"  Esperado: R\"QUALQUER_DELIM(...)QUALQUER_DELIM\" com PROGMEM.\n"
            f"  Verifique se dashboard.h contém uma raw string C++ válida."
        )

    delimiter = match.group(1)
    html = match.group(2).strip()
    print(f"  delimitador detectado: {delimiter!r}")
    return html


def save(html: str, out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(html, encoding="utf-8")
    size_kb = out_path.stat().st_size / 1024
    print(f"✅ HTML extraído: {out_path} ({size_kb:.1f} KB)")


def watch_mode(header_path: Path, out_path: Path) -> None:
    print(f"👁️  Modo watch ativo em {header_path}")
    print("   (Ctrl+C para sair)\n")
    last_mtime = 0
    try:
        while True:
            mtime = header_path.stat().st_mtime
            if mtime != last_mtime:
                try:
                    html = extract(header_path)
                    save(html, out_path)
                except Exception as e:
                    print(f"⚠️  {e}")
                last_mtime = mtime
            sleep(1)
    except KeyboardInterrupt:
        print("\n👋 Watch encerrado.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Extrai HTML do dashboard.h")
    parser.add_argument("--watch", action="store_true", help="Modo watch")
    parser.add_argument("--open", action="store_true", help="Abre no browser")
    parser.add_argument(
        "--header", type=Path, default=HEADER,
        help=f"Caminho do header (default: {HEADER})"
    )
    parser.add_argument(
        "--out", type=Path, default=OUT_FILE,
        help=f"Saída HTML (default: {OUT_FILE})"
    )
    args = parser.parse_args()

    try:
        if args.watch:
            watch_mode(args.header, args.out)
        else:
            html = extract(args.header)
            save(html, args.out)
            if args.open:
                webbrowser.open(args.out.as_uri())
        return 0
    except Exception as e:
        print(f"❌ Erro: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
