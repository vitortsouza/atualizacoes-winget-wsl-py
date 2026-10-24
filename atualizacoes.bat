@echo off
setlocal EnableExtensions

title Atualizacao do Winget, WSL e Python

set "LOG=%TEMP%\atualizacao.log"
set "WINGETLOG=%TEMP%\winget-atualizacao.log"
set "PYTHONLOG=%TEMP%\python-atualizacao.log"
set "WSL_LOG=%TEMP%\wsl-atualizacao.log"
set "PACOTES_JSON=%TEMP%\python-pacotes-desatualizados.json"
set "PACOTES_TXT=%TEMP%\python-pacotes-desatualizados.txt"

set "FALHAS=0"
set "PAUSA=1"
set "LISTAR=0"
set "CONFIRMAR=1"
set "PACOTES_PYTHON=1"
set "WSL_DISPONIVEL=0"

:argumentos
if "%~1"=="" goto :fim_argumentos

if /i "%~1"=="--ajuda" goto :ajuda
if /i "%~1"=="-h" goto :ajuda

if /i "%~1"=="--listar" (
    set "LISTAR=1"
    shift
    goto :argumentos
)

if /i "%~1"=="--sem-pausa" (
    set "PAUSA=0"
    shift
    goto :argumentos
)

if /i "%~1"=="--sem-confirmacao" (
    set "CONFIRMAR=0"
    shift
    goto :argumentos
)

if /i "%~1"=="--sem-pacotes" (
    set "PACOTES_PYTHON=0"
    shift
    goto :argumentos
)

echo Opcao desconhecida: %~1
echo Use --ajuda para ver as opcoes disponiveis.
endlocal & exit /b 2

:fim_argumentos

echo.
echo ==========================================
echo  ATUALIZACAO DO WINGET, WSL E PYTHON
echo ==========================================
echo.

echo.>> "%LOG%"
echo [%date% %time%] Inicio da atualizacao>> "%LOG%"
if "%LISTAR%"=="1" echo [%date% %time%] Modo lista (sem alteracoes)>> "%LOG%"

if "%LISTAR%"=="0" if "%CONFIRMAR%"=="1" (
    echo Este script pode:
    echo  - atualizar aplicativos Windows pelo Winget;
    echo  - atualizar o WSL e os pacotes da distribuicao Linux;
    echo  - atualizar pip e pacotes Python do usuario no Windows e no WSL.
    echo.
    echo O WSL sera encerrado e os pacotes Python do usuario poderao ser
    echo atualizados em massa. Revise as alteracoes antes de continuar.
    echo.
    choice /C SN /N /M "Deseja continuar? [S/N] "
    if errorlevel 2 goto :cancelado
)

REM ==========================================
REM 1 - Atualizar aplicativos Windows
REM ==========================================

echo.
echo [1/6] Atualizando aplicativos com Winget...
echo [%date% %time%] Inicio do Winget>> "%LOG%"

where winget.exe >nul 2>&1
if errorlevel 1 (
    echo AVISO: Winget nao encontrado. Instale o App Installer.
    echo [%date% %time%] Winget nao encontrado>> "%LOG%"
    set /a FALHAS+=1
    goto :python_windows
)

winget.exe --version >> "%WINGETLOG%" 2>&1

set "WINGET_INCLUDE="
winget.exe upgrade --help 2>&1 | findstr /C:"--include-unknown" >nul
if not errorlevel 1 set "WINGET_INCLUDE=--include-unknown"

if "%LISTAR%"=="1" (
    echo Modo lista: mostrando atualizacoes disponiveis...
    winget.exe upgrade %WINGET_INCLUDE%
    echo [%date% %time%] Winget: listagem concluida>> "%LOG%"
    goto :python_windows
)

winget.exe upgrade --all %WINGET_INCLUDE% --accept-source-agreements --accept-package-agreements --silent > "%WINGETLOG%" 2>&1
set "WINGET_RC=%ERRORLEVEL%"

if not "%WINGET_RC%"=="0" (
    echo AVISO: Winget retornou codigo %WINGET_RC%.
    echo Consulte: "%WINGETLOG%"
    echo [%date% %time%] Erro Winget: %WINGET_RC%>> "%LOG%"
    set /a FALHAS+=1
) else (
    echo Winget concluido.
    echo [%date% %time%] Winget concluido>> "%LOG%"
)

REM ==========================================
REM 2 - Atualizar pip e pacotes Python Windows
REM ==========================================

:python_windows
echo.
echo [2/6] Atualizando Python, pip e pacotes no Windows...
echo [%date% %time%] Inicio Python Windows>> "%LOG%"

set "PYTHON_CMD="
py -3 -c "import sys" >nul 2>&1
if not errorlevel 1 set "PYTHON_CMD=py -3"

if not defined PYTHON_CMD (
    python -c "import sys" >nul 2>&1
    if not errorlevel 1 set "PYTHON_CMD=python"
)

if not defined PYTHON_CMD (
    echo AVISO: Python 3 nao encontrado no Windows.
    echo Instale o Python ou verifique o PATH.
    echo [%date% %time%] Python Windows nao encontrado>> "%LOG%"
    set /a FALHAS+=1
    goto :wsl_update
)

echo Python encontrado: %PYTHON_CMD%
%PYTHON_CMD% --version >> "%PYTHONLOG%" 2>&1

%PYTHON_CMD% -m pip --version >nul 2>&1
if errorlevel 1 (
    echo AVISO: pip nao esta disponivel no Windows.
    echo Tentando habilitar pip...
    %PYTHON_CMD% -m ensurepip --upgrade >> "%PYTHONLOG%" 2>&1
)

%PYTHON_CMD% -m pip --version >nul 2>&1
if errorlevel 1 (
    echo AVISO: Nao foi possivel disponibilizar o pip.
    echo [%date% %time%] pip Windows indisponivel>> "%LOG%"
    set /a FALHAS+=1
    goto :wsl_update
)

if "%LISTAR%"=="1" (
    echo.
    echo Pip do Windows:
    %PYTHON_CMD% -m pip --version
    echo.
    echo Pacotes Python desatualizados no Windows:
    %PYTHON_CMD% -m pip list --user --outdated --disable-pip-version-check
    echo [%date% %time%] Python Windows: listagem concluida>> "%LOG%"
    goto :wsl_update
)

echo Atualizando pip no Windows...
%PYTHON_CMD% -m pip install --upgrade pip --disable-pip-version-check >> "%PYTHONLOG%" 2>&1
if errorlevel 1 (
    echo AVISO: Falha ao atualizar pip no Windows.
    echo Consulte: "%PYTHONLOG%"
    echo [%date% %time%] Falha pip Windows>> "%LOG%"
    set /a FALHAS+=1
) else (
    echo pip do Windows atualizado.
    echo [%date% %time%] pip Windows atualizado>> "%LOG%"
)

if "%PACOTES_PYTHON%"=="0" (
    echo Atualizacao de pacotes Python do usuario desativada.
    echo [%date% %time%] Pacotes Python Windows ignorados>> "%LOG%"
    goto :wsl_update
)

echo Atualizando pacotes Python do usuario no Windows...
%PYTHON_CMD% -m pip list --user --outdated --format=json --disable-pip-version-check > "%PACOTES_JSON%" 2>> "%PYTHONLOG%"
if errorlevel 1 (
    echo AVISO: Nao foi possivel listar os pacotes Python.
    echo Consulte: "%PYTHONLOG%"
    echo [%date% %time%] Falha ao listar pacotes Windows>> "%LOG%"
    set /a FALHAS+=1
    goto :wsl_update
)

%PYTHON_CMD% -c "import json,sys; dados=json.load(open(sys.argv[1], encoding='utf-8')); print('\n'.join(item['name'] for item in dados))" "%PACOTES_JSON%" > "%PACOTES_TXT%" 2>> "%PYTHONLOG%"
if errorlevel 1 (
    echo AVISO: Nao foi possivel interpretar a lista de pacotes.
    echo Consulte: "%PYTHONLOG%"
    echo [%date% %time%] Falha ao interpretar pacotes Windows>> "%LOG%"
    set /a FALHAS+=1
    goto :wsl_update
)

for %%A in ("%PACOTES_TXT%") do if %%~zA==0 echo Nenhum pacote Python desatualizado no Windows.

for /f "usebackq delims=" %%P in ("%PACOTES_TXT%") do (
    if not "%%P"=="" (
        echo Atualizando pacote %%P...
        %PYTHON_CMD% -m pip install --user --upgrade "%%P" --disable-pip-version-check >> "%PYTHONLOG%" 2>&1
        if errorlevel 1 (
            echo AVISO: Falha ao atualizar %%P.
            echo [%date% %time%] Falha pacote Windows: %%P>> "%LOG%"
            set /a FALHAS+=1
        ) else (
            echo [%date% %time%] Pacote Windows atualizado: %%P>> "%LOG%"
        )
    )
)

REM ==========================================
REM 3 - Atualizar WSL
REM ==========================================

:wsl_update
echo.
echo [3/6] Atualizando o WSL...
echo [%date% %time%] Inicio WSL>> "%LOG%"

where wsl.exe >nul 2>&1
if errorlevel 1 (
    echo AVISO: WSL nao encontrado.
    echo [%date% %time%] WSL nao encontrado>> "%LOG%"
    set /a FALHAS+=1
    goto :fim
)

set "WSL_DISPONIVEL=1"

if "%LISTAR%"=="1" (
    echo Modo lista: mostrando versao/status do WSL...
    wsl.exe --version
    echo [%date% %time%] WSL: listagem concluida>> "%LOG%"
    goto :wsl_shutdown
)

wsl.exe --update >> "%WSL_LOG%" 2>&1
if errorlevel 1 (
    echo AVISO: Nao foi possivel atualizar o WSL.
    echo Consulte: "%WSL_LOG%"
    echo [%date% %time%] Erro WSL>> "%LOG%"
    set /a FALHAS+=1
) else (
    echo WSL atualizado.
    echo [%date% %time%] WSL atualizado>> "%LOG%"
)

REM ==========================================
REM 4 - Reiniciar ambiente WSL
REM ==========================================

:wsl_shutdown
echo.
echo [4/6] Reiniciando o ambiente WSL...
echo [%date% %time%] Inicio shutdown WSL>> "%LOG%"

if "%LISTAR%"=="1" (
    echo Modo lista: wsl --shutdown nao sera executado.
    goto :linux_packages
)

wsl.exe --shutdown >> "%WSL_LOG%" 2>&1
if errorlevel 1 (
    echo AVISO: Erro ao encerrar o WSL.
    echo [%date% %time%] Erro shutdown WSL>> "%LOG%"
    set /a FALHAS+=1
) else (
    echo WSL reiniciado.
    echo [%date% %time%] WSL reiniciado>> "%LOG%"
)

REM ==========================================
REM 5 - Atualizar pacotes Linux
REM ==========================================

:linux_packages
echo.
echo [5/6] Atualizando pacotes Linux...
echo [%date% %time%] Inicio pacotes Linux>> "%LOG%"

if "%LISTAR%"=="1" (
    echo Modo lista: simulando full-upgrade com os indices atuais...
    wsl.exe -e bash -lc "set -o pipefail; apt-get -s -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade 2>&1 | tee -a /tmp/atualizacao-wsl.log"
    if errorlevel 1 (
        echo AVISO: Nao foi possivel simular os pacotes Linux.
        echo Consulte: "%WSL_LOG%"
        echo [%date% %time%] Falha simulacao pacotes Linux>> "%LOG%"
        set /a FALHAS+=1
    ) else (
        echo Simulacao dos pacotes Linux concluida.
        echo [%date% %time%] Simulacao pacotes Linux concluida>> "%LOG%"
    )
    goto :python_wsl
)

wsl.exe -e bash -lc "set -o pipefail; sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get update 2>&1 | tee -a /tmp/atualizacao-wsl.log && sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold full-upgrade 2>&1 | tee -a /tmp/atualizacao-wsl.log && sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -y autoremove 2>&1 | tee -a /tmp/atualizacao-wsl.log"
if errorlevel 1 (
    echo AVISO: Falha na atualizacao dos pacotes Linux.
    echo Consulte: "%WSL_LOG%"
    echo [%date% %time%] Falha pacotes Linux>> "%LOG%"
    set /a FALHAS+=1
) else (
    echo Pacotes Linux atualizados.
    echo [%date% %time%] Pacotes Linux atualizados>> "%LOG%"
)

REM ==========================================
REM 6 - Atualizar pip e pacotes Python no WSL
REM ==========================================

:python_wsl
echo.
echo [6/6] Atualizando pip e pacotes Python no WSL...
echo [%date% %time%] Inicio Python WSL>> "%LOG%"

if "%LISTAR%"=="1" (
    echo Modo lista: verificando Python e pip no WSL...
    wsl.exe -e bash -lc "python3 --version; python3 -m pip --version 2>/dev/null || echo 'pip indisponivel'; python3 -m venv --help >/dev/null 2>&1 && echo 'python3-venv disponivel' || echo 'python3-venv ausente'; python3 -m pip list --user --outdated 2>/dev/null"
    if errorlevel 1 (
        echo AVISO: Nao foi possivel consultar o Python no WSL.
        echo [%date% %time%] Falha consulta Python WSL>> "%LOG%"
        set /a FALHAS+=1
    ) else (
        echo Consulta do Python no WSL concluida.
        echo [%date% %time%] Consulta Python WSL concluida>> "%LOG%"
    )
    goto :fim
)

wsl.exe -e bash -lc "command -v python3 >/dev/null 2>&1 || { echo 'python3 nao encontrado'; exit 4; }; if ! python3 -m pip --version >/dev/null 2>&1 || ! python3 -m venv --help >/dev/null 2>&1; then sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get update 2>&1 | tee -a /tmp/atualizacao-wsl.log && sudo env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y python3-pip python3-venv 2>&1 | tee -a /tmp/atualizacao-wsl.log || exit 5; fi; python3 -m pip --version >/dev/null 2>&1 || { echo 'pip WSL indisponivel'; exit 6; }"
if errorlevel 1 (
    echo AVISO: Nao foi possivel preparar o pip no WSL.
    echo Consulte: "%WSL_LOG%"
    echo [%date% %time%] Falha preparando pip WSL>> "%LOG%"
    set /a FALHAS+=1
    goto :fim
)

if "%PACOTES_PYTHON%"=="1" (
    echo Atualizando pacotes Python do usuario no WSL...
    wsl.exe -e bash -lc "set -o pipefail; lista=$(mktemp) || exit 3; if ! python3 -m pip list --user --outdated --format=json 2>> /tmp/atualizacao-wsl.log | python3 -c 'import json,sys; print(chr(10).join(p[\"name\"] for p in json.load(sys.stdin)))' > \"$lista\" 2>> /tmp/atualizacao-wsl.log; then rm -f \"$lista\"; exit 3; fi; falhas=0; while IFS= read -r pacote; do [ -n \"$pacote\" ] || continue; python3 -m pip install --user --upgrade \"$pacote\" 2>&1 | tee -a /tmp/atualizacao-wsl.log || { echo \"AVISO: falha ao atualizar $pacote\"; falhas=1; }; done < \"$lista\"; rm -f \"$lista\"; exit $falhas"
    if errorlevel 1 (
        echo AVISO: Pode ter ocorrido falha nos pacotes Python do WSL.
        echo Consulte: "%WSL_LOG%"
        echo [%date% %time%] Aviso pacotes Python WSL>> "%LOG%"
        set /a FALHAS+=1
    ) else (
        echo Pacotes Python do WSL verificados.
        echo [%date% %time%] Pacotes Python WSL verificados>> "%LOG%"
    )
) else (
    echo Atualizacao de pacotes Python do WSL desativada.
    echo [%date% %time%] Pacotes Python WSL ignorados>> "%LOG%"
)

echo Atualizando pip no ambiente virtual auxiliar do WSL...
wsl.exe -e bash -lc "set -o pipefail; python3 -m venv \"$HOME/.venvs/atualizador-pip\" && \"$HOME/.venvs/atualizador-pip/bin/python\" -m pip install --upgrade pip --disable-pip-version-check 2>&1 | tee -a /tmp/atualizacao-wsl.log"
if errorlevel 1 (
    echo AVISO: Nao foi possivel atualizar pip no ambiente virtual do WSL.
    echo Consulte: "%WSL_LOG%"
    echo [%date% %time%] Aviso pip WSL>> "%LOG%"
    set /a FALHAS+=1
) else (
    echo pip atualizado no ambiente virtual auxiliar do WSL.
    echo [%date% %time%] pip WSL atualizado no venv>> "%LOG%"
)

:fim
echo.
echo ==========================================
echo       PROCESSO FINALIZADO
echo ==========================================
echo.

if "%LISTAR%"=="1" echo Modo lista: nenhuma instalacao/atualizacao foi solicitada.
echo Etapas com falha: %FALHAS%
echo.
echo Log geral: "%LOG%"
echo Log do Winget: "%WINGETLOG%"
echo Log do Python: "%PYTHONLOG%"
echo Log do WSL: "%WSL_LOG%"

if "%WSL_DISPONIVEL%"=="1" (
    echo.>> "%WSL_LOG%"
    echo === Log interno do WSL ===>> "%WSL_LOG%"
    wsl.exe -e bash -lc "cat /tmp/atualizacao-wsl.log 2>/dev/null" >> "%WSL_LOG%" 2>nul
)

echo.
if "%FALHAS%"=="0" (
    echo Nenhuma falha registrada.
    set "CODIGO=0"
) else (
    echo Falhas registradas: %FALHAS%
    set "CODIGO=1"
)

echo [%date% %time%] Fim da execucao>> "%LOG%"

if "%PAUSA%"=="1" pause
endlocal & exit /b %CODIGO%

:cancelado
echo.
echo Operacao cancelada pelo usuario.
echo [%date% %time%] Cancelado pelo usuario>> "%LOG%"
if "%PAUSA%"=="1" pause
endlocal & exit /b 1

:ajuda
echo Uso: atualizacoes.bat [opcoes]
echo.
echo Opcoes:
echo   --listar            mostra o que seria atualizado, sem instalar
echo   --sem-pausa         nao pausa ao final (uso em automacao)
echo   --sem-confirmacao   nao pede confirmacao antes de comecar
echo   --sem-pacotes       nao atualiza pacotes Python do usuario
echo   --ajuda, -h         mostra esta ajuda
echo.
echo Codigos de saida:
echo   0 = execucao sem falhas
echo   1 = uma ou mais etapas falharam ou a execucao foi cancelada
echo   2 = opcao de linha de comando invalida
endlocal & exit /b 0
