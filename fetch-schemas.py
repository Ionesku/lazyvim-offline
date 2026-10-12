#!/usr/bin/env python3
"""Зеркало схем SchemaStore для офлайн-работы yamlls, jsonls и taplo.

usage: fetch-schemas.py <out_dir> <file_url_prefix>
  out_dir/<host>/<path>  схемы (и всё, на что они ссылаются через $ref)
  out_dir/index.json     {исходный url: file url}
  out_dir/catalog.json   каталог SchemaStore только с локальными схемами, без старых версий
  out_dir/taplo-cache/   тот же каталог (только TOML) в формате дискового кэша taplo
Абсолютные $ref и верхний $id внутри схем переписываются на file://, чтобы серверы не ходили в сеть.
"""
import concurrent.futures as cf
import hashlib
import json
import os
import re
import subprocess
import sys
import urllib.parse

OUT, PREFIX = sys.argv[1], sys.argv[2].rstrip("/")
CATALOG = "https://www.schemastore.org/api/json/catalog.json"
SKIP_HOSTS = {"json-schema.org"}  # мета-схемы draft-* встроены в серверы
MAX_DOCS = 20000


def local_rel(url):
    u = urllib.parse.urlsplit(url)
    path = urllib.parse.unquote(u.path).lstrip("/") or "index"
    if path.endswith("/"):
        path += "index"
    if u.query:
        path += "_" + re.sub(r"[^A-Za-z0-9._-]", "_", u.query)
    path = re.sub(r"[^\w./@+-]", "_", path).replace("..", "_")
    return u.netloc + "/" + path


def fetch(url):
    # curl с жёстким --max-time: у urllib таймаут на каждую операцию, и медленный сервер держит поток вечно
    cmd = ["curl", "-fsSL", "--connect-timeout", "15", "--max-time", "60", "-A", "lazyvim-offline-build", url]
    err = None
    for _ in range(2):
        try:
            r = subprocess.run(cmd, capture_output=True, timeout=90)
            if r.returncode == 0:
                return url, json.loads(r.stdout)
            err = Exception(f"curl exit {r.returncode}")
        except Exception as e:  # noqa: BLE001
            err = e
    return url, err


def refs(node):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "$ref" and isinstance(v, str):
                yield v
            else:
                yield from refs(v)
    elif isinstance(node, list):
        for v in node:
            yield from refs(v)


def wanted(url):
    u = urllib.parse.urlsplit(url)
    return u.scheme in ("http", "https") and u.netloc not in SKIP_HOSTS


_, catalog = fetch(CATALOG)
if isinstance(catalog, Exception):
    sys.exit(f"не скачался каталог SchemaStore: {catalog}")
# Только актуальные схемы: старые версии ("versions") — половина объёма, а SchemaStore.nvim и taplo их не берут
todo = {urllib.parse.urldefrag(s["url"])[0] for s in catalog["schemas"]}
todo = {u for u in todo if wanted(u)}

docs, failed = {}, {}
with cf.ThreadPoolExecutor(32) as pool:
    while todo and len(docs) < MAX_DOCS:
        nxt = set()
        for url, res in pool.map(fetch, sorted(todo)):
            if isinstance(res, Exception) or not isinstance(res, (dict, list)):
                failed[url] = str(res)[:120]
                continue
            docs[url] = res
            for ref in refs(res):
                t = urllib.parse.urldefrag(urllib.parse.urljoin(url, ref))[0]
                if t and wanted(t) and t not in docs and t not in failed:
                    nxt.add(t)
        todo = nxt - docs.keys() - failed.keys()
        print(f"  скачано {len(docs)}, ошибок {len(failed)}, по ссылкам $ref осталось {len(todo)}", file=sys.stderr)

mapping = {u: PREFIX + "/" + urllib.parse.quote(local_rel(u)) for u in docs}


def file_url(url):
    base, frag = urllib.parse.urldefrag(url)
    if base in mapping:
        return mapping[base] + ("#" + frag if frag else "")
    return None


def rewrite(node, base):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "$ref" and isinstance(v, str) and urllib.parse.urlsplit(v).scheme in ("http", "https"):
                node[k] = file_url(v) or v
            else:
                rewrite(v, base)
    elif isinstance(node, list):
        for v in node:
            rewrite(v, base)


total = 0
for url, doc in docs.items():
    rewrite(doc, url)
    if isinstance(doc, dict):
        for key in ("$id", "id"):
            if isinstance(doc.get(key), str) and doc[key].startswith("http"):
                doc[key] = mapping[url]
    path = os.path.join(OUT, local_rel(url))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, separators=(",", ":"))
    total += os.path.getsize(path)

local = []
for s in catalog["schemas"]:
    fu = file_url(s["url"])
    if not fu:
        continue
    s = dict(s, url=fu)
    s.pop("versions", None)
    local.append(s)
# taplo 0.10 принимает каталог, только если $schema равен старому адресу SchemaStore
taplo_schema = "https://json.schemastore.org/schema-catalog.json"
with open(os.path.join(OUT, "catalog.json"), "w", encoding="utf-8") as f:
    json.dump(dict(catalog, schemas=local, **{"$schema": taplo_schema}), f, ensure_ascii=False)
with open(os.path.join(OUT, "index.json"), "w", encoding="utf-8") as f:
    json.dump(mapping, f, ensure_ascii=False)

# taplo при старте, ещё до получения настроек, грузит каталог по зашитому адресу. Сначала он смотрит
# в свой дисковый кэш (cachePath, имя файла = sha1 от url), поэтому кладём туда локальный каталог
# с TOML-схемами под этим адресом и сроком годности до 2099 года — и taplo не ходит в сеть.
taplo_url = "https://www.schemastore.org/api/json/catalog.json"
toml = []
for s in local:
    fm = [m if m.startswith("**/") else "**/" + m for m in s.get("fileMatch", [])]
    if any(".toml" in m for m in fm):
        toml.append(dict(s, fileMatch=fm))
cache_dir = os.path.join(OUT, "taplo-cache")
os.makedirs(cache_dir, exist_ok=True)
with open(os.path.join(cache_dir, hashlib.sha1(taplo_url.encode()).hexdigest()), "w", encoding="utf-8") as f:
    json.dump({"expires_by": [2099, 1, 0, 0, 0, 0, 0, 0, 0], "url": taplo_url,
               "value": {"$schema": taplo_schema, "schemas": toml}}, f, ensure_ascii=False)

top = sum(1 for s in catalog["schemas"] if file_url(s["url"]))
print(f"schemas: {top}/{len(catalog['schemas'])} из каталога, всего файлов {len(docs)}, "
      f"{total / 1e6:.1f} МБ, не скачалось {len(failed)}, TOML для taplo: {len(toml)}")
# Часть схем на сторонних хостах бывает недоступна; если не скачалось больше 10% — сборку останавливаем
if top < 0.9 * len(catalog["schemas"]) or not toml:
    sys.exit("слишком много схем не скачалось")
