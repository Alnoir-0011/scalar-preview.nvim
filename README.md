# scalar-preview.nvim

[![CI](https://github.com/Alnoir-0011/scalar-preview.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/Alnoir-0011/scalar-preview.nvim/actions/workflows/ci.yml)

Live-reloading OpenAPI/Swagger preview for Neovim, powered by [Scalar CLI](https://github.com/scalar/scalar) (`@scalar/cli`).

Unlike older Swagger-preview plugins built on `swagger-ui-watcher` → `swagger-editor-dist@3.x` (which has no OpenAPI 3.1/3.2 support and throws on `openapi: 3.2.x` documents), this plugin shells out to Scalar's actively maintained CLI, which understands OpenAPI 3.2 (`$self`, `additionalOperations`, etc.).

> This is an unofficial, community project. It is not affiliated with, endorsed by, or sponsored by Scalar; it simply invokes their open-source `@scalar/cli` as an external process. The command/module structure took inspiration from [vinnymeller/swagger-preview.nvim](https://github.com/vinnymeller/swagger-preview.nvim).

## Requirements

- Neovim ≥ 0.10 (uses `vim.ui.open`)
- Node.js ≥ 24 and `npx` available in `$PATH` (required by `@scalar/cli`)

Run `:checkhealth scalar-preview` to verify both.

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
                        -- opened in your browser; it does NOT control who can connect — use
                        -- `bind` for that (see "Restricting who can reach the preview").
  bind = nil,          -- default: nil (reachable from your whole network). Set to "127.0.0.1"
                        -- so other devices on your network cannot reach the preview.
  cli_version = "latest", -- default: "latest". @scalar/cli version (or dist-tag) to run, e.g.
                           -- "2.8.0" to pin it instead of tracking whatever "latest" resolves
                           -- to on each run.
  config = nil,         -- default: nil. Path to a JSON file with API Reference configuration,
                         -- passed to the CLI as `-c`/`--config` (theme, layout, etc. — see
                         -- @scalar/cli's own docs for the file's shape). Unset by default.
})
```

### Restricting who can reach the preview

By default the preview server is reachable from every device on your network (see "Known limitations"). If you only need to view it on this machine, add one line to keep other devices out:

```lua
{
  "Alnoir-0011/scalar-preview.nvim",
  cmd = { "ScalarPreview", "ScalarPreviewStop", "ScalarPreviewToggle" },
  opts = {
    bind = "127.0.0.1", -- other devices on the network cannot reach the preview
  },
}
```

`bind` takes an IP address (not a hostname):

| `bind` | Listens on | Reachable from | When to use |
|---|---|---|---|
| unset (default) | every interface, IPv4 and IPv6 | your whole network | You want to open the preview from another device |
| `"127.0.0.1"` | IPv4 loopback only | programs on this machine, not other devices | **Most setups** |
| `"::1"` | IPv6 loopback only | programs on this machine, not other devices | You specifically want IPv6 loopback |
| `"0.0.0.0"` | every IPv4 interface | your whole network | A container where the forwarded port must be bound to all interfaces |
| your LAN address, e.g. `"192.168.1.20"` | that one interface | the network that interface is on | You want to expose it to one network only (also set `host` to it, see below) |

Loopback keeps other devices off the preview; it does not make it private to you. Other users and other programs on the same machine can still connect to it, and it does not defend against DNS rebinding (a web page in your browser getting at the server through a hostname it controls).

`host` and `bind` do different jobs: `host` only builds the URL opened in your browser, while `bind` decides who can connect. With `bind = "127.0.0.1"` (or `"0.0.0.0"`) you can leave `host = "localhost"` as it is. With any other address, such as your LAN address, `localhost` no longer reaches the server, so set `host` to the same address or the browser will open a URL that is refused.

`bind` has to be an IP address: a hostname such as `"localhost"`, an empty string, a non-string, or a malformed IPv4 address such as `"999.1.1.1"` is rejected with an error, **and `:ScalarPreview` then refuses to start until it is fixed** rather than falling back to listening on all network interfaces. IPv6 addresses with a zone id (`fe80::1%en0`) are not accepted. An IPv6 address that is written oddly and gets past the plugin's check is rejected by the preload, so the CLI exits with `ScalarPreview exited with code 1`. A well-formed address that is not one of your machine's makes the CLI fail to start in the same way. A change to `bind` applies the next time a preview starts; one that is already running keeps the address it was started with.

How it works: `@scalar/cli` has no option for the address it listens on, so when `bind` is set the plugin starts it with `NODE_OPTIONS=--import=<scripts/bind-loopback.mjs>`. That script makes Node bind to your address, stops the server with an error if it ends up listening anywhere else, and prints a confirmation line once the bind is in place. The plugin waits for that line before it opens the browser, and stops the server with an error if it reports that it is listening without having confirmed the bind, for example because the script was never loaded. A `NODE_OPTIONS` in your environment is kept. A `node-options` setting in an `.npmrc` is not applied to the preview while `bind` is set: npm would otherwise replace `NODE_OPTIONS` with it and silently drop the script, so the plugin also sets `npm_config_node_options`, which takes precedence over every `.npmrc`.

Where this has been checked: by hand with `@scalar/cli` 2.11.0 running through `npx`, on macOS with Node 25 and on Linux (aarch64, in a container) with Node 24, where `:ScalarPreviewStop` also took down the `npx`, `sh` and `node` processes together. CI covers the preload script itself and, through `npm exec`, that the setting reaches a process started by npm on Linux; it does not run `@scalar/cli`. The path that stops a server which did not confirm the bind has only been exercised by unit tests, since there is no way left to make the real CLI skip the preload. It has not been checked on Windows.

## Known limitations

- **Only preview specs you trust.** `@scalar/cli` resolves every `$ref` in the document — including ones pointing outside its directory on the local filesystem, and ones pointing at an `http(s)://` URL — and embeds what it finds into the page it serves. A spec from an untrusted source can use this to have the preview server expose the contents of any other local file your user can read (as long as it parses as YAML/JSON) and/or make it send a request to an attacker-controlled URL, revealing that the spec was opened. This is `@scalar/cli`'s own behavior; this plugin has no way to sandbox or restrict it.
- **By default the preview is reachable from your whole network.** The underlying server (`@scalar/cli document serve`) listens on all network interfaces, both IPv4 and IPv6 (`0.0.0.0` and `::`) — not just `localhost` — and the CLI has no flag to restrict this. Anything reachable on your network can view whatever you're previewing while the server is running. Set `bind = "127.0.0.1"` (see "Restricting who can reach the preview") to keep other devices out, and run `:ScalarPreviewStop` when you're done, especially on an untrusted network. `bind` is off by default so that existing setups that open the preview from another device keep working.
- The first `:ScalarPreview` run may take a few seconds while `npx` fetches `@scalar/cli`; it's cached after that.
- With the default `cli_version = "latest"`, the exact version of `@scalar/cli` that runs isn't pinned and can change between runs whenever a new version is published upstream — `npx` fetches and runs whatever "latest" currently resolves to, with no confirmation prompt (`--yes`). Set `cli_version` to a specific version (e.g. `"2.8.0"`) to pin it instead. Pinning a version doesn't guarantee its integrity (there's no hash check); it only stops it from silently changing between runs.
- `npx` runs in the previewed file's directory and looks for an already-installed `@scalar/cli` in the nearest `node_modules` at or above it (the closest directory that has a `package.json` or `node_modules`); the search stops at that directory and doesn't look further up. If that copy's own `package.json` claims a matching version — the exact `cli_version`, or a range such as `7.x` — `npx` runs it instead of downloading from the registry, so pinning `cli_version` does not rule this out. For `latest`, the same happens when the copy's `package.json` has a `resolved` equal to `latest`'s current tarball URL. A `.npmrc` in that same directory can also point `npx` at a different registry. This is `npm`/`npx`'s own resolution, outside this plugin's control. Don't preview specs inside a checkout you don't trust.
- If warnings are printed by the underlying CLI, they're written to `stdpath("state") .. "/scalar-preview.log"` instead of flooding Neovim with one notification per line. Warnings from `npm`/`npx` itself (e.g. `EBADENGINE`, deprecated-subdependency notices) are logged but never trigger that notification, since they show up on practically every run and aren't actionable.
- The preview always reflects the file's contents on disk, not unsaved buffer changes; `:ScalarPreview` warns about this but still starts.
- On Windows, `npx` resolves to `npx.cmd`, which Windows runs through `cmd.exe` regardless of how this plugin invokes it, so the previewed file *and* the resolved `config` path are both refused outright, rather than risked, if either contains a `cmd.exe` metacharacter (` & | ^ % ( ) ! < > " `) — this plugin can't quote for `cmd.exe` the way the underlying `jobstart()` call quotes for `CommandLineToArgvW`. This caveat is specific to Windows; it doesn't apply on macOS/Linux. (Verified against Neovim's and npm's own documented behavior, not against a real Windows install — please report an issue if you hit something unexpected here.)

## Help

See `:help scalar-preview` for the full command/configuration reference (`doc/scalar-preview.txt`).

## License

MIT. This plugin invokes `@scalar/cli` (MIT License) as an external process via `npx`; no Scalar source is bundled or redistributed.
