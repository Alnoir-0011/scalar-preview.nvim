# scalar-preview.nvim

Live-reloading OpenAPI/Swagger preview for Neovim, powered by [Scalar CLI](https://github.com/scalar/scalar) (`@scalar/cli`).

Unlike older Swagger-preview plugins built on `swagger-ui-watcher` → `swagger-editor-dist@3.x` (which has no OpenAPI 3.1/3.2 support and throws on `openapi: 3.2.x` documents), this plugin shells out to Scalar's actively maintained CLI, which understands OpenAPI 3.2 (`$self`, `additionalOperations`, etc.).

## Requirements

- Neovim ≥ 0.10 (uses `vim.ui.open`)
- Node.js ≥ 24 and `npx` available in `$PATH` (required by `@scalar/cli`)

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "Alnoir-0011/scalar-preview.nvim",
  cmd = { "ScalarPreview", "ScalarPreviewStop", "ScalarPreviewToggle" },
  opts = {},
}
```

## Usage

Open an OpenAPI/Swagger file (`.yaml`, `.yml`, `.json`) and run:

```
:ScalarPreview
```

This starts a local preview server via `npx @scalar/cli document serve --watch` and opens it in your browser. The preview reloads automatically whenever you save the file.

- `:ScalarPreviewStop` — stop the server
- `:ScalarPreviewToggle` — toggle start/stop

## Configuration

```lua
require("scalar-preview").setup({
  port = 8000,        -- default: 8000
  host = "localhost",  -- default: "localhost"
})
```

## Known limitations

- OpenAPI 3.2's `stability` operation field currently crashes `@scalar/cli`'s server (upstream bug, not something this plugin can work around). Everything else tested — `$self`, `additionalOperations`, OpenAPI 3.0/3.1/3.2 in general — works.
- The first `:ScalarPreview` run may take a few seconds while `npx` fetches `@scalar/cli`; it's cached after that.
- If warnings are printed by the underlying CLI, they're written to `stdpath("state") .. "/scalar-preview.log"` instead of flooding Neovim with one notification per line.

## License

MIT. This plugin invokes `@scalar/cli` (MIT License) as an external process via `npx`; no Scalar source is bundled or redistributed.
