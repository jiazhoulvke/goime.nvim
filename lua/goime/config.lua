-- lua/goime/config.lua — 插件配置

---@class GoIMEConfig
local M = {}

M.defaults = {
  --- Socket 路径，空则自动推导
  socket_path = '',
  --- goimed 可执行文件路径，空则从 PATH 查找
  binary = '',
  --- TCP 连接地址（port 非空时启用 TCP 模式）
  host = '127.0.0.1',
  --- TCP 端口，设置后启用 TCP 连接（空=使用 Unix socket）
  port = nil,
  --- 中文模式状态栏显示文本
  status_cn = '中',
  --- 英文模式状态栏显示文本
  status_en = 'EN',
  --- 未连接时状态栏显示文本（空=隐藏状态栏组件）
  status_off = '',
  --- 中/英文切换键（右 Shift 等效；终端下无法区分左右 Shift，用 <S-Space> 代替）
  toggle_key = '<S-Space>',
  --- 中/英标点模式（true=中文标点，false=英文标点）
  ascii_punct = false,
  --- 是否自动在插入模式连接
  auto_connect = true,
  --- 客户端标识
  client_name = 'nvim-goime-0.1',
  --- 调试模式
  debug = false,
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
    if M.config[k] ~= nil then
      M.config[k] = v
    end
  end
end

return M
