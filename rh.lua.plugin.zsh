#! /usr/bin/env zsh

RHLUA_SCRIPT="${0:A:h}/rh.lua"

[[ -n "$RHLUA_EXEC" ]] && [[ ! -x "$RHLUA_EXEC" ]] && RHLUA_EXEC=""

# search lua executable
if [[ -z "$RHLUA_EXEC" ]]; then
	  if [[ -x "$(command which lua)" ]]; then
		    RHLUA_EXEC="$(command which lua)"
	  elif [[ -x "$(command which luajit)" ]]; then
		    RHLUA_EXEC="$(command which luajit)"
	  elif [[ -x "$(command which lua5.3)" ]]; then
		    RHLUA_EXEC="$(command which lua5.3)"
	  elif [[ -x "$(command which lua5.2)" ]]; then
		    RHLUA_EXEC="$(command which lua5.2)"
	  elif [[ -x "$(command which lua5.1)" ]]; then
		    RHLUA_EXEC="$(command which lua5.1)"
	  else
		    echo "Not find lua in your $PATH, please install it."
		    return
	  fi
fi

eval "$($RHLUA_EXEC $RHLUA_SCRIPT --init zsh ~/work)"
