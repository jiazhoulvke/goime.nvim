# goime.nvim

GoIME 的 Neovim 客户端。通过 Unix Socket 与 goimed 通信，直接输入中文。

## 安装

需要 [goimed](https://github.com/jiazhoulvke/goime) 守护进程。

### lazy.nvim

```lua
{
  'jiazhoulvke/goime.nvim',
  config = function()
    require('goime').setup({ auto_connect = true })
  end,
}
```

### 手动

```lua
-- 将项目目录加入 rtp
vim.cmd('set rtp+=~/workspace/vim/goime.nvim')
require('goime').setup({ auto_connect = true })
```

## 配置

```lua
require('goime').setup({
  socket_path = '',           -- Socket 路径（空=自动）
  page_size = 5,              -- 每页候选数
  schemes = {},               -- 启用方案列表
  auto_connect = true,        -- 自动连接
  debug = false,              -- 调试日志
})
```

## 命令

| 命令 | 说明 |
|------|------|
| `:GoIMEConnect` | 连接 |
| `:GoIMEToggle` | 中/英切换 |
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
| `<BS>` | expr | 退格删除拼音（buffer 局部映射，在 InsertEnter 时注册） |

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
    tab = '<Tab>',            -- 默认无映射
    backspace = '<C-h>',      -- 默认无映射
  },
})
```

设置映射为 `nil` 或 `''` 表示使用默认值。

### 禁用默认映射

```lua
require('goime').setup({
  no_default_mappings = true, -- 禁用所有默认字母/数字/翻页/回车/ESC 映射
})
```

禁用后你仍需自行定义 `a-z`、数字选词、翻页等映射。`<S-Space>` 和 `<C-;>` 不受此选项影响。

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

## 与 Vim 的关系

`goime.nvim` 是 **Neovim 专用**插件。Vim 8+ 用户请使用 [goime.vim](https://github.com/jiazhoulvke/goime.vim)。

许可证 GPLv3
