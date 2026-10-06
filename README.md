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

This starts a local preview server via `npx @scalar/cli document serve --watch` (run directly, with no shell involved on POSIX; `npx` is a `.cmd` on Windows, so Windows still goes through `cmd.exe` — see "Known limitations") and opens it in your browser. The preview reloads automatically whenever you save the file.

- `:ScalarPreviewStop` — stop the server
- `:ScalarPreviewToggle` — toggle start/stop

## Configuration

```lua
require("scalar-preview").setup({
  port = 8000,         -- default: 8000
  host = "localhost",  -- default: "localhost", the hostname used to build the URL that's
                        -- opened in your browser; it is NOT passed to the CLI (which has no
                        -- option to control what address it binds to — see "Known limitations").
  cli_version = "latest", -- default: "latest". @scalar/cli version (or dist-tag) to run, e.g.
                           -- "2.8.0" to pin it instead of tracking whatever "latest" resolves
                           -- to on each run.
  config = nil,         -- default: nil. Path to a JSON file with API Reference configuration,
                         -- passed to the CLI as `-c`/`--config` (theme, layout, etc. — see
                         -- @scalar/cli's own docs for the file's shape). Unset by default.
})
```

## Known limitations

- **Only preview specs you trust.** `@scalar/cli` resolves every `$ref` in the document — including ones pointing outside its directory on the local filesystem, and ones pointing at an `http(s)://` URL — and embeds what it finds into the page it serves. A spec from an untrusted source can use this to have the preview server expose the contents of any other local file your user can read (as long as it parses as YAML/JSON) and/or make it send a request to an attacker-controlled URL, revealing that the spec was opened. This is `@scalar/cli`'s own behavior; this plugin has no way to sandbox or restrict it.
- The underlying server (`@scalar/cli document serve`) listens on all network interfaces, both IPv4 and IPv6 (`0.0.0.0` and `::`) — not just `localhost` — and the CLI has no flag to restrict this. Anything reachable on your network can view whatever you're previewing while the server is running. Run `:ScalarPreviewStop` when you're done, especially on an untrusted network.
- The first `:ScalarPreview` run may take a few seconds while `npx` fetches `@scalar/cli`; it's cached after that.
- With the default `cli_version = "latest"`, the exact version of `@scalar/cli` that runs isn't pinned and can change between runs whenever a new version is published upstream — `npx` always fetches and runs whatever "latest" currently resolves to, with no confirmation prompt (`--yes`). Set `cli_version` to a specific version (e.g. `"2.8.0"`) to pin it instead. Pinning a version doesn't guarantee its integrity (there's no hash check); it only stops it from silently changing between runs. It also doesn't override a `node_modules/@scalar/cli` that `npx` finds first in a parent of the previewed file's directory — Node's own resolution, outside this plugin's control.
- If warnings are printed by the underlying CLI, they're written to `stdpath("state") .. "/scalar-preview.log"` instead of flooding Neovim with one notification per line. Warnings from `npm`/`npx` itself (e.g. `EBADENGINE`, deprecated-subdependency notices) are logged but never trigger that notification, since they show up on practically every run and aren't actionable.
- The preview always reflects the file's contents on disk, not unsaved buffer changes; `:ScalarPreview` warns about this but still starts.
- On Windows, `npx` resolves to `npx.cmd`, which Windows runs through `cmd.exe` regardless of how this plugin invokes it, so a previewed file whose name contains a `cmd.exe` metacharacter (` & | ^ % ( ) ! < > " `) is refused outright rather than risked — this plugin can't quote for `cmd.exe` the way the underlying `jobstart()` call quotes for `CommandLineToArgvW`. This caveat is specific to Windows; it doesn't apply on macOS/Linux. (Verified against Neovim's and npm's own documented behavior, not against a real Windows install — please report an issue if you hit something unexpected here.)

## License

MIT. This plugin invokes `@scalar/cli` (MIT License) as an external process via `npx`; no Scalar source is bundled or redistributed.
