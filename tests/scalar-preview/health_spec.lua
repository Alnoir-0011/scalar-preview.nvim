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

describe("health", function()
  local health
  local original_executable, original_system
  local calls, health_originals

  before_each(function()
    package.loaded["scalar-preview.health"] = nil
    health = require("scalar-preview.health")
    original_executable = vim.fn.executable
    original_system = vim.fn.system
    calls, health_originals = stub_health()
  end)

  after_each(function()
    vim.fn.executable = original_executable
    vim.fn.system = original_system
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

  it("reports ok for everything when npx and a new-enough node are both found", function()
    vim.fn.executable = function(name)
      return (name == "npx" or name == "node") and 1 or 0
    end
    stub_system("v24.0.0\n", true)

    health.check()

    assert.are.equal(3, #calls.ok) -- Neovim version, npx, Node.js version
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

    assert.are.equal(1, #calls.error)
    assert.truthy(calls.error[1].msg:match("^`npx` not found"))
    assert.truthy(calls.error[1].advice[1]:match("nodejs%.org"))
  end)

  it("reports a warning, not an error, when node itself is missing", function()
    vim.fn.executable = function(name)
      return name == "npx" and 1 or 0
    end

    health.check()

    assert.are.equal(1, #calls.warn)
    assert.truthy(calls.warn[1].msg:match("^`node` not found"))
    assert.are.same({}, calls.error)
  end)

  it("reports an error when node is found but below the minimum version", function()
    vim.fn.executable = function(name)
      return (name == "npx" or name == "node") and 1 or 0
    end
    stub_system("v18.0.0\n", true)

    health.check()

    assert.are.equal(1, #calls.error)
    assert.truthy(calls.error[1].msg:match("^Node%.js v18%.0%.0 is below the minimum"))
  end)

  it("reports a warning when node --version output can't be parsed", function()
    vim.fn.executable = function(name)
      return (name == "npx" or name == "node") and 1 or 0
    end
    stub_system("not a version string\n", true)

    health.check()

    assert.are.equal(1, #calls.warn)
    assert.truthy(calls.warn[1].msg:match("^couldn't parse"))
    assert.are.same({}, calls.error)
  end)

  it("reports a warning when node --version itself fails", function()
    vim.fn.executable = function(name)
      return (name == "npx" or name == "node") and 1 or 0
    end
    stub_system("", false)

    health.check()

    assert.are.equal(1, #calls.warn)
    assert.truthy(calls.warn[1].msg:match("^`node %-%-version` failed"))
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
