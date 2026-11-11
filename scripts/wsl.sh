#!/usr/bin/env bash
#
# Rotinas executadas dentro do WSL pelo atualizacoes.ps1.
# Saida vai para stdout (exibida e registrada no Windows) e para $WSL_LOG.
#
# Uso:
#   wsl.sh <comando> [--sem-pip] [--sem-pacotes]
#
# Comandos:
#   info-apt         simula o full-upgrade com os indices atuais
#   apt-update       apt-get update
#   apt-upgrade      apt-get full-upgrade
#   apt-autoremove   apt-get autoremove
#   info-python      versoes de python3, pip, venv e pacotes desatualizados
#   python-prepare   garante python3-pip/python3-venv e atualiza o pip do venv
#   python-pacotes   atualiza os pacotes do usuario (propaga falhas)
#   reboot-status    informa se ha reinicializacao pendente
#
# Codigos de saida:
#   0 sucesso, 1 falha generica, 2 uso invalido, 3 falha ao listar pacotes,
#   4 python3 ausente, 5 falha ao instalar python3-pip/python3-venv,
#   6 pip indisponivel, 7 sudo ausente, 8 comando desconhecido.

set -Eeuo pipefail
IFS=$'\n\t'

WSL_LOG="${WSL_LOG:-/tmp/atualizacao-wsl.log}"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export PYTHONIOENCODING=utf-8

SEM_PIP=0
SEM_PACOTES=0
COMANDO=""

# Opcoes do APT: entradas de lista (sufixo "::"), preservando as duas flags.
APT_CONF=(-o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

unir_args() {
  local IFS=' '
  printf '%s' "$*"
}

log() {
  printf '[%s] %s\n' "$(date -Is)" "$(unir_args "$@")" | tee -a "$WSL_LOG"
}

run() {
  printf '\n>>> %s\n' "$(unir_args "$@")" | tee -a "$WSL_LOG"
  "$@" 2>&1 | tee -a "$WSL_LOG"
}

SUDO=()
preparar_sudo() {
  if [[ ${EUID} -eq 0 ]]; then
    return 0
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    log "ERRO: sudo nao encontrado e o usuario nao e root."
    exit 7
  fi
  SUDO=(sudo)
}

apt() {
  preparar_sudo
  run "${SUDO[@]}" env DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get "$@"
}

cmd_info_apt() {
  run apt-get -s "${APT_CONF[@]}" full-upgrade || true
}

cmd_apt_update() {
  apt update
}

cmd_apt_upgrade() {
  apt -y "${APT_CONF[@]}" full-upgrade
}

cmd_apt_autoremove() {
  apt -y autoremove
}

cmd_info_python() {
  if command -v python3 >/dev/null 2>&1; then
    log "python3: $(python3 --version 2>&1)"
  else
    log "python3: ausente"
    return 0
  fi

  if python3 -m pip --version >/dev/null 2>&1; then
    log "pip: $(python3 -m pip --version 2>&1)"
  else
    log "pip: indisponivel"
  fi

  if python3 -m venv --help >/dev/null 2>&1; then
    log "python3-venv: disponivel"
  else
    log "python3-venv: ausente"
  fi

  run python3 -m pip list --user --outdated --disable-pip-version-check || true
}

cmd_python_prepare() {
  if ! command -v python3 >/dev/null 2>&1; then
    log "ERRO: python3 nao encontrado."
    exit 4
  fi

  if ! python3 -m pip --version >/dev/null 2>&1 ||
    ! python3 -m venv --help >/dev/null 2>&1; then
    log "Instalando python3-pip e python3-venv..."
    apt update
    apt install -y python3-pip python3-venv
  fi

  if ! python3 -m pip --version >/dev/null 2>&1; then
    log "ERRO: pip continua indisponivel apos a instalacao."
    exit 6
  fi

  if [[ ${SEM_PIP} -eq 1 ]]; then
    log "Atualizacao do pip ignorada (--sem-pip)."
    return 0
  fi

  local venv="$HOME/.venvs/atualizador-pip"
  log "Atualizando pip no ambiente virtual auxiliar: $venv"
  python3 -m venv "$venv" 2>&1 | tee -a "$WSL_LOG"
  "$venv/bin/python" -m pip install --upgrade pip \
    --disable-pip-version-check 2>&1 | tee -a "$WSL_LOG"
}

cmd_python_pacotes() {
  if [[ ${SEM_PACOTES} -eq 1 ]]; then
    log "Atualizacao dos pacotes do usuario ignorada (--sem-pacotes)."
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    log "ERRO: python3 nao encontrado."
    exit 4
  fi

  local bruto lista
  bruto="$(mktemp)"
  lista="$(mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$bruto' '$lista'" EXIT

  if ! python3 -m pip list --user --outdated --format=json \
    --disable-pip-version-check 2>>"$WSL_LOG" >"$bruto"; then
    log "ERRO: nao foi possivel listar os pacotes desatualizados."
    exit 3
  fi

  if ! python3 -c 'import json,sys; print("\n".join(p["name"] for p in json.load(sys.stdin)))' \
    <"$bruto" >"$lista" 2>>"$WSL_LOG"; then
    log "ERRO: nao foi possivel interpretar a lista de pacotes."
    exit 3
  fi

  if [[ ! -s $lista ]]; then
    log "Nenhum pacote Python desatualizado no WSL."
    return 0
  fi

  local falhas=0 pacote
  while IFS= read -r pacote; do
    [[ -n $pacote ]] || continue
    log "Atualizando pacote Python (WSL): $pacote"
    if ! python3 -m pip install --user --upgrade "$pacote" \
      --disable-pip-version-check </dev/null 2>&1 | tee -a "$WSL_LOG"; then
      log "AVISO: falha ao atualizar $pacote."
      falhas=1
    fi
  done <"$lista"

  return "$falhas"
}

cmd_reboot_status() {
  if [[ -f /var/run/reboot-required ]]; then
    log "reboot-required"
    if [[ -f /var/run/reboot-required.pkgs ]]; then
      # shellcheck disable=SC2002
      cat /var/run/reboot-required.pkgs | tee -a "$WSL_LOG" || true
    fi
  else
    log "ok"
  fi
}

uso() {
  sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --sem-pip) SEM_PIP=1 ;;
  --sem-pacotes) SEM_PACOTES=1 ;;
  -h | --ajuda | --help)
    uso
    exit 0
    ;;
  -*)
    printf 'Opcao desconhecida: %s\n' "$1" >&2
    exit 2
    ;;
  *)
    if [[ -n $COMANDO ]]; then
      printf 'Comando duplicado: %s\n' "$1" >&2
      exit 2
    fi
    COMANDO="$1"
    ;;
  esac
  shift
done

case "$COMANDO" in
info-apt) cmd_info_apt ;;
apt-update) cmd_apt_update ;;
apt-upgrade) cmd_apt_upgrade ;;
apt-autoremove) cmd_apt_autoremove ;;
info-python) cmd_info_python ;;
python-prepare) cmd_python_prepare ;;
python-pacotes) cmd_python_pacotes ;;
reboot-status) cmd_reboot_status ;;
"")
  uso >&2
  exit 2
  ;;
*)
  printf 'Comando desconhecido: %s\n' "$COMANDO" >&2
  exit 8
  ;;
esac
