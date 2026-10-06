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

  local major = tonumber(output:match("^v(%d+)"))
  if major == nil then
    vim.health.warn("couldn't parse `node --version` output: " .. vim.inspect(output))
    return
  end

  if major >= MIN_NODE_MAJOR then
    vim.health.ok("Node.js " .. output:gsub("%s+$", "") .. " (>= " .. MIN_NODE_MAJOR .. " required by @scalar/cli)")
  else
    vim.health.error(
      "Node.js "
        .. output:gsub("%s+$", "")
        .. " is below the minimum of "
        .. MIN_NODE_MAJOR
        .. " required by @scalar/cli",
      { "Upgrade Node.js to " .. MIN_NODE_MAJOR .. " or later: https://nodejs.org/" }
    )
  end
end

function M.check()
  vim.health.start("scalar-preview.nvim")
  check_neovim_version()
  check_npx()
  check_node_version()
end

return M
