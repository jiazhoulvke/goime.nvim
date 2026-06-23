-- lua/goime/ui.lua — 候选窗/浮动窗口渲染（Neovim）

local api = vim.api
local config = require('goime.config')

local M = {}
local UI = {}
UI.__index = UI

--- 创建新的 UI 实例
---@return table
function M.new()
  local self = setmetatable({}, UI)
  self.win_id = nil
  self.buf_id = nil
  return self
end

--- 创建浮动窗口内容
---@param list table 候选词列表
---@return string[]
local function build_lines(preedit_text, list)
  local lines = {}
  -- 第一行显示 preedit 文本（输入码）
  if preedit_text ~= nil and preedit_text ~= '' then
    table.insert(lines, preedit_text)
    table.insert(lines, '')
  end
  for i, item in ipairs(list) do
    local text = item.text or ''
    local code = item.code or ''
    local label = tostring(i)
    table.insert(lines, string.format('%s. %s  [%s]', label, text, code))
  end
  return lines
end

--- 获取浮动窗口宽度和高度
---@param lines string[]
---@return integer, integer
local function calc_size(lines)
  local max_width = 20
  for _, line in ipairs(lines) do
    local w = vim.api.nvim_strwidth(line)
    if w > max_width then
      max_width = w
    end
  end
  return max_width + 2, #lines + 1
end

--- 显示候选词浮动窗口
---@param list table 候选词列表
---@param page number 当前页码（0-based）
---@param total_pages number 总页数
---@param preedit_text string|nil 输入码文本（显示在顶部）
function UI:show(list, page, total_pages, preedit_text)
  self:close()

  if (not list or #list == 0) and (preedit_text == nil or preedit_text == '') then
    return
  end

  local lines = build_lines(preedit_text or '', list or {})

  -- 翻页信息行
  if total_pages > 1 then
    table.insert(lines, string.format('— %d/%d页 —', page + 1, total_pages))
  end

  local width, height = calc_size(lines)

  -- 获取当前光标位置
  local cursor = api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  local buf = api.nvim_create_buf(false, true)

  -- 写入内容
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- 设置缓冲区选项
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'

  -- 计算浮动窗口位置（在光标下方）
  local win_height = vim.o.lines - vim.o.cmdheight - 1
  local win_width = vim.o.columns

  -- 窗口位置：光标行 + 1，光标列
  local opts = {
    relative = 'cursor',
    width = width,
    height = height,
    row = 1,
    col = 0,
    style = 'minimal',
    border = 'rounded',
    focusable = false,
  }

  -- 检查是否超出屏幕右侧
  if col + width > win_width then
    opts.col = -(col + width - win_width + 1)
    if opts.col < -col then
      opts.col = -col
    end
  end

  -- 检查是否超出屏幕底部
  if row + height + 1 > win_height then
    opts.row = -(height + 1)
    opts.relative = 'cursor'
  end

  local win_id = api.nvim_open_win(buf, false, opts)
  vim.wo[win_id].winhighlight = 'Normal:Pmenu'

  self.win_id = win_id
  self.buf_id = buf
end

--- 关闭浮动窗口
function UI:close()
  if self.win_id and api.nvim_win_is_valid(self.win_id) then
    api.nvim_win_close(self.win_id, true)
  end
  self.win_id = nil
  if self.buf_id and api.nvim_buf_is_valid(self.buf_id) then
    api.nvim_buf_delete(self.buf_id, { force = true })
  end
  self.buf_id = nil
end

return M
