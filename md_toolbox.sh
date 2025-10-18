#!/usr/bin/env bash
# md_toolbox.sh – installe et pilote les outils ROM Mega Drive
# Auteur : AI + toi ;-)
set -e

APT_PKGS="ucon64 flips git build-essential python3-pip"
GUIX_PKGS="ucon64 flips"
EXTRA_GITHUB=(md-fix-rom smd2bin split_md)

GITHUB_URL() {  # retourne l'URL selon le projet
  case $1 in
    md-fix-rom) echo "https://github.com/MatteoTurbo/md-fix-rom.git" ;;
    smd2bin)    echo "https://github.com/dborth/smd2bin.git" ;;
    split_md)   echo "https://github.com/sverx/split_md.git" ;;
  esac
}

# ---------------------------------------------------------------------
install_tools() {
  echo ">>> Détection du gestionnaire de paquets..."
  if command -v apt >/dev/null 2>&1; then
    echo ">>> Installation via apt : $APT_PKGS"
    sudo apt update && sudo apt install -y $APT_PKGS
  elif command -v guix >/dev/null 2>&1; then
    echo ">>> Installation via guix : $GUIX_PKGS"
    guix install $GUIX_PKGS
  else
    echo "Ni apt, ni guix n'ont été trouvés – install manuelle nécessaire."
    exit 1
  fi

  echo ">>> Clonage / compilation des petits utilitaires manquants"
  mkdir -p $HOME/.local/src
  cd       $HOME/.local/src

  for repo in "${EXTRA_GITHUB[@]}"; do
    if ! command -v $repo >/dev/null 2>&1; then
      echo "Clonage $repo …"
      git clone --depth 1 "$(GITHUB_URL $repo)" $repo
      cd $repo
      make && sudo make install   # tous fournissent un Makefile simple
      cd ..
    else
      echo "$repo déjà présent."
    fi
  done
  echo ">>> Outils installés ✔"
}

# ---------------------------------------------------------------------
decimal () {  # convertit 0xHEX → décimal pour ucon64
  printf "%d" "$(( $1 ))"
}

mdfix() {
  if [[ -z $1 ]]; then
    echo "Usage : $0 mdfix ROM.bin [--sram 0|2|8|32] [--patch hack.ips]"
    exit 1
  fi

  ROM_IN=$1; shift
  SRAM_KB=0; PATCH=""

  # --- analyse des options ---
  while [[ $# -gt 0 ]]; do
    case $1 in
      --sram)  SRAM_KB="$2"; shift 2 ;;
      --patch) PATCH="$2";  shift 2 ;;
      *)       echo "Option inconnue : $1"; exit 1 ;;
    esac
  done

  TMP="$ROM_IN"
  # 1) SMD → BIN si besoin
  if file "$TMP" | grep -qi "interleaved\|SMD"; then
    echo ">>> Conversion SMD → BIN"
    smd2bin "$TMP" "${TMP%.smd}.bin"
    TMP="${TMP%.smd}.bin"
  fi

  # 2) Ajout SRAM si demandé
  if [[ $SRAM_KB -gt 0 ]]; then
    echo ">>> Ajout de ${SRAM_KB} kio de SRAM"
    HEX_START=0x200000
    HEX_END=$(( 0x200000 + $SRAM_KB*1024 - 1 ))
    DEC_START=$(decimal $HEX_START)
    DEC_END=$(decimal $HEX_END)
    ucon64 --sram=${DEC_START}-${DEC_END} -o "${TMP%.bin}_sram.bin" "$TMP"
    TMP="${TMP%.bin}_sram.bin"
  fi

  # 3) Application patch IPS/BPS
  if [[ -n $PATCH ]]; then
    echo ">>> Application du patch $PATCH"
    flips --apply "$PATCH" "$TMP" "${TMP%.bin}_patched.bin"
    TMP="${TMP%.bin}_patched.bin"
  fi

  # 4) Nettoyage + checksum final
  echo ">>> ucon64 --md-fix (checksum, dépaddage, etc.)"
  FINAL="${TMP%.bin}_fixed.bin"
  ucon64 --strip --md-fix -o "$FINAL" "$TMP"

  echo -e "\n✅  ROM finale : $FINAL"
  ucon64 --gen "$FINAL" | grep -E "Cartridge RAM|Checksum"
}

# ---------------------------------------------------------------------
case $1 in
  install) install_tools ;;
  mdfix)   shift; mdfix "$@" ;;
  *) echo "Usage : $0 {install|mdfix}" ;;
esac