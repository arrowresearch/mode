lua require('mode')

command! ModeHover lua require('mode').hover()
command! ModeDefinition lua require('mode').definition()
command! ModeFiles lua require('mode.fzy').files()
command! ModeNextLocation lua require('mode').next_diagnostic_location()
command! ModePrevLocation lua require('mode').prev_diagnostic_location()

highlight link ModeError ErrorMsg
