-- lua/goime/client.lua — GoIME Unix Socket/TCP 客户端（Neovim）

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
  self.client = nil
  self.buffer = ''
  self.pending = {}          --- 连接前缓冲的请求
  self.callbacks = {}
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
    return runtime_dir .. '/goime.sock'
  end
  local tmpdir = vim.fn.environ()['TMPDIR']
  if tmpdir then
    local uid = vim.fn.system('id -u'):gsub('%s+', '')
    return tmpdir .. '/goime-' .. uid .. '.sock'
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

  -- TCP 模式（配置了 port）
  if config.config.port then
    self:_connect_tcp(callback)
    return
  end

  -- Unix socket 模式
  self:_connect_unix(callback)
end

--- TCP 连接
---@param callback fun(success: boolean, msg: string)|nil
function Client:_connect_tcp(callback)
  local host = config.config.host or '127.0.0.1'
  local port = config.config.port

  local handle = uv.new_tcp()
  if not handle then
    if callback then callback(false, 'failed to create tcp handle') end
    return
  end

  local function on_connect(err)
    if err then
      vim.schedule(function()
        vim.notify('[goime] TCP 连接失败: ' .. tostring(err), vim.log.levels.ERROR)
        handle:close()
        if callback then callback(false, 'connection failed') end
      end)
      return
    end

    self.connected = true
    self.client = handle
    self.buffer = ''
    vim.schedule(function() self:_flush_pending() end)

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

    -- 握手
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

  handle:connect(host, port, on_connect)
end

--- Unix socket 连接
---@param callback fun(success: boolean, msg: string)|nil
function Client:_connect_unix(callback)
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

  local handle = uv.new_pipe(false)
  if not handle then
    if callback then callback(false, 'failed to create pipe') end
    return
  end

  local function on_connect(err)
    if err then
      local stale = uv.fs_stat(socket_path)
      if stale then
        os.remove(socket_path)
      end
      vim.schedule(function()
        local binary = self:_find_binary()
        if binary ~= '' then
          vim.fn.jobstart({ binary }, { detach = true })
          vim.defer_fn(function() self:connect(callback) end, 500)
          if callback then callback(true, 'starting goimed') end
          return
        end
        vim.notify('[goime] 连接失败，请安装 goimed', vim.log.levels.ERROR)
        handle:close()
        if callback then callback(false, 'binary not found') end
      end)
      return
    end

    self.connected = true
    self.client = handle
    self.buffer = ''
    vim.schedule(function() self:_flush_pending() end)

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
  local function attempt()
    handle:connect(socket_path, on_connect)
  end

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
  if not self.connected then
    table.insert(self.pending, { method = 'input', key = key })
    return
  end
  self:_send({ method = 'input', key = key })
end

--- 连接后发送缓冲的请求
function Client:_flush_pending()
  if not self.connected then return end
  for _, msg in ipairs(self.pending) do
    self:_send(msg)
  end
  self.pending = {}
function Client:enter() self:_send({ method = 'enter' }) end
function Client:escape() self:_send({ method = 'escape' }) end
function Client:backspace() self:_send({ method = 'backspace' }) end
function Client:space() self:_send({ method = 'space' }) end
function Client:select(index) self:_send({ method = 'select', index = index }) end
function Client:page(dir) self:_send({ method = 'page', dir = dir }) end
function Client:arrow(dir) self:_send({ method = 'arrow', dir = dir }) end
function Client:set_scheme(name) self:_send({ method = 'set_scheme', name = name }) end
function Client:commit_preedit() self:_send({ method = 'commit_preedit' }) end
function Client:reset() self:_send({ method = 'reset' }) end

function Client:send_config()
  local msg = { method = 'config', page_size = config.config.page_size or 5 }
  if config.config.schemes and #config.config.schemes > 0 then
    msg.schemes = config.config.schemes
  end
  self:_send(msg)
end

function Client:is_connected() return self.connected end

return M
