local mode = require 'mode'
local fs = require 'mode.fs'

local function is_esy(p)
  return fs.exists(p / 'esy.json') or fs.exists(p / 'package.json')
end

local exe = 'ocaml-lsp-server'

mode.configure_lsp {
  id = 'ocaml-lsp',
  languageId = 'ocaml',
  filetype = {'ocaml', 'reason'},
  command = function(root)
    if is_esy(root) then
      local cmd = 'esy'
      local args = {
        'exec-command',
        '--include-build-env',
        '--include-current-env',
        exe
      }
      return cmd, args
    else
      return exe, {}
    end
  end,
  root = function(filename)
    return fs.find_closest_ancestor(filename.parent, function(p)
      return is_esy(p) or fs.exists(p / 'dune-project')
    end)
  end
}
