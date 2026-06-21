-- lua/goime/status.lua — 状态栏接口（Neovim）
-- 返回状态文本供 airline/lightline/lualine 等状态栏插件使用
-- 约定：返回空字符串 "" 时隐藏状态栏组件

local config = require('goime.config')

local M = {}

--- 当前状态
---@field connected boolean
---@field chinese_mode boolean
---@field plugin_enabled boolean
local state = {
  connected = false,
  chinese_mode = true,
  plugin_enabled = true,
  active_scheme = '',
}

--- 更新内部状态
---@param opts {connected: boolean, chinese_mode: boolean, plugin_enabled: boolean}
function M.update(opts)
  opts = opts or {}
  if opts.connected ~= nil then state.connected = opts.connected end
  if opts.chinese_mode ~= nil then state.chinese_mode = opts.chinese_mode end
  if opts.plugin_enabled ~= nil then state.plugin_enabled = opts.plugin_enabled end
  if opts.active_scheme ~= nil then state.active_scheme = opts.active_scheme end
end

--- 方案中文名映射
local scheme_names = {
  xiaohe = '小鹤双拼',
  fullpin = '全拼',
}

--- 返回当前状态栏显示文本
function M.current()
  if not state.connected then
    return config.config.status_off or ''
  end
  if not state.plugin_enabled then
    return ''
  end
  if not state.chinese_mode then
    return config.config.status_en
  end
  if config.config.status_cn ~= '中' then
    return config.config.status_cn
  end
  return scheme_names[state.active_scheme] or state.active_scheme or config.config.status_cn
end

return M
