# Atualização do Winget, WSL e Python

Script em lote (`.bat`) para automatizar a manutenção de aplicativos do
Windows, do Windows Subsystem for Linux (WSL), dos pacotes da distribuição
Linux via APT e dos componentes Python instalados no Windows e no WSL.

O script reúne as etapas em um único processo, com confirmação inicial, modo de
listagem, logs separados por etapa, tratamento de falhas e código de saída
adequado para uso manual ou em automação.

## Funcionalidades

- **Atualização do Winget:** atualiza os aplicativos disponíveis, incluindo
  aqueles cuja versão instalada é desconhecida quando o Winget oferece suporte
  ao parâmetro.
- **Atualização do pip no Windows:** localiza um Python 3 funcional, verifica o
  `pip`, tenta habilitá-lo com `ensurepip` quando necessário e executa sua
  atualização.
- **Atualização dos pacotes Python no Windows:** consulta os pacotes
  desatualizados do usuário em JSON, atualiza cada um individualmente e
  registra falhas sem interromper os demais.
- **Atualização do WSL:** verifica a disponibilidade do WSL e executa
  `wsl --update`.
- **Reinicialização do ambiente WSL:** encerra as instâncias em execução com
  `wsl --shutdown` antes da manutenção Linux. Essa etapa é ignorada no modo de
  listagem.
- **Atualização dos pacotes Linux:** executa `apt-get update`,
  `apt-get full-upgrade` e `apt-get autoremove` na distribuição padrão do WSL,
  com opções para reduzir prompts durante a atualização.
- **Atualização do pip no WSL:** instala `python3-pip` e `python3-venv` apenas
  quando necessário e atualiza o `pip` em um ambiente virtual auxiliar,
  respeitando o PEP 668.
- **Atualização dos pacotes Python no WSL:** identifica e atualiza os pacotes
  desatualizados do usuário, propagando o código de erro quando alguma
  atualização falha.
- **Modo de listagem:** mostra o que seria atualizado sem instalar nada.
- **Confirmação e automação:** pede confirmação antes das alterações, mas pode
  ser executado sem interação com `--sem-confirmacao` e `--sem-pausa`.
- **Logs separados:** grava logs do processo geral, do Winget, do Python e do
  WSL no diretório temporário do usuário.
- **Código de saída:** retorna `0` quando não há falhas, `1` quando alguma
  etapa falha ou a execução é cancelada e `2` para opções inválidas.

## Requisitos

- Windows 10 ou Windows 11 compatível com Winget e WSL.
- [Windows Package Manager (Winget)](https://learn.microsoft.com/pt-br/windows/package-manager/winget/).
- [Windows Subsystem for Linux (WSL)](https://learn.microsoft.com/pt-br/windows/wsl/).
- Uma distribuição Linux instalada no WSL que utilize APT, como Ubuntu ou
  Debian.
- Python 3 funcional no Windows, com `py -3` ou `python` disponível no `PATH`.
- Python 3 e `python3-pip` disponíveis ou instaláveis na distribuição Linux.
- `sudo` configurado para a distribuição Linux.
- Conexão com a internet para baixar atualizações e consultar os repositórios.

Alguns instaladores do Winget podem solicitar elevação (UAC). O `sudo` pode
solicitar a senha da distribuição Linux durante a execução.

## Como utilizar

1. Baixe ou copie o arquivo `atualizacoes.bat` para uma pasta de sua
   preferência. Mantenha o `README.md`, o `LICENSE` e o `.gitattributes` junto
   apenas se quiser versionar o projeto.
2. Abra o Prompt de Comando ou o Windows Terminal na pasta do arquivo.
3. Execute:

   ```bat
   atualizacoes.bat
   ```

   O nome correto é `atualizacoes.bat` (no plural).

4. Leia o resumo, confirme a execução e acompanhe as mensagens no terminal.
5. Ao final, consulte os caminhos dos logs exibidos.
6. Pressione uma tecla para fechar a janela, exceto quando usar
   `--sem-pausa`.

### Opções de linha de comando

| Opção | Descrição |
|---|---|
| `--listar` | Mostra o que seria atualizado, sem instalar ou atualizar pacotes. Não executa `wsl --shutdown`. |
| `--sem-pausa` | Não pausa ao final; útil para automação. |
| `--sem-confirmacao` | Não pede confirmação antes de iniciar. |
| `--sem-pacotes` | Não atualiza pacotes Python do usuário no Windows nem no WSL. O `pip` ainda é atualizado. |
| `--ajuda`, `-h` | Mostra a ajuda. |

Exemplos:

```bat
REM Apenas visualizar o que seria atualizado
atualizacoes.bat --listar

REM Executar sem interação (por exemplo, em uma tarefa agendada)
atualizacoes.bat --sem-confirmacao --sem-pausa

REM Atualizar tudo, exceto os pacotes Python do usuário
atualizacoes.bat --sem-pacotes
```

O modo `--listar` não altera pacotes, mas ainda consulta Winget, WSL e pip. A
simulação do APT usa os índices atuais da distribuição e **não** executa
`apt-get update`; para ver atualizações mais recentes, execute o script no modo
normal.

### Códigos de saída

| Código | Significado |
|---:|---|
| `0` | Execução concluída sem falhas registradas. |
| `1` | Uma ou mais etapas falharam ou a execução foi cancelada. |
| `2` | Opção de linha de comando inválida. |

## Etapas da execução

1. Atualiza os aplicativos do Windows com o Winget. No modo de listagem, apenas
   mostra as atualizações disponíveis.
2. Localiza o Python 3 no Windows, verifica o `pip` e atualiza o `pip` e os
   pacotes do usuário. No modo de listagem, apenas mostra a versão do `pip` e
   os pacotes desatualizados.
3. Verifica a disponibilidade do WSL e executa `wsl --update`. No modo de
   listagem, mostra a versão do WSL.
4. Encerra as instâncias do WSL com `wsl --shutdown`. No modo de listagem, essa
   etapa é ignorada.
5. Atualiza os índices, instala atualizações e remove pacotes desnecessários na
   distribuição Linux padrão. No modo de listagem, simula o `full-upgrade` com
   os índices atuais.
6. Verifica o Python e o `pip` no WSL, prepara `python3-pip`/`python3-venv`
   quando necessário, atualiza os pacotes do usuário e atualiza o `pip` no
   ambiente virtual auxiliar. No modo de listagem, apenas consulta as versões e
   os pacotes desatualizados.

As falhas são contabilizadas e o resumo final informa quantas etapas
apresentaram problemas. Uma falha em determinada etapa não interrompe
necessariamente as etapas seguintes.

## Atualização do Python e do pip

### Windows

O script testa primeiro `py -3 -c "import sys"` e, se falhar, tenta
`python -c "import sys"`. Isso evita considerar o launcher `py` disponível
quando ele existe, mas não consegue iniciar um interpretador.

As operações incluem:

- Verificação da versão do Python e da disponibilidade do `pip`.
- Tentativa de habilitar o `pip` por meio de `ensurepip`, caso necessário.
- Atualização do `pip` com `pip install --upgrade pip`.
- Consulta dos pacotes desatualizados do usuário em formato JSON.
- Atualização individual dos pacotes encontrados, com registro de falhas.

Use `--sem-pacotes` para atualizar apenas o `pip` e não os pacotes do usuário.

**Limitações:**

- O script usa o interpretador selecionado por `py -3` ou `python`; não garante
  a atualização de todas as versões Python instaladas no Windows.
- A atualização dos pacotes do usuário não abrange ambientes virtuais de
  projetos nem instalações globais.
- Pacotes que exigem permissões administrativas ou dependências específicas
  podem falhar.
- Não há rollback automático. Anote as versões atuais se precisar voltar atrás.

### WSL/Linux

O script atualiza primeiro os pacotes do sistema pelo APT. Depois, verifica se
`python3-pip` e `python3-venv` estão disponíveis; se não estiverem, tenta
instalá-los.

Em seguida, atualiza os pacotes Python instalados no espaço do usuário e usa um
ambiente virtual auxiliar para atualizar o próprio `pip`.

O ambiente virtual auxiliar é criado em:

```text
~/.venvs/atualizador-pip
```

Essa abordagem evita forçar uma atualização global do `pip` em distribuições
que protegem o Python do sistema.

A atualização dos pacotes do WSL agora propaga falhas: se algum `pip install`
falhar, o script registra o problema e retorna código de saída diferente de
zero.

**Limitações:**

- A atualização dos pacotes do usuário não abrange ambientes virtuais
  existentes nos projetos.
- Pacotes instalados pelo APT devem, em geral, ser atualizados pelo próprio
  APT.
- A disponibilidade do `pip`, as permissões e as políticas da distribuição
  Linux podem afetar o resultado.
- O ambiente virtual auxiliar é independente dos ambientes virtuais dos
  projetos.

### Ambientes virtuais e PEP 668

Algumas distribuições Linux implementam a proteção conhecida como PEP 668, que
impede a instalação ou atualização de pacotes Python diretamente no ambiente
gerenciado pelo sistema operacional.

O script não utiliza `--break-system-packages`, pois forçar essa operação pode
causar conflitos entre o `pip` e o gerenciador de pacotes do sistema.

Para atualizar as dependências de um projeto específico, ative o ambiente
virtual do projeto e execute:

```bash
python -m pip install --upgrade pip
python -m pip list --outdated
```

Para atualizar um pacote específico:

```bash
python -m pip install --upgrade nome-do-pacote
```

## Logs

Os arquivos de log são armazenados no diretório temporário do usuário do
Windows (`%TEMP%`) e são anexados a cada execução.

| Arquivo | Finalidade |
|---|---|
| `atualizacao.log` | Registra início, etapas, avisos, falhas e encerramento. |
| `winget-atualizacao.log` | Saída detalhada do Winget. |
| `python-atualizacao.log` | Saída do Python, `pip`, `ensurepip` e atualizações de pacotes no Windows. |
| `wsl-atualizacao.log` | Saída de `wsl --update`, `wsl --shutdown` e, ao final, o log interno das operações APT/pip executadas dentro do WSL. |

As saídas do APT e do `pip` no WSL são mostradas no terminal e gravadas em
`/tmp/atualizacao-wsl.log` dentro da distribuição. No encerramento, esse arquivo
é copiado para o log do Windows.

Para consultar os logs gerados pelo próprio Winget, utilize:

```bat
winget.exe --logs
```

## Comandos utilizados

| Comando | Descrição |
|---|---|
| `winget upgrade` | Mostra as atualizações disponíveis no modo de listagem. |
| `winget upgrade --all [--include-unknown]` | Atualiza os pacotes identificados pelo Winget, incluindo versões desconhecidas quando suportado. |
| `py -3 -m pip --version` | Verifica o `pip` do Python selecionado por `py -3`. |
| `python -m pip --version` | Verifica o `pip` do interpretador `python`. |
| `python -m ensurepip --upgrade` | Tenta habilitar ou atualizar o `pip` usando os recursos do Python. |
| `python -m pip install --upgrade pip` | Atualiza o `pip` no ambiente Python selecionado. |
| `python -m pip list --user --outdated --format=json` | Lista em JSON os pacotes desatualizados do usuário. |
| `python -m pip install --user --upgrade nome` | Atualiza um pacote Python no espaço do usuário. |
| `wsl --update` | Atualiza o WSL. |
| `wsl --shutdown` | Encerra as instâncias em execução do WSL. |
| `apt-get update` | Atualiza a lista de pacotes disponíveis. |
| `apt-get full-upgrade -y` | Instala atualizações, permitindo alterações nas dependências. |
| `apt-get autoremove -y` | Remove pacotes considerados desnecessários pelo APT. |
| `python3 -m venv` | Cria um ambiente virtual Python isolado. |
| `python3 -m pip install --upgrade pip` | Atualiza o `pip` no ambiente Python correspondente. |

As operações do APT usam `DEBIAN_FRONTEND=noninteractive`,
`NEEDRESTART_MODE=a` e opções de `dpkg` para reduzir prompts. Ainda assim,
revisões de configuração podem exigir atenção em ambientes personalizados.

## Avisos importantes

- O comando `wsl --shutdown` encerra todas as distribuições WSL em execução,
  interrompendo processos em andamento. Salve seu trabalho antes.
- O `apt-get full-upgrade` pode instalar ou remover pacotes para concluir as
  atualizações.
- O `apt-get autoremove` pode remover dependências que deixaram de ser
  necessárias.
- A atualização em massa de pacotes Python pode introduzir incompatibilidades
  em projetos que dependem de versões específicas. Use `--sem-pacotes` ou um
  ambiente virtual por projeto quando necessário.
- O script não reinicia o Windows automaticamente.
- O Python do Windows e o Python do WSL são instalações independentes.
- O modo `--listar` não instala nada, mas não é um congelamento total: ele
  consulta serviços e usa os índices atuais do APT.
- O script não garante a atualização de todas as versões do Python nem de todos
  os ambientes virtuais existentes.
- Evite executar duas instâncias do script ao mesmo tempo: os nomes dos logs são
  compartilhados e as execuções podem disputar os mesmos arquivos.
- Recomenda-se salvar o trabalho, manter cópias dos arquivos de dependências e
  revisar os logs antes de considerar a manutenção concluída.

## Solução de problemas

### O Winget não foi encontrado

Instale ou atualize o **App Installer** pela Microsoft Store e confirme que
`winget --version` funciona no Prompt de Comando.

### O Python não foi encontrado no Windows

Confirme que `py -3 --version` ou `python --version` funciona. Ajuste o `PATH`
ou reinstale o Python marcando a opção para adicioná-lo ao `PATH`.

### O pip do WSL está bloqueado pelo PEP 668

O script evita `--break-system-packages`. Para projetos, use um ambiente virtual
por projeto. O `pip` global do sistema deve ser atualizado preferencialmente pelo
APT.

### O APT parou em uma pergunta

O script usa opções não interativas, mas configurações personalizadas podem
exigir intervenção. Consulte o `wsl-atualizacao.log` e o terminal para identificar
o pacote ou arquivo de configuração envolvido.

### O WSL não foi encontrado

Confirme que o recurso WSL está habilitado e que `wsl --status` funciona. As
etapas do Windows continuam sendo executadas mesmo quando o WSL não está
disponível.

### O script retornou código 1

Consulte o resumo final e os logs indicados. O código `1` significa que pelo
menos uma etapa falhou; nem todas as etapas são interrompidas por causa disso.

### A execução não termina em uma tarefa agendada

Use `--sem-confirmacao` para evitar a pergunta inicial e `--sem-pausa` para não
aguardar uma tecla no final.

## Estrutura do projeto

```text
.
├── atualizacoes.bat   # Script principal
├── README.md          # Documentação
├── LICENSE            # Licença MIT
└── .gitattributes     # Normalização de finais de linha
```

## Licença

Distribuído sob a licença MIT. Consulte [LICENSE](LICENSE).
