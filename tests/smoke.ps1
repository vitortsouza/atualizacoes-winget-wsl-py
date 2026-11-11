#Requires -Version 5.1
<#
.SYNOPSIS
    Testes de fumaca dos argumentos de linha de comando.
.DESCRIPTION
    Executa o script como processo filho e valida os codigos de saida das
    opcoes que nao iniciam nenhuma alteracao no sistema.
#>

$ErrorActionPreference = 'Stop'

$raiz = Split-Path -Parent $PSScriptRoot
$alvo = Join-Path $raiz 'atualizacoes.ps1'
$pwsh = (Get-Process -Id $PID).Path
$falhas = 0

if (-not (Test-Path -LiteralPath $alvo)) {
    Write-Host ('Script nao encontrado: {0}' -f $alvo) -ForegroundColor Red
    exit 1
}

function Testar-Codigo {
    param(
        [Parameter(Mandatory)][string]$Nome,
        [Parameter(Mandatory)][int]$Esperado,
        [string[]]$Argumentos = @()
    )

    $saida = & $pwsh -NoLogo -NoProfile -File $alvo @Argumentos 2>&1
    $codigo = $LASTEXITCODE

    if ($codigo -ne $Esperado) {
        Write-Host ('FALHOU: {0} (esperado {1}, obtido {2})' -f $Nome, $Esperado, $codigo) -ForegroundColor Red
        $saida | ForEach-Object { Write-Host ('  {0}' -f $_) }
        $script:falhas++
        return
    }

    Write-Host ('ok: {0}' -f $Nome) -ForegroundColor Green
}

Testar-Codigo -Nome '--ajuda retorna 0' -Esperado 0 -Argumentos @('--ajuda')
Testar-Codigo -Nome '-h retorna 0' -Esperado 0 -Argumentos @('-h')
Testar-Codigo -Nome '--versao retorna 0' -Esperado 0 -Argumentos @('--versao')
Testar-Codigo -Nome 'opcao desconhecida retorna 2' -Esperado 2 -Argumentos @('--nao-existe')
Testar-Codigo -Nome '--somente invalido retorna 2' -Esperado 2 -Argumentos @('--somente', 'banana')
Testar-Codigo -Nome '--timeout invalido retorna 2' -Esperado 2 -Argumentos @('--timeout', 'abc')
Testar-Codigo -Nome '--timeout negativo retorna 2' -Esperado 2 -Argumentos @('--timeout', '-1')
Testar-Codigo -Nome '--distro sem valor retorna 2' -Esperado 2 -Argumentos @('--distro')

$versao = & $pwsh -NoLogo -NoProfile -File $alvo --versao 2>&1
if (("$versao" -match '^atualizacoes \d+\.\d+\.\d+') -eq $false) {
    Write-Host ('FALHOU: saida de --versao inesperada: {0}' -f $versao) -ForegroundColor Red
    $falhas++
}
else {
    Write-Host 'ok: formato de --versao' -ForegroundColor Green
}

if ($falhas -gt 0) {
    Write-Host ('{0} teste(s) falharam.' -f $falhas) -ForegroundColor Red
    exit 1
}

Write-Host 'Todos os testes passaram.' -ForegroundColor Green
exit 0
