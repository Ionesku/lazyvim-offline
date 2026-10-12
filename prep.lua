-- Запуск: nvim --headless "+luafile prep.lua" +qa  (после "Lazy! sync")
-- Ставит пакеты Mason и парсеры treesitter, которые LazyVim обычно докачивает при первом открытии
-- файлов, и проверяет, что всё на месте. Если чего-то не хватает — выходит с кодом 1.
local function log(...) io.stdout:write(table.concat(vim.tbl_map(tostring, { ... }), " ") .. "\n") end

local function main()
  local fails = {}
  local lazy_root = require("lazy.core.config").options.root
  require("lazy").load({ plugins = { "nvim-treesitter", "mason.nvim", "mason-lspconfig.nvim", "nvim-lspconfig", "blink.cmp" } })

  -- mason: инструменты из extras + LSP-серверы. tree-sitter CLI из Mason не берём: ему нужна glibc 2.39
  local map = require("mason-lspconfig.mappings").get_mason_map().lspconfig_to_package
  local want = vim.deepcopy(LazyVim.opts("mason.nvim").ensure_installed or {})
  for server, sopts in pairs(LazyVim.opts("nvim-lspconfig").servers or {}) do
    if server ~= "*" and type(sopts) == "table" and sopts.enabled ~= false and sopts.mason ~= false and map[server] then
      want[#want + 1] = map[server]
    end
  end
  want = vim.fn.uniq(vim.fn.sort(want))
  log("mason:", table.concat(want, " "))

  -- LazyVim сам запускает установку при загрузке mason; ставим только то, что он не взял
  local mr = require("mason-registry")
  local refreshed = false
  mr.refresh(function() refreshed = true end)
  vim.wait(5 * 60 * 1000, function() return refreshed end, 500)
  local pkgs = {}
  for _, name in ipairs(want) do
    local ok, p = pcall(mr.get_package, name)
    if ok then
      pkgs[#pkgs + 1] = p
      if not p:is_installed() and not p:is_installing() then p:install() end
    else
      fails[#fails + 1] = "mason " .. name .. " (нет в реестре)"
    end
  end
  vim.wait(30 * 60 * 1000, function()
    for _, p in ipairs(pkgs) do
      if p:is_installing() then return false end
    end
    return true
  end, 1000)
  for _, p in ipairs(pkgs) do
    if not p:is_installed() then fails[#fails + 1] = "mason " .. p.name end
  end

  -- treesitter
  local parsers = LazyVim.opts("nvim-treesitter").ensure_installed or {}
  log("treesitter:", #parsers, "parsers, cli:", vim.fn.exepath("tree-sitter"))
  require("nvim-treesitter").install(parsers, { summary = true }):wait(30 * 60 * 1000)
  -- Файлы ищем напрямую: query.get кэширует результат и после переустановки вернул бы старый nil
  local function broken_langs()
    local res = {}
    for _, lang in ipairs(parsers) do
      local so = vim.api.nvim_get_runtime_file("parser/" .. lang .. ".so", false)
      local hl = vim.api.nvim_get_runtime_file("queries/" .. lang .. "/highlights.scm", false)
      -- language.add не бросает ошибку, а возвращает nil
      local ok, added = pcall(vim.treesitter.language.add, lang)
      if #so == 0 or #hl == 0 or not (ok and added) then res[#res + 1] = lang end
    end
    return res
  end
  -- LazyVim параллельно ставит те же парсеры сам; при гонке остаётся .so без ссылки на запросы,
  -- а обычная установка такой язык пропускает — переустанавливаем принудительно
  local broken = broken_langs()
  if #broken > 0 then
    log("treesitter: переустановка " .. table.concat(broken, " "))
    require("nvim-treesitter").install(broken, { force = true, summary = true }):wait(30 * 60 * 1000)
    broken = broken_langs()
  end
  for _, lang in ipairs(broken) do
    fails[#fails + 1] = "treesitter " .. lang
  end

  -- плагины и их нативные части
  for _, p in ipairs(require("lazy").plugins()) do
    if not p._.installed then fails[#fails + 1] = "plugin " .. p.name end
  end
  vim.wait(60 * 1000, function()
    return #vim.fn.glob(lazy_root .. "/blink.cmp/target/release/*.so", false, true) > 0
  end, 1000)
  if #vim.fn.glob(lazy_root .. "/blink.cmp/target/release/*.so", false, true) == 0 then
    fails[#fails + 1] = "blink.cmp: нет нативной библиотеки"
  end
  if vim.fn.executable(lazy_root .. "/markdown-preview.nvim/app/bin/markdown-preview-linux") ~= 1 then
    fails[#fails + 1] = "markdown-preview: нет бинарника"
  end
  return fails
end

local ok, res = xpcall(main, debug.traceback)
if not ok then
  log("FAIL: " .. tostring(res))
  vim.cmd("cquit 1")
elseif #res > 0 then
  log("FAIL: " .. table.concat(res, ", "))
  vim.cmd("cquit 1")
end
log("prep OK")
