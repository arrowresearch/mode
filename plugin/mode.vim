lua require('mode')

command! ModeHover lua require('mode').hover()
command! ModeDefinition lua require('mode').definition()
command! ModeFiles lua require('mode.fzy').files()
