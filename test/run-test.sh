#!/bin/bash
# Запуск теста LazyVim в tmux от текущего пользователя; $1 — команда nvim
NV=${1:-nvim}
rm -rf ~/proj ~/lv-report.txt; mkdir -p ~/proj/roles/web/tasks ~/proj/.github/workflows && cd ~/proj
printf 'import os\nimport sys\n\ndef hello(name: str) -> str:\n    return os.path.join("/tmp", name)\n\nhello(1)\n' > app.py
printf '[defaults]\ninventory = hosts\n' > ansible.cfg
printf -- '- name: install nginx\n  apt:\n    name: nginx\n' > roles/web/tasks/main.yml
printf 'services:\n  web:\n    image: nginx\n    ports:\n      - 80:80\n' > docker-compose.yml
printf 'FROM debian:12\nRUN apt-get update && apt-get install -y curl\n' > Dockerfile
printf '{\n  "a": 1,\n  "a": 2\n}\n' > data.json
printf '[project]\nname = "x"\nversion = 1\n' > pyproject.toml
printf '# Title\n\nSee [link](#nope)\n' > README.md
printf 'local x = 1\nprint(y)\n' > init.lua
printf '#!/bin/bash\necho $1\n' > run.sh
printf 'on: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    stepz:\n      - run: echo hi\n' > .github/workflows/ci.yml
printf '{\n  "name": 1,\n  "version": "1.0.0"\n}\n' > package.json
git init -q && git add -A && git -c user.name=t -c user.email=t@t commit -qm init && printf 'print("changed")\n' >> app.py
tmux kill-server 2>/dev/null
tmux new-session -d -s t -x 200 -y 50 "$NV -c 'luafile ~/test.lua' app.py"
for i in $(seq 1 180); do [ -s ~/lv-report.txt ] && break; sleep 1; done
cat ~/lv-report.txt
