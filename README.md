# goime.nvim

GoIME 的 Neovim 客户端。通过 Unix Socket（或 TCP）与 goimed 通信，直接输入中文。

## 安装

需要 [goimed](https://github.com/jiazhoulvke/goime) 守护进程。

### lazy.nvim

```lua
{
  'jiazhoulvke/goime.nvim',
  config = function()
    require('goime').setup()
  end,
}
```

### 手动

```lua
vim.cmd('set rtp+=~/workspace/vim/goime.nvim')
require('goime').setup()
```

默认插件禁用，按 `<C-;>` 启用。也可以传入 `enabled = true` 使初始化时自动启用：

```lua
require('goime').setup({ enabled = true })
```

## 配置

```lua
require('goime').setup({
  -- 是否默认启用插件（false=禁用，按 <C-;> 启用或传 true 表示默认启用）
  enabled = false,

  -- Socket 路径（空=自动推导）
  socket_path = '',

  -- goimed 可执行文件路径（空=从 PATH 查找）
  binary = '',

  -- TCP 连接地址（仅 port 非空时生效）
  host = '127.0.0.1',

  -- TCP 端口（nil=使用 Unix Socket，设值后自动切换到 TCP 模式）
  port = nil,

  -- 每页候选数
  page_size = 5,

  -- 启用方案列表（空=服务端全部方案）
  schemes = {},

  -- 自动连接（true=进入插入模式自动连接，false=手动）
  auto_connect = false,

  -- 中/英标点模式（true=中文标点，false=英文标点）
  ascii_punct = false,

  -- 客户端标识
  client_name = 'nvim-goime-0.1',

  -- 调试日志
  debug = false,

  -- 禁用所有默认按键映射
  no_default_mappings = false,

  -- 按键映射（nil=使用默认）
  mappings = {
    toggle = nil,          -- 中/英切换（默认 <S-Space>）
    toggle_enable = nil,   -- 启用/禁用（默认 <C-;>）
    page_prev = nil,       -- 上一页（默认 ,）
    page_next = nil,       -- 下一页（默认 .）
    space = nil,           -- 空格选词（默认 <Space>）
    backspace = nil,       -- 退格（默认 <BS>）
    enter = nil,           -- 回车上屏（默认 <CR>）
    escape = nil,          -- 取消（默认 <Esc>）
    tab = nil,             -- 暂未实现
  },
})
```

## 命令

| 命令 | 说明 |
|------|------|
| `:GoIMEConnect` | 连接 |
| `:GoIMEDisconnect` | 断开连接 |
| `:GoIMEToggle` | 中/英切换 |
| `:GoIMEToggleEnabled` | 切换插件启用/禁用 |
| `:GoIMEStatus` | 状态 |
| `:GoIMEScheme <name>` | 切换方案 |
| `:GoIMESchemeNext` | 下一个方案 |
| `:GoIMESchemePrev` | 上一个方案 |

## 按键

### 默认映射（插入模式）

| 按键 | 类型 | 说明 |
|------|------|------|
| `a`-`z` | expr | 输入拼音字母（中文模式下发送给 goimed，英文模式直接输出） |
| `1`-`9` | expr | 选择第 1-9 个候选词 |
| `0` | expr | 选择第 10 个候选词 |
| `<Space>` | expr | 选择第一个候选词（首选） |
| `<CR>` | expr | 上屏当前预编辑文本。补全菜单打开时让给补全插件 |
| `,` | expr | 上一页候选词 |
| `.` | expr | 下一页候选词 |
| `<Esc>` | expr | 取消输入（发送 escape 给 goimed，再透传 Escape） |
| `<BS>` | expr | 退格删除拼音（buffer 局部映射，在 InsertEnter 时动态注册） |

### 全局映射（始终生效）

| 按键 | 模式 | 说明 |
|------|------|------|
| `<S-Space>` | i | 中/英文输入模式切换 |
| `<C-;>` | i | 插件启用/禁用切换 |

### 自定义映射

通过 `mappings` 表覆盖任意默认按键：

```lua
require('goime').setup({
  mappings = {
    toggle = '<C-Space>',     -- 中/英切换（默认 <S-Space>）
    toggle_enable = '<F2>',   -- 启用/禁用（默认 <C-;>）
    page_prev = '<PageUp>',   -- 上一页（默认 ,）
    page_next = '<PageDown>', -- 下一页（默认 .）
    space = '<C-f>',          -- 空格选词（默认 <Space>）
    enter = '<C-m>',          -- 回车上屏（默认 <CR>）
    escape = '<C-c>',         -- 取消（默认 <Esc>）
    tab = '<Tab>',            -- 暂未实现
    backspace = '<C-h>',      -- 退格（默认 <BS>）
  },
})
```

设置映射为 `nil` 或 `''` 表示使用默认值。

### 禁用默认映射

```lua
require('goime').setup({
  no_default_mappings = true,
})
```

禁用后你仍需自行定义 `a-z`、数字选词、翻页等映射。`<S-Space>` 和 `<C-;>` 不受此选项影响。

## 候选窗

goime.nvim 使用浮动窗口（float window）显示候选词。

### 外观

- 圆角边框（`rounded`）
- 使用 `Pmenu` 高亮组配色
- 第一行显示正在输入的拼音（preedit 文本）
- 候选词编号行，格式 `N. text [code]`，如 `1. 你好 [ni3hao3]`
- 多页时底部显示 `— 1/3页 —`

### 光标跟随

候选窗在光标位置打开，若超出屏幕边界自动重新定位到右侧/左侧/上方。

### 方向键

客户端提供 `Client:arrow()` 方法支持方向键翻页，需手动映射：

```lua
-- 注意：arrow 是 Client 对象的方法，不是 require('goime') 的直接导出
-- 需要在 client 实例上调用
vim.keymap.set('i', '<Down>', function()
  -- 获取当前 client 实例
  local goime = require('goime')
  -- 暂未直接暴露，参考 client.lua 中的 arrow 方法
end, { desc = 'GoIME 下一个候选', silent = true })
```

## 状态栏

`require('goime.status').current()` 返回当前状态文本，供状态栏插件使用。

### 显示逻辑

| 状态 | 显示内容 |
|------|----------|
| 未连接 | `status_off` 配置值（默认空字符串，表示隐藏） |
| 插件禁用 | 空字符串（隐藏） |
| 英文模式 | `status_en` 配置值（默认 `EN`） |
| 中文模式（`status_cn` 保持默认 `'中'`） | 方案中文名（如 `小鹤双拼`、`全拼`） |
| 中文模式（`status_cn` 自定义） | `status_cn` 配置值 |

### 配合原生 statusline

```lua
vim.o.statusline = '%{%v:lua.require("goime.status").current()%} %f%='
```

### 配合 lualine

```lua
require('lualine').setup({
  sections = {
    lualine_x = {
      { function() return require('goime.status').current() end, icon = '' },
    },
  },
})
```

### 配置显示文本

```lua
require('goime').setup({
  status_cn = '中',    -- 中文模式显示（默认'中'=显示方案名，如"小鹤双拼"）
  status_en = 'EN',    -- 英文模式显示
  status_off = '',     -- 未连接时显示（空=隐藏）
})
```

> 提示：`status_cn` 设为 `'中'` 时会自动显示当前方案的中文名（如"小鹤双拼"、"全拼"）；设为其他值则直接显示该值。

## 公共 API

通过 `require('goime')` 暴露的 Lua 函数：

```lua
local goime = require('goime')
goime.connect()          -- 连接
goime.disconnect()       -- 断开
goime.toggle()           -- 中/英切换
goime.toggle_enabled()   -- 插件启用/禁用
goime.echo_status()      -- 打印状态
goime.cycle_scheme(dir)  -- 循环切换方案
```

> 注意：`arrow()` 方法在 `Client` 对象上（`client.lua`），未从 `init.lua` 直接导出。如需使用可直接调用 `require('goime.client')` 创建独立客户端实例。
```

## TCP 支持

goime.nvim 支持 TCP 连接。配置 `port` 即可自动切换到 TCP 模式：

```lua
require('goime').setup({
  port = 11527,
  host = '127.0.0.1', -- 可选，默认 127.0.0.1
})
```

### TCP 自动发现链

当未指定端口时，插件按以下顺序尝试发现 goimed：
1. 尝试指定端口（如果 `port > 0`）
2. 读取端口文件 `~/.cache/goime/goime.port`
3. 自动启动 `goimed --listen tcp --host <host> --port <port>`
4. 每 500ms 重试，最长 6 秒

## 自动启动

插件检测到 socket 不存在且 `goimed` 可在 PATH 中找到时，会自动异步启动 `goimed` 守护进程并等待 socket 就绪。

## 与 Vim 的关系

`goime.nvim` 是 **Neovim 专用**插件。Vim 8+ 用户请使用 [goime.vim](https://github.com/jiazhoulvke/goime.vim)。

许可证 GPLv3
