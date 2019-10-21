lua require('mode')

command! ModeHover lua require('mode').hover()
command! ModeDefinition lua require('mode').definition()
command! ModeTypeDefinition lua require('mode').type_definition()
command! ModeFiles lua require('mode.fzy').files()
command! ModeNextLocation lua require('mode').next_diagnostic_location()
command! ModePrevLocation lua require('mode').prev_diagnostic_location()

command! CoqModeInit lua require('mode.coq').init()
command! CoqModeStop lua require('mode.coq').stop()
command! CoqModeNext lua require('mode.coq').next()
command! CoqModeNextAndJump lua require('mode.coq').next { jump = true }
command! CoqModePrev lua require('mode.coq').prev()
command! CoqModePrevAndJump lua require('mode.coq').prev { jump = true }
command! CoqModeAtPosition lua require('mode.coq').at_position()

nnoremap <leader>cc <Cmd>CoqModeAtPosition<Cr>
nnoremap <leader>cp <Cmd>CoqModePrev<Cr>
nnoremap <leader>cP <Cmd>CoqModePrevAndJump<Cr>
nnoremap <leader>cn <Cmd>CoqModeNext<Cr>
nnoremap <leader>cN <Cmd>CoqModeNextAndJump<Cr>

highlight link ModeError ErrorMsg
highlight link ModeWarning WarningMsg

highlight link CoqModeAdded WarningMsg
" TODO(andreypopp): fix it to a link to a semantic highlight group instead
highlight CoqModeChecked ctermfg=2 ctermbg=NONE
highlight link CoqModeError ErrorMsg
