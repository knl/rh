@echo off
setlocal EnableDelayedExpansion

set "HomeDir=%~dp0"
set "PathSave=%PATH%"
set "LuaExe=lua"
set "LuaScript=%HomeDir%rh.lua"

if /i not "%_RH_LUA_EXE%"=="" (
	set "LuaExe=%_ZL_LUA_EXE%"
)

:parse

if /i "%1"=="" (
  call "%LuaExe%" "%LuaScript%" -l "%_RH_ROOT%"
  goto end
)
if /i "%1"=="-h" (
	call "%LuaExe%" "%LuaScript%" -h
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

:end
echo.
