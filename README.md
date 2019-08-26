# mode

mode is a **work in progress**.

mode is a plugin for [neovim][] which attempts to do the following:

- mode is a standard library for neovim

  mode provides a foundation for other plugins to be built with expressive and
  ergonomic Lua API.

- mode is an integrated development environment

  mode includes an implementation of LSP client along with other IDE-like
  features like an integration with fuzzy finder.

- mode is an experiment with new neovim features

## Installation

Put the following lines into `~/.config/nvim/init.vim` (assuming [vim-plug][]):

```
Plug 'arrowresearch/mode'
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
