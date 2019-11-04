<p align="center">
  <img src="./logo.png" width="150" title="mode!" alt="mode logo">
</p>
<h1 align="center">mode</h1>
<h2 align="center">
  an IDE experience and a standard library for neovim Lua runtime
</h2>

mode is a **work in progress**.

mode is a plugin for [neovim][] which attempts to do the following:

- mode is a standard library for neovim

  mode provides a foundation for other plugins to be built with expressive and
  ergonomic Lua API.

- mode is an integrated development environment

  mode includes an implementation of LSP client along with other IDE-like
  features like an integration with fuzzy finder.

- mode is an experiment with new neovim features

## Installation & Usage

Put the following lines into `~/.config/nvim/init.vim` (assuming [vim-plug][]):

```
Plug 'arrowresearch/mode'
```

### Keybindings

The following keybindings are recommended (though you might want to make them
buffer local for those buffers which you want enable mode for):

```
nmap <silent> t  <Cmd>ModeHover<CR>
nmap <silent> gd <Cmd>ModeDefinition<CR>
nmap <silent> gt <Cmd>ModeTypeDefinition<CR>
nmap <silent> mm <Cmd>ModeNextLocation<CR>
nmap <silent> mp <Cmd>ModePrevLocation<CR>
set omnifunc=ModeOmni
```

### Integration with `statusline`

There's `diagnostics_count()` function which returns current counts of errors
and warnings for the buffer, one can make use of it to inject the info into
`statusline`:

```
function! ModeWarnings() abort
  let l:counts = luaeval("require('mode').diagnostics_count().warnings")
  return l:counts == 0 ? '' : printf('WARN:%d', l:counts)
endfunction

function! ModeErrors() abort
  let l:counts = luaeval("require('mode').diagnostics_count().errors")
  return l:counts == 0 ? '' : printf('ERR:%d', l:counts)
endfunction

set statusline+=\%#StatusLineError#%{ModeErrors()}
set statusline+=\%#StatusLineWarning#%{ModeWarnings()}
```

## Thank you

mode borrows code from:

- [bfredl/nvim-luvlsp][] by @bfredl
- [neovim LSP PR][] by @h-michael
- [ptr-path][] library by Jérôme Vuarand

[neovim]: https://github.com/neovim/neovim
[vim-plug]: https://github.com/junegunn/vim-plug
[bfredl/nvim-luvlsp]: https://github.com/bfredl/nvim-luvlsp
[neovim LSP PR]: https://github.com/neovim/neovim/pull/10222
[ptr-path]: http://piratery.net/path/index.html
