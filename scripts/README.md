# scripts/

Utilitários de desenvolvimento e automação do RS50H.

## Python

| Script | Descrição |
|--------|-----------|
| `extract_dashboard.py` | Extrai o HTML do `dashboard.h` (PROGMEM raw string) para preview local. Aceita qualquer delimitador C++ raw literal. |

**Uso local (preview):**
```bash
python3 scripts/extract_dashboard.py \
  --header src/rs50h_thermal/dashboard.h \
  --out /tmp/dashboard_preview.html --open
```

> **Caminhos nos workflows de CI:** `build.yml` usa `/tmp/dashboard_from_header.html`
> para comparação com `docs/dashboard-source.html`; `release.yml` usa `dashboard.html`
> (raiz do workspace) como Release Asset.
> O diretório `dist/` **não é usado** por nenhum workflow.

---

## PowerShell (`ps/`)

Scripts ordenados pelo fluxo típico de desenvolvimento. Execute sempre na raiz do projeto.

| Script | Quando usar |
|--------|-------------|
| `00_AUDIT_REPORT.ps1` | Diagnóstico completo — roda antes de qualquer outra coisa |
| `01_fix_scaffold.ps1` | Valida estrutura de arquivos e configura hooks; **aborta** se `config.h.example` ou firmware estiverem ausentes (não gera placeholders) |
| `02_commit_history.ps1` | Consulta e analisa histórico de commits |
| `03_push.ps1` | Push para `origin/main` com validações |
| `04_tag_release.ps1` | Cria e envia tag semântica (`vX.Y.Z`) |
| `05_ci_watch.ps1` | Monitora o status do CI/CD no terminal |
| `06_hotfix.ps1` | Fluxo rápido de hotfix (branch → fix → merge → tag) |
| `commit.ps1` | Helper interativo de commit convencional (uso diário) |

**Fluxo de release normal:**
```
00_AUDIT_REPORT → commit.ps1 → 03_push → 04_tag_release → 05_ci_watch
```

**Fluxo de hotfix:**
```
06_hotfix (autocontido)
```

> **Pré-requisito:** PowerShell 5.1+ (`pwsh` ou `powershell`), git no PATH, na raiz do repo.
