-- lua/goime/init.lua — GoIME Neovim 入口
-- 在 Neovim 中使用：
--   lua require('goime').setup({ debug = true })

local api = vim.api
local config = require('goime.config')
local Client = require('goime.client')
local UI = require('goime.ui')
local status = require('goime.status')

local M = {}

--- 插件实例状态
local goime = {
  client = nil,         ---@type table
  ui = nil,             ---@type table
  chinese_mode = true,  --- 中文模式（true） / 英文模式（false）
  plugin_enabled = true,
  preedit_text = '',
  schemes = {},
  active_scheme = '', --- 插件是否启用
}

--- 设置插件
---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
  goime.client = Client.new()
  goime.ui = UI.new()

  -- 注册响应回调
  goime.client:on('welcome', function(resp)
    goime.schemes = resp.schemes or {}
    goime.active_scheme = resp.active or ''
    if config.config.debug then
      vim.notify('[goime] 握手成功，方案：' .. goime.active_scheme, vim.log.levels.INFO)
    end
    status.update({ connected = true, active_scheme = goime.active_scheme })
    vim.cmd('redrawstatus!')
  end)

  goime.client:on('commit', function(resp)
    local text = resp.text or ''
    if text ~= '' then
      -- 插入文本到当前缓冲区
      local bufnr = api.nvim_get_current_buf()
      local row, col = unpack(api.nvim_win_get_cursor(0))
      local line = api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ''
      local new_line = line:sub(1, col) .. text .. line:sub(col + 1)
      api.nvim_buf_set_lines(bufnr, row - 1, row, false, { new_line })
      api.nvim_win_set_cursor(0, { row, col + #text })
    end

    -- 部分提交：commit 中可能附带剩余输入的候选项
    goime.preedit_text = ''
    local remain = resp.candidates
    if remain and remain.list and #remain.list > 0 then
      goime.ui:show(remain.list, remain.page or 0, remain.total or 1, '')
    else
      goime.ui:close()
    end

    -- 处理 pending_key
    local pending = resp.pending_key or ''
    if pending ~= '' then
      vim.api.nvim_input(pending)
    end
  end)

  goime.client:on('preedit', function(resp)
    goime.preedit_text = resp.text or ''
    local candidates = resp.candidates
    local preedit = goime.preedit_text
    if candidates and candidates.list and #candidates.list > 0 then
      goime.ui:show(candidates.list, candidates.page or 0, candidates.total or 1, preedit)
    else
      goime.ui:close()
    end
  end)

  goime.client:on('idle', function()
    goime.ui:close()
  end)

  goime.client:on('error', function(resp)
    local msg = resp.message or '未知错误'
    vim.notify('[goime] 服务端错误: ' .. msg, vim.log.levels.WARN)
  end)

  -- 创建命令
  vim.api.nvim_create_user_command('GoIMESchemeNext', function()
    M.cycle_scheme(1)
  end, {})

  vim.api.nvim_create_user_command('GoIMESchemePrev', function()
    M.cycle_scheme(-1)
  end, {})

  vim.api.nvim_create_user_command('GoIMEScheme', function(opts)
    local name = opts.args
    if goime.client and goime.client:is_connected() then
      goime.client:set_scheme(name)
      goime.preedit_text = ''
      goime.ui:close()
      status.update({ active_scheme = name })
    vim.notify('[goime] 方案切换: ' .. name, vim.log.levels.INFO)
    end
  end, { nargs = 1 })

  vim.api.nvim_create_user_command('GoIMEToggle', function()
    M.toggle()
  end, {})

  vim.api.nvim_create_user_command('GoIMEStatus', function()
    M.echo_status()
  end, {})

  vim.api.nvim_create_user_command('GoIMEConnect', function()
    M.connect()
  end, {})

  vim.api.nvim_create_user_command('GoIMEDisconnect', function()
    M.disconnect()
  end, {})

  vim.api.nvim_create_user_command('GoIMEToggleEnabled', function()
    M.toggle_enabled()
  end, {})

  -- 设置自动命令
  local augroup = api.nvim_create_augroup('goime', { clear = true })

  if config.config.auto_connect then
    api.nvim_create_autocmd('InsertEnter', {
      group = augroup,
      desc = '进入插入模式时连接 GoIME',
      callback = function()
        M.on_insert_enter()
      end,
    })
  end

  api.nvim_create_autocmd('InsertLeave', {
    group = augroup,
    desc = '离开插入模式时清理 GoIME',
    callback = function()
      M.on_insert_leave()
    end,
  })

  -- 使用自定义映射（用户可覆盖）
  local map = config.config.mappings or {}
  local function k(key, fallback)
    return (key ~= nil and key ~= '') and key or fallback
  end

  vim.keymap.set('i', k(map.toggle, '<S-Space>'), function()
    M.toggle()
  end, { desc = 'GoIME 中/英文切换', silent = true })

  vim.keymap.set('i', k(map.toggle_enable, '<C-;>'), function()
    M.toggle_enabled()
  end, { desc = 'GoIME 插件启用/禁用', silent = true })

  -- 右 Shift 中英文切换（在能区分左右 Shift 的终端/GVim 下生效）
  -- 禁用所有默认映射
  if not config.config.no_default_mappings then
  -- 大多数终端无法区分左右 Shift，已通过 toggle_key（默认 <S-Space>）提供等效功能

  -- 设置插入模式映射（仅中文模式时激活）
  --, 逗号：向上翻页
  vim.keymap.set('i', k(map.page_prev, ','), function()
    if not goime.plugin_enabled or not goime.client or not goime.client:is_connected() or not goime.chinese_mode then
      return k(map.page_prev, ',')
    end
    goime.client:page('prev')
    return ''
  end, { desc = 'GoIME 上一页', expr = true, silent = true })

  vim.keymap.set('i', k(map.page_next, '.'), function()
    if not goime.plugin_enabled or not goime.client or not goime.client:is_connected() or not goime.chinese_mode then
      return k(map.page_next, '.')
    end
    goime.client:page('next')
    return ''
  end, { desc = 'GoIME 下一页', expr = true, silent = true })

  -- 字母键映射（expr mode）
  for c in ('abcdefghijklmnopqrstuvwxyz'):gmatch('.') do
    vim.keymap.set('i', c, function()
      if not goime.plugin_enabled or not goime.client or not goime.client:is_connected() or not goime.chinese_mode then
        return c
      end
      goime.client:input(c)
      return ''
    end, { expr = true, silent = true })
  end

  -- 补菜单打开时让给补全插件
  local function completion_active()
    if vim.fn.pumvisible() == 1 then return true end
    if pcall(require, 'blink.cmp') and require('blink.cmp').is_visible() then return true end
    return false
  end

  -- 空格
  vim.keymap.set('i', k(map.space, '<Space>'), function()
    if not goime.plugin_enabled or not goime.client or not goime.client:is_connected() or not goime.chinese_mode then
      return '<Space>'
    end
    goime.client:space()
    return ''
  end, { expr = true, silent = true })

  -- 退格
  -- 回车：先发 enter 给 goime，再插入回车
  vim.keymap.set('i', k(map.enter, '<CR>'), function()
    if completion_active() then
      return '<CR>'
    end
    if goime.plugin_enabled and goime.client and goime.client:is_connected() and goime.chinese_mode then
      if goime.preedit_text and goime.preedit_text ~= '' then
        goime.client:enter()
        return ''
      end
    end
    return '<CR>'
  end, { expr = true, silent = true })

  -- Escape：发 escape 给 goime，再透传 Escape
  vim.keymap.set('i', k(map.escape, '<Esc>'), function()
    if goime.plugin_enabled and goime.client and goime.client:is_connected() then
      goime.client:escape()
    end
    return '<Esc>'
  end, { expr = true, silent = true })

  -- 数字键 1-0 选词（0=索引 9，第 10 个候选）
  for i = 1, 9 do
    vim.keymap.set('i', tostring(i), function()
      if not goime.plugin_enabled or not goime.client or not goime.client:is_connected() or not goime.chinese_mode then
        return tostring(i)
      end
      goime.client:select(i - 1)
      return ''
    end, { expr = true, silent = true })
  end
  -- 0 选第 10 个候选（索引 9）
  vim.keymap.set('i', '0', function()
    if not goime.plugin_enabled or not goime.client or not goime.client:is_connected() or not goime.chinese_mode then
      return '0'
    end
    goime.client:select(9)
    return ''
  end, { expr = true, silent = true })
end  -- no_default_mappings
end

--- 连接 GoIME
function M.connect()
  if not goime.client then
    goime.client = Client.new()
  end
  goime.client:connect(function(success, msg)
    if success then
      status.update({ connected = true })
      vim.cmd('redrawstatus!')
    end
  end)
end

--- 断开连接
function M.disconnect()
  if goime.client then
    goime.client:disconnect()
  end
  if goime.ui then
    goime.ui:close()
  end
  status.update({ connected = false })
  vim.cmd('redrawstatus!')
end

--- 中/英文模式切换（右 Shift）
function M.toggle()
  if not goime.plugin_enabled then
    return
  end
  goime.chinese_mode = not goime.chinese_mode
  status.update({ chinese_mode = goime.chinese_mode })
  goime.ui:close()
  if goime.client and goime.client:is_connected() then
    goime.client:escape()
  end
  vim.cmd('redrawstatus!')
  if goime.chinese_mode then
    vim.notify('GoIME: 中文模式', vim.log.levels.INFO)
  else
    vim.notify('GoIME: 英文模式', vim.log.levels.INFO)
  end
end

--- 插件启用/禁用（<C-;>）
function M.toggle_enabled()
  goime.plugin_enabled = not goime.plugin_enabled
  goime.ui:close()
  if goime.client and goime.client:is_connected() then
    goime.client:escape()
  end
  status.update({ plugin_enabled = goime.plugin_enabled })
  vim.cmd('redrawstatus!')
  if goime.plugin_enabled then
    vim.notify('GoIME: 已启用', vim.log.levels.INFO)
  else
    vim.notify('GoIME: 已禁用', vim.log.levels.INFO)
  end
end

--- 进入插入模式时自动连接
function M.on_insert_enter()
  if not goime.plugin_enabled then
    return
  end
  -- 为当前缓冲区注册局部 BS 映射（防止 autopairs 等插件拦截）
  vim.keymap.set('i', '<BS>', function()
    if goime.plugin_enabled and goime.client and goime.client:is_connected() and goime.chinese_mode then
      goime.client:backspace()
      return ''
    end
    return '<BS>'
  end, { expr = true, desc = 'GoIME 退格', buffer = true })
  if not goime.client or not goime.client:is_connected() then
    M.connect()
  end
end

--- 离开插入模式时清理
function M.on_insert_leave()
  if goime.ui then
    goime.ui:close()
  end
  if goime.client and goime.client:is_connected() then
    goime.client:escape()
  end
end

--- 显示当前状态
function M.echo_status()
  if not goime.client or not goime.client:is_connected() then
    print('GoIME: 未连接')
    return
  end
  local mode = goime.chinese_mode and '中文' or '英文'
  print('GoIME: ' .. mode)
end

--- 循环切换输入方案
---@param dir integer 1=下一个, -1=上一个
function M.cycle_scheme(dir)
  local schemes = goime.schemes
  if not schemes or #schemes == 0 then return end
  local active = goime.active_scheme
  local idx = 0
  for i, s in ipairs(schemes) do
    if s == active then idx = i; break end
  end
  idx = ((idx - 1 + dir) % #schemes) + 1
  if idx <= 0 then idx = #schemes end
  local name = schemes[idx]
  if goime.client and goime.client:is_connected() then
    goime.client:set_scheme(name)
    goime.active_scheme = name
    goime.preedit_text = ''
    goime.ui:close()
    vim.notify('[goime] 方案切换: ' .. name, vim.log.levels.INFO)
  end
end

return M
