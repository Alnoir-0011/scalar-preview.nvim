local function stub_health()
  local calls = { ok = {}, warn = {}, error = {} }
  local originals = {
    start = vim.health.start,
    ok = vim.health.ok,
    warn = vim.health.warn,
    error = vim.health.error,
  }
  vim.health.start = function() end
  vim.health.ok = function(msg)
    table.insert(calls.ok, msg)
  end
  vim.health.warn = function(msg, advice)
    table.insert(calls.warn, { msg = msg, advice = advice })
  end
  vim.health.error = function(msg, advice)
    table.insert(calls.error, { msg = msg, advice = advice })
  end
  return calls, originals
end

local function restore_health(originals)
  vim.health.start = originals.start
  vim.health.ok = originals.ok
  vim.health.warn = originals.warn
  vim.health.error = originals.error
end

-- Finds the one entry (if any) whose .msg matches `pattern`, out of `calls.ok` (plain
-- strings) or `calls.warn`/`calls.error` (tables with a .msg field).
local function find(entries, pattern)
  for _, entry in ipairs(entries) do
    local msg = type(entry) == "string" and entry or entry.msg
    if msg:match(pattern) then
      return entry
    end
  end
  return nil
end

describe("health", function()
  local health
  local original_executable, original_system, original_version_ge
  local calls, health_originals

  before_each(function()
    package.loaded["scalar-preview.health"] = nil
    health = require("scalar-preview.health")
    original_executable = vim.fn.executable
    original_system = vim.fn.system
    original_version_ge = vim.version.ge
    calls, health_originals = stub_health()

    -- check_neovim_version() is its own, separately-meaningful check (also covered below);
    -- pinning it to "ok" here keeps every other test's assertions about npx/node isolated
    -- from whatever vim.version() happens to report in the environment running this suite
    -- (observed in CI: installing an exact "v0.10.0" can still resolve to a prerelease like
    -- "0.10.0-dev+g27fb62988", which vim.version.ge() correctly ranks *below* "0.10.0").
    vim.version.ge = function()
      return true
    end
  end)

  after_each(function()
    vim.fn.executable = original_executable
    vim.fn.system = original_system
    vim.version.ge = original_version_ge
    restore_health(health_originals)
  end)

  -- vim.v.shell_error is read-only from Lua, so rather than trying to assign it directly,
  -- this stub runs a trivial real command first (to set it as a genuine side effect) and
  -- then returns the fake `node --version`-shaped output on top of it.
  local function stub_system(output, succeeds)
    vim.fn.system = function()
      original_system({ succeeds and "true" or "false" })
      return output
    end
  end

  it("reports ok for npx and a new-enough node", function()
    vim.fn.executable = function(name)
      return (name == "npx" or name == "node") and 1 or 0
    end
    stub_system("v24.0.0\n", true)

    health.check()

    assert.truthy(find(calls.ok, "^`npx` found"))
    assert.truthy(find(calls.ok, "^Node%.js v24%.0%.0"))
    assert.are.same({}, calls.warn)
    assert.are.same({}, calls.error)
  end)

  it("reports an error, with upgrade advice, when npx is missing", function()
    -- node's own check is irrelevant to this case, so it's pinned to "missing" too rather
    -- than falling through to whatever node happens (or doesn't) to be on this machine --
    -- otherwise this test's outcome for that branch would depend on the environment it runs
    -- in, and could fork a real `node --version` subprocess along the way.
    vim.fn.executable = function()
      return 0
    end

    health.check()

    local npx_error = find(calls.error, "^`npx` not found")
    assert.truthy(npx_error)
    assert.truthy(npx_error.advice[1]:match("nodejs%.org"))
  end)

  it("reports a warning, not an error, when node itself is missing", function()
    vim.fn.executable = function(name)
      return name == "npx" and 1 or 0
    end

    health.check()

    assert.truthy(find(calls.warn, "^`node` not found"))
    assert.falsy(find(calls.error, "node"))
  end)

  it("reports an error when node is found but below the minimum version", function()
    vim.fn.executable = function(name)
      return (name == "npx" or name == "node") and 1 or 0
    end
    stub_system("v18.0.0\n", true)

    health.check()

    assert.truthy(find(calls.error, "^Node%.js v18%.0%.0 is below the minimum"))
  end)

  it("reports a warning when node --version output can't be parsed", function()
    vim.fn.executable = function(name)
      return (name == "npx" or name == "node") and 1 or 0
    end
    stub_system("not a version string\n", true)

    health.check()

    assert.truthy(find(calls.warn, "^couldn't parse"))
    assert.falsy(find(calls.error, "Node%.js"))
  end)

  it("reports a warning when node --version itself fails", function()
    vim.fn.executable = function(name)
      return (name == "npx" or name == "node") and 1 or 0
    end
    stub_system("", false)

    health.check()

    assert.truthy(find(calls.warn, "^`node %-%-version` failed"))
  end)

  it("reports an error, with upgrade advice, when Neovim itself is below the minimum", function()
    vim.fn.executable = function(name)
      return (name == "npx" or name == "node") and 1 or 0
    end
    stub_system("v24.0.0\n", true)
    vim.version.ge = function()
      return false
    end

    health.check()

    local nvim_error = find(calls.error, "^Neovim .* is below the minimum of 0%.10")
    assert.truthy(nvim_error)
    assert.truthy(nvim_error.advice[2]:match("Upgrade Neovim"))
  end)

  -- Regression test: vim.health.start()/ok()/warn()/error() are themselves a Neovim >= 0.10
  -- API; check() must not raise on an older Neovim where they don't exist.
  it("falls back to vim.notify instead of erroring when vim.health doesn't have the new API", function()
    local original_health = vim.health
    local original_notify = vim.notify
    local notified = {}
    vim.notify = function(msg, level)
      table.insert(notified, { msg = msg, level = level })
    end
    vim.health = {} -- simulates a pre-0.10 Neovim: no start/ok/warn/error

    local ok = pcall(health.check)

    vim.health = original_health
    vim.notify = original_notify

    assert.is_true(ok)
    assert.are.equal(1, #notified)
    assert.are.equal(vim.log.levels.ERROR, notified[1].level)
    assert.truthy(notified[1].msg:match("too old"))
  end)
end)
