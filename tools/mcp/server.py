#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Servidor MCP do ReportsHowie (Fase 12.b).

Expoe, via Model Context Protocol, ferramentas para um LLM (Claude/etc.) criar,
validar e renderizar relatorios .rhr — reusando o JSON Schema (12.a) e o rhtool
CLI (12.a). O nucleo pesado continua em Pascal; este servidor e um adaptador fino.

Ferramentas:
  - get_schema()                      -> o JSON Schema do formato .rhr
  - list_functions()                  -> funcoes/agregados/pseudo-vars de expressao
  - validate_template(template)       -> {valid, errors} (via JSON Schema)
  - info_template(template)           -> resumo textual (rhtool info)
  - export_template(template, out, fmt)-> renderiza p/ pdf/html/xlsx/docx (rhtool export)

Execucao (stdio):  python server.py
Requisitos:        pip install -r requirements.txt   (mcp, jsonschema)

Config (env, opcionais):
  REPORTSHOWIE_SCHEMA  -> caminho do reportshowie.schema.json
  REPORTSHOWIE_RHTOOL  -> caminho do rhtool.exe
"""

from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Optional

# --------------------------------------------------------------------------- #
# Localizacao do schema e do rhtool (env > deteccao relativa ao repo)
# --------------------------------------------------------------------------- #
HERE = Path(__file__).resolve().parent          # .../tools/mcp
REPO = HERE.parent.parent                        # raiz do repositorio


def _schema_path() -> Path:
    env = os.environ.get("REPORTSHOWIE_SCHEMA")
    if env:
        return Path(env)
    return REPO / "schema" / "reportshowie.schema.json"


def _find_rhtool() -> Optional[Path]:
    env = os.environ.get("REPORTSHOWIE_RHTOOL")
    if env and Path(env).exists():
        return Path(env)
    candidates = [
        REPO / "tools" / "rhtool" / "rhtool.exe",
        REPO / "tools" / "rhtool" / "Win64" / "Debug" / "rhtool.exe",
        REPO / "tools" / "rhtool" / "Win32" / "Debug" / "rhtool.exe",
        REPO / "tools" / "rhtool" / "Win64" / "Release" / "rhtool.exe",
        REPO / "tools" / "rhtool" / "Win32" / "Release" / "rhtool.exe",
    ]
    for c in candidates:
        if c.exists():
            return c
    return None


# --------------------------------------------------------------------------- #
# Catalogo de funcoes do motor de expressoes (fiel ao rh.Expr.*)
# --------------------------------------------------------------------------- #
FUNCTIONS: dict[str, Any] = {
    "islands": "Use [expr] para inserir uma 'ilha' avaliada dentro do texto. "
               "Ex.: 'Total: R$ [FORMATFLOAT('#,##0.00', SUM([valor]))]'. "
               "Campos do dataset viram [nomeDoCampo].",
    "string": {
        "UPPER(s)": "maiusculas",
        "LOWER(s)": "minusculas",
        "TRIM(s)": "remove espacos das pontas",
        "LEN(s)": "tamanho do texto",
        "COPY(s, ini, qtd)": "substring (base 1)",
        "POS(sub, s)": "posicao de sub em s (0 se nao achar)",
        "STR(x)": "converte numero/valor em texto",
    },
    "numeric": {
        "ROUND(x [, casas])": "arredonda",
        "TRUNC(x)": "trunca para inteiro",
        "INT(x)": "parte inteira",
        "ABS(x)": "valor absoluto",
        "FORMATFLOAT(mascara, x)": "formata numero (ex.: '#,##0.00')",
    },
    "datetime": {
        "FORMATDATETIME(mascara, dt)": "formata data/hora (ex.: 'dd/mm/yyyy')",
        "DATETOSTR(dt)": "data como texto",
        "NOW()": "data e hora atuais",
    },
    "logic": {
        "IIF(cond, a, b)": "retorna a se cond, senao b",
        "COALESCE(a, b, ...)": "primeiro valor nao nulo",
    },
    "aggregates": {
        "SUM([campo])": "soma no escopo da banda (grupo/summary)",
        "AVG([campo])": "media",
        "COUNT([campo])": "contagem",
        "MIN([campo])": "minimo",
        "MAX([campo])": "maximo",
        "FIRST([campo])": "primeiro valor do escopo",
        "LAST([campo])": "ultimo valor do escopo",
    },
    "pseudo": {
        "PAGE": "numero da pagina atual",
        "TOTALPAGES": "total de paginas",
        "DATE": "data atual",
        "TIME": "hora atual",
        "NOW": "data e hora atuais",
        "PI": "3.14159...",
        "TRUE": "verdadeiro",
        "FALSE": "falso",
        "NULL": "nulo",
    },
    "operators": ["+", "-", "*", "/", "=", "<>", "<", "<=", ">", ">=",
                  "and", "or", "not", "( )"],
    "notes": "Agregados leem o escopo da banda onde estao: groupFooter = total do "
             "grupo; summary = total geral. O dataset deve estar ordenado na ordem "
             "dos grupos (ex.: ORDER BY cliente, categoria).",
}


# --------------------------------------------------------------------------- #
# Nucleo (funcoes testaveis, independentes do transporte MCP)
# --------------------------------------------------------------------------- #
def load_schema() -> dict:
    return json.loads(_schema_path().read_text(encoding="utf-8"))


def validate(template: dict) -> dict:
    """Valida o template contra o JSON Schema. Retorna {valid, errors}."""
    try:
        from jsonschema import Draft7Validator
    except ImportError:
        return {"valid": False,
                "errors": ["dependencia ausente: pip install jsonschema"]}
    schema = load_schema()
    v = Draft7Validator(schema)
    errors = []
    for e in sorted(v.iter_errors(template), key=lambda x: list(x.path)):
        loc = "/".join(str(p) for p in e.path) or "(raiz)"
        errors.append(f"{loc}: {e.message}")
    return {"valid": not errors, "errors": errors}


def _write_temp_rhr(template: dict) -> str:
    fd, path = tempfile.mkstemp(suffix=".rhr", prefix="rh_mcp_")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(template, f, ensure_ascii=False, indent=2)
    return path


def _run_rhtool(args: list[str]) -> dict:
    exe = _find_rhtool()
    if exe is None:
        return {"ok": False,
                "error": "rhtool.exe nao encontrado. Compile tools/rhtool no IDE "
                         "ou defina REPORTSHOWIE_RHTOOL.",
                "stdout": "", "stderr": ""}
    try:
        proc = subprocess.run([str(exe), *args], capture_output=True,
                              text=True, timeout=120)
    except Exception as ex:  # noqa: BLE001
        return {"ok": False, "error": str(ex), "stdout": "", "stderr": ""}
    return {"ok": proc.returncode == 0, "returncode": proc.returncode,
            "stdout": proc.stdout.strip(), "stderr": proc.stderr.strip()}


def info(template: dict) -> dict:
    tmp = _write_temp_rhr(template)
    try:
        return _run_rhtool(["info", tmp])
    finally:
        try:
            os.remove(tmp)
        except OSError:
            pass


def _write_temp_json(obj: Any, prefix: str) -> str:
    fd, path = tempfile.mkstemp(suffix=".json", prefix=prefix)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=2)
    return path


def export(template: dict, out_path: str, fmt: str = "pdf",
           data: Optional[dict] = None) -> dict:
    fmt = (fmt or "pdf").lower().lstrip(".")
    if fmt not in ("pdf", "html", "xlsx", "docx"):
        return {"ok": False, "error": f"formato invalido: {fmt} "
                "(use pdf/html/xlsx/docx)"}
    # valida antes de gastar render
    val = validate(template)
    if not val["valid"]:
        return {"ok": False, "error": "template invalido pelo schema",
                "errors": val["errors"]}
    if not out_path.lower().endswith("." + fmt):
        out_path = out_path + "." + fmt
    out_abs = str(Path(out_path).resolve())
    Path(out_abs).parent.mkdir(parents=True, exist_ok=True)
    tmp = _write_temp_rhr(template)
    data_tmp = _write_temp_json(data, "rh_data_") if data else None
    try:
        args = ["export", tmp, out_abs]
        if data_tmp:
            args += ["--data", data_tmp]
        res = _run_rhtool(args)
        if res.get("ok"):
            res["output"] = out_abs
        return res
    finally:
        for p in (tmp, data_tmp):
            if p:
                try:
                    os.remove(p)
                except OSError:
                    pass


# --------------------------------------------------------------------------- #
# Servidor MCP (FastMCP) — wrappers finos sobre o nucleo acima
# --------------------------------------------------------------------------- #
def build_server():
    from mcp.server.fastmcp import FastMCP

    mcp = FastMCP("reportshowie")

    @mcp.resource("schema://reportshowie")
    def schema_resource() -> str:
        """JSON Schema (draft-07) do formato de template .rhr do ReportsHowie."""
        return _schema_path().read_text(encoding="utf-8")

    @mcp.tool()
    def get_schema() -> dict:
        """Retorna o JSON Schema (draft-07) do template .rhr. Use-o como contrato
        para montar/validar o JSON do relatorio."""
        return load_schema()

    @mcp.tool()
    def list_functions() -> dict:
        """Lista as funcoes, agregados e pseudo-variaveis do motor de expressoes
        do ReportsHowie (para usar dentro de ilhas [expr] nos textos)."""
        return FUNCTIONS

    @mcp.tool()
    def validate_template(template: dict) -> dict:
        """Valida um template .rhr (objeto JSON) contra o JSON Schema.
        Retorna {valid: bool, errors: [str]}."""
        return validate(template)

    @mcp.tool()
    def info_template(template: dict) -> dict:
        """Resumo da estrutura do template (paginas, bandas, objetos) via rhtool.
        Retorna a saida do comando 'rhtool info'."""
        return info(template)

    @mcp.tool()
    def export_template(template: dict, out_path: str, fmt: str = "pdf",
                        data: Optional[dict] = None) -> dict:
        """Valida e renderiza o template, exportando para um arquivo.
        fmt: 'pdf' | 'html' | 'xlsx' | 'docx'. Retorna {ok, output|error}.

        data (opcional): dados para as bandas, no formato
        {"NomeDataset": [ {campo: valor, ...}, ... ]}. O nome do dataset casa com
        o dataSetName das bandas. Sem data, bandas de dados nao geram linhas."""
        return export(template, out_path, fmt, data)

    return mcp


def main() -> None:
    build_server().run()  # transporte stdio por padrao


if __name__ == "__main__":
    main()
