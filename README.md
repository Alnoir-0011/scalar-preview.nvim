# scalar-preview.nvim

Live-reloading OpenAPI/Swagger preview for Neovim, powered by [Scalar CLI](https://github.com/scalar/scalar) (`@scalar/cli`).

Unlike older Swagger-preview plugins built on `swagger-ui-watcher` → `swagger-editor-dist@3.x` (which has no OpenAPI 3.1/3.2 support and throws on `openapi: 3.2.x` documents), this plugin shells out to Scalar's actively maintained CLI, which understands OpenAPI 3.2 (`$self`, `additionalOperations`, etc.).

> This is an unofficial, community project. It is not affiliated with, endorsed by, or sponsored by Scalar; it simply invokes their open-source `@scalar/cli` as an external process. The command/module structure took inspiration from [vinnymeller/swagger-preview.nvim](https://github.com/vinnymeller/swagger-preview.nvim).

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
  host = "localhost",  -- default: "localhost", the hostname used to build the URL that's
                        -- opened in your browser; it is NOT passed to the CLI (which has no
                        -- option to control what address it binds to — see "Known limitations").
})
```

## Known limitations

- The underlying server (`@scalar/cli document serve`) listens on all network interfaces (`0.0.0.0`), not just `localhost`, and the CLI has no flag to restrict this. Anything reachable on your network can view whatever OpenAPI/Swagger file you're previewing while the server is running. Run `:ScalarPreviewStop` when you're done, especially on untrusted networks.
- The first `:ScalarPreview` run may take a few seconds while `npx` fetches `@scalar/cli`; it's cached after that.
- If warnings are printed by the underlying CLI, they're written to `stdpath("state") .. "/scalar-preview.log"` instead of flooding Neovim with one notification per line. Warnings from `npm`/`npx` itself (e.g. `EBADENGINE`, deprecated-subdependency notices) are logged but never trigger that notification, since they show up on practically every run and aren't actionable.
- The preview always reflects the file's contents on disk, not unsaved buffer changes; `:ScalarPreview` warns about this but still starts.

## License

MIT. This plugin invokes `@scalar/cli` (MIT License) as an external process via `npx`; no Scalar source is bundled or redistributed.
