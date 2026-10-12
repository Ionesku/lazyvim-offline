#!/bin/sh
# nvim из lazyvim-offline: neovim 0.12 + LazyVim.
# Конфиг живёт в ~/.config/lazyvim (NVIM_APPNAME), поэтому ~/.config/nvim системного nvim не трогается.
LAZYVIM_PREFIX=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
export LAZYVIM_PREFIX
export NVIM_APPNAME="${NVIM_APPNAME:-lazyvim}"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}/$NVIM_APPNAME"
if [ ! -e "$cfg" ] && [ -d "$LAZYVIM_PREFIX/skel" ]; then
  # копируем во временный каталог и переименовываем, чтобы не остался недокопированный конфиг
  mkdir -p "$(dirname "$cfg")" && cp -r "$LAZYVIM_PREFIX/skel" "$cfg.tmp.$$" && mv "$cfg.tmp.$$" "$cfg"
fi
exec "$LAZYVIM_PREFIX/nvim-linux-x86_64/bin/nvim" "$@"
