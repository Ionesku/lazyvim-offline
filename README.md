# lazyvim-offline

Neovim 0.12 + LazyVim для Astra Linux 1.8 без интернета. Внутри node, плагины, языковые серверы Mason, парсеры treesitter и JSON-схемы SchemaStore. Во время работы в сеть не обращается.

Языки: Python, YAML, Ansible, JSON, Docker, TOML, Markdown, Git. Дополнительно rg, fd, lazygit.

## Сборка

Нужны docker и интернет. Сборка идёт около 25 минут в `debian:bookworm`: у Astra 1.8 та же glibc 2.36 и python 3.11.

```bash
docker run --rm --network host -v "$PWD":/src:ro -v "$PWD/out":/out debian:bookworm bash /src/build.sh
```

В `out/` появятся:
- `lazyvim-offline_<версия>_amd64.deb` — системная установка в `/opt/lazyvim`;
- `lazyvim-offline_<версия>.tar.xz` — установка без root в `~/.local/lib/lazyvim`;
- `.sha256` и `lazy-lock_<версия>.json` с точными версиями плагинов.

Сборка останавливается, если что-то не поставилось: плагин, пакет Mason, парсер, запросы подсветки, схемы. Она останавливается и если бинарникам нужна glibc новее 2.36 или GLIBCXX новее 3.4.30. Зависимости deb вычисляются по библиотекам, которые требуют бинарники.

`build.sh` нужен tree-sitter CLI, который работает на старой glibc. Если файл `tree-sitter` лежит рядом (он в `.gitignore`), сборка берёт его, иначе собирает через cargo (это ещё минут 5). Готовые сборки CLI требуют glibc 2.39.

Языки задаёт список `extras` в `setup.lua`. После его изменения пакет нужно пересобрать.

## Установка

```bash
sudo apt install ./lazyvim-offline_<версия>_amd64.deb      # или
tar xJf lazyvim-offline_<версия>.tar.xz && ./lazyvim-offline/install.sh
```

- Команда `lazyvim` работает всегда.
- `nvim` указывает на пакет:
  - для deb — в login-шеллах bash (через `/etc/profile.d/lazyvim.sh`);
  - для архива — через `~/.local/bin` в `.bashrc` и `.zshrc`.
- Системный `/usr/bin/nvim` и `~/.config/nvim` не затрагиваются.
- Личный конфиг создаётся в `~/.config/lazyvim` при первом запуске.

Перед установкой на Астре проверьте `astra-digsig-control status`: при включённой ЗПС неподписанные бинарники пакета не запустятся.

## Файлы

| Файл | Что делает |
|---|---|
| `build.sh` | собирает дерево `/opt/lazyvim`, проверяет его и упаковывает deb и tar.xz |
| `setup.lua` | системная часть конфига: языки, офлайн-настройки Mason, treesitter, LSP (ansiblels, схемы для yamlls, jsonls и taplo), blink |
| `prep.lua` | ставит пакеты Mason и парсеры при сборке и проверяет полноту |
| `fetch-schemas.py` | зеркалит схемы SchemaStore с `$ref` на `file://`; готовит каталог и кэш для taplo |
| `nvim-wrapper.sh` | `bin/nvim`: `NVIM_APPNAME=lazyvim`, копирование skel в `~/.config/lazyvim` |
| `skel-init.lua` | `init.lua` пользователя, подключает `setup.lua` |
| `profile.sh` | `/etc/profile.d/lazyvim.sh` |
| `install.sh` | установка архива без root с переносом путей `/opt/lazyvim` |
| `test/` | проверка без сети: открывает 11 файлов разных типов и пишет отчёт в `~/lv-report.txt` |

## Проверка

Скопируйте `test/test.lua` и `test/run-test.sh` в домашний каталог чистого пользователя на машине без сети. Затем запустите `bash -l ./run-test.sh nvim` (нужен tmux).

Отчёт показывает по каждому файлу:
- подключённые языковые серверы;
- диагностику, в том числе по схемам;
- подсветку treesitter;
- подсказку ansible-doc.

В конце отчёта: ошибки из `lsp.log` и `:messages`.
