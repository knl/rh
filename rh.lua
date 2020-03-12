#!/usr/bin/env lua
--=====================================================================
--
-- rh.lua - repository hierarchy aware cd command, by knl 2019
-- Based on z.lua - a cd command that learns, by skywind 2018, 2019
-- Licensed under MIT license.
--
-- Version 1.0.0, Last Modified: 2019/03/22
--
-- * based on z.lua
-- * compatible with lua 5.1, 5.2, 5.3+, and luajit
--
-- USE:
--     for hierarchy in form <server>/<org>/<repo>
--
--     * rh              # list all visited repositories
--     * rh foo          # cd to most frecent repo matching foo
--     * rh foo/bar      # cd to most frecent repo matching bar for org foo
--     * rh foo bar      # - same as above -
--     * rh hub/foo/bar  # cd to most frecent repo matching bar for server hub and org foo
--     * rh hub foo bar  # - same as above -
--     * rh <url>        # cd to the repo based on URL, or clone a new one and cd there
--
-- Bash Install:
--     * put something like this in your .bashrc:
--         eval "$(lua /path/to/rh.lua --init bash ~/work)"
--
-- Zsh Install:
--     * put something like this in your .zshrc:
--         eval "$(lua /path/to/rh.lua --init zsh ~/work)"
--
-- Posix Shell Install:
--     * put something like this in your .profile:
--         eval "$(lua /path/to/rh.lua --init posix ~/work)"
--
-- Fish Shell Install:
--     * put something like this in your config file:
--         source (lua /path/to/rh.lua --init fish ~/work | psub)
--
-- Power Shell Install:
--     * put something like this in your config file:
--         iex ($(lua /path/to/rh.lua --init powershell) -join "`n")
--
-- Windows Install (with Clink):
--     * copy rh.lua and rh.cmd to clink's home directory
--     * Add clink's home to %PATH% (rh.cmd can be called anywhere)
--     * Ensure that "lua" can be called in %PATH%
--
-- Windows Cmder Install:
--     * copy rh.lua and rh.cmd to cmder/vendor
--     * Add cmder/vendor to %PATH%
--     * Ensure that "lua" can be called in %PATH%
--
-- Configure (optional):
--   set $_RH_CMD in .bashrc/.zshrc to change the command (default rh).
--   set $_RH_DATA in .bashrc/.zshrc to change the datafile (default ~/.zlua).
--   set $_RH_ROOT in .bashrc/.zshrc to change the store root (default ~/work).
--
--=====================================================================

-----------------------------------------------------------------------
-- Module Header
-----------------------------------------------------------------------
local modname = 'rh'
local MM = {}
_G[modname] = MM
package.loaded[modname] = MM  --return modname
setmetatable(MM, {__index = _G})

if _ENV ~= nil then
  _ENV[modname] = MM
else
  setfenv(1, MM)
end


-----------------------------------------------------------------------
-- Environment
-----------------------------------------------------------------------
local windows = package.config:sub(1, 1) ~= '/' and true or false
local in_module = pcall(debug.getlocal, 4, 1) and true or false
os.path = {}
os.argv = arg ~= nil and arg or {}
os.path.sep = windows and '\\' or '/'


-----------------------------------------------------------------------
-- Global Variables
-----------------------------------------------------------------------
DATA_FILE = '~/.zlua'  -- we don't modify, just read, so it's safe
RH_ROOT = '~/work'
RH_CMD = 'rh'


-----------------------------------------------------------------------
-- string lib
-----------------------------------------------------------------------
function string:split(sSeparator, nMax, bRegexp)
  assert(sSeparator ~= '')
  assert(nMax == nil or nMax >= 1)
  local aRecord = {}
  if self:len() > 0 then
    local bPlain = not bRegexp
    nMax = nMax or -1
    local nField, nStart = 1, 1
    local nFirst, nLast = self:find(sSeparator, nStart, bPlain)
    while nFirst and nMax ~= 0 do
      aRecord[nField] = self:sub(nStart, nFirst - 1)
      nField = nField + 1
      nStart = nLast + 1
      nFirst, nLast = self:find(sSeparator, nStart, bPlain)
      nMax = nMax - 1
    end
    aRecord[nField] = self:sub(nStart)
  else
    aRecord[1] = ''
  end
  return aRecord
end

function string:startswith(text)
  local size = text:len()
  if self:sub(1, size) == text then
    return true
  end
  return false
end

function string:endswith(text)
  return text == "" or self:sub(-#text) == text
end

function string:join(parts)
  if parts == nil or #parts == 0 then
    return ''
  end
  local size = #parts
  local text = ''
  local index = 1
  while index <= size do
    if index == 1 then
      text = text .. parts[index]
    else
      text = text .. self .. parts[index]
    end
    index = index + 1
  end
  return text
end


-----------------------------------------------------------------------
-- table size
-----------------------------------------------------------------------
function table.length(T)
  local count = 0
  if T == nil then return 0 end
  for _ in pairs(T) do count = count + 1 end
  return count
end


-----------------------------------------------------------------------
-- print table
-----------------------------------------------------------------------
function dump(o)
  if type(o) == 'table' then
    local s = '{ '
    for k,v in pairs(o) do
      if type(k) ~= 'number' then k = '"'..k..'"' end
      s = s .. '['..k..'] = ' .. dump(v) .. ','
    end
    return s .. '} '
  else
    return tostring(o)
  end
end


-----------------------------------------------------------------------
-- print table
-----------------------------------------------------------------------
function printT(table, level)
  key = ""
  local func = function(table, level) end
  func = function(table, level)
    level = level or 1
    local indent = ""
    for i = 1, level do
      indent = indent.."  "
    end
    if key ~= "" then
      print(indent..key.." ".."=".." ".."{")
    else
      print(indent .. "{")
    end

    key = ""
    for k, v in pairs(table) do
      if type(v) == "table" then
        key = k
        func(v, level + 1)
      else
        local content = string.format("%s%s = %s", indent .. "  ",tostring(k), tostring(v))
        print(content)
      end
    end
    print(indent .. "}")
  end
  func(table, level)
end


-----------------------------------------------------------------------
-- invoke command and retrive output
-----------------------------------------------------------------------
function os.call(command)
  local fp = io.popen(command)
  if fp == nil then
    return nil
  end
  local line = fp:read('*l')
  fp:close()
  return line
end


-----------------------------------------------------------------------
-- ffi optimize (luajit has builtin ffi module)
-----------------------------------------------------------------------
os.native = {}
os.native.status, os.native.ffi =  pcall(require, "ffi")
if os.native.status then
  local ffi = os.native.ffi
  if windows then
    ffi.cdef[[
    int GetFullPathNameA(const char *name, uint32_t size, char *out, char **name);
    uint32_t GetFileAttributesA(const char *name);
    uint32_t GetCurrentDirectoryA(uint32_t size, char *ptr);
    ]]
    local kernel32 = ffi.load('kernel32.dll')
    local buffer = ffi.new('char[?]', 300)
    local INVALID_FILE_ATTRIBUTES = 0xffffffff
    local FILE_ATTRIBUTE_DIRECTORY = 0x10
    os.native.kernel32 = kernel32
    function os.native.GetFullPathName(name)
      local hr = kernel32.GetFullPathNameA(name, 290, buffer, nil)
      return (hr > 0) and ffi.string(buffer, hr) or nil
    end
    function os.native.GetFileAttributes(name)
      return kernel32.GetFileAttributesA(name)
    end
    function os.native.exists(name)
      local attr = os.native.GetFileAttributes(name)
      return attr ~= INVALID_FILE_ATTRIBUTES
    end
    function os.native.isdir(name)
      local attr = os.native.GetFileAttributes(name)
      local isdir = FILE_ATTRIBUTE_DIRECTORY
      if attr == INVALID_FILE_ATTRIBUTES then
        return false
      end
      return (attr % (2 * isdir)) >= isdir
    end
    function os.native.getcwd()
      local hr = kernel32.GetCurrentDirectoryA(299, buffer)
      if hr <= 0 then return nil end
      return ffi.string(buffer, hr)
    end
  else
    ffi.cdef[[
    int access(const char *name, int mode);
    char *realpath(const char *path, char *resolve);
    char *getcwd(char *buf, size_t size);
    ]]
    local buffer = ffi.new('char[?]', 4100)
    local F_OK = 0  -- from unistd.h
    local EOK = 0x00  -- from intro(2)
    local ENOENT = 0x02  -- from intro(2)
    function os.native.exists(name)
      local ret = ffi.C.access(name, F_OK)
      if ret == EOK then
        return true
      elseif ret == ENOENT then
        return false
      else  -- FIXME: maybe better error handling
        return false
      end
    end
    function os.native.realpath(name)
      local path = ffi.C.realpath(name, buffer)
      return (path ~= nil) and ffi.string(buffer) or nil
    end
    function os.native.getcwd()
      local hr = ffi.C.getcwd(buffer, 4099)
      return hr ~= nil and ffi.string(buffer) or nil
    end
  end
  os.native.init = true
end


-----------------------------------------------------------------------
-- get current path
-----------------------------------------------------------------------
function os.pwd()
  if os.native and os.native.getcwd then
    local hr = os.native.getcwd()
    if hr then return hr end
  end
  if os.getcwd then
    return os.getcwd()
  end
  if windows then
    local fp = io.popen('cd')
    if fp == nil then
      return ''
    end
    local line = fp:read('*l')
    fp:close()
    return line
  else
    local fp = io.popen('pwd')
    if fp == nil then
      return ''
    end
    local line = fp:read('*l')
    fp:close()
    return line
  end
end


-----------------------------------------------------------------------
-- which executable
-----------------------------------------------------------------------
function os.path.which(exename)
  local path = os.getenv('PATH')
  if windows then
    paths = ('.;' .. path):split(';')
  else
    paths = path:split(':')
  end
  for _, path in pairs(paths) do
    if not windows then
      local name = path .. '/' .. exename
      if os.path.exists(name) then
        return name
      end
    else
      for _, ext in pairs({'.exe', '.cmd', '.bat'}) do
        local name = path .. '\\' .. exename .. ext
        if path == '.' then
          name = exename .. ext
        end
        if os.path.exists(name) then
          return name
        end
      end
    end
  end
  return nil
end


-----------------------------------------------------------------------
-- absolute path (simulated)
-----------------------------------------------------------------------
function os.path.absolute(path)
  local pwd = os.pwd()
  return os.path.normpath(os.path.join(pwd, path))
end


-----------------------------------------------------------------------
-- absolute path (system call, can fall back to os.path.absolute)
-----------------------------------------------------------------------
function os.path.abspath(path)
  if path == '' then path = '.' end
  if os.native and os.native.GetFullPathName then
    local test = os.native.GetFullPathName(path)
    if test then return test end
  end
  if windows then
    local script = 'FOR /f "delims=" %%i IN ("%s") DO @echo %%~fi'
    local script = string.format(script, path)
    local script = 'cmd.exe /C ' .. script .. ' 2> nul'
    local output = os.call(script)
    local test = output:gsub('%s$', '')
    if test ~= nil and test ~= '' then
      return test
    end
  else
    local test = os.path.which('realpath')
    if test ~= nil and test ~= '' then
      test = os.call('realpath -s \'' .. path .. '\' 2> /dev/null')
      if test ~= nil and test ~= '' then
        return test
      end
      test = os.call('realpath \'' .. path .. '\' 2> /dev/null')
      if test ~= nil and test ~= '' then
        return test
      end
    end
    local test = os.path.which('perl')
    if test ~= nil and test ~= '' then
      local s = 'perl -MCwd -e "print Cwd::realpath(\\$ARGV[0])" \'%s\''
      local s = string.format(s, path)
      test = os.call(s)
      if test ~= nil and test ~= '' then
        return test
      end
    end
    for _, python in pairs({'python', 'python2', 'python3'}) do
      local s = 'sys.stdout.write(os.path.abspath(sys.argv[1]))'
      local s = '-c "import os, sys;' .. s .. '" \'' .. path .. '\''
      local s = python .. ' ' .. s
      local test = os.path.which(python)
      if test ~= nil and test ~= '' then
        return os.call(s)
      end
    end
  end
  return os.path.absolute(path)
end


-----------------------------------------------------------------------
-- dir exists
-----------------------------------------------------------------------
function os.path.isdir(pathname)
  if pathname == '/' then
    return true
  elseif pathname == '' then
    return false
  elseif windows then
    if pathname == '\\' then
      return true
    end
  end
  if os.native and os.native.isdir then
    return os.native.isdir(pathname)
  end
  if clink and os.isdir then
    return os.isdir(pathname)
  end
  local name = pathname
  if (not name:endswith('/')) and (not name:endswith('\\')) then
    name = name .. os.path.sep
  end
  return os.path.exists(name)
end


-----------------------------------------------------------------------
-- file or path exists
-----------------------------------------------------------------------
function os.path.exists(name)
  if name == '/' then
		return true
	end
  if os.native and os.native.exists then
    return os.native.exists(name)
  end
  local ok, _, code = os.rename(name, name)
  local EPERM   = 1   -- from intro(2)
  local EACCESS = 13  -- from intro(2)
  local EBUSY   = 16  -- from intro(2)
  local ENOTDIR = 20  -- from intro(2)
  local EINVAL  = 22  -- from intro(2)
  local EROFS   = 30  -- from intro(2)
  if not ok then
    if code == EACCESS or (not windows and code == EPERM) then
      return true
    elseif code == EROFS then
      local f = io.open(name,"r")
      if f ~= nil then
        io.close(f)
        return true
      end
    elseif name:sub(-1) == '/' and code == ENOTDIR and (not windows) then
      local test = name .. '.'
      ok, err, code = os.rename(test, test)
      if code == EBUSY or code == EACCESS or code == EINVAL then
        return true
      end
    end
    return false
  end
  return true
end


-----------------------------------------------------------------------
-- is absolute path
-----------------------------------------------------------------------
function os.path.isabs(path)
  if path == nil or path == '' then
    return false
  elseif path:sub(1, 1) == '/' then
    return true
  end
  if windows then
    local head = path:sub(1, 1)
    if head == '\\' then
      return true
    elseif path:match('^%a:[/\\]') ~= nil then
      return true
    end
  end
  return false
end


-----------------------------------------------------------------------
-- normalize path
-----------------------------------------------------------------------
function os.path.norm(pathname)
  if windows then
    pathname = pathname:gsub('\\', '/')
  end
  if windows then
    pathname = pathname:gsub('/', '\\')
  end
  return pathname
end


-----------------------------------------------------------------------
-- normalize . and ..
-----------------------------------------------------------------------
function os.path.normpath(path)
  if os.path.sep ~= '/' then
    path = path:gsub('\\', '/')
  end
  path = path:gsub('/+', '/')
  local srcpath = path
  local basedir = ''
  local isabs = false
  if windows and path:sub(2, 2) == ':' then
    basedir = path:sub(1, 2)
    path = path:sub(3, -1)
  end
  if path:sub(1, 1) == '/' then
    basedir = basedir .. '/'
    isabs = true
    path = path:sub(2, -1)
  end
  local parts = path:split('/')
  local output = {}
  for _, path in ipairs(parts) do
    if path == '.' or path == '' then
    elseif path == '..' then
      local size = #output
      if size == 0 then
        if not isabs then
          table.insert(output, '..')
        end
      elseif output[size] == '..' then
        table.insert(output, '..')
      else
        table.remove(output, size)
      end
    else
      table.insert(output, path)
    end
  end
  path = basedir .. string.join('/', output)
  if windows then path = path:gsub('/', '\\') end
  return path == '' and '.' or path
end


-----------------------------------------------------------------------
-- join two path
-----------------------------------------------------------------------
function os.path.join(path1, path2)
  if path1 == nil or path1 == '' then
    if path2 == nil or path2 == '' then
      return ''
    else
      return path2
    end
  elseif path2 == nil or path2 == '' then
    local head = path1:sub(-1, -1)
    if head == '/' or (windows and head == '\\') then
      return path1
    end
    return path1 .. os.path.sep
  elseif os.path.isabs(path2) then
    if windows then
      local head = path2:sub(1, 1)
      if head == '/' or head == '\\' then
        if path1:match('^%a:') then
          return path1:sub(1, 2) .. path2
        end
      end
    end
    return path2
  elseif windows then
    local d1 = path1:match('^%a:') and path1:sub(1, 2) or ''
    local d2 = path2:match('^%a:') and path2:sub(1, 2) or ''
    if d1 ~= '' then
      if d2 ~= '' then
        if d1:lower() == d2:lower() then
          return d2 .. os.path.join(path1:sub(3), path2:sub(3))
        else
          return path2
        end
      end
    elseif d2 ~= '' then
      return path2
    end
  end
  local postsep = true
  local len1 = path1:len()
  local len2 = path2:len()
  if path1:sub(-1, -1) == '/' then
    postsep = false
  elseif windows then
    if path1:sub(-1, -1) == '\\' then
      postsep = false
    elseif len1 == 2 and path1:sub(2, 2) == ':' then
      postsep = false
    end
  end
  if postsep then
    return path1 .. os.path.sep .. path2
  else
    return path1 .. path2
  end
end


-----------------------------------------------------------------------
-- check single name element
-----------------------------------------------------------------------
function os.path.single(path)
  if string.match(path, '/') then
    return false
  end
  if windows then
    if string.match(path, '\\') then
      return false
    end
  end
  return true
end


-----------------------------------------------------------------------
-- expand user home
-----------------------------------------------------------------------
function os.path.expand(pathname)
  if not pathname:find('~') then
    return pathname
  end
  local home = ''
  if windows then
    home = os.getenv('USERPROFILE')
  else
    home = os.getenv('HOME')
  end
  if pathname == '~' then
    return home
  end
  local head = pathname:sub(1, 2)
  if windows then
    if head == '~/' or head == '~\\' then
      return home .. '\\' .. pathname:sub(3, -1)
    end
  elseif head == '~/' then
    return home .. '/' .. pathname:sub(3, -1)
  end
  return pathname
end


-----------------------------------------------------------------------
-- get lua executable
-----------------------------------------------------------------------
function os.interpreter()
  if os.argv == nil then
    io.stderr:write("cannot get arguments (arg), recompiled your lua\n")
    return nil
  end
  local lua = os.argv[-1]
  if lua == nil then
    io.stderr:write("cannot get executable name, recompiled your lua\n")
  end
  if os.path.single(lua) then
    local path = os.path.which(lua)
    if not os.path.isabs(path) then
      return os.path.abspath(path)
    end
    return path
  end
  return os.path.abspath(lua)
end


-----------------------------------------------------------------------
-- get script name
-----------------------------------------------------------------------
function os.scriptname()
  if os.argv == nil then
    io.stderr:write("cannot get arguments (arg), recompiled your lua\n")
    return nil
  end
  local script = os.argv[0]
  if script == nil then
    io.stderr:write("cannot get script name, recompiled your lua\n")
  end
  return os.path.abspath(script)
end


-----------------------------------------------------------------------
-- parse option
-----------------------------------------------------------------------
function os.getopt(argv)
  local args = {}
  local options = {}
  argv = argv ~= nil and argv or os.argv
  if argv == nil then
    return nil, nil
  elseif (#argv) == 0 then
    return options, args
  end
  local count = #argv
  local index = 1
  while index <= count do
    local arg = argv[index]
    local head = arg:sub(1, 1)
    if arg ~= '' then
      if head ~= '-' then
        break
      end
      if arg == '-' then
        options['-'] = ''
      elseif arg == '--' then
        options['-'] = '-'
      elseif arg:match('^-%d+$') then
        options['-'] = arg:sub(2)
      else
        local part = arg:split('=')
        options[part[1]] = part[2] ~= nil and part[2] or ''
      end
    end
    index = index + 1
  end
  while index <= count do
    table.insert(args, argv[index])
    index = index + 1
  end
  return options, args
end


-----------------------------------------------------------------------
-- returns true for path is insensitive
-----------------------------------------------------------------------
function path_case_insensitive()
  if windows then
    return true
  end
  local eos = os.getenv('OS')
  eos = eos ~= nil and eos or ''
  eos = eos:lower()
  if eos:sub(1, 7) == 'windows' then
    return true
  end
  return false
end


-----------------------------------------------------------------------
-- load and split data
---local --------------------------------------------------------------
function data_load(filename)
  local M = {}
  local N = {}
  local insensitive = path_case_insensitive()
  local fp = io.open(os.path.expand(filename), 'r')
  if fp == nil then
    return {}
  end
  for line in fp:lines() do
    local part = string.split(line, '|')
    local item = {}
    if part and part[1] and part[2] and part[3] then
      local key = insensitive and part[1]:lower() or part[1]
      item.name = part[1]
      item.rank = tonumber(part[2])
      item.time = tonumber(part[3]) + 0
      item.score = item.rank
      if string.len(part[3]) < 12 then
        if item.rank ~= nil and item.time ~= nil then
          if N[key] == nil then
            table.insert(M, item)
            N[key] = 1
          end
        end
      end
    end
  end
  fp:close()
  return M
end


-----------------------------------------------------------------------
-- filter out bad dirname
---local --------------------------------------------------------------
function data_filter(M)
  local N = {}
  local i
  M = M ~= nil and M or {}
  for i = 1, #M do
    local item = M[i]
    if os.path.isdir(item.name) then
      table.insert(N, item)
    end
  end
  return N
end


-----------------------------------------------------------------------
-- change pattern
---local --------------------------------------------------------------
function case_insensitive_pattern(pattern)
  -- find an optional '%' (group 1) followed by any character (group 2)
  local p = pattern:gsub("(%%?)(.)", function(percent, letter)

    if percent ~= "" or not letter:match("%a") then
      -- if the '%' matched, or `letter` is not a letter, return "as is"
      return percent .. letter
    else
      -- else, return a case-insensitive character class of the matched letter
      return string.format("[%s%s]", letter:lower(), letter:upper())
    end
  end)
  return p
end


-----------------------------------------------------------------------
-- smart path match -- match starting from the last
---local --------------------------------------------------------------
function path_match(components, patterns)
  -- components is a list of 3
  -- patterns is a list of at most 3
  local j = 3
  local i = 0
  for i = #patterns, 1, -1 do
    -- use - as a regular character in the pattern
    local pat = patterns[i]:gsub('-', '%%-')
    local comp = components[j]
    j = j - 1
    local start, endup = comp:find(pat, 0)
    if start == nil or endup == nil then
      return false
    end
  end
  return true
end


-----------------------------------------------------------------------
-- select matched pathnames
---local --------------------------------------------------------------
function data_select(M, patterns)
  local N = {}
  local i = 1
  local pats = {}
  local root = os.path.expand(RH_ROOT) .. '/'
  local comp_index = root:len() + 1  -- we'll use this as starting index
  for i = 1, #patterns do
    local p = case_insensitive_pattern(patterns[i])
    table.insert(pats, p)
  end
  for i = 1, #M do
    local item = M[i]
    -- must start with root
    if item.name:startswith(root) then
      local components = item.name:sub(comp_index):split('/')
      if #components == 3 and path_match(components, pats) then
        table.insert(N, item)
      end
    end
  end
  return N
end


-----------------------------------------------------------------------
-- match method
---local --------------------------------------------------------------
function rh_match(patterns)
  patterns = patterns ~= nil and patterns or {}
  local M = data_load(DATA_FILE)
  M = data_select(M, patterns)
  M = data_filter(M)
  table.sort(M, function (a, b) return a.score > b.score end)
  return M
end


-----------------------------------------------------------------------
-- pretty print
---local --------------------------------------------------------------
function rh_print(M)
  local fp = io.stdout
  for _, item in pairs(M) do
    if fp ~= nil then
      fp:write(item.name .. '\n')
    end
  end
end


-----------------------------------------------------------------------
-- do multiplexing
---local --------------------------------------------------------------
function rh_cd(patterns)
  if patterns == nil or #patterns == 0 then
    return nil
  end
  if #patterns == 1 then
    -- check if we are passing an url, per `git help clone`
    -- at the moment, only support github.com and gitlab.com
    if (patterns[1]:match("^(git://") or
          patterns[1]:match("^https?://") or
          patterns[1]:match("^ssh://") or
          patterns[1]:match("^[^/]+:.*/"))
      and
      (patterns[1]:match("github") or patterns[1]:match("gitlab"))
    then
      return rh_checkout(patterns[1])
    end
    -- check if we're passing an absolute dir
    local last = patterns[#patterns]
    if (os.path.isabs(last) and os.path.isdir(last)) or last:sub(1, 1) == "~" then
      return last
    end
    patterns = patterns[1]:split('/')
  end
  return rh_do_cd(patterns)
end


-----------------------------------------------------------------------
-- calculate jump dir
---local --------------------------------------------------------------
function rh_do_cd(patterns)
  local M = rh_match(patterns)
  if M == nil then
    return nil
  end
  if #M == 0 then
    return nil
  elseif #M == 1 then
    return M[1].name
  else
    -- in case our first match is the current folder
    if os.pwd() == M[1].name then
      return M[2].name
    else
      return M[1].name
    end
  end
end


-----------------------------------------------------------------------
-- checkout
---local --------------------------------------------------------------
function rh_checkout(url)
  local whole = url:match(".*://(([^/]+)/([^/]+)/([^/]+))")
  if whole == nil then
    -- try scp variant [user@]server:path/to/repo.git
    -- in this case we'll have to change some args
    local user_server, org, repo = url:match("([^/]+):([^/]+)/([^/]+)")
    if user_server ~= nil and org ~= nil and repo ~= nil then
      local extract = user_server:split("@")
      whole = extract[#extract] .. "/" .. org .. "/" .. repo
    end
  end
  if whole ~= nil then
    if whole:sub(-4, -1) == ".git" then
      whole = whole:sub(1, -5)
    end
    local patterns = whole:split('/')
    local M = rh_match(patterns)
    if M == nil or #M == 0 then
      -- we need to do the checkout
      local root = os.path.join(os.path.expand(RH_ROOT), whole)
      os.execute("mkdir -p '" .. root .. "'")
      os.execute("cd '" .. root .. "' && git clone '" .. url .. "' .")
    end
    return root
  end
end


-----------------------------------------------------------------------
-- main entry
---local --------------------------------------------------------------
function main(argv)
  local options, args = os.getopt(argv)
  if options == nil then
    return false
  elseif table.length(args) == 0 and table.length(options) == 0 then
    print(os.argv[0] .. ': missing arguments')
    help = os.argv[-1] .. ' ' .. os.argv[0] .. ' --help'
    print('Try \'' .. help .. '\' for more information')
    return false
  end
  if options['--cd'] then
    local path = ''
    if table.length(args) == 0 then
      -- FIXME: handle this error better, maybe print something
      path = nil
    else
      RH_ROOT = table.remove(args, 1)
      path = rh_cd(args)
      if path == nil and table.length(args) == 1 then
        -- case when we have no match, but folder with that name exists
        local last = args[#args]
        if os.path.isdir(last) then
          path = last
        end
      end
    end
    if path ~= nil then
      io.write(path .. "\n")
    end
  elseif options['--init'] then
    local opts = {}
    if table.length(args) ~= 2 then
      print(os.argv[0] .. ': missing arguments to --init, needs at shell type and root directory')
      return false
    end
    opts[args[1]] = 1
    opts.root = args[2]
    if windows then
      rh_windows_init(opts)
    elseif opts.fish then
      rh_fish_init(opts)
    else
      rh_shell_init(opts)
    end
  elseif options['-l'] then
    RH_ROOT = table.length(args) >= 1 and args[1] or RH_ROOT
    local M = rh_match({})
    rh_print(M)
  elseif options['--complete'] then
    local line = args[1] and args[1] or ''
    local head = line:sub(RH_CMD:len()+1):gsub('^%s+', '')
    local M = rh_match({head})
    for _, item in pairs(M) do
      print(item.name)
    end
  elseif options['--help'] or options['-h'] then
    rh_help()
  end
  return true
end


-----------------------------------------------------------------------
-- initialize from environment variable
---local --------------------------------------------------------------
function rh_init()
  local _rh_cmd = os.getenv('_RH_CMD')
  local _rh_data = os.getenv('_RH_DATA')
  local _rh_root = os.getenv('_RH_ROOT')
  -- print('INIT:root ' .. _rh_root)
  if _rh_data ~= nil and _rh_data ~= "" then
    if windows then
      DATA_FILE = _rh_data
    else
      -- avoid windows environments affect cygwin & msys
      if not string.match(_rh_data, '^%a:[/\\]') then
				DATA_FILE = _rh_data
      end
    end
  end
  if _rh_cmd ~= nil and _rh_cmd ~= '' then
    RH_CMD = _rh_cmd
  end
  if _rh_root ~= nil and _rh_root ~= '' then
    RH_ROOT = _rh_root
  end
end


-----------------------------------------------------------------------
-- initialize clink hooks
-----------------------------------------------------------------------
function rh_clink_init()
  function rh_match_completion(word)
    local M = rh_match({word})
    for _, item in pairs(M) do
      clink.add_match(item.name)
    end
    return {}
  end
  local rh_parser = clink.arg.new_parser()
  rh_parser:set_arguments({ rh_match_completion })
  clink.arg.register_parser("rh", rh_parser)
end


-----------------------------------------------------------------------
-- shell scripts
-----------------------------------------------------------------------
local script_rhlua = [[
_rhlua() {
  if [ "$1" = "--complete" ]; then
    shift
    "$RHLUA_LUAEXE" "$RHLUA_SCRIPT" --complete "$@"
    return
  fi
  if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    "$RHLUA_LUAEXE" "$RHLUA_SCRIPT" -h
  elif [ "$#" -eq 0 ]; then
    "$RHLUA_LUAEXE" "$RHLUA_SCRIPT" -l "$_RH_ROOT"
  else
    local rhdest=$("$RHLUA_LUAEXE" "$RHLUA_SCRIPT" --cd "$_RH_ROOT" "$@")
    if [ -n "$rhdest" ] && [ -d "$rhdest" ]; then
      builtin cd "$rhdest"
    fi
  fi
}
alias ${_RH_CMD:-rh}='_rhlua'
]]

local script_complete_bash = [[
if [ -n "$BASH_VERSION" ]; then
  complete -o filenames -C '_rhlua --complete "$COMP_LINE"' ${_RH_CMD:-rh}
fi
]]

local script_complete_zsh = [[
_rhlua_zsh_tab_completion() {
  # tab completion
  (( $+compstate )) && compstate[insert]=menu # no expand
  local -a tmp=(${(f)"$(_zlua --complete "${words/_zlua/z}")"})
	_describe "directory" tmp -U
}
if [ "${+functions[compdef]}" -ne 0 ]; then
  compdef _zlua_zsh_tab_completion _zlua 2> /dev/null
fi
]]



-----------------------------------------------------------------------
-- initialize bash/zsh
----------------------------------------------------------------------
function rh_shell_init(opts)
  print('RHLUA_SCRIPT="' .. os.scriptname() .. '"')
  print('RHLUA_LUAEXE="' .. os.interpreter() .. '"')
  print('_RH_ROOT="${_RH_ROOT:-' .. opts.root .. '}"')
  print('')
  if not opts.posix then
    print(script_rhlua)
  elseif not opts.legacy then
    local script = script_rhlua:gsub('builtin ', '')
    print(script)
  else
    local script = script_rhlua:gsub('local ', ''):gsub('builtin ', '')
    print(script)
  end

  if opts.bash ~= nil then
    print(script_complete_bash)
  elseif opts.zsh ~= nil then
    print(script_complete_zsh)
  end
end


-----------------------------------------------------------------------
-- Fish shell init
-----------------------------------------------------------------------
local script_rhlua_fish = [[
function _rhlua
  function _rhlua_call; eval (string escape -- $argv); end
  if test "$argv[1]" = "--complete"
    set -e argv[1]
    _rhlua_call "$RHLUA_LUAEXE" "$RHLUA_SCRIPT" --complete $argv
    return
  end
  if test "$argv[1]" = "-h" -a "$argv[1]" = "--help"
    _rhlua_call "$RHLUA_LUAEXE" "$RHLUA_SCRIPT" -h
  else if test (count $argv) -eq 0
    _rhlua_call "$RHLUA_LUAEXE" "$RHLUA_SCRIPT" -l "$_RH_ROOT"
  else
    set -l dest (_rhlua_call "$RHLUA_LUAEXE" "$RHLUA_SCRIPT" --cd "$_RH_ROOT" $argv)
    if test -n "$dest" -a -d "$dest"
      builtin cd "$dest"
    end
  end
end

if test -z "$_RH_CMD"; set -x _RH_CMD rh; end
alias "$_RH_CMD"=_rhlua
]]

local script_complete_fish = [[
function _rh_complete
  eval "$_RH_CMD" --complete (commandline -t)
end

complete -c $_RH_CMD -f -a '(_rh_complete)'
complete -c $_RH_CMD -s 't' -d 'cd to most recently accessed dir matching'
complete -c $_RH_CMD -s 'l' -d 'list matches instead of cd'
]]


function rh_fish_init(opts)
  print('set -x RHLUA_SCRIPT "' .. os.scriptname() .. '"')
  print('set -x RHLUA_LUAEXE "' .. os.interpreter() .. '"')
  print('set -q _RH_ROOT; or set -x _RH_ROOT "' .. opts.root .. '"')
  print(script_rhlua_fish)
  print(script_complete_fish)
end


-----------------------------------------------------------------------
-- windows .cmd script
-----------------------------------------------------------------------
local script_init_cmd = [[
if /i not "%_RH_LUA_EXE%"=="" (
  set "LuaExe=%_RH_LUA_EXE%"
)
if /i "%1"=="-h" (
  call "%LuaExe%" "%LuaScript%" -h
  goto end
)
if /i "%1"=="" (
  call "%LuaExe%" "%LuaScript%" -l "%_RH_ROOT%"
  goto end
)
:check
for /f "delims=" %%i in ('call "%LuaExe%" "%LuaScript%" --cd "%_RH_ROOT%" %*') do set "NewPath=%%i"
  if not "!NewPath!"=="" (
    if exist !NewPath!\nul (
      pushd !NewPath!
      pushd !NewPath!
      endlocal
      popd
    )
  )
)
:end
]]


-----------------------------------------------------------------------
-- powershell
-----------------------------------------------------------------------
local script_rhlua_powershell = [[
function global:_rhlua {
  $arg_mode = ""
  if ($args[0] -eq "--complete") {
    $_, $rest = $args
    & $script:RHLUA_LUAEXE $script:RHLUA_SCRIPT --complete $rest
    return
  }
  :loop while ($args) {
    switch -casesensitive ($args[0]) {
      "-h" { $arg_mode="-h"; break }
      "--help" { $arg_mode="-h"; break }
      Default { break loop }
    }
    $_, $args = $args
    if (!$args) { break loop }
  }
  $root = ""
  if ($env:_RH_ROOT) { $root=$env:_RH_ROOT }
  else { $root = $script:RH_ROOT }
  if ($arg_mode -eq "-h") {
    & $script:RHLUA_LUAEXE $script:RHLUA_SCRIPT $arg_mode
  } elseif ($args.Length -eq 0) {
    & $script:RHLUA_LUAEXE $script:RHLUA_SCRIPT -l $root
  } else {
    $dest = & $script:RHLUA_LUAEXE $script:RHLUA_SCRIPT --cd $root $args
    if ($dest) {
      & "Push-Location" "$dest"
    }
  }
}

if ($env:_RH_CMD) { Set-Alias $env:_RH_CMD _rhlua -Scope Global }
else { Set-Alias rh _rhlua -Scope Global }
]]


-----------------------------------------------------------------------
-- initialize cmd/powershell
-----------------------------------------------------------------------
function rh_windows_init(opts)
  if opts.powershell ~= nil then
    print('$script:RHLUA_LUAEXE = "' .. os.interpreter() .. '"')
    print('$script:RHLUA_SCRIPT = "' .. os.scriptname() .. '"')
    print('$script:RH_ROOT = "' .. opts.root .. '"')
    print(script_rhlua_powershell)
  else
    print('@echo off')
    print('setlocal EnableDelayedExpansion')
    print('set "LuaExe=' .. os.interpreter() .. '"')
    print('set "LuaScript=' .. os.scriptname() .. '"')
    print('if NOT DEFINED _RH_ROOT set "_RH_ROOT=' .. opts.root .. '"')
    print(script_init_cmd)
    if opts.newline then
      print('echo.')
    end
  end
end


-----------------------------------------------------------------------
-- help
-----------------------------------------------------------------------
function rh_help()
  local cmd = RH_CMD .. ' '
  print('Navigate server/org/repo checkouts easily')
  print()
  print(cmd .. '              # list all frecently used repositories')
  print(cmd .. 'foo           # cd to most frecent repository matching foo')
  print(cmd .. 'bar/foo       # cd to most frecent repository matching foo and organization matching bar')
  print(cmd .. 'baz/bar/foo   # cd to most frecent repository matching foo, organization matching bar, and server matching baz')
  print(cmd .. '<url>         # cd to repository or checkout if it doesn\'t exist')
end


-----------------------------------------------------------------------
-- testing case
-----------------------------------------------------------------------
if not in_module then
  -- main script
  rh_init()
  if windows and type(clink) == 'table' and clink.prompt ~= nil then
    rh_clink_init()
  else
    main()
  end
end
