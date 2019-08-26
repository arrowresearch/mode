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

[neovim]: https://github.com/neovim/neovim
[vim-plug]: https://github.com/junegunn/vim-plug
