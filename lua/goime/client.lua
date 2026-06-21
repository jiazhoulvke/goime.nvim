-- lua/goime/client.lua — GoIME Unix Socket 客户端（Neovim）

local uv = vim.uv or vim.loop
local config = require('goime.config')

local M = {}

--- 检查路径是否为已存在的 socket 文件
---@param path string
---@return boolean
local function socket_exists(path)
  local stat = uv.fs_stat(path)
  return stat ~= nil and stat.type == 'socket'
end

local Client = {}
Client.__index = Client

--- 创建新的客户端实例
---@return table
function M.new()
  local self = setmetatable({}, Client)
  self.connected = false
  self.client = nil          --- uv_pipe 句柄
  self.buffer = ''           --- 接收缓冲区
  self.callbacks = {}        --- 响应回调
  return self
end

--- 获取 socket 文件路径
---@return string
function Client:_socket_path()
  if config.config.socket_path and config.config.socket_path ~= '' then
    return config.config.socket_path
  end
  -- 项目内常用：当前目录的 .goime.sock
  local cwd_sock = '.goime.sock'
  if socket_exists(cwd_sock) then
    return vim.fn.getcwd() .. '/.goime.sock'
  end
  local runtime_dir = vim.fn.environ()['XDG_RUNTIME_DIR']
  if runtime_dir then
    local candidate = runtime_dir .. '/goime.sock'
    if socket_exists(candidate) then
      return candidate
    end
  end
  local uid = vim.fn.system('id -u'):gsub('%s+', '')
  return '/tmp/goime-' .. uid .. '.sock'
end

--- 查找 goimed 可执行文件
---@return string
function Client:_find_binary()
  if config.config.binary and config.config.binary ~= '' then
    return config.config.binary
  end
  if vim.fn.executable('goimed') == 1 then
    return 'goimed'
  end
  return ''
end

--- 连接 goimed 守护进程
---@param callback fun(success: boolean, msg: string)|nil
function Client:connect(callback)
  if self.connected then
    if callback then callback(true, 'already connected') end
    return
  end

  local socket_path = self:_socket_path()

  -- socket 不存在时尝试启动 goimed
  if not socket_exists(socket_path) then
    local binary = self:_find_binary()
    if binary == '' then
      vim.notify('[goime] goimed 未找到，请先安装：go install github.com/jiazhoulvke/goime/cmd/goimed@latest',
        vim.log.levels.ERROR)
      if callback then callback(false, 'goimed not found') end
      return
    end
    -- 异步启动 goimed
    vim.fn.jobstart({ binary }, {
      detach = true,
      on_stderr = function(_, data)
        if data and config.config.debug then
          vim.notify('[goime] ' .. vim.inspect(data), vim.log.levels.DEBUG)
        end
      end,
    })
  end

  -- 创建 Unix 连接
  local handle = uv.new_pipe(false)
  if not handle then
    if callback then callback(false, 'failed to create pipe') end
    return
  end

  local function on_connect(err)
    if err then
      -- 连接失败（如 ECONNREFUSED 可能是 socket 残留）
      -- 删除残留 socket，启动 goimed，重试
      local stale = uv.fs_stat(socket_path)
      if stale then
        os.remove(socket_path)
      end
      local binary = self:_find_binary()
      if binary ~= '' then
        vim.fn.jobstart({ binary }, { detach = true })
        vim.defer_fn(function()
          attempt()
        end, 500)
        if callback then callback(true, 'starting goimed') end
        return
      end
      vim.schedule(function()
        vim.notify('[goime] 连接失败: ' .. err .. '，请安装 goimed', vim.log.levels.ERROR)
      end)
      handle:close()
      if callback then vim.schedule(function() callback(false, err) end) end
      return
    end

    self.connected = true
    self.client = handle
    self.buffer = ''

    -- 设置读取回调
    handle:read_start(function(read_err, data)
      if read_err then
        vim.schedule(function()
          vim.notify('[goime] 读取错误: ' .. read_err, vim.log.levels.ERROR)
        end)
        self:disconnect()
        return
      end
      if data then
        vim.schedule(function()
          self:_on_data(data)
        end)
      end
    end)

    -- 连接成功，发送握手（推迟到主循环，避免 fast event）
    vim.schedule(function()
      local hello = { method = 'hello', version = 1, client = config.config.client_name }
    if config.config.page_size and config.config.page_size > 0 then
      hello.page_size = config.config.page_size
    end
    if config.config.schemes and #config.config.schemes > 0 then
      hello.schemes = config.config.schemes
    end
    self:_send(hello)
    end)

    if callback then vim.schedule(function() callback(true, 'connected') end) end
  end

  -- 尝试连接（带重试）
  local retries = 0
  local max_retries = 10

  local function attempt()
    handle:connect(socket_path, on_connect)
  end

  -- 如果 socket 还不可用，先等待
  if not socket_exists(socket_path) then
    vim.defer_fn(function()
      attempt()
    end, 100)
  else
    attempt()
  end
end

--- 断开连接
function Client:disconnect()
  if self.client then
    self.client:read_stop()
    self.client:close()
  end
  self.client = nil
  self.connected = false
  self.buffer = ''
end

--- 发送 JSON Lines 消息
---@param msg table
function Client:_send(msg)
  if not self.connected or not self.client then
    return
  end
  local json = vim.fn.json_encode(msg)
  self.client:write(json .. '\n')
end

--- 处理接收到的数据
---@param data string
function Client:_on_data(data)
  self.buffer = self.buffer .. data

  while true do
    local nl = self.buffer:find('\n')
    if not nl then break end
    local line = self.buffer:sub(1, nl - 1)
    self.buffer = self.buffer:sub(nl + 1)

    if line == '' then goto continue end

    local ok, resp = pcall(vim.fn.json_decode, line)
    if ok and type(resp) == 'table' then
      self:_handle_response(resp)
    end
    ::continue::
  end
end

--- 处理服务端响应
---@param resp table
function Client:_handle_response(resp)
  local response_type = resp.type or ''
  local handler = self.callbacks[response_type]
  if handler then
    handler(resp)
  end
end

--- 注册响应回调
---@param response_type string 响应类型（welcome, commit, preedit, idle, error）
---@param handler fun(resp: table)
function Client:on(response_type, handler)
  self.callbacks[response_type] = handler
end

--- 发送按键输入
---@param key string 单个字母 (a-z)
function Client:input(key)
  self:_send({ method = 'input', key = key })
end

--- 上屏原始输入码
function Client:enter()
  self:_send({ method = 'enter' })
end

--- 清空缓冲区
function Client:escape()
  self:_send({ method = 'escape' })
end

--- 退格
function Client:backspace()
  self:_send({ method = 'backspace' })
end

--- 空格（选首选或上屏原始输入码）
function Client:space()
  self:_send({ method = 'space' })
end

--- 选择候选词
---@param index number 0-based 索引
function Client:select(index)
  self:_send({ method = 'select', index = index })
end

--- 翻页
---@param dir string "next" 或 "prev"
function Client:page(dir)
  self:_send({ method = 'page', dir = dir })
end

--- 方向键
---@param dir string "up", "down", "left", "right"
function Client:arrow(dir)
  self:_send({ method = 'arrow', dir = dir })
end

--- 切换输入方案
---@param name string 方案名
function Client:set_scheme(name)
  self:_send({ method = 'set_scheme', name = name })
end

--- 上屏当前输入码
function Client:commit_preedit()
  self:_send({ method = 'commit_preedit' })
end

--- 重置状态
function Client:reset()
  self:_send({ method = 'reset' })
end

--- 发送配置更新（分页大小、启用方案）
function Client:send_config()
  local msg = { method = 'config', page_size = config.config.page_size or 5 }
  if config.config.schemes and #config.config.schemes > 0 then
    msg.schemes = config.config.schemes
  end
  self:_send(msg)
end

--- 返回是否已连接
---@return boolean
function Client:is_connected()
  return self.connected
end

return M
