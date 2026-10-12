#!/bin/sh
# Ставит lazyvim-offline в ~/.local/lib/lazyvim без root. Сеть не нужна.
# Для системной установки в /opt есть deb-пакет из той же сборки.
set -e
cd "$(dirname "$0")"
BUILD_PREFIX=/opt/lazyvim
DEST="$HOME/.local/lib/lazyvim" # не должен содержать "$BUILD_PREFIX", иначе проверка переноса ниже бессмысленна
BIN="$HOME/.local/bin"

if [ -e "$DEST" ]; then
  mv "$DEST" "$DEST.bak.$(date +%Y%m%d%H%M%S)"
  echo "старый $DEST переименован в $DEST.bak.*"
fi
mkdir -p "$(dirname "$DEST")" "$BIN"
cp -a lazyvim "$DEST"

# Пакет собран под /opt/lazyvim: переносим пути в скриптах venv ansible-lint, в file://-ссылках схем
# и в абсолютных симлинках запросов treesitter
grep -rlI --null "$BUILD_PREFIX" "$DEST/share" | xargs -0 -r sed -i "s|$BUILD_PREFIX|$DEST|g"
find "$DEST" -type l -lname "$BUILD_PREFIX/*" | while read -r l; do
  t=$(readlink "$l")
  ln -sfn "$DEST${t#"$BUILD_PREFIX"}" "$l"
done
left=$(grep -rlI "$BUILD_PREFIX" "$DEST/share" | wc -l)
# битые ссылки внутрь дерева (venv ссылается на системный python3 — он проверяется отдельно ниже)
broken=$(find "$DEST" -xtype l | while read -r l; do
  case "$(readlink -m "$l")" in "$DEST"/*) echo "$l" ;; esac
done | wc -l)
if [ "$left" -ne 0 ] || [ "$broken" -ne 0 ]; then
  echo "ОШИБКА: после переноса осталось файлов со ссылкой на $BUILD_PREFIX: $left, битых симлинков: $broken" >&2
  exit 1
fi

for b in nvim rg fd lazygit; do ln -sfn "$DEST/bin/$b" "$BIN/$b"; done
ln -sfn "$DEST/bin/nvim" "$BIN/lazyvim"

# ~/.local/bin в начало PATH: bash и zsh (login-шеллы на Astra берут его из ~/.profile, если каталог есть)
line='export PATH="$HOME/.local/bin:$PATH"'
for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
  case "$rc" in
    *zshrc) [ -e "$rc" ] || [ "$(basename "${SHELL:-}")" = zsh ] || continue ;;
  esac
  if ! grep -qsF "$line" "$rc"; then
    echo "$line" >> "$rc"
    echo "добавил ~/.local/bin в начало PATH ($rc)"
  fi
done

# В deb это зависимости, здесь только предупреждаем
command -v git >/dev/null || echo "нет git: не будет пометок изменений (gitsigns) и lazygit"
python3 -c 'import sys; sys.exit(sys.version_info[:2] != (3, 11))' 2>/dev/null ||
  echo "нет python3 3.11: не будет работать ansible-lint (диагностика и подсказки в ролях Ansible)"
ls /usr/lib/x86_64-linux-gnu/libicuuc.so.* >/dev/null 2>&1 ||
  echo "нет libicu: marksman (Markdown) запустится в режиме без ICU"

echo "готово: $("$BIN/nvim" --version | head -1)"
case ":$PATH:" in
  *":$BIN:"*)
    if [ "$(command -v nvim)" != "$BIN/nvim" ]; then
      echo "ВНИМАНИЕ: в PATH раньше ~/.local/bin стоит $(command -v nvim); новый nvim: $BIN/nvim или lazyvim"
    fi
    ;;
  *) echo "В этой сессии ~/.local/bin ещё нет в PATH: перелогиньтесь или выполните $line" ;;
esac
