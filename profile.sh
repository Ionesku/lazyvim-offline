# lazyvim-offline: nvim -> /opt/lazyvim (neovim 0.12 + LazyVim), там же rg, fd, lazygit.
# Системный /usr/bin/nvim остаётся на месте. Чтобы вернуть его по умолчанию, удалите этот файл.
case ":$PATH:" in
  *":/opt/lazyvim/bin:"*) ;;
  *) PATH="/opt/lazyvim/bin:$PATH" ;;
esac
