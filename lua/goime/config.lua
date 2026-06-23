-- lua/goime/config.lua — 插件配置

---@class GoIMEConfig
local M = {}

M.defaults = {
  --- 是否默认启用插件（false=禁用，用户需按 <M-;> 启用或设置 enabled=true）
  enabled = false,
  --- 默认中文模式（true=中文，false=英文；仅 enabled=true 时生效）
  default_chinese = true,
  --- Socket 路径，空则自动推导
  socket_path = '',
  --- goimed 可执行文件路径，空则从 PATH 查找
  binary = '',
  --- TCP 连接地址
  host = '127.0.0.1',
  --- TCP 端口（默认 11527，设为 0 则使用 Unix socket 模式）
  port = 11527,
  --- 中文模式状态栏显示文本
  status_cn = '中',
  --- 英文模式状态栏显示文本
  status_en = 'EN',
  --- 未连接时状态栏显示文本（空=隐藏状态栏组件）
  status_off = '',
  --- 中/英文切换键（右 Shift 等效；终端下无法区分左右 Shift，用 <S-Space> 代替）
  toggle_key = '<S-Space>',
  --- 是否自动在插入模式连接
  auto_connect = false,
  --- 客户端标识
  client_name = 'nvim-goime-0.1',
  --- 调试模式
  debug = false,
  --- 标点全角转换开关（false=中文标点，true=英文标点）
  ascii_punct = false,
  --- 标点映射表（ASCII → 全角），用户可增删改
  punct_map = {
    [','] = '，',
    ['.'] = '。',
    [';'] = '；',
    [':'] = '：',
    ['<'] = '《',
    ['>'] = '》',
    ['?'] = '？',
    ['!'] = '！',
    ['('] = '（',
    [')'] = '）',
    ['/'] = '、',
    ['\\'] = '、',
    ['['] = '【',
    [']'] = '】',
    ["'"] = '‘',
    ['"'] = '“',
  },
  page_size = 5,
  schemes = {},
  no_default_mappings = false,
  -- 按键映射，nil=使用默认
  mappings = {
    toggle = nil,       -- 中/英切换
    toggle_enable = nil,-- 启用/禁用
    page_prev = nil,    -- 上一页
    page_next = nil,    -- 下一页
    space = nil,        -- 空格选词
    backspace = nil,    -- 退格
    enter = nil,        -- 回车
    escape = nil,       -- 取消
    tab = nil,          -- Tab 选第二个
  },
}

M.config = vim.deepcopy(M.defaults)

--- 设置配置
---@param opts table|nil
function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do
    M.config[k] = v
  end
end

return M
