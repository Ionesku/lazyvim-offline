#!/bin/bash
# Сборка lazyvim-offline для Astra 1.8 из одного дерева /opt/lazyvim:
#   out/lazyvim-offline_<версия>_amd64.deb      — системная установка в /opt/lazyvim
#   out/lazyvim-offline_<версия>.tar.xz         — установка без root в ~/.local/lib/lazyvim (install.sh)
# Запускать внутри debian:bookworm (как у Astra 1.8: glibc 2.36, python 3.11), нужна сеть:
#   docker run --rm --network host -v "$PWD":/src:ro -v "$PWD/out":/out debian:bookworm bash /src/build.sh
# Любая недостающая часть (плагин, пакет Mason, парсер, схемы, лишняя glibc) останавливает сборку.
set -euo pipefail
SRC=$(cd "$(dirname "$0")" && pwd)
# Версии зафиксированы, чтобы сборка повторялась и не ходила в GitHub API (лимит 60 запросов в час)
NVIM_VER=${NVIM_VER:-v0.12.6}
NODE_VER=${NODE_VER:-v24.21.0}
RG_VER=${RG_VER:-15.2.0}
FD_VER=${FD_VER:-v10.5.0}
LAZYGIT_VER=${LAZYGIT_VER:-v0.66.1}
# Astra 1.8: glibc 2.36, libstdc++ из GCC 12 (GLIBCXX_3.4.30)
TARGET_GLIBC=${TARGET_GLIBC:-2.36}
TARGET_GLIBCXX=${TARGET_GLIBCXX:-3.4.30}
PREFIX=/opt/lazyvim
export HOME=/root NVIM_APPNAME=lazyvim LAZYVIM_BUILD=1
# Без CFLAGS "tree-sitter build" (0.27.1) зависает на парсере gitcommit ещё до вызова компилятора
export CFLAGS=-O2
CURL="curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 20 --max-time 600"
die() { echo "ОШИБКА: $*" >&2; exit 1; }
mkdir -p "$PREFIX/bin" "$PREFIX/share" /tmp/dl /out

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
  git curl ca-certificates gcc libc6-dev make unzip xz-utils python3 python3-venv python3-pip binutils file >/dev/null

cd /tmp/dl
echo "== tree-sitter CLI (только для сборки парсеров, в пакет не входит)"
# Готовые сборки CLI (релизы и Mason) требуют glibc 2.39
mkdir -p "$HOME/bin"
if [ -x "$SRC/tree-sitter" ]; then
  cp "$SRC/tree-sitter" "$HOME/bin/"
else
  $CURL https://sh.rustup.rs | sh -s -- -y -q --profile minimal >/dev/null
  "$HOME/.cargo/bin/cargo" install tree-sitter-cli --locked -q --root "$HOME"
fi

echo "== neovim $NVIM_VER, node, rg, fd, lazygit"
$CURL -o nvim.tgz "https://github.com/neovim/neovim/releases/download/$NVIM_VER/nvim-linux-x86_64.tar.gz"
tar xzf nvim.tgz -C "$PREFIX"
NODE=$NODE_VER
$CURL -o node.txz "https://nodejs.org/dist/$NODE/node-$NODE-linux-x64.tar.xz"
tar xJf node.txz -C "$PREFIX"
ln -sfn "node-$NODE-linux-x64" "$PREFIX/node"
GH=https://github.com
for spec in "rg $GH/BurntSushi/ripgrep/releases/download/$RG_VER/ripgrep-$RG_VER-x86_64-unknown-linux-musl.tar.gz" \
            "fd $GH/sharkdp/fd/releases/download/$FD_VER/fd-$FD_VER-x86_64-unknown-linux-musl.tar.gz" \
            "lazygit $GH/jesseduffield/lazygit/releases/download/$LAZYGIT_VER/lazygit_${LAZYGIT_VER#v}_linux_x86_64.tar.gz"; do
  set -- $spec
  rm -rf "x-$1" && mkdir "x-$1"
  $CURL -o "$1.tgz" "$2"
  tar xzf "$1.tgz" -C "x-$1"
  install -m755 "$(find "x-$1" -type f -name "$1" | head -1)" "$PREFIX/bin/"
done
install -m755 "$SRC/nvim-wrapper.sh" "$PREFIX/bin/nvim"
install -m644 "$SRC/setup.lua" "$PREFIX/setup.lua"
export PATH=$HOME/bin:$PREFIX/bin:$PATH
"$PREFIX/nvim-linux-x86_64/bin/nvim" --version | head -1
"$PREFIX/node/bin/node" -v

echo "== skel: личный конфиг, который копируется в ~/.config/lazyvim при первом запуске"
git clone -q --depth 1 https://github.com/LazyVim/starter "$PREFIX/skel"
# Языки (extras) задаёт setup.lua пакета, поэтому lazyvim.json в skel не кладём
rm -rf "$PREFIX/skel/.git" "$PREFIX/skel/lua/config/lazy.lua" "$PREFIX/skel/.neoconf.json" "$PREFIX/skel/lazyvim.json"
install -m644 "$SRC/skel-init.lua" "$PREFIX/skel/init.lua"
rm -rf "$HOME/.config/lazyvim" && mkdir -p "$HOME/.config" && cp -r "$PREFIX/skel" "$HOME/.config/lazyvim"

echo "== плагины, Mason, парсеры"
# Первый запуск ставит LazyVim, второй — плагины из его спецификаций и extras; полноту проверяет prep.lua
for pass in 1 2; do
  nvim --headless "+Lazy! sync" +qa >/dev/null 2>&1 || true
done
ok=0
for pass in 1 2 3; do
  echo "-- prep pass $pass"
  if nvim --headless "+luafile $SRC/prep.lua" +qa >/tmp/prep.log 2>&1; then ok=1; fi
  tr '\r' '\n' </tmp/prep.log | grep -E '^(mason|treesitter):|FAIL|prep OK' | cut -c1-400 || true
  [ "$ok" = 1 ] && break
done
[ "$ok" = 1 ] || die "плагины, пакеты Mason или парсеры поставились не полностью"
rm -rf "$PREFIX/share/mason/staging" "$PREFIX/share/mason/packages/tree-sitter-cli" "$PREFIX/share/mason/bin/tree-sitter"

echo "== JSON-схемы SchemaStore"
python3 -I "$SRC/fetch-schemas.py" "$PREFIX/share/schemas" "file://$PREFIX/share/schemas"

echo "== проверки"
broken=$(find "$PREFIX" -xtype l | wc -l)
[ "$broken" -eq 0 ] || die "битых симлинков: $broken"
# Каталоги плагинов должны совпадать с lazy-lock.json
python3 - "$PREFIX/share" <<'PY' || die "lazy-lock.json не совпадает с каталогами плагинов"
import json, os, sys
share = sys.argv[1]
lock = set(json.load(open(os.path.join(share, "lazy-lock.json"))))
dirs = {d for d in os.listdir(os.path.join(share, "lazy")) if os.path.isdir(os.path.join(share, "lazy", d))}
print(f"плагинов: в lazy-lock {len(lock)}, каталогов {len(dirs)}")
if lock != dirs:
    print("только в lock:", sorted(lock - dirs), "только каталоги:", sorted(dirs - lock))
    sys.exit(1)
PY
mapfile -t elfs < <(find "$PREFIX" -type f -exec file {} + | grep -E 'ELF.*(executable|shared object)' | cut -d: -f1)
glibc=$(for f in "${elfs[@]}"; do objdump -T "$f" 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' || true; done | sed 's/GLIBC_//' | sort -uV | tail -1)
echo "ELF-файлов: ${#elfs[@]}, максимальная glibc: $glibc (цель $TARGET_GLIBC)"
[ "$(printf '%s\n%s\n' "$glibc" "$TARGET_GLIBC" | sort -V | tail -1)" = "$TARGET_GLIBC" ] || die "нужна glibc $glibc > $TARGET_GLIBC"
glibcxx=$(for f in "${elfs[@]}"; do objdump -T "$f" 2>/dev/null | grep -oE 'GLIBCXX_[0-9.]+' || true; done | sed 's/GLIBCXX_//' | sort -uV | tail -1)
echo "максимальная GLIBCXX: ${glibcxx:-нет} (цель $TARGET_GLIBCXX)"
[ -z "$glibcxx" ] || [ "$(printf '%s\n%s\n' "$glibcxx" "$TARGET_GLIBCXX" | sort -V | tail -1)" = "$TARGET_GLIBCXX" ] ||
  die "нужна GLIBCXX $glibcxx > $TARGET_GLIBCXX"

# Зависимости deb: библиотеки, которые ELF-файлы требуют (NEEDED), но которых нет в самом дереве
needed=$(for f in "${elfs[@]}"; do objdump -p "$f" 2>/dev/null | awk '/NEEDED/{print $2}'; done | sort -u)
bundled=$(find "$PREFIX" \( -type f -o -type l \) -name '*.so*' -printf '%f\n' | sort -u)
libpkgs=()
for so in $(comm -23 <(echo "$needed") <(echo "$bundled")); do
  p=$(dpkg -S "*/$so" 2>/dev/null | head -1 | cut -d: -f1 || true)
  [ -n "$p" ] || die "библиотека $so нужна, но не найдена ни в одном пакете системы сборки"
  echo "  $so -> $p"
  [ "$p" = libc6 ] || libpkgs+=("$p")
done
# marksman (.NET) загружает ICU через dlopen; venv ansible-lint привязан к системному python3 3.11;
# git нужен gitsigns, lazygit и LazyVim
DEPENDS="libc6 (>= $glibc)$(printf ', %s' $(printf '%s\n' "${libpkgs[@]}" | sort -u)), libicu72, python3 (>= 3.11), python3 (<< 3.12), git"
echo "Depends: $DEPENDS"

VER="${NVIM_VER#v}+lazyvim$(date +%Y%m%d%H%M)"
echo "== deb $VER"
PKG=/tmp/pkg
rm -rf "$PKG" && mkdir -p "$PKG/DEBIAN" "$PKG/opt" "$PKG/usr/bin" "$PKG/etc/profile.d"
cp -a "$PREFIX" "$PKG/opt/"
chmod -R u+rwX,go+rX,go-w "$PKG/opt"
ln -s /opt/lazyvim/bin/nvim "$PKG/usr/bin/lazyvim"
install -m644 "$SRC/profile.sh" "$PKG/etc/profile.d/lazyvim.sh"
echo /etc/profile.d/lazyvim.sh > "$PKG/DEBIAN/conffiles"
cat > "$PKG/DEBIAN/control" <<EOF
Package: lazyvim-offline
Version: $VER
Architecture: amd64
Maintainer: ionesku <artem.ionesku@gmail.com>
Section: editors
Priority: optional
Installed-Size: $(du -sk "$PKG" | cut -f1)
Depends: $DEPENDS
Description: Neovim ${NVIM_VER#v} + LazyVim для офлайн-установки
 Neovim, node $NODE, плагины LazyVim, языковые серверы Mason, парсеры
 treesitter и JSON-схемы SchemaStore в /opt/lazyvim; в сеть не обращается.
 Языки: Python, YAML, Ansible, JSON, Docker, TOML, Markdown, Git. Плюс rg,
 fd, lazygit.
 .
 Команда lazyvim работает всегда. nvim указывает на пакет только в
 login-шеллах bash/sh (через /etc/profile.d); в zsh, у sudo и в
 не-login терминалах это /usr/bin/nvim. Личный конфиг создаётся в
 ~/.config/lazyvim при первом запуске; системный /usr/bin/nvim и
 ~/.config/nvim не затрагиваются.
EOF
(cd "$PKG" && find opt usr etc -type f -exec md5sum {} + | sort -k2 > DEBIAN/md5sums)
dpkg-deb --root-owner-group -Zxz --build "$PKG" "/out/lazyvim-offline_${VER}_amd64.deb" >/dev/null

echo "== архив для установки без root"
T=/tmp/tarroot/lazyvim-offline
rm -rf /tmp/tarroot && mkdir -p "$T"
cp -a "$PREFIX" "$T/lazyvim"
install -m755 "$SRC/install.sh" "$T/install.sh"
tar -C /tmp/tarroot --owner=0 --group=0 --numeric-owner -I 'xz -T0' -cf "/out/lazyvim-offline_${VER}.tar.xz" lazyvim-offline

cp "$PREFIX/share/lazy-lock.json" "/out/lazy-lock_${VER}.json"
cd /out && sha256sum "lazyvim-offline_${VER}_amd64.deb" "lazyvim-offline_${VER}.tar.xz" > "lazyvim-offline_${VER}.sha256"
ls -lh /out
