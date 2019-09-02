local mode = require 'mode'
local fs = require 'mode.fs'

mode.configure_lsp {
  id = 'merlin',
  languageId = 'ocaml',
  filetype = {'ocaml', 'reason'},
  command = function(_)
    local cmd = 'esy'
    local args = {
      'exec-command',
      '--include-build-env',
      '--include-current-env',
      '/Users/andreypopp/Workspace/esy-ocaml/merlin/ocamlmerlin-lsp'
    }
    return cmd, args
  end,
  root = function(filename)
    return fs.find_closest_ancestor(filename.parent, function(p)
      return fs.exists(p / 'esy.json') or fs.exists(p / 'package.json')
    end)
  end
}
