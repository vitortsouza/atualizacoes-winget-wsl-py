# Atualização do Winget, WSL e Python

Automação de manutenção para Windows que atualiza aplicativos do Winget, o
WSL, os pacotes da distribuição Linux (APT) e o Python instalado no Windows e
no WSL.

A lógica fica em `atualizacoes.ps1` (PowerShell 5.1 ou superior). O
`atualizacoes.bat` continua sendo o ponto de entrada: ele localiza o
PowerShell, repassa os argumentos e devolve o mesmo código de saída para uso
manual ou em automação.

## Funcionalidades

- **Winget:** atualiza os aplicativos disponíveis, incluindo versões
  desconhecidas quando o `--include-unknown` é suportado. Códigos de retorno
  considerados normais ("nada aplicável") não contam como falha.
- **Python no Windows:** localiza `py -3` ou `python`, garante o `pip` com
  `ensurepip` quando necessário e atualiza `pip` e os pacotes do usuário.
- **WSL:** valida a distribuição (inclusive com `--distro`), executa
  `wsl --update` e encerra as instâncias antes da manutenção Linux.
- **Pacotes Linux:** executa `apt-get update`, `full-upgrade` e
  `autoremove` como etapas separadas, com opções não interativas.
- **Python no WSL:** prepara `python3-pip`/`python3-venv` quando necessário,
  atualiza os pacotes do usuário e atualiza o `pip` em um ambiente virtual
  auxiliar, respeitando o PEP 668.
- **Modo de listagem:** mostra o que seria atualizado sem instalar nada.
- **Confirmação e automação:** pode ser executado sem interação com
  `--sem-confirmacao` e `--sem-pausa`.
- **Logs por execução:** uma pasta nova a cada execução, sem crescimento
  infinito de arquivos.
- **Limite de tempo:** comandos externos são encerrados após `--timeout`
  segundos (padrão: 3600).
- **Trava de execução:** impede duas instâncias simultâneas.
- **Reinicialização pendente:** verifica Windows (CBS/Windows Update) e WSL.

## Requisitos

- Windows 10 ou Windows 11 com Winget e WSL.
- PowerShell 5.1 (incluído no Windows 10/11) ou superior. O `.bat` usa o
  `pwsh` quando disponível e cai para o `powershell.exe` do sistema.
  O [PowerShell 7](https://aka.ms/powershell-release) é recomendado por
  encerrar a árvore de processos nos timeouts e por melhores padrões de
  UTF-8, mas **não é obrigatório**. Para instalá-lo:
  ```bat
  winget install --id Microsoft.PowerShell --source winget
  ```
- [Windows Package Manager (Winget)](https://learn.microsoft.com/pt-br/windows/package-manager/winget/).
- [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/pt-br/windows/wsl/).
- Distribuição WSL baseada em APT (Ubuntu, Debian) — qualquer uma serve, mas
  a distribuição precisa usar `apt-get`.
- Python 3 funcional no Windows (`py -3` ou `python` no `PATH`), se quiser
  atualizar pacotes Python do Windows. A etapa é ignorada com aviso quando
  não existe.
- `sudo` configurado na distribuição Linux.
- Conexão com a internet.

O `wsl --update` e alguns instaladores do Winget podem solicitar elevação
(UAC). A etapa APT roda em uma única sessão dentro do WSL: o `sudo` pede a
senha da distribuição (não a do Windows) **uma vez** e usa o cache para
`update`, `full-upgrade` e `autoremove`. Por isso ela precisa de um terminal
interativo; em tarefas agendadas, configure `NOPASSWD` no `sudoers` para os
comandos do APT (ou execute o script manualmente).

## Como utilizar

1. Mantenha `atualizacoes.bat`, `atualizacoes.ps1` e a pasta `scripts/` juntos
   (o `.bat` procura o `.ps1` na própria pasta e o `.ps1` procura
   `scripts/wsl.sh`).
2. Abra o Prompt de Comando ou o Windows Terminal na pasta do projeto.
3. Execute:

   ```bat
   atualizacoes.bat
   ```

4. Leia o resumo, confirme a execução e acompanhe o andamento no terminal.
5. Ao final, o caminho da pasta de logs é exibido.

### Opções de linha de comando

| Opção | Descrição |
|---|---|
| `--listar`, `-n` | Mostra o que seria atualizado, sem instalar ou atualizar. Não executa `wsl --shutdown`. |
| `--sem-pausa` | Não aguarda Enter ao final; útil para automação. |
| `--sem-confirmacao`, `-y` | Não pede confirmação antes de iniciar. |
| `--sem-pacotes` | Não atualiza pacotes Python do usuário (Windows e WSL). O `pip` continua sendo atualizado. |
| `--sem-pip` | Não atualiza o próprio `pip` (Windows e WSL). |
| `--sem-autoremove` | Não executa `apt-get autoremove`. |
| `--distro NOME` | Distribuição WSL alvo. Padrão: a distribuição default. |
| `--somente LISTA` | Etapas a executar: `winget,wsl,linux,python`. Pode ser repetida. |
| `--log-dir DIR` | Diretório base dos logs. Padrão: `%TEMP%\atualizacoes`. |
| `--timeout SEGUNDOS` | Limite por comando externo (0 desativa). Padrão: 3600. |
| `--winget-silencioso` | Adiciona `--silent` ao Winget (pode quebrar instaladores que exigem interface). |
| `--ignorar-trava` | Remove a trava de execução de uma execução anterior interrompida. |
| `--versao`, `-V` | Mostra a versão. |
| `--ajuda`, `-h`, `/?` | Mostra a ajuda. |

Exemplos:

```bat
REM Apenas visualizar o que seria atualizado
atualizacoes.bat --listar

REM Executar sem interação (tarefa agendada)
atualizacoes.bat --sem-confirmacao --sem-pausa

REM Atualizar tudo, exceto os pacotes Python do usuário
atualizacoes.bat --sem-pacotes

REM Somente o WSL e os pacotes Linux, em uma distribuição específica
atualizacoes.bat --somente wsl,linux --distro Ubuntu

REM Ambiente com pouca banda: limitar cada comando a 10 minutos
atualizacoes.bat --timeout 600
```

O modo `--listar` não altera nada, mas ainda consulta Winget, WSL e `pip`. A
simulação do APT usa os índices atuais da distribuição e **não** executa
`apt-get update`; para ver atualizações mais recentes, execute o script no
modo normal.

### Códigos de saída

| Código | Significado |
|---:|---|
| `0` | Execução concluída sem falhas registradas. |
| `1` | Uma ou mais etapas falharam, ou a execução foi cancelada. |
| `2` | Opção de linha de comando inválida. |
| `3` | Outra execução está em andamento (trava ativa). |

## Etapas da execução

A ordem é fixa (`winget`, `wsl`, `linux`, `python`), mesmo quando `--somente`
é informado em outra ordem. A numeração `[n/total]` reflete apenas as etapas
selecionadas.

1. **Winget:** atualiza os aplicativos. No modo de listagem, apenas lista.
2. **WSL:** valida a distribuição, executa `wsl --update` e `wsl --shutdown`
   (o encerramento é ignorado no modo de listagem).
3. **Pacotes Linux:** `apt-get update`, `apt-get full-upgrade` e, salvo
   `--sem-autoremove`, `apt-get autoremove`, na mesma sessão do WSL. Cada
   comando tem seu próprio status, então uma falha no `update` não esconde o
   resultado do `upgrade`; o `sudo` pede a senha apenas uma vez.
4. **Python:** atualiza `pip` e pacotes do usuário no Windows e no WSL.

As falhas são contabilizadas e o resumo final informa quantas ocorreram. Uma
falha em determinada etapa não interrompe as etapas seguintes.

## Logs

Cada execução cria uma pasta própria:

```text
%TEMP%\atualizacoes\<AAAAMMDD-HHMMSS-rand>\
├── atualizacao.log   # inicio, etapas, avisos, falhas e fim
├── winget.log        # saida do Winget
├── python.log        # saida do Python/pip no Windows
└── wsl.log           # saida de wsl.exe e do scripts/wsl.sh
```

Use `--log-dir` para gravar em outro local. Os nomes são únicos por execução,
o que evita colisão entre instâncias e rotação manual de logs.

Os logs internos do APT/pip também são gravados em
`/tmp/atualizacao-wsl.log` dentro da distribuição. O arquivo é zerado no
início de cada execução e o conteúdo relevante já aparece em `wsl.log`.

## Atualização do Python e do pip

### Windows

O script testa `py -3 -c "import sys"`, depois `python` e `python3`, para não
considerar um launcher quebrado como interpretador válido.

As operações incluem:

- Verificação da versão do Python e da disponibilidade do `pip`.
- `python -m ensurepip --upgrade` quando o `pip` está ausente.
- `python -m pip install --user --upgrade pip`; se falhar (por exemplo, em
  instalações que exigem elevação), tenta a instalação padrão e registra o
  resultado.
- `pip list --user --outdated --format=json`, interpretado nativamente com
  `ConvertFrom-Json` (sem depender de chamadas extras ao Python).
- Atualização individual dos pacotes, com registro de cada falha.

**Limitações:**

- Apenas o interpretador selecionado (`py -3` ou `python`) é atualizado; não
  há varredura de todas as versões instaladas.
- Pacotes do usuário em ambientes virtuais de projetos não são tocados.
- Não há rollback automático.

### WSL/Linux

A lógica fica em `scripts/wsl.sh`, chamado com
`bash --noprofile --norc` (sem carregar perfis que poderiam poluir a saída) e
com `set -o pipefail` (falhas do APT não são mascaradas pelo `tee`).

Comandos disponíveis no script auxiliar:

| Comando | Função |
|---|---|
| `apt-tudo` | Autentica o `sudo` uma vez e executa `update`, `full-upgrade` e `autoremove` na mesma sessão (usado pelo script). |
| `info-apt` | Simula o `full-upgrade` (`apt-get -s`). |
| `apt-update` | `apt-get update`. |
| `apt-upgrade` | `apt-get -y full-upgrade`. |
| `apt-autoremove` | `apt-get -y autoremove`. |
| `info-python` | Versões de `python3`, `pip`, `venv` e pacotes desatualizados. |
| `python-prepare` | Instala `python3-pip`/`python3-venv` se necessário e atualiza o `pip` do venv auxiliar. |
| `python-pacotes` | Atualiza os pacotes do usuário e propaga falhas. |
| `reboot-status` | Informa se há reinicialização pendente. |

O ambiente virtual auxiliar do `pip` fica em:

```text
~/.venvs/atualizador-pip
```

Essa abordagem evita forçar atualização global do `pip` em distribuições que
protegem o Python do sistema (PEP 668). O script não usa
`--break-system-packages`.

**Limitações:**

- Ambientes virtuais de projetos não são atualizados.
- Pacotes instalados pelo APT devem ser atualizados pelo próprio APT.
- O ambiente virtual auxiliar é independente dos projetos.

## Comportamento e robustez

- **Trava de execução:** uma pasta `%TEMP%\atualizacoes.lock` é criada no
  início e removida no fim. Se o script for interrompido, use
  `--ignorar-trava` na próxima execução.
- **Tempo limite:** cada comando externo é encerrado após `--timeout`
  segundos (código interno `124`) e conta como falha. Na etapa Linux o
  limite cobre a sessão inteira (`update` + `full-upgrade` + `autoremove`).
  No PowerShell 7 a árvore de processos é encerrada; no 5.1 o processo
  direto é encerrado e, para comandos do WSL, a distribuição é terminada
  com `wsl --terminate`.
- **Codificação:** o console é ajustado para UTF-8 e o Python recebe
  `PYTHONIOENCODING=utf-8`; saídas UTF-16 do `wsl.exe` são convertidas.
- **Winget:** `0x8A150014` (nenhuma atualização aplicável) e `0x8A15002B`
  (nenhum instalador aplicável) são tratados como sucesso.
- **APT:** as opções `Dpkg::Options::=--force-confdef` e
  `Dpkg::Options::=--force-confold` são passadas como entradas de lista,
  mantendo as configurações existentes sem prompts.

## Avisos importantes

- `wsl --shutdown` encerra **todas** as distribuições em execução; salve o
  trabalho antes.
- `apt-get full-upgrade` pode instalar ou remover pacotes.
- `apt-get autoremove` pode remover dependências que deixaram de ser
  necessárias.
- A atualização em massa de pacotes Python pode introduzir incompatibilidades
  em projetos que dependem de versões específicas. Use `--sem-pacotes` ou
  ambientes virtuais por projeto.
- O script não reinicia o Windows automaticamente; apenas detecta
  reinicializações pendentes.
- Evite usar `--winget-silencioso` se algum aplicativo exigir interface.

## Solução de problemas

### O lançador não encontra o PowerShell

O Windows 10/11 inclui o PowerShell 5.1 em
`%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`; confirme que
esse arquivo existe. O `.bat` também procura `pwsh.exe` no `PATH`, em
`%ProgramFiles%\PowerShell\7` e no alias da Microsoft Store, e o usa quando
presente.

### O Winget não foi encontrado

Instale ou atualize o **App Installer** pela Microsoft Store e confirme que
`winget --version` funciona no Prompt de Comando.

### O Python não foi encontrado no Windows

Confirme que `py -3 --version` ou `python --version` funciona. Ajuste o
`PATH` ou reinstale o Python marcando a opção para adicioná-lo ao `PATH`.

### O pip do WSL está bloqueado pelo PEP 668

O script evita `--break-system-packages`. Para projetos, use um ambiente
virtual por projeto; o `pip` global deve ser atualizado pelo APT.

### O APT parou em uma pergunta ou pediu a senha várias vezes

O script usa opções não interativas, mas configurações personalizadas podem
exigir intervenção. Consulte `wsl.log` para identificar o pacote ou arquivo
envolvido.

### A etapa Linux falhou por falta de sudo

A autenticação do `sudo` acontece uma vez, no início do APT. Se aparecer
`o sudo exige senha e as credenciais nao foram validadas`, execute o script
manualmente em um terminal (com entrada interativa) ou libere os comandos
usados no `sudoers` com `NOPASSWD`. O script não usa `sudo -S` nem guarda a
senha: ele cria um pseudo-terminal com `script` apenas para o `sudo -v` e,
na mesma sessão, usa o cache normal do `sudo` (que expira conforme a
configuração do sistema, normalmente 15 minutos).

### Nenhuma distribuição WSL foi encontrada

Confirme que existe ao menos uma distribuição instalada:

```bat
wsl.exe -l -v
```

Se necessário, instale uma com `wsl.exe --install -d Ubuntu`.

### O script retornou código 3

Há uma trava de `%TEMP%\atualizacoes.lock` de uma execução anterior. Confirme
que não há outra execução ativa e use `--ignorar-trava`.

### A execução não termina em uma tarefa agendada

Use `--sem-confirmacao` e `--sem-pausa`. Considere também `--timeout` para
evitar que um instalador travado bloqueie a tarefa.

### Uma etapa ficou lenta e foi encerrada

O log indica `Tempo limite de Ns excedido`. Aumente `--timeout` (ou use 0 para
desativar) em redes lentas.

## Desenvolvimento

```text
.
├── atualizacoes.bat          # lançador (localiza o PowerShell)
├── atualizacoes.ps1          # implementação principal (PowerShell 5.1+)
├── scripts/
│   └── wsl.sh                # rotinas executadas dentro do WSL
├── tests/
│   └── smoke.ps1             # testes de argumentos e códigos de saída
├── .github/workflows/ci.yml  # CI: sintaxe, PSScriptAnalyzer, testes, shellcheck
├── .gitattributes
├── .gitignore
├── CHANGELOG.md
├── LICENSE
└── README.md
```

Verificações locais (use `pwsh` no PowerShell 7 ou `powershell.exe` no 5.1):

```powershell
# Sintaxe
pwsh -NoProfile -Command "[void][System.Management.Automation.Language.Parser]::ParseFile('atualizacoes.ps1', [ref]`$null, [ref]`$erros); `$erros"

# Testes de argumentos
pwsh -NoProfile -File tests/smoke.ps1

# ShellCheck (Linux/WSL)
shellcheck --severity=warning scripts/wsl.sh
```

A CI do GitHub Actions roda esses passos em `windows-latest` e
`ubuntu-latest`. Ela não executa atualizações reais.

## Licença

Distribuído sob a licença MIT. Consulte [LICENSE](LICENSE).
