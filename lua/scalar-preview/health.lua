local M = {}

-- @scalar/cli's own package.json requires Node >= 24; `node --version` prints "vX.Y.Z".
local MIN_NODE_MAJOR = 24

local function check_neovim_version()
  if vim.version.ge(vim.version(), "0.10.0") then
    vim.health.ok("Neovim " .. tostring(vim.version()) .. " (>= 0.10 required for vim.ui.open)")
  else
    vim.health.error("Neovim " .. tostring(vim.version()) .. " is below the minimum of 0.10", {
      "scalar-preview.nvim uses vim.ui.open(), added in Neovim 0.10.",
      "Upgrade Neovim to 0.10 or later.",
    })
  end
end

local function check_npx()
  if vim.fn.executable("npx") == 1 then
    vim.health.ok("`npx` found on $PATH (" .. vim.fn.exepath("npx") .. ")")
  else
    vim.health.error("`npx` not found on $PATH", {
      "Install Node.js (which bundles npm/npx): https://nodejs.org/",
      "Make sure npx is on $PATH in the environment Neovim itself runs in"
        .. " (a GUI-launched Neovim may not inherit your shell's $PATH).",
    })
  end
end

local function check_node_version()
  if vim.fn.executable("node") == 0 then
    vim.health.warn("`node` not found on $PATH; can't check its version", {
      "This is only a problem if `npx` (checked separately above) can't find a Node"
        .. " runtime either -- some npx installs (e.g. via a version manager's shim)"
        .. " resolve `node` differently than a plain $PATH lookup would here.",
    })
    return
  end

  local output = vim.fn.system({ "node", "--version" })
  if vim.v.shell_error ~= 0 then
    vim.health.warn("`node --version` failed; can't check its version")
    return
  end

  -- vim.fn.system() merges stderr into the same string as stdout (confirmed: a command that
  -- writes to both interleaves them in the result), and node --version's own output is just
  -- "vX.Y.Z" -- but something else on $PATH ahead of it in the resolution (an nvm/fnm/volta
  -- shim, an NODE_OPTIONS/ExperimentalWarning banner, a corporate AV wrapper, ...) can still
  -- write a line to stderr before it prints the version. Scan line by line for the one
  -- that's just a bare version, instead of anchoring to the very first character of
  -- (possibly noisy) `output` as a whole, so a banner ahead of it doesn't produce a false
  -- "couldn't parse" warning for an otherwise perfectly fine, new-enough Node.
  local version_line
  for line in output:gmatch("[^\r\n]+") do
    if line:match("^v%d+[%d.]*$") then
      version_line = line
      break
    end
  end

  if version_line == nil then
    vim.health.warn("couldn't parse `node --version` output: " .. vim.inspect(output))
    return
  end

  local major = tonumber(version_line:match("^v(%d+)"))

  if major >= MIN_NODE_MAJOR then
    vim.health.ok("Node.js " .. version_line .. " (>= " .. MIN_NODE_MAJOR .. " required by @scalar/cli)")
  else
    vim.health.error(
      "Node.js " .. version_line .. " is below the minimum of " .. MIN_NODE_MAJOR .. " required by @scalar/cli",
      { "Upgrade Node.js to " .. MIN_NODE_MAJOR .. " or later: https://nodejs.org/" }
    )
  end
end

function M.check()
  -- vim.health.start()/ok()/warn()/error() are themselves a Neovim >= 0.10 API (replacing
  -- the older vim.health.report_*() names); on an older Neovim, vim.health.start would be
  -- nil, and calling it would raise a raw "attempt to call field 'start' (a nil value)"
  -- instead of the check_neovim_version() message below that's meant to tell a user on
  -- exactly that older Neovim to upgrade. Fall back to a plain notification instead.
  if vim.health == nil or vim.health.start == nil then
    vim.notify(
      "scalar-preview.nvim: this Neovim version is too old to run `:checkhealth scalar-preview` "
        .. "itself (needs the vim.health API added in Neovim 0.10); scalar-preview.nvim needs "
        .. "Neovim >= 0.10 regardless. Please upgrade Neovim.",
      vim.log.levels.ERROR
    )
    return
  end

  vim.health.start("scalar-preview.nvim")
  check_neovim_version()
  check_npx()
  check_node_version()
end

return M
