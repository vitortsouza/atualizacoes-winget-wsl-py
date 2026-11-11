#Requires -Version 5.1
<#
.SYNOPSIS
    Atualiza Winget, WSL, pacotes Linux (APT) e Python no Windows e no WSL.

.DESCRIPTION
    Executa as etapas em sequencia, com confirmacao, modo de listagem,
    logs por execucao, limite de tempo por comando e codigos de saida
    apropriados para uso manual ou em automacao.

    A logica executada dentro do WSL fica em scripts/wsl.sh.

.PARAMETER Listar
    Mostra o que seria atualizado, sem instalar nada.

.PARAMETER SemPausa
    Nao aguarda uma tecla ao final.

.PARAMETER SemConfirmacao
    Nao pede confirmacao antes de iniciar.

.PARAMETER SemPacotes
    Nao atualiza pacotes Python do usuario (o pip ainda e atualizado).

.PARAMETER SemPip
    Nao atualiza o proprio pip.

.PARAMETER SemAutoremove
    Nao executa apt-get autoremove.

.PARAMETER Distro
    Distribuicao WSL alvo. Padrao: a distribuicao default.

.PARAMETER Somente
    Lista separada por virgulas com as etapas desejadas:
    winget, wsl, linux, python.

.PARAMETER LogDir
    Diretorio base dos logs. Padrao: %TEMP%\atualizacoes.

.PARAMETER Timeout
    Limite em segundos por comando externo (0 desativa). Padrao: 3600.

.PARAMETER WingetSilencioso
    Adiciona --silent ao Winget (pode quebrar instaladores que exigem UI).

.PARAMETER Ajuda
    Mostra a ajuda.

.PARAMETER Versao
    Mostra a versao do script.
#>

$ErrorActionPreference = 'Stop'

$script:Versao = '2.0.0'
$script:Falhas = 0
$script:Writers = @{}
$script:RunDir = ''
$script:LogGeral = ''
$script:LogWinget = ''
$script:LogPython = ''
$script:LogWsl = ''
$script:Distro = ''
$script:WslDisponivel = $false
$script:PyExe = ''
$script:PyPrefixo = @()
$script:Opt = @{}
$script:Trava = Join-Path $env:TEMP 'atualizacoes.lock'

function Show-Ajuda {
    @'
Uso: atualizacoes.bat [opcoes]

Opcoes:
  --listar, -n          mostra o que seria atualizado, sem instalar
  --sem-pausa           nao pausa ao final (uso em automacao)
  --sem-confirmacao, -y  nao pede confirmacao antes de comecar
  --sem-pacotes         nao atualiza pacotes Python do usuario
  --sem-pip             nao atualiza o proprio pip
  --sem-autoremove      nao executa apt-get autoremove
  --distro NOME         distribuicao WSL alvo (padrao: a default)
  --somente LISTA       etapas: winget,wsl,linux,python (padrao: todas)
  --log-dir DIR         diretorio base dos logs (padrao: %TEMP%\atualizacoes)
  --timeout SEGUNDOS    limite por comando externo; 0 desativa (padrao: 3600)
  --winget-silencioso   adiciona --silent ao Winget
  --versao, -V          mostra a versao
  --ajuda, -h, /?       mostra esta ajuda
  --ignorar-trava       remove a trava de execucao de uma execucao anterior

Codigos de saida:
  0 = execucao sem falhas
  1 = uma ou mais etapas falharam ou a execucao foi cancelada
  2 = opcao de linha de comando invalida
  3 = outra execucao em andamento (trava ativa)
'@ | Write-Host
}

function Get-LogWriter {
    param([Parameter(Mandatory)][string]$Caminho)

    if (-not $script:Writers.ContainsKey($Caminho)) {
        $writer = [System.IO.StreamWriter]::new(
            $Caminho,
            $true,
            [System.Text.UTF8Encoding]::new($false))
        $writer.AutoFlush = $true
        $script:Writers[$Caminho] = $writer
    }

    return $script:Writers[$Caminho]
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Mensagem,
        [ValidateSet('INFO', 'OK', 'AVISO', 'ERRO', 'ETAPA')][string]$Nivel = 'INFO',
        [string]$Arquivo = $script:LogGeral
    )

    $linha = '[{0}] {1,-5} {2}' -f (Get-Date -Format 's'), $Nivel, $Mensagem
    if ($Arquivo) {
        (Get-LogWriter -Caminho $Arquivo).WriteLine($linha)
    }

    $cor = switch ($Nivel) {
        'OK' { 'Green' }
        'AVISO' { 'Yellow' }
        'ERRO' { 'Red' }
        'ETAPA' { 'Cyan' }
        default { 'Gray' }
    }
    Write-Host $Mensagem -ForegroundColor $cor
}

function Write-Etapa {
    param([int]$Numero, [int]$Total, [string]$Titulo)
    Write-Log -Mensagem ('[{0}/{1}] {2}' -f $Numero, $Total, $Titulo) -Nivel ETAPA
}

function Read-LinhaDisponivel {
    param(
        [Parameter(Mandatory)][System.IO.StreamReader]$Leitor,
        [System.Threading.Tasks.Task]$Tarefa,
        [Parameter(Mandatory)][System.Text.StringBuilder]$Buffer,
        [string]$LogArquivo,
        [bool]$Silencioso,
        [int]$EsperaMs
    )

    if ($null -eq $Tarefa) { return $null }

    try {
        if (-not $Tarefa.Wait($EsperaMs)) { return $Tarefa }
        $linha = $Tarefa.Result
    }
    catch {
        return $null
    }

    if ($null -eq $linha) { return $null }

    # Alguns comandos do wsl.exe respondem em UTF-16LE.
    $linha = ($linha -replace "`0", '').TrimStart([char]0xFEFF)
    if ([string]::IsNullOrWhiteSpace($linha)) {
        return $Leitor.ReadLineAsync()
    }

    [void]$Buffer.AppendLine($linha)
    if (-not $Silencioso) { Write-Host $linha }
    if ($LogArquivo) { (Get-LogWriter -Caminho $LogArquivo).WriteLine($linha) }

    return $Leitor.ReadLineAsync()
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string]$Arquivo,
        [string[]]$Argumentos = @(),
        [string]$LogArquivo = $script:LogGeral,
        [int]$LimiteSeg = -1,
        [switch]$Silencioso,
        [ValidateSet('utf8', 'unicode')][string]$Codificacao = 'utf8'
    )

    $resultado = [pscustomobject]@{
        Codigo     = 127
        SaidaTexto = ''
        SaidaErro  = ''
        Expirou    = $false
    }

    if ($LimiteSeg -lt 0) { $LimiteSeg = [int]$script:Opt.Timeout }

    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $Arquivo
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $encoder = if ($Codificacao -eq 'unicode') {
        [System.Text.Encoding]::Unicode
    }
    else {
        [System.Text.UTF8Encoding]::new($false)
    }
    $info.StandardOutputEncoding = $encoder
    $info.StandardErrorEncoding = $encoder
    # citação apenas quando necessario: alguns executaveis (wsl.exe) interpretam
    # a linha de comando bruta e nao removem aspas simples de argumentos curtos.
    $info.Arguments = ($Argumentos | ForEach-Object {
            $arg = [string]$_
            if ($arg -eq '') { '""' }
            elseif ($arg -notmatch '[\s"]') { $arg }
            else {
                $escapado = $arg -replace '(\\*)"', '$1$1\"'
                if ($escapado -match '\\$') { $escapado += '\' }
                '"' + $escapado + '"'
            }
        }) -join ' '

    $proc = [System.Diagnostics.Process]::new()
    $proc.StartInfo = $info

    try {
        [void]$proc.Start()
    }
    catch {
        Write-Log -Mensagem ('Nao foi possivel executar {0}: {1}' -f $Arquivo, $_.Exception.Message) -Nivel ERRO -Arquivo $LogArquivo
        return $resultado
    }

    $saida = [System.Text.StringBuilder]::new()
    $erros = [System.Text.StringBuilder]::new()
    $tarefaOut = $proc.StandardOutput.ReadLineAsync()
    $tarefaErr = $proc.StandardError.ReadLineAsync()
    $limite = if ($LimiteSeg -gt 0) { (Get-Date).AddSeconds($LimiteSeg) } else { [datetime]::MaxValue }

    try {
        while ($true) {
            $tarefaOut = Read-LinhaDisponivel -Leitor $proc.StandardOutput -Tarefa $tarefaOut `
                -Buffer $saida -LogArquivo $LogArquivo -Silencioso $Silencioso.IsPresent -EsperaMs 150
            $tarefaErr = Read-LinhaDisponivel -Leitor $proc.StandardError -Tarefa $tarefaErr `
                -Buffer $erros -LogArquivo $LogArquivo -Silencioso $Silencioso.IsPresent -EsperaMs 150

            if ($proc.HasExited -and $null -eq $tarefaOut -and $null -eq $tarefaErr) { break }

            if ((Get-Date) -ge $limite) {
                $resultado.Expirou = $true
                try { $proc.Kill($true) }
                catch {
                    try { $proc.Kill() } catch { }
                }
                Write-Log -Mensagem ('Tempo limite de {0}s excedido: {1}' -f $LimiteSeg, $Arquivo) -Nivel AVISO -Arquivo $LogArquivo
                break
            }

            if ($null -eq $tarefaOut -and $null -eq $tarefaErr) {
                Start-Sleep -Milliseconds 100
            }
        }

        $proc.WaitForExit()

        if ($resultado.Expirou) {
            $resultado.Codigo = 124
        }
        else {
            $resultado.Codigo = $proc.ExitCode
        }

        $resultado.SaidaTexto = $saida.ToString()
        $resultado.SaidaErro = $erros.ToString()
    }
    finally {
        $proc.Dispose()
    }

    return $resultado
}

function Resolve-Wsl {
    if ($script:WslDisponivel) { return $true }

    if (-not (Get-Command 'wsl.exe' -ErrorAction SilentlyContinue)) {
        Write-Log -Mensagem 'WSL nao encontrado.' -Nivel AVISO
        return $false
    }

    $lista = Invoke-Native -Arquivo 'wsl.exe' -Argumentos @('-l', '-q') -Silencioso -LimiteSeg 120 -Codificacao unicode
    $nomes = @()
    if ($lista.Codigo -eq 0) {
        $nomes = @(($lista.SaidaTexto -replace "`0", '') -split "`r?`n" |
            ForEach-Object { $_.Trim().TrimStart([char]0xFEFF) } |
            Where-Object { $_ -and $_ -notmatch '^NAME' })
    }

    if ($nomes.Count -eq 0) {
        Write-Log -Mensagem 'Nenhuma distribuicao WSL instalada.' -Nivel AVISO
        return $false
    }

    $padrao = ''
    $detalhada = Invoke-Native -Arquivo 'wsl.exe' -Argumentos @('-l', '-v') -Silencioso -LimiteSeg 120 -Codificacao unicode
    if ($detalhada.Codigo -eq 0) {
        foreach ($linha in (($detalhada.SaidaTexto -replace "`0", '') -split "`r?`n")) {
            $texto = $linha.Trim().TrimStart([char]0xFEFF)
            if ($texto -match '^\*\s+(\S+)') {
                $padrao = $Matches[1]
                break
            }
        }
    }
    if (-not $padrao) { $padrao = $nomes[0] }

    if ($script:Opt.Distro) {
        $achada = $nomes | Where-Object { $_ -ieq $script:Opt.Distro } | Select-Object -First 1
        if (-not $achada) {
            Write-Log -Mensagem ('Distribuicao "{0}" nao encontrada. Disponiveis: {1}' -f $script:Opt.Distro, ($nomes -join ', ')) -Nivel ERRO
            return $false
        }
        $script:Distro = $achada
    }
    else {
        $script:Distro = $padrao
    }

    $script:WslDisponivel = $true
    Write-Log -Mensagem ('WSL: usando a distribuicao "{0}".' -f $script:Distro)
    return $true
}

function Invoke-WslScript {
    param(
        [Parameter(Mandatory)][string]$Comando,
        [string[]]$Argumentos = @(),
        [int]$LimiteSeg = -1,
        [switch]$Silencioso
    )

    if (-not (Resolve-Wsl)) { return $null }

    $scriptWin = Join-Path $PSScriptRoot 'scripts/wsl.sh'
    if (-not (Test-Path -LiteralPath $scriptWin)) {
        Write-Log -Mensagem ('Arquivo auxiliar nao encontrado: {0}' -f $scriptWin) -Nivel ERRO
        return $null
    }

    if ($scriptWin -notmatch '^[A-Za-z]:\\') {
        Write-Log -Mensagem ('O projeto precisa estar em uma unidade local do Windows (C:, D:...): {0}' -f $scriptWin) -Nivel ERRO
        return $null
    }

    # Converte C:\pasta\wsl.sh em /mnt/c/pasta/wsl.sh (sem depender de wslpath).
    $linuxPath = '/mnt/' + $scriptWin.Substring(0, 1).ToLowerInvariant() + ($scriptWin.Substring(2) -replace '\\', '/')

    $seguro = $linuxPath.Replace("'", "'\''")
    $sufixo = ''
    if ($Argumentos.Count -gt 0) {
        $sufixo = ' ' + (($Argumentos | ForEach-Object { $_.Replace("'", "'\''") }) -join ' ')
    }

    $comandoBash = "tr -d '\r' < '$seguro' > /tmp/atualizacoes-wsl.sh && exec bash --noprofile --norc /tmp/atualizacoes-wsl.sh $Comando$sufixo"
    $argsWsl = @('-d', $script:Distro, '--', 'bash', '--noprofile', '--norc', '-c', $comandoBash)

    $resultado = Invoke-Native -Arquivo 'wsl.exe' -Argumentos $argsWsl -LogArquivo $script:LogWsl -LimiteSeg $LimiteSeg -Silencioso:$Silencioso

    if ($null -ne $resultado -and $resultado.Expirou) {
        Write-Log -Mensagem ('Encerrando a distribuicao {0} para interromper o comando...' -f $script:Distro) -Nivel AVISO
        [void](Invoke-Native -Arquivo 'wsl.exe' -Argumentos @('--terminate', $script:Distro) `
                -LogArquivo $script:LogWsl -LimiteSeg 120 -Codificacao unicode)
    }

    return $resultado
}

function Find-PythonWindows {
    $candidatos = @(
        [pscustomobject]@{ Exe = 'py.exe'; Prefixo = @('-3') },
        [pscustomobject]@{ Exe = 'python.exe'; Prefixo = @() },
        [pscustomobject]@{ Exe = 'python3.exe'; Prefixo = @() }
    )

    foreach ($candidato in $candidatos) {
        if (-not (Get-Command $candidato.Exe -ErrorAction SilentlyContinue)) { continue }
        $teste = Invoke-Native -Arquivo $candidato.Exe `
            -Argumentos ($candidato.Prefixo + @('-c', 'import sys')) `
            -Silencioso -LimiteSeg 60
        if ($teste.Codigo -eq 0) { return $candidato }
    }

    return $null
}

function Invoke-Python {
    param(
        [string[]]$Argumentos = @(),
        [string]$LogArquivo = $script:LogPython,
        [switch]$Silencioso,
        [int]$LimiteSeg = 600
    )

    return Invoke-Native -Arquivo $script:PyExe `
        -Argumentos ($script:PyPrefixo + $Argumentos) `
        -LogArquivo $LogArquivo -Silencioso:$Silencioso -LimiteSeg $LimiteSeg
}

function Invoke-EtapaWinget {
    param([int]$Numero, [int]$Total)

    if ($script:Opt.Listar) {
        Write-Etapa -Numero $Numero -Total $Total -Titulo 'Consultando atualizacoes do Winget...'
    }
    else {
        Write-Etapa -Numero $Numero -Total $Total -Titulo 'Atualizando aplicativos com Winget...'
    }

    if (-not (Get-Command 'winget.exe' -ErrorAction SilentlyContinue)) {
        Write-Log -Mensagem 'Winget nao encontrado. Instale o App Installer.' -Nivel AVISO
        $script:Falhas++
        return
    }

    [void](Invoke-Native -Arquivo 'winget.exe' -Argumentos @('--version') -LogArquivo $script:LogWinget -LimiteSeg 120)

    $desconhecido = @()
    $ajuda = Invoke-Native -Arquivo 'winget.exe' -Argumentos @('upgrade', '--help') -Silencioso -LimiteSeg 120
    if ($ajuda.SaidaTexto -match '--include-unknown') { $desconhecido = @('--include-unknown') }

    if ($script:Opt.Listar) {
        Write-Log -Mensagem 'Modo lista: mostrando atualizacoes disponiveis...'
        $r = Invoke-Native -Arquivo 'winget.exe' -Argumentos (@('upgrade') + $desconhecido) -LogArquivo $script:LogWinget
        if ($r.Codigo -ne 0) {
            Write-Log -Mensagem ('AVISO: listagem do Winget retornou codigo {0}.' -f $r.Codigo) -Nivel AVISO
            $script:Falhas++
        }
        else {
            Write-Log -Mensagem 'Listagem do Winget concluida.' -Nivel OK
        }
        return
    }

    $argumentos = @('upgrade', '--all') + $desconhecido + @(
        '--accept-source-agreements',
        '--accept-package-agreements',
        '--disable-interactivity'
    )
    if ($script:Opt.WingetSilencioso) { $argumentos += '--silent' }

    $r = Invoke-Native -Arquivo 'winget.exe' -Argumentos $argumentos -LogArquivo $script:LogWinget

    # 0x8A150014 e 0x8A15002B significam "nada aplicavel", nao falha real.
    $benignos = @(0, -1978335212, -1978335189)
    if ($benignos -contains $r.Codigo) {
        Write-Log -Mensagem ('Winget concluido (codigo {0}).' -f $r.Codigo) -Nivel OK
    }
    else {
        Write-Log -Mensagem ('AVISO: Winget retornou codigo {0}. Consulte {1}' -f $r.Codigo, $script:LogWinget) -Nivel AVISO
        $script:Falhas++
    }
}

function Invoke-EtapaWsl {
    param([int]$Numero, [int]$Total)

    if ($script:Opt.Listar) {
        Write-Etapa -Numero $Numero -Total $Total -Titulo 'Consultando o WSL...'
    }
    else {
        Write-Etapa -Numero $Numero -Total $Total -Titulo 'Atualizando o WSL...'
    }

    if (-not (Resolve-Wsl)) {
        $script:Falhas++
        return
    }

    if ($script:Opt.Listar) {
        [void](Invoke-Native -Arquivo 'wsl.exe' -Argumentos @('--version') -LogArquivo $script:LogWsl -LimiteSeg 120 -Codificacao unicode)
        Write-Log -Mensagem 'Modo lista: wsl --shutdown nao sera executado.'
        return
    }

    $atualizacao = Invoke-Native -Arquivo 'wsl.exe' -Argumentos @('--update') -LogArquivo $script:LogWsl -LimiteSeg $script:Opt.Timeout -Codificacao unicode
    if ($atualizacao.Codigo -ne 0) {
        Write-Log -Mensagem ('AVISO: wsl --update retornou codigo {0}. Consulte {1}' -f $atualizacao.Codigo, $script:LogWsl) -Nivel AVISO
        $script:Falhas++
    }
    else {
        Write-Log -Mensagem 'WSL atualizado.' -Nivel OK
    }

    $parada = Invoke-Native -Arquivo 'wsl.exe' -Argumentos @('--shutdown') -LogArquivo $script:LogWsl -LimiteSeg 300
    if ($parada.Codigo -ne 0) {
        Write-Log -Mensagem 'AVISO: falha ao encerrar as instancias do WSL.' -Nivel AVISO
        $script:Falhas++
    }
    else {
        Write-Log -Mensagem 'Instancias do WSL encerradas.' -Nivel OK
    }
}

function Invoke-EtapaLinux {
    param([int]$Numero, [int]$Total)

    if ($script:Opt.Listar) {
        Write-Etapa -Numero $Numero -Total $Total -Titulo 'Simulando a atualizacao dos pacotes Linux...'
    }
    else {
        Write-Etapa -Numero $Numero -Total $Total -Titulo 'Atualizando pacotes Linux...'
    }

    if (-not (Resolve-Wsl)) {
        $script:Falhas++
        return
    }

    if ($script:Opt.Listar) {
        $r = Invoke-WslScript -Comando 'info-apt' -LimiteSeg $script:Opt.Timeout
        if ($null -eq $r -or $r.Codigo -ne 0) {
            Write-Log -Mensagem 'AVISO: nao foi possivel simular os pacotes Linux.' -Nivel AVISO
            $script:Falhas++
        }
        else {
            Write-Log -Mensagem 'Simulacao dos pacotes Linux concluida.' -Nivel OK
        }
        return
    }

    $acoes = @(
        [pscustomobject]@{ Nome = 'apt-get update'; Comando = 'apt-update' },
        [pscustomobject]@{ Nome = 'apt-get full-upgrade'; Comando = 'apt-upgrade' }
    )
    if ($script:Opt.Autoremove) {
        $acoes += [pscustomobject]@{ Nome = 'apt-get autoremove'; Comando = 'apt-autoremove' }
    }

    foreach ($acao in $acoes) {
        Write-Log -Mensagem ('Executando {0}...' -f $acao.Nome)
        $r = Invoke-WslScript -Comando $acao.Comando -LimiteSeg $script:Opt.Timeout
        if ($null -eq $r) {
            $script:Falhas++
            return
        }
        if ($r.Codigo -ne 0) {
            Write-Log -Mensagem ('AVISO: {0} falhou (codigo {1}). Consulte {2}' -f $acao.Nome, $r.Codigo, $script:LogWsl) -Nivel AVISO
            $script:Falhas++
        }
        else {
            Write-Log -Mensagem ('{0} concluido.' -f $acao.Nome) -Nivel OK
        }
    }
}

function Invoke-PythonWindows {
    $py = Find-PythonWindows
    if ($null -eq $py) {
        Write-Log -Mensagem 'Python 3 nao encontrado no Windows. Verifique py -3 ou o PATH.' -Nivel AVISO
        $script:Falhas++
        return
    }

    $script:PyExe = $py.Exe
    $script:PyPrefixo = $py.Prefixo
    [void](Invoke-Python -Argumentos @('--version') -LimiteSeg 120)

    $pip = Invoke-Python -Argumentos @('-m', 'pip', '--version') -Silencioso
    if ($pip.Codigo -ne 0) {
        Write-Log -Mensagem 'pip indisponivel; tentando ensurepip...' -Nivel AVISO
        [void](Invoke-Python -Argumentos @('-m', 'ensurepip', '--upgrade'))
        $pip = Invoke-Python -Argumentos @('-m', 'pip', '--version') -Silencioso
    }
    if ($pip.Codigo -ne 0) {
        Write-Log -Mensagem 'Nao foi possivel disponibilizar o pip no Windows.' -Nivel AVISO
        $script:Falhas++
        return
    }

    if ($script:Opt.Listar) {
        Write-Host 'Pip e pacotes desatualizados no Windows:'
        [void](Invoke-Python -Argumentos @('-m', 'pip', 'list', '--user', '--outdated', '--disable-pip-version-check'))
        return
    }

    if ($script:Opt.AtualizarPip) {
        $r = Invoke-Python -Argumentos @('-m', 'pip', 'install', '--user', '--upgrade', 'pip', '--disable-pip-version-check')
        if ($r.Codigo -ne 0) {
            Write-Log -Mensagem 'pip --user falhou; tentando instalacao padrao...' -Nivel AVISO
            $r = Invoke-Python -Argumentos @('-m', 'pip', 'install', '--upgrade', 'pip', '--disable-pip-version-check')
        }
        if ($r.Codigo -ne 0) {
            Write-Log -Mensagem ('AVISO: falha ao atualizar o pip no Windows. Consulte {0}' -f $script:LogPython) -Nivel AVISO
            $script:Falhas++
        }
        else {
            Write-Log -Mensagem 'pip do Windows atualizado.' -Nivel OK
        }
    }
    else {
        Write-Log -Mensagem 'Atualizacao do pip ignorada (--sem-pip).'
    }

    if (-not $script:Opt.PacotesPython) {
        Write-Log -Mensagem 'Pacotes Python do usuario ignorados (--sem-pacotes).'
        return
    }

    $lista = Invoke-Python -Argumentos @(
        '-m', 'pip', 'list', '--user', '--outdated', '--format=json', '--disable-pip-version-check'
    ) -Silencioso
    if ($lista.Codigo -ne 0) {
        Write-Log -Mensagem ('AVISO: nao foi possivel listar os pacotes Python. Consulte {0}' -f $script:LogPython) -Nivel AVISO
        $script:Falhas++
        return
    }

    $texto = $lista.SaidaTexto.Trim()
    $pacotes = @()
    if ($texto) {
        try {
            $pacotes = @($texto | ConvertFrom-Json)
        }
        catch {
            Write-Log -Mensagem 'AVISO: resposta invalida ao listar os pacotes Python.' -Nivel AVISO
            $script:Falhas++
            return
        }
    }

    if ($pacotes.Count -eq 0) {
        Write-Log -Mensagem 'Nenhum pacote Python desatualizado no Windows.' -Nivel OK
        return
    }

    foreach ($pacote in $pacotes) {
        $nome = [string]$pacote.name
        if ([string]::IsNullOrWhiteSpace($nome)) { continue }
        Write-Log -Mensagem ('Atualizando pacote Windows: {0}' -f $nome)
        $atualizado = Invoke-Python -Argumentos @(
            '-m', 'pip', 'install', '--user', '--upgrade', $nome, '--disable-pip-version-check'
        )
        if ($atualizado.Codigo -ne 0) {
            Write-Log -Mensagem ('AVISO: falha ao atualizar {0}.' -f $nome) -Nivel AVISO
            $script:Falhas++
        }
    }
}

function Invoke-PythonWsl {
    if (-not (Resolve-Wsl)) {
        Write-Log -Mensagem 'Etapa Python no WSL ignorada: WSL indisponivel.'
        return
    }

    if ($script:Opt.Listar) {
        $r = Invoke-WslScript -Comando 'info-python' -LimiteSeg $script:Opt.Timeout
        if ($null -eq $r -or $r.Codigo -ne 0) {
            Write-Log -Mensagem 'AVISO: nao foi possivel consultar o Python no WSL.' -Nivel AVISO
            $script:Falhas++
        }
        else {
            Write-Log -Mensagem 'Consulta do Python no WSL concluida.' -Nivel OK
        }
        return
    }

    $argumentos = @()
    if (-not $script:Opt.AtualizarPip) { $argumentos += '--sem-pip' }

    $r = Invoke-WslScript -Comando 'python-prepare' -Argumentos $argumentos -LimiteSeg $script:Opt.Timeout
    if ($null -eq $r) {
        $script:Falhas++
        return
    }
    if ($r.Codigo -ne 0) {
        Write-Log -Mensagem ('AVISO: falha ao preparar o pip no WSL (codigo {0}). Consulte {1}' -f $r.Codigo, $script:LogWsl) -Nivel AVISO
        $script:Falhas++
        return
    }
    Write-Log -Mensagem 'Python e pip do WSL verificados.' -Nivel OK

    if (-not $script:Opt.PacotesPython) {
        Write-Log -Mensagem 'Pacotes Python do usuario ignorados (--sem-pacotes).'
        return
    }

    $r = Invoke-WslScript -Comando 'python-pacotes' -LimiteSeg $script:Opt.Timeout
    if ($null -eq $r -or $r.Codigo -ne 0) {
        $codigo = if ($null -eq $r) { 'desconhecido' } else { $r.Codigo }
        Write-Log -Mensagem ('AVISO: falha em pacotes Python do WSL (codigo {0}). Consulte {1}' -f $codigo, $script:LogWsl) -Nivel AVISO
        $script:Falhas++
    }
    else {
        Write-Log -Mensagem 'Pacotes Python do WSL verificados.' -Nivel OK
    }
}

function Invoke-EtapaPython {
    param([int]$Numero, [int]$Total)

    if ($script:Opt.Listar) {
        Write-Etapa -Numero $Numero -Total $Total -Titulo 'Consultando Python no Windows e no WSL...'
    }
    else {
        Write-Etapa -Numero $Numero -Total $Total -Titulo 'Atualizando pip e pacotes Python...'
    }

    Invoke-PythonWindows
    Invoke-PythonWsl
}

function Get-RebootPendente {
    $pendencias = @()

    $chaves = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    foreach ($chave in $chaves) {
        if (Test-Path -LiteralPath $chave) {
            $pendencias += 'Windows (CBS/Windows Update)'
            break
        }
    }

    $sessao = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' `
        -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
    if ($null -ne $sessao) { $pendencias += 'Windows (arquivos pendentes)' }

    if ($script:WslDisponivel) {
        $r = Invoke-WslScript -Comando 'reboot-status' -LimiteSeg 120 -Silencioso
        if ($null -ne $r -and $r.Codigo -eq 0 -and $r.SaidaTexto -match 'reboot-required') {
            $pendencias += 'WSL/Linux'
        }
    }

    return $pendencias
}

# ==========================================
# Argumentos
# ==========================================

$opt = @{
    Listar           = $false
    Pausa            = $true
    Confirmar        = $true
    PacotesPython    = $true
    AtualizarPip     = $true
    Autoremove       = $true
    WingetSilencioso = $false
    IgnorarTrava     = $false
    Distro           = ''
    Somente          = @()
    LogDir           = ''
    Timeout          = 3600
}
$etapasValidas = @('winget', 'wsl', 'linux', 'python')
$selecionadas = New-Object System.Collections.Generic.List[string]

$i = 0
while ($i -lt $args.Count) {
    $atual = [string]$args[$i]

    switch ($atual.ToLowerInvariant()) {
        '--ajuda' { Show-Ajuda; exit 0 }
        '-h' { Show-Ajuda; exit 0 }
        '/?' { Show-Ajuda; exit 0 }
        '--help' { Show-Ajuda; exit 0 }
        '--versao' { Write-Host ('atualizacoes {0}' -f $script:Versao); exit 0 }
        '-v' { Write-Host ('atualizacoes {0}' -f $script:Versao); exit 0 }
        '--listar' { $opt.Listar = $true }
        '-n' { $opt.Listar = $true }
        '--sem-pausa' { $opt.Pausa = $false }
        '--sem-confirmacao' { $opt.Confirmar = $false }
        '-y' { $opt.Confirmar = $false }
        '--sem-pacotes' { $opt.PacotesPython = $false }
        '--sem-pip' { $opt.AtualizarPip = $false }
        '--sem-autoremove' { $opt.Autoremove = $false }
        '--winget-silencioso' { $opt.WingetSilencioso = $true }
        '--ignorar-trava' { $opt.IgnorarTrava = $true }
        '--distro' {
            if ($i + 1 -ge $args.Count) {
                Write-Host 'Falta o valor de --distro.'
                exit 2
            }
            $i++
            $opt.Distro = [string]$args[$i]
        }
        '--log-dir' {
            if ($i + 1 -ge $args.Count) {
                Write-Host 'Falta o valor de --log-dir.'
                exit 2
            }
            $i++
            $opt.LogDir = [string]$args[$i]
        }
        '--timeout' {
            if ($i + 1 -ge $args.Count) {
                Write-Host 'Falta o valor de --timeout.'
                exit 2
            }
            $i++
            $segundos = 0
            if (-not [int]::TryParse([string]$args[$i], [ref]$segundos) -or $segundos -lt 0) {
                Write-Host ('Valor invalido para --timeout: {0}' -f $args[$i])
                exit 2
            }
            $opt.Timeout = $segundos
        }
        '--somente' {
            if ($i + 1 -ge $args.Count) {
                Write-Host 'Falta o valor de --somente.'
                exit 2
            }
            $i++
            foreach ($item in ([string]$args[$i] -split ',')) {
                $nome = $item.Trim().ToLowerInvariant()
                if (-not $etapasValidas.Contains($nome)) {
                    Write-Host ('Etapa invalida: {0}. Use: {1}' -f $nome, ($etapasValidas -join ', '))
                    exit 2
                }
                if (-not $selecionadas.Contains($nome)) { $selecionadas.Add($nome) }
            }
        }
        default {
            Write-Host ('Opcao desconhecida: {0}' -f $atual)
            Write-Host 'Use --ajuda para ver as opcoes disponiveis.'
            exit 2
        }
    }

    $i++
}

if ($selecionadas.Count -gt 0) {
    $opt.Somente = @($selecionadas)
}
else {
    $opt.Somente = $etapasValidas
}
$script:Opt = $opt

# ==========================================
# Trava de execucao
# ==========================================

if ($opt.IgnorarTrava) {
    Remove-Item -LiteralPath $script:Trava -Recurse -Force -ErrorAction SilentlyContinue
}

try {
    New-Item -ItemType Directory -Path $script:Trava -ErrorAction Stop | Out-Null
    Set-Content -LiteralPath (Join-Path $script:Trava 'dono.txt') `
        -Value ('PID {0} em {1}' -f $PID, (Get-Date -Format 's')) -Encoding ascii
}
catch {
    Write-Host ('Outra execucao esta em andamento (trava: {0}).' -f $script:Trava) -ForegroundColor Yellow
    Write-Host 'Se nao houver execucao ativa, use --ignorar-trava.'
    exit 3
}

# ==========================================
# Logs, encoding e console
# ==========================================

$codigo = 0

try {
    $baseLog = if ($opt.LogDir) {
        [System.IO.Path]::GetFullPath($opt.LogDir)
    }
    else {
        Join-Path $env:TEMP 'atualizacoes'
    }
    New-Item -ItemType Directory -Path $baseLog -Force | Out-Null

    $runId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), (Get-Random -Minimum 1000 -Maximum 9999)
    $script:RunDir = Join-Path $baseLog $runId
    New-Item -ItemType Directory -Path $script:RunDir -Force | Out-Null

    $script:LogGeral = Join-Path $script:RunDir 'atualizacao.log'
    $script:LogWinget = Join-Path $script:RunDir 'winget.log'
    $script:LogPython = Join-Path $script:RunDir 'python.log'
    $script:LogWsl = Join-Path $script:RunDir 'wsl.log'

    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    }
    catch {
        # Console sem suporte a UTF-8; segue com o padrao.
    }
    $env:PYTHONIOENCODING = 'utf-8'
    $env:PYTHONUTF8 = '1'

    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host (' ATUALIZACOES {0}' -f $script:Versao) -ForegroundColor Cyan
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ''

    Write-Log -Mensagem ('Inicio em {0}' -f (Get-Date -Format 's'))
    Write-Log -Mensagem ('Logs desta execucao: {0}' -f $script:RunDir)
    if ($opt.Listar) { Write-Log -Mensagem 'Modo lista: nenhuma alteracao sera feita.' }

    $cancelado = $false
    if (-not $opt.Listar -and $opt.Confirmar) {
        Write-Host 'Este script pode:'
        Write-Host ' - atualizar aplicativos Windows pelo Winget;'
        Write-Host ' - atualizar o WSL e os pacotes da distribuicao Linux;'
        Write-Host ' - atualizar pip e pacotes Python do usuario no Windows e no WSL.'
        Write-Host ''
        Write-Host 'O WSL sera encerrado e os pacotes Python do usuario poderao ser'
        Write-Host 'atualizados em massa. Revise as alteracoes antes de continuar.'
        Write-Host ''
        $resposta = Read-Host 'Deseja continuar? [S/N]'
        if ($resposta -notmatch '^[sS]') { $cancelado = $true }
    }

    if ($cancelado) {
        Write-Log -Mensagem 'Operacao cancelada pelo usuario.' -Nivel AVISO
    }
    else {
        $ordem = @()
        foreach ($id in $etapasValidas) {
            if ($opt.Somente -contains $id) { $ordem += $id }
        }
        $total = $ordem.Count

        for ($n = 0; $n -lt $total; $n++) {
            $id = $ordem[$n]
            switch ($id) {
                'winget' { Invoke-EtapaWinget -Numero ($n + 1) -Total $total }
                'wsl' { Invoke-EtapaWsl -Numero ($n + 1) -Total $total }
                'linux' { Invoke-EtapaLinux -Numero ($n + 1) -Total $total }
                'python' { Invoke-EtapaPython -Numero ($n + 1) -Total $total }
            }
        }

        try {
            $pendencias = Get-RebootPendente
            if ($pendencias.Count -gt 0) {
                Write-Log -Mensagem ('Reinicializacao pendente: {0}.' -f ($pendencias -join '; ')) -Nivel AVISO
            }
            else {
                Write-Log -Mensagem 'Nenhuma reinicializacao pendente detectada.' -Nivel OK
            }
        }
        catch {
            Write-Log -Mensagem ('Nao foi possivel verificar reinicializacao pendente: {0}' -f $_.Exception.Message) -Nivel AVISO
        }
    }

    Write-Host ''
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host '      PROCESSO FINALIZADO' -ForegroundColor Cyan
    Write-Host '==========================================' -ForegroundColor Cyan
    Write-Host ''

    if ($opt.Listar) {
        Write-Host 'Modo lista: nenhuma instalacao/atualizacao foi solicitada.'
    }

    if ($cancelado) {
        $codigo = 1
    }
    elseif ($script:Falhas -eq 0) {
        Write-Log -Mensagem 'Nenhuma falha registrada.' -Nivel OK
        $codigo = 0
    }
    else {
        Write-Log -Mensagem ('Falhas registradas: {0}' -f $script:Falhas) -Nivel AVISO
        $codigo = 1
    }

    Write-Host ''
    Write-Host ('Log geral:  {0}' -f $script:LogGeral)
    Write-Host ('Log Winget: {0}' -f $script:LogWinget)
    Write-Host ('Log Python: {0}' -f $script:LogPython)
    Write-Host ('Log WSL:    {0}' -f $script:LogWsl)

    Write-Log -Mensagem ('Fim da execucao (codigo {0})' -f $codigo)
}
catch {
    $mensagem = 'Erro inesperado: {0}' -f $_.Exception.Message
    if ($script:LogGeral) {
        Write-Log -Mensagem $mensagem -Nivel ERRO
        Write-Log -Mensagem ('Linha {0}: {1}' -f $_.InvocationInfo.ScriptLineNumber, $_.InvocationInfo.Line.Trim()) -Nivel ERRO
    }
    else {
        Write-Host $mensagem -ForegroundColor Red
    }
    $codigo = 1
}
finally {
    foreach ($writer in $script:Writers.Values) {
        try { $writer.Dispose() } catch { }
    }
    Remove-Item -LiteralPath $script:Trava -Recurse -Force -ErrorAction SilentlyContinue
}

if ($opt.Pausa) {
    Write-Host ''
    [void](Read-Host 'Pressione Enter para sair')
}

exit $codigo
