# ReportsHowie MCP server

Servidor **MCP** (Model Context Protocol) que permite a assistentes como o **Claude** criar, validar e renderizar relatórios ReportsHowie (`.rhr`). É um **adaptador fino** em Python sobre o **JSON Schema** (Fase 12.a) e o **`rhtool` CLI** (Fase 12.a) — o núcleo pesado continua em Pascal.

## Ferramentas expostas

| Tool | O que faz |
|---|---|
| `get_schema()` | Retorna o JSON Schema (draft-07) do `.rhr` — contrato para montar/validar o relatório. |
| `list_functions()` | Funções, agregados e pseudo-variáveis do motor de expressões (para usar em ilhas `[expr]`). |
| `validate_template(template)` | Valida o JSON do template contra o schema → `{valid, errors}`. |
| `info_template(template)` | Resumo da estrutura (páginas/bandas/objetos) via `rhtool info`. |
| `export_template(template, out_path, fmt)` | Valida e renderiza para `pdf`/`html`/`xlsx`/`docx` via `rhtool export`. |

Também expõe o schema como **recurso** MCP: `schema://reportshowie`.

> `info`/`export` chamam o `rhtool.exe` — compile `tools/rhtool` no IDE antes (ver [tools/rhtool](../rhtool/)). `get_schema`/`list_functions`/`validate_template` funcionam sem o `rhtool`.

## Instalação

```sh
cd tools/mcp
pip install -r requirements.txt      # mcp, jsonschema
```

## Executar (teste local)

```sh
python server.py                     # fala MCP por stdio (aguarda um cliente)
```

Para localizar schema/rhtool fora do layout padrão do repo, defina:

- `REPORTSHOWIE_SCHEMA` → caminho do `reportshowie.schema.json`
- `REPORTSHOWIE_RHTOOL` → caminho do `rhtool.exe`

## Conectar ao Claude

### Claude Code (CLI)
```sh
claude mcp add reportshowie -- python "C:\\Users\\Windows\\Mentor_WorkSpace\\ReportsHowie\\tools\\mcp\\server.py"
```

### Claude Desktop
Edite `claude_desktop_config.json` (Settings → Developer → Edit Config):
```json
{
  "mcpServers": {
    "reportshowie": {
      "command": "python",
      "args": ["C:\\Users\\Windows\\Mentor_WorkSpace\\ReportsHowie\\tools\\mcp\\server.py"]
    }
  }
}
```
Use o `python` do ambiente onde instalou as dependências (ex.: o do `.venv`). Reinicie o Claude Desktop e as ferramentas `reportshowie` aparecerão.

## Exemplo de conversa

> "Pegue o schema (`get_schema`) e as funções (`list_functions`), monte um relatório com título e uma banda de dados 'Vendas' mostrando cliente e valor formatado, **valide** e **exporte** para `saida/vendas.pdf`."

O Claude usa `get_schema`/`list_functions` para montar o JSON, `validate_template` para conferir e `export_template` para gerar o arquivo.

> **Nota:** sem dados ligados, bandas de dados não produzem linhas (o `export` renderiza o *layout*). Alimentar datasets a partir de JSON/CSV é um próximo passo.
