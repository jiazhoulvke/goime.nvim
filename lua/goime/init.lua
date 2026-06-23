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
  chinese_mode = config.config.default_chinese,  --- 中文模式（true） / 英文模式（false）
  plugin_enabled = config.config.enabled,
  preedit_text = '',
  schemes = {},
  active_scheme = '', --- 插件是否启用
  input_context = nil,  --- 发送按键时的 buffer/window/cursor 上下文
  quote_double = false, --- 双引号配对状态（false=下次输出左引号，true=下次输出右引号）
  quote_single = false, --- 单引号配对状态
}

--- 保存当前 buffer/cursor 上下文（发送按键前调用）
local function save_input_context()
  goime.input_context = {
    bufnr = api.nvim_get_current_buf(),
    win = api.nvim_get_current_win(),
    row = api.nvim_win_get_cursor(0)[1],
    col = api.nvim_win_get_cursor(0)[2],
  }
end

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
      -- 使用发送按键时保存的 buffer/cursor 上下文
      local ctx = goime.input_context
      local bufnr, win, row, col
      if ctx and api.nvim_buf_is_valid(ctx.bufnr) and api.nvim_win_is_valid(ctx.win) then
        bufnr = ctx.bufnr
        win = ctx.win
        row, col = ctx.row, ctx.col
      else
        bufnr = api.nvim_get_current_buf()
        win = api.nvim_get_current_win()
        local cursor = api.nvim_win_get_cursor(0)
        row, col = cursor[1], cursor[2]
      end
      local line = api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ''
      local new_line = line:sub(1, col) .. text .. line:sub(col + 1)
      api.nvim_buf_set_lines(bufnr, row - 1, row, false, { new_line })
      if win == api.nvim_get_current_win() then
        api.nvim_win_set_cursor(0, { row, col + #text })
      end
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
    local clist = candidates and candidates.list
    goime.ui:show(clist, candidates and candidates.page or 0, candidates and candidates.total or 1, preedit)
  end)

  goime.client:on('idle', function()
    goime.preedit_text = ''
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

  -- InsertEnter 始终注册：注册 buffer-local BS 映射（覆盖 autopairs 等）
  api.nvim_create_autocmd('InsertEnter', {
    group = augroup,
    desc = '进入插入模式时注册 buffer-local 映射并按需连接 GoIME',
    callback = function()
      M.on_insert_enter()
    end,
  })

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

  vim.keymap.set('i', k(map.toggle_enable, '<M-;>'), function()
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
    if not goime.preedit_text or goime.preedit_text == '' then
      if config.config.ascii_punct then return ',' end
      return config.config.punct_map[','] or '，'
    end
    goime.client:page('prev')
    return ''
  end, { desc = 'GoIME 上一页', expr = true, silent = true })

  vim.keymap.set('i', k(map.page_next, '.'), function()
    if not goime.plugin_enabled or not goime.client or not goime.client:is_connected() or not goime.chinese_mode then
      return k(map.page_next, '.')
    end
    if not goime.preedit_text or goime.preedit_text == '' then
      if config.config.ascii_punct then return '.' end
      return config.config.punct_map['.'] or '。'
    end
    goime.client:page('next')
    return ''
  end, { desc = 'GoIME 下一页', expr = true, silent = true })

  -- 字母键映射（expr mode）
  for c in ('abcdefghijklmnopqrstuvwxyz'):gmatch('.') do
    vim.keymap.set('i', c, function()
      if not goime.plugin_enabled or not goime.chinese_mode then
        return c
      end
      if goime.client then
        save_input_context()
        goime.client:input(c)
        return ''
      end
      return c
    end, { expr = true, silent = true })
  end

  -- 标点符号全角转换（排除 , . 已在上方翻页映射中处理，" ' 使用配对切换）
  for ascii, fullwidth in pairs(config.config.punct_map or {}) do
    if ascii == ',' or ascii == '.' or ascii == '"' or ascii == "'" then
      goto continue_punct
    end
    vim.keymap.set('i', ascii, function()
      if not goime.plugin_enabled or not goime.chinese_mode then return ascii end
      if config.config.ascii_punct then return ascii end
      return fullwidth
    end, { expr = true, silent = true })
    ::continue_punct::
  end

  -- 引号配对（左右切换）
  for _, q in ipairs({ '"', "'" }) do
    vim.keymap.set('i', q, function()
      if not goime.plugin_enabled or not goime.chinese_mode then return q end
      if config.config.ascii_punct then return q end
      if q == '"' then
        goime.quote_double = not goime.quote_double
        return goime.quote_double and '\u{201C}' or '\u{201D}'
      end
      goime.quote_single = not goime.quote_single
      return goime.quote_single and '\u{2018}' or '\u{2019}'
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
    if goime.preedit_text and goime.preedit_text ~= '' then
      save_input_context()
      goime.client:space()
      return ''
    end
    return '<Space>'
  end, { expr = true, silent = true })

  -- 退格
  -- 退格：删除拼音输入
  vim.keymap.set('i', k(map.backspace, '<BS>'), function()
    if not goime.plugin_enabled or not goime.client or not goime.client:is_connected() or not goime.chinese_mode then
      return '<BS>'
    end
    if goime.preedit_text and goime.preedit_text ~= '' then
      goime.client:backspace()
      return ''
    end
    return '<BS>'
  end, { expr = true, silent = true })

  -- 回车：先发 enter 给 goime，再插入回车
  vim.keymap.set('i', k(map.enter, '<CR>'), function()
    if completion_active() then
      return '<CR>'
    end
    if goime.plugin_enabled and goime.client and goime.client:is_connected() and goime.chinese_mode then
      if goime.preedit_text and goime.preedit_text ~= '' then
        save_input_context()
        goime.client:enter()
        return '<CR>'
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
      if goime.preedit_text and goime.preedit_text ~= '' then
        save_input_context()
        goime.client:select(i - 1)
        return ''
      end
      return tostring(i)
    end, { expr = true, silent = true })
  end
  -- 0 选第 10 个候选（索引 9）
  vim.keymap.set('i', '0', function()
    if not goime.plugin_enabled or not goime.client or not goime.client:is_connected() or not goime.chinese_mode then
      return '0'
    end
    if goime.preedit_text and goime.preedit_text ~= '' then
      save_input_context()
      goime.client:select(9)
      return ''
    end
    return '0'
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

--- 插件启用/禁用（<M-;>）
function M.toggle_enabled()
  goime.plugin_enabled = not goime.plugin_enabled
  goime.ui:close()
  if goime.client and goime.client:is_connected() then
    goime.client:escape()
  end
  status.update({ plugin_enabled = goime.plugin_enabled })
  vim.cmd('redrawstatus!')
  if goime.plugin_enabled then
    if not goime.client or not goime.client:is_connected() then
      M.connect()
    end
    vim.notify('GoIME: 已启用', vim.log.levels.INFO)
  else
    vim.notify('GoIME: 已禁用', vim.log.levels.INFO)
  end
end

--- 进入插入模式时注册 buffer-local 映射并按需连接
function M.on_insert_enter()
  -- 插件禁用或非普通 buffer 时不设置映射
  if not goime.plugin_enabled then return end
  local bt = vim.bo.buftype
  if bt ~= '' and bt ~= 'acwrite' then return end

  local map = config.config.mappings or {}
  local function k(key, fallback)
    return (key ~= nil and key ~= '') and key or fallback
  end

  -- 补菜单打开时让给补全插件
  local function completion_active()
    if vim.fn.pumvisible() == 1 then return true end
    if pcall(require, 'blink.cmp') and require('blink.cmp').is_visible() then return true end
    return false
  end

  -- 为当前 buffer 注册局部映射（优先级高于 autopairs 等插件）
  -- BS
  vim.keymap.set('i', k(map.backspace, '<BS>'), function()
    if goime.plugin_enabled and goime.client and goime.client:is_connected() and goime.chinese_mode then
      if goime.preedit_text and goime.preedit_text ~= '' then
        goime.client:backspace()
        return ''
      end
    end
    return '<BS>'
  end, { expr = true, desc = 'GoIME 退格', buffer = true })

  -- CR
  vim.keymap.set('i', k(map.enter, '<CR>'), function()
    if completion_active() then
      return '<CR>'
    end
    if goime.plugin_enabled and goime.client and goime.client:is_connected() and goime.chinese_mode then
      if goime.preedit_text and goime.preedit_text ~= '' then
        save_input_context()
        goime.client:enter()
        return '<CR>'
      end
    end
    return '<CR>'
  end, { expr = true, desc = 'GoIME 回车', buffer = true })

  -- Esc
  vim.keymap.set('i', k(map.escape, '<Esc>'), function()
    if goime.plugin_enabled and goime.client and goime.client:is_connected() then
      goime.client:escape()
    end
    return '<Esc>'
  end, { expr = true, desc = 'GoIME Escape', buffer = true })

  -- Space
  vim.keymap.set('i', k(map.space, '<Space>'), function()
    if not goime.plugin_enabled or not goime.client or not goime.client:is_connected() or not goime.chinese_mode then
      return '<Space>'
    end
    if goime.preedit_text and goime.preedit_text ~= '' then
      save_input_context()
      goime.client:space()
      return ''
    end
    return '<Space>'
  end, { expr = true, desc = 'GoIME 空格', buffer = true })

  -- 标点符号全角转换（buffer-local，覆盖 autopairs，" ' 使用配对切换）
  for ascii, fullwidth in pairs(config.config.punct_map or {}) do
    if ascii == ',' or ascii == '.' or ascii == '"' or ascii == "'" then
      goto continue_bl_punct
    end
    vim.keymap.set('i', ascii, function()
      if not goime.plugin_enabled or not goime.chinese_mode then return ascii end
      if config.config.ascii_punct then return ascii end
      return fullwidth
    end, { expr = true, desc = 'GoIME 标点', buffer = true })
    ::continue_bl_punct::
  end

  -- 引号配对（buffer-local，覆盖 autopairs）
  for _, q in ipairs({ '"', "'" }) do
    vim.keymap.set('i', q, function()
      if not goime.plugin_enabled or not goime.chinese_mode then return q end
      if config.config.ascii_punct then return q end
      if q == '"' then
        goime.quote_double = not goime.quote_double
        return goime.quote_double and '\u{201C}' or '\u{201D}'
      end
      goime.quote_single = not goime.quote_single
      return goime.quote_single and '\u{2018}' or '\u{2019}'
    end, { expr = true, desc = 'GoIME 引号', buffer = true })
  end

  -- 仅在启用且 auto_connect 时自动连接
  if goime.plugin_enabled and config.config.auto_connect then
    if not goime.client or not goime.client:is_connected() then
      M.connect()
    end
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
