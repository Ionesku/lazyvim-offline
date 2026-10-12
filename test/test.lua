-- Открывает файлы разных языков и пишет отчёт в ~/lv-report.txt
local out = {}
local function log(s) out[#out + 1] = s end
local files = {
  "app.py", "roles/web/tasks/main.yml", "docker-compose.yml", "Dockerfile",
  "data.json", "pyproject.toml", "README.md", "init.lua", "run.sh",
  ".github/workflows/ci.yml", "package.json",
}
vim.defer_fn(function()
  for _, f in ipairs(files) do
    vim.cmd.edit(f)
    local buf = vim.api.nvim_get_current_buf()
    vim.wait(30000, function() return #vim.lsp.get_clients({ bufnr = buf }) > 0 end, 200)
    vim.wait(8000, function() return #vim.diagnostic.get(buf) > 0 end, 200)
    local names = vim.tbl_map(function(c) return c.name end, vim.lsp.get_clients({ bufnr = buf }))
    local hl = vim.treesitter.highlighter.active[buf] ~= nil
    log(string.format("%-26s ft=%-20s ts=%-3s diag=%-2d lsp=%s", f, vim.bo[buf].filetype,
      hl and "да" or "НЕТ", #vim.diagnostic.get(buf), table.concat(names, ",")))
    for i, d in ipairs(vim.diagnostic.get(buf)) do
      if i > 3 then break end
      log("    [" .. tostring(d.source) .. "] " .. d.message:gsub("\n", " "):sub(1, 90))
    end
  end
  -- подсказка ansible-doc по модулю (сервер зовёт ansible-doc из venv)
  local abuf = vim.fn.bufnr("roles/web/tasks/main.yml")
  local params = { textDocument = { uri = vim.uri_from_bufnr(abuf) }, position = { line = 1, character = 3 } }
  local res = vim.lsp.buf_request_sync(abuf, "textDocument/hover", params, 20000) or {}
  local hover = ""
  for _, r in pairs(res) do
    local c = r.result and r.result.contents
    hover = hover .. (type(c) == "table" and (c.value or vim.inspect(c)) or tostring(c or ""))
  end
  log("ansible hover apt: " .. (#hover > 0 and hover:gsub("\n", " "):sub(1, 100) or "ПУСТО"))
  log("mason registry_cache.refresh: " .. tostring(require("mason.settings").current.registry_cache.refresh))
  local miss = {}
  for _, l in ipairs(LazyVim.opts("nvim-treesitter").ensure_installed) do
    local ok, r = pcall(vim.treesitter.language.add, l)
    if not (ok and r) then miss[#miss + 1] = l end
  end
  log("parsers missing: " .. vim.inspect(miss))
  local qmiss = {}
  for _, l in ipairs(LazyVim.opts("nvim-treesitter").ensure_installed) do
    if not vim.treesitter.query.get(l, "highlights") then qmiss[#qmiss + 1] = l end
  end
  log("highlights queries missing: " .. vim.inspect(qmiss))
  local gs = vim.b[vim.fn.bufnr("app.py")].gitsigns_status_dict
  log("gitsigns app.py: " .. (gs and string.format("head=%s added=%s changed=%s", gs.head, gs.added, gs.changed) or "нет"))
  log("lazygit: " .. (vim.fn.system("lazygit --version"):match("version=([^,]+)") or "?"))
  log("node внутри nvim: " .. vim.fn.system("node -v"):gsub("\n", ""))
  log("blink rust: " .. tostring(pcall(require, "blink.cmp.fuzzy.rust")))
  local st = require("lazy").stats()
  log(string.format("lazy: %d плагинов, старт %d мс", st.count, st.startuptime))
  log("mason установлено: " .. #require("mason-registry").get_installed_package_names())
  log("nvim: " .. vim.v.progpath .. "  config: " .. vim.fn.stdpath("config") .. "  appname: " .. tostring(vim.env.NVIM_APPNAME))
  local errs = {}
  local ok_log, lines = pcall(vim.fn.readfile, vim.lsp.log.get_filename())
  for _, l in ipairs(ok_log and lines or {}) do
    if l:find("%[ERROR%]") then errs[#errs + 1] = l:gsub("^.-log%.lua:%d+\t", ""):sub(1, 200) end
  end
  log("lsp.log ERROR: " .. #errs)
  for i = 1, math.min(10, #errs) do log("    " .. errs[i]) end
  log("messages: " .. vim.fn.execute("messages"):gsub("\n", " | "))
  local ok, hist = pcall(function() return Snacks.notifier.get_history() end)
  if ok then
    for _, n in ipairs(hist) do
      log("notify[" .. tostring(n.level) .. "]: " .. tostring(n.msg):gsub("\n", " "):sub(1, 200))
    end
  end
  vim.fn.writefile(vim.split(table.concat(out, "\n"), "\n"), vim.fn.expand("~/lv-report.txt"))
end, 3000)
