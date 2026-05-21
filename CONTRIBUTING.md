# Contribuindo com o RS50H Thermal Controller

Obrigado pelo interesse! Este guia cobre o que você precisa para contribuir.

---

## Pré-requisitos

| Ferramenta | Versão mínima | Notas |
|------------|---------------|-------|
| `arduino-cli` | **1.1.1** (fixado — igual ao CI) | ver instalação abaixo |
| ESP32 core | **2.0.14** (fixado) | `arduino-cli core install esp32:esp32@2.0.14` |
| Python 3 | 3.8+ | para `scripts/extract_dashboard.py` |

> ⚠️ **Não atualizar o core para 3.x** sem antes migrar as chamadas LEDC legadas no firmware
> (`ledcSetup` / `ledcAttachPin` / `ledcWrite(channel, duty)` foram removidas no core v3.x).

### Instalação do arduino-cli 1.1.1 (mesma versão do CI)

```bash
# Linux
curl -fsSL \
  "https://github.com/arduino/arduino-cli/releases/download/v1.1.1/arduino-cli_1.1.1_Linux_64bit.tar.gz" \
  | tar -xz -C /usr/local/bin arduino-cli

# macOS
curl -fsSL \
  "https://github.com/arduino/arduino-cli/releases/download/v1.1.1/arduino-cli_1.1.1_macOS_64bit.tar.gz" \
  | tar -xz -C /usr/local/bin arduino-cli

arduino-cli version  # deve exibir 1.1.1
```

---

## Configuração local

```bash
# 1. Fork + clone
git clone https://github.com/<seu-fork>/rs50h-thermal-controller.git
cd rs50h-thermal-controller

# 2. Registrar o hook de pre-commit
git config core.hooksPath .githooks

# 3. Copiar o template de configuração (nunca commitar config.h)
cp include/config.h.example include/config.h
# Editar include/config.h com suas credenciais e pinagem local

# 4. Instalar bibliotecas
arduino-cli lib install FastLED@3.6.0
arduino-cli lib install WebSockets@2.4.1
```

---

## Compilar e fazer upload

> **Por que `-I` com caminho absoluto?**
> O `arduino-cli` copia o sketch para um diretório temporário de build antes de invocar o GCC.
> O `#include "config.h"` (nome simples, sem barras) é resolvido via search path (`-I`),
> então passar o caminho absoluto da pasta `include/` garante que o compilador encontre o arquivo
> independente de onde o build temporário estiver. Caminhos relativos como `../../include/config.h`
> **não funcionam** com arduino-cli porque o ponto de origem muda durante o build.

```bash
# Linux / macOS — Compilar
arduino-cli compile \
  --fqbn "esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashMode=qio,FlashSize=4M,PartitionScheme=default,PSRAM=disabled" \
  --build-property "compiler.cpp.extra_flags=-I$(pwd)/include" \
  src/rs50h_thermal

# Linux / macOS — Upload (ajuste a porta conforme seu sistema)
arduino-cli upload \
  -p /dev/ttyACM0 \
  --fqbn "esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashMode=qio,FlashSize=4M,PartitionScheme=default,PSRAM=disabled" \
  src/rs50h_thermal
```

```powershell
# Windows PowerShell — Compilar
arduino-cli compile `
  --fqbn "esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashMode=qio,FlashSize=4M,PartitionScheme=default,PSRAM=disabled" `
  --build-property "compiler.cpp.extra_flags=-I$((Get-Location).Path.Replace('\','/'))/include" `
  src\rs50h_thermal

# Windows PowerShell — Upload (substitua COM3 pela porta correta)
arduino-cli upload `
  -p COM3 `
  --fqbn "esp32:esp32:esp32s3:USBMode=hwcdc,CDCOnBoot=cdc,FlashMode=qio,FlashSize=4M,PartitionScheme=default,PSRAM=disabled" `
  src\rs50h_thermal

# Monitor serial
arduino-cli monitor -p COM3 -c baudrate=115200
```

---

## Fluxo de contribuição

1. Crie uma branch a partir de `main`:
   ```bash
   git checkout -b fix/descricao-curta    # para correções
   git checkout -b feat/descricao-curta   # para funcionalidades
   ```

2. Faça commits com mensagens no formato [Conventional Commits](https://www.conventionalcommits.org/):
   ```
   fix(ntc): corrigir saturação ADC no limite inferior
   feat(dashboard): adicionar gráfico histórico de temperatura
   docs(wiring): atualizar diagrama de pinagem do relay
   ```

3. O pre-commit hook vai rodar automaticamente ao fazer `git commit`:
   - Verificação de arquivos sensíveis (`config.h`, `.env`, `.key`)
   - Validação de `FW_VERSION` como SemVer em `config.h.example`
   - Lint de Markdown (se `markdownlint-cli2` estiver instalado)

4. Abra um Pull Request para `main`.

---

## Dashboard

O dashboard web é mantido em dois arquivos sincronizados:

- `docs/dashboard-source.html` — fonte editável
- `src/rs50h_thermal/dashboard.h` — versão embutida no firmware (gerada)

Se editar o dashboard, **sempre atualize `dashboard.h`** antes do commit:
O CI falhará se os dois estiverem dessincronizados.

```bash
# 1. Edite docs/dashboard-source.html
# 2. Copie o HTML para dentro da raw string em src/rs50h_thermal/dashboard.h
# 3. Verifique a sincronização:
python3 scripts/extract_dashboard.py \
  --header src/rs50h_thermal/dashboard.h \
  --out /tmp/check.html
diff /tmp/check.html docs/dashboard-source.html  # deve ser vazio
```

---

## Versionamento

Este projeto usa [SemVer](https://semver.org/). Ao contribuir com mudanças
que justifiquem um release, atualize `FW_VERSION` em `include/config.h.example`
e adicione uma entrada em `CHANGELOG.md`.
