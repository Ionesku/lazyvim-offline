-- Системная часть LazyVim из lazyvim-offline: плагины, Mason, парсеры и JSON-схемы лежат рядом с этим
-- файлом (/opt/lazyvim в deb, ~/.local/lib/lazyvim в архиве) и только читаются. Личный конфиг — в
-- ~/.config/lazyvim, его init.lua подключает этот файл.
local prefix = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local share = prefix .. "/share"
local build = vim.env.LAZYVIM_BUILD == "1" -- сборка пакета: можно ходить в сеть и ставить пакеты

-- Языки (LazyVim extras) задаются здесь, а не в lazyvim.json пользователя: в пакете есть плагины,
-- серверы и парсеры только для них, и с новой версией пакета список обновится у всех.
local extras = { "ansible", "docker", "git", "json", "markdown", "python", "toml", "yaml" }

-- Свежий node для языковых серверов (только внутри nvim, системный node не трогаем); rg, fd, lazygit
vim.env.PATH = prefix .. "/node/bin:" .. prefix .. "/bin:" .. vim.env.PATH
vim.env.MASON = share .. "/mason"
-- marksman (.NET) без libicu падает; если ICU в системе нет, переводим его в режим без неё
if vim.fn.glob("/usr/lib/x86_64-linux-gnu/libicuuc.so.*") == "" and vim.fn.glob("/usr/lib/libicuuc.so.*") == "" then
  vim.env.DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = "1"
end

-- Схемы SchemaStore из пакета: url -> file://. Схемы, которых нет локально, не подключаем,
-- иначе yamlls и jsonls пытаются скачать их из сети.
local schema_index
local function local_schema(url)
  if not url:match("^https?://") then
    return url
  end
  if schema_index == nil then
    local ok, data = pcall(function()
      return vim.json.decode(table.concat(vim.fn.readfile(share .. "/schemas/index.json"), "\n"))
    end)
    schema_index = ok and data or {}
  end
  local base, frag = url:match("^([^#]*)(.*)$")
  return schema_index[base] and schema_index[base] .. frag or nil
end

-- Дописать обработку к before_init, который уже задал LazyVim (там подключается SchemaStore.nvim)
local function after_before_init(opts, server, fix)
  opts.servers[server] = opts.servers[server] or {}
  local orig = opts.servers[server].before_init
  opts.servers[server].before_init = function(params, config)
    if orig then
      orig(params, config)
    end
    fix(config)
  end
end

local function offline_lsp(_, opts)
  opts.servers = opts.servers or {}
  local venv = vim.env.MASON .. "/packages/ansible-lint/venv/bin"
  -- venv привязан к системному python3 3.11; без него ansible-lint падал бы с ошибкой на каждом файле
  local venv_ok = vim.fn.executable(venv .. "/python") == 1
  -- ansible-config, ansible-doc и прочее сервер ищет рядом с ansible.path; берём ansible-core из venv ansible-lint
  -- (--offline сервер передаёт ansible-lint сам)
  opts.servers.ansiblels = vim.tbl_deep_extend("force", opts.servers.ansiblels or {}, {
    settings = {
      ansible = {
        ansible = { path = venv_ok and venv .. "/ansible" or "ansible" },
        python = { interpreterPath = venv_ok and venv .. "/python" or "python3" },
        validation = { lint = { enabled = venv_ok, path = venv .. "/ansible-lint" } },
      },
    },
  })
  -- По умолчанию lua-language-server пишет лог и кэш рядом с собой, а каталог пакета только для чтения
  opts.servers.lua_ls = vim.tbl_deep_extend("force", opts.servers.lua_ls or {}, {
    cmd = {
      "lua-language-server",
      "--logpath=" .. vim.fn.stdpath("log") .. "/lua_ls",
      "--metapath=" .. vim.fn.stdpath("cache") .. "/lua_ls_meta",
    },
  })
  if build then
    return
  end
  after_before_init(opts, "yamlls", function(config)
    local schemas = {}
    for url, match in pairs(config.settings.yaml.schemas or {}) do
      local f = local_schema(url)
      if f then
        schemas[f] = match
      end
    end
    config.settings.yaml.schemas = schemas
  end)
  after_before_init(opts, "jsonls", function(config)
    local schemas = {}
    for _, s in ipairs(config.settings.json.schemas or {}) do
      local f = s.url and local_schema(s.url)
      if f then
        schemas[#schemas + 1] = vim.tbl_extend("force", s, { url = f })
      end
    end
    config.settings.json.schemas = schemas
  end)
  -- taplo грузит каталог схем по зашитому адресу ещё до настроек; в его дисковом кэше лежит локальный каталог
  opts.servers.taplo = vim.tbl_deep_extend("force", opts.servers.taplo or {}, {
    init_options = { cachePath = share .. "/schemas/taplo-cache" },
  })
end

local lazypath = share .. "/lazy/lazy.nvim"
if build and not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", "https://github.com/folke/lazy.nvim.git", lazypath })
end
vim.opt.rtp:prepend(lazypath)

local spec = { { "LazyVim/LazyVim", import = "lazyvim.plugins" } }
for _, name in ipairs(extras) do
  spec[#spec + 1] = { import = "lazyvim.plugins.extras.lang." .. name }
end
-- После языков — личные плагины пользователя, затем офлайн-настройки пакета
vim.list_extend(spec, {
  { import = "plugins" },
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.install_root_dir = vim.env.MASON
      if not build then
        -- Не обновлять реестр (по умолчанию раз в сутки) и не докачивать то, чего нет в пакете
        opts.registry_cache = { refresh = false }
        local root = vim.env.MASON .. "/packages/"
        opts.ensure_installed = vim.tbl_filter(function(name)
          return vim.fn.isdirectory(root .. name) == 1
        end, opts.ensure_installed or {})
      end
    end,
  },
  { "nvim-treesitter/nvim-treesitter", opts = { install_dir = share .. "/site" } },
  { "neovim/nvim-lspconfig", opts = offline_lsp },
  {
    "saghen/blink.cmp",
    opts = function()
      -- Готовая библиотека уже в пакете. Проверка её версии запускает git в каталоге плагина:
      -- без git это ошибка на каждом старте, а с git каталог root в /opt даёт «dubious ownership».
      if not build and pcall(require, "blink.cmp.fuzzy.rust") then
        require("blink.cmp.fuzzy.download").ensure_downloaded = function(cb)
          vim.schedule(function() cb(nil, "rust") end)
        end
      end
    end,
  },
})

require("lazy").setup({
  root = share .. "/lazy",
  lockfile = share .. "/lazy-lock.json",
  spec = spec,
  defaults = { lazy = false, version = false },
  install = { missing = build, colorscheme = { "tokyonight", "habamax" } },
  checker = { enabled = false },
  rocks = { enabled = false },
  performance = {
    rtp = {
      disabled_plugins = { "gzip", "tarPlugin", "tohtml", "tutor", "zipPlugin" },
    },
  },
})
