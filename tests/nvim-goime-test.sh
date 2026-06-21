#!/bin/sh
GOIME_NVIM_HOME="$(cd "$(dirname "$0")/.." && pwd)"
GOIME_SOCKET="${GOIME_SOCKET:-/run/user/1000/goime.sock}"

if [ ! -d "$GOIME_NVIM_HOME" ]; then
  echo "错误：goime.nvim 目录不存在：$GOIME_NVIM_HOME"
  exit 1
fi

if [ ! -S "$GOIME_SOCKET" ]; then
  echo "错误：goimed socket 不存在：$GOIME_SOCKET"
  exit 1
fi

INIT_LUA=$(mktemp /tmp/goime-nvim-init-XXXXXX.lua)
cat > "$INIT_LUA" << LUAEOF
vim.cmd('set rtp+=' .. vim.fn.fnameescape('${GOIME_NVIM_HOME}'))
require('goime').setup({
  debug = true,
  auto_connect = true,
  socket_path = '${GOIME_SOCKET}',
  page_size = 10,
})
vim.o.laststatus = 2
vim.o.statusline = '%{%v:lua.require("goime.status").current()%} %f%='
LUAEOF

echo "=== GoIME Neovim 测试环境 ==="
echo "插件路径: ${GOIME_NVIM_HOME}"
exec nvim -u "${INIT_LUA}" "${@}"
