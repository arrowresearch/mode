local mode = require 'mode'
local fs = require 'mode.fs'

mode.configure_linter {
  id = 'luacheck',
  filetype = {'lua'},
  command = function(_)
    return 'luacheck', {
      '--formatter', 'plain',
      '--filename', '%{FILENAME}%',
      '--codes',
      '-'
    }
  end,
  root = function(filename)
    local root
    root = fs.find_closest_ancestor(filename.parent, function(dir)
      return fs.exists(dir / 'package.lua')
    end)
    return root or filename.parent
  end,
  produce = function(line_raw)
    local pattern = '(.+):(%d+):(%d+):%s*%(([WE])%d+%)%s*(.+)'
    local _, _, filename, line, character, kind, message = line_raw:find(pattern)
    line = tonumber(line)
    character = tonumber(character)
    return {
      filename = filename,
      kind = kind,
      range = { start = {line = line - 1, character = character - 1} },
      message = message,
    }
  end
}

