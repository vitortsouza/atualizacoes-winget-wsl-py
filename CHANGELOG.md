# Changelog

Todas as mudanças relevantes deste projeto são registradas aqui.

## [2.0.0] - 2026-11-11

Reescrita da implementação em PowerShell (5.1+), mantendo `atualizacoes.bat` como
ponto de entrada.

### Adicionado

- `atualizacoes.ps1` (PowerShell 5.1+) com toda a lógica de orquestração.
- `scripts/wsl.sh` com as rotinas Linux, executado com
  `bash --noprofile --norc`.
- Novas opções: `--distro`, `--somente`, `--log-dir`, `--timeout`,
  `--sem-pip`, `--sem-autoremove`, `--winget-silencioso`, `--ignorar-trava`,
  `--versao`.
- Trava de execução (`%TEMP%\atualizacoes.lock`) contra instâncias
  simultâneas, com `--ignorar-trava` para recuperação.
- Pasta de logs exclusiva por execução, eliminando colisões e crescimento
  infinito.
- Limite de tempo configurável por comando externo, com encerramento da
  árvore de processos.
- Detecção de reinicialização pendente no Windows (CBS/Windows Update e
  arquivos pendentes) e no WSL (`/var/run/reboot-required`).
- Validação da distribuição WSL (existência e distribuição default) antes de
  qualquer operação.
- Testes de fumaça (`tests/smoke.ps1`) e CI no GitHub Actions, incluindo
  execução no PowerShell 5.1.
- Compatibilidade com o PowerShell 5.1 incluído no Windows: o `.bat` prefere
  `pwsh` e usa `powershell.exe` como alternativa.
- `CHANGELOG.md`, `.gitignore` e regras de fim de linha para `.ps1`, `.sh` e
  `.yml`.

### Corrigido

- `apt-get update`/`install` no WSL podiam falhar sem que o erro fosse
  detectado, porque o status do pipeline era o do `tee`. Agora o script
  Linux usa `set -o pipefail`.
- `pip install --upgrade pip` no Windows podia falhar por permissão; agora
  tenta `--user` primeiro.
- Códigos do Winget `0x8A150014` e `0x8A15002B` ("nada aplicável") não são
  mais contabilizados como falha.
- `--silent` deixou de ser o padrão do Winget (pode quebrar instaladores com
  interface); use `--winget-silencioso` para reativar.
- Saídas UTF-16 do `wsl.exe` (`-l`, `--version`, `--update`) são decodificadas
  corretamente.
- Argumentos com espaços passaram a ser citados apenas quando necessário,
  evitando a interpretação incorreta de linha de comando pelo `wsl.exe`.
- `apt-get` agora executa `update`, `full-upgrade` e `autoremove` como etapas
  independentes, com diagnóstico e contagem de falhas separados.
- `Dpkg::Options` passou a ser fornecido como entradas de lista, preservando
  `--force-confdef` e `--force-confold`.

### Alterado

- Os logs agora ficam em `%TEMP%\atualizacoes\<AAAAMMDD-HHMMSS-rand>\` em vez
  de arquivos fixos em `%TEMP%`.
- O script não carrega mais o perfil de login do WSL (`-l`).
- O JSON de pacotes do Windows é interpretado com `ConvertFrom-Json`, sem a
  chamada intermediária ao Python.
- O resumo final informa a pasta de logs, o estado da reinicialização e o
  código de saída usados.
- Código de saída `3` documentado para execução concorrente.

### Removido

- Dependência de `findstr` e de arquivos temporários fixos para a lista de
  pacotes.
- Cópia redundante do log interno do WSL ao final da execução (o conteúdo já
  é transmitido e gravado em `wsl.log`).

## [1.0.0] - 2025-10-24

- Versão inicial em lote (`.bat`) com atualização de Winget, pip no Windows,
  WSL, pacotes APT e Python no WSL.
