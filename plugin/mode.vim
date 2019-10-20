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
command! CoqModePrev lua require('mode.coq').prev()
command! CoqModeAddTillCursor lua require('mode.coq').add_till_cursor()

nnoremap <leader>cc <Cmd>CoqModeAddTillCursor<Cr>
nnoremap <leader>cp <Cmd>CoqModePrev<Cr>

highlight link ModeError ErrorMsg
highlight link ModeWarning WarningMsg

highlight link CoqModeAdded WarningMsg
" TODO(andreypopp): fix it to a link to a semantic highlight group instead
highlight CoqModeChecked ctermfg=2 ctermbg=NONE
highlight link CoqModeError ErrorMsg
