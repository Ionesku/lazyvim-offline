-- Плагины, Mason и парсеры — в каталоге пакета lazyvim-offline (см. setup.lua там же).
-- Свои настройки — в lua/config/{options,keymaps,autocmds}.lua и lua/plugins/*.lua этого каталога.
dofile((vim.env.LAZYVIM_PREFIX or "/opt/lazyvim") .. "/setup.lua")
