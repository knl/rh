# rh.lua

A [Go](https://golang.org) modules-like hierarchy aware `cd` command for
easier navigation to your repositories.
 
Go organizes modules based on `server/organization/repository` hierachy (for
example, `github.com/knl/rh`), which I liked a lot. `rh.lua` is a step toward
having that structure with all repositories I keep on my machine, while making
my workflow as smooth as possible.

`rh.lua` assumes that all the repositories are checked-out under a specific
umbrella folder in the filesystem, for example `~/work`. Under this
umbrella repository it would help navigate and maintain the repository hierarchy
in the same manner as go modules, that is,
`~/work/server/organization/repository`.

`rh.lua` is fully implemented in lua in order to make it fast. `rh.lua` is
heavily influenced and based on [`z.lua`](https://github.com/skywind3000/z.lua),
from which it took all filesystem/datastore code.

## Usage

<p align="center">
  <img width="600" src="http://knezevic.ch/files/rh.svg">
</p>

* `rh.lua` lists all known repositories under predefined umbrella folder (that
  is set during the installation).

* `rh.lua [[server/]org/]repo` does a frecency search (a la `z.lua` and/or
  `fasd_cd`) and searches for a repository whose name is partially matching
  `repo`, for an org `org` and server `server`. If found, `cd`s to that folder.
  If you omit both `server` and `org`, the search will be only over repository
  names. If your search term is in form `org/repo`, it will try to match `org`
  and then `repo` at respective positions. Similarly for the full blown term
  `server/org/repo`. You could also use spaces instead of `/`.
  If the best match matches the current folder, it will jump to the next
  matching one.
  
  For example, `rh.lua pkg` will jump to `~/work/github.com/NixOs/nixpkgs`,
  while `rh.lua f/pkg` will jump to `~/work/github.com/FreeBSD/pkg`.

* `rh.lua [http|git|https]://server/org/repo` will look for a
  `~/work/<server>/<org>/<repo>` folder and `cd` to it. If the folder doesn't
  exist, it will clone it with git and `cd` to it.

* `rh.lua term<TAB>` will autocomplete based on `term`.

## Dependencies

Apart from a working [lua](https://www.lua.org/) installation, `rh.lua` requires
either `z.lua` or `fasd_cd` (for the latter, set `$_RH_DATA` to `~/.fasd`). 

## Installation

Copy the `rh.lua` script to somewhere in the PATH.

* Zsh Install:
  Put something like this in your `.zshrc`:

      eval "$(lua /path/to/rh.lua --init zsh ~/work)"

  It can also be initialized from "knl/rh" with your zsh plugin
  managers (antigen / oh-my-zsh). Just don't forget to set `$_RH_ROOT`.

* Bash Install:
  Put something like this in your `.bashrc`:

      eval "$(lua /path/to/rh.lua --init bash ~/work)"

* Posix Shell Install:
  Put something like this in your `.profile`:

      eval "$(lua /path/to/rh.lua --init posix ~/work)"

* Fish Shell Install:
  Put something like this in `~/.config/fish/conf.d/z.fish`:

      source (lua /path/to/rh.lua --init fish ~/work | psub)

  Fish version 2.4.0 or above is required.

* Power Shell Install:
  Put something like this in your `profile.ps1`:

      iex ($(lua /path/to/rh.lua --init powershell) -join "`n")

* Windows Install (with [Clink](https://mridgers.github.io/clink/)):
    * Copy `rh.lua` and `rh.cmd` to clink's home directory
    * Add clink's home to `%PATH%` (`rh.cmd` can be called anywhere)
    * Ensure that "lua" can be called in `%PATH%`
    * Ensure that "lua" can be called in %PATH%

* Windows Cmder Install:
    * Copy `rh.lua` and `rh.cmd` to `cmder/vendor`
    * Add `cmder/vendor` to `%PATH%`
    * Ensure that "lua" can be called in `%PATH%`

## Configure

This is optional step, use it if you really need to.

* Set `$_RH_CMD` in `.bashrc`/`.zshrc` to change the command (default `rh`).
* Set `$_RH_DATA` in `.bashrc`/`.zshrc` to change the datafile (default `~/.zlua`).
* Set `$_RH_ROOT` in `.bashrc`/`.zshrc` to change the store root (default `~/work`).

## History

- 1.0.0 (2019-03-22): First official release

## FAQ

### Why is it called `rh`?

Repository Hierarchy.

### Why did you write this in Lua, isn't Lua slow?

Lua is a great language and pretty fast at it. For example `z.lua` is faster
than other alternatives, even tho it code gets interpreted and requires loading
of lua executable. Plus, basing the code on `z.lua` allows this gem to run on
many platforms.

### OMG, why >1000 LoC?

Mostly to make it self contained and avoid loading many modules. Everything sits
in a single file.

### How different is `rh.lua` from `z.lua`?

For the initial release, `git diff --stat -b` shows:

     z.lua => ../../knl/rh/rh.lua | 1734 ++++++--------------------------------
     1 file changed, 253 insertions(+), 1481 deletions(-)

This code is a modification of `z.lua` to support reading the same data file and
have all the supporting functions, however some parts were modified in order to
have the desired functionality.

`rh.lua` will not update the data file, ever! It only reads from it and makes
decision where to jump.
