@echo off
REM ==========================================================
REM  Lancador do atualizacoes.ps1.
REM  A logica fica em atualizacoes.ps1; este arquivo so
REM  localiza o PowerShell, repassa os argumentos e propaga
REM  o codigo de saida.
REM
REM  Prefere PowerShell 7+ (pwsh) quando disponivel e cai
REM  para o PowerShell 5.1 incluido no Windows.
REM ==========================================================
setlocal EnableExtensions

chcp 65001 >nul 2>&1

set "PS="
for %%P in (pwsh.exe) do if not defined PS set "PS=%%~$PATH:P"
if not defined PS if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PS=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PS if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" set "PS=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"
if not defined PS if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not defined PS for %%P in (powershell.exe) do if not defined PS set "PS=%%~$PATH:P"

if not defined PS (
    echo.
    echo PowerShell nao encontrado.
    echo O Windows normalmente inclui o PowerShell 5.1 em:
    echo   %SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
    echo.
    echo Se necessario, instale o PowerShell 7 com:
    echo   winget install --id Microsoft.PowerShell --source winget
    if "%~1"=="" pause
    endlocal & exit /b 1
)

"%PS%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0atualizacoes.ps1" %*
set "CODIGO=%ERRORLEVEL%"

endlocal & exit /b %CODIGO%
