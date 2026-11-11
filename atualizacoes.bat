@echo off
REM ==========================================================
REM  Lancador do atualizacoes.ps1 (requer PowerShell 7+).
REM  A logica fica em atualizacoes.ps1; este arquivo so
REM  localiza o pwsh, repassa os argumentos e propaga o
REM  codigo de saida.
REM ==========================================================
setlocal EnableExtensions

chcp 65001 >nul 2>&1

set "PWSH="
for %%P in (pwsh.exe) do if not defined PWSH set "PWSH=%%~$PATH:P"
if not defined PWSH if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not defined PWSH if exist "%ProgramFiles(x86)%\PowerShell\7\pwsh.exe" set "PWSH=%ProgramFiles(x86)%\PowerShell\7\pwsh.exe"
if not defined PWSH if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe" set "PWSH=%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe"

if not defined PWSH (
    echo.
    echo PowerShell 7 nao encontrado.
    echo Instale com:
    echo   winget install --id Microsoft.PowerShell --source winget
    echo.
    echo Ou baixe em: https://aka.ms/powershell-release
    if "%~1"=="" pause
    endlocal & exit /b 1
)

"%PWSH%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0atualizacoes.ps1" %*
set "CODIGO=%ERRORLEVEL%"

endlocal & exit /b %CODIGO%
