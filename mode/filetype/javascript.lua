local mode = require 'mode'
local fs = require 'mode.fs'

mode.configure_lsp {
  id = 'flow',
  filetype = {'javascript', 'javascript.jsx'},
  languageId = 'javascript',
  command = function(root)
    local cmd = root / 'node_modules/.bin/flow'
    local args = {'lsp'}
    return cmd, args
  end,
  root = function(filename)
    return fs.find_closest_ancestor(filename.parent, function(p)
      return fs.exists(p / '.flowconfig')
    end)
  end
}
