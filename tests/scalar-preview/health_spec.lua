describe("health", function()
  local health
  local original_executable, original_system

  before_each(function()
    package.loaded["scalar-preview.health"] = nil
    health = require("scalar-preview.health")
    original_executable = vim.fn.executable
    original_system = vim.fn.system
  end)

  after_each(function()
    vim.fn.executable = original_executable
    vim.fn.system = original_system
  end)

  -- vim.v.shell_error is read-only from Lua, so rather than trying to assign it directly,
  -- these stubs run a trivial real command first (to set it as a genuine side effect) and
  -- then return the fake `node --version`-shaped output on top of it.
  local function stub_system(output, succeeds)
    vim.fn.system = function()
      original_system({ succeeds and "true" or "false" })
      return output
    end
  end

  -- vim.health.* writes into a report buffer that only exists once :checkhealth has started
  -- one; calling check() standalone (as these tests do, to drive it with controlled
  -- vim.fn.executable()/system() stubs) still runs the same checks without erroring, it just
  -- has nowhere to render the output -- which is all these tests care about.
  it("does not error when npx and a new-enough node are both found", function()
    vim.fn.executable = function(name)
      return (name == "npx" or name == "node") and 1 or 0
    end
    stub_system("v24.0.0\n", true)

    assert.has_no.errors(health.check)
  end)

  it("does not error when npx is missing", function()
    vim.fn.executable = function(name)
      return name == "npx" and 0 or original_executable(name)
    end

    assert.has_no.errors(health.check)
  end)

  it("does not error when node is found but below the minimum version", function()
    vim.fn.executable = function(name)
      return (name == "npx" or name == "node") and 1 or 0
    end
    stub_system("v18.0.0\n", true)

    assert.has_no.errors(health.check)
  end)

  it("does not error when node --version output can't be parsed", function()
    vim.fn.executable = function(name)
      return (name == "npx" or name == "node") and 1 or 0
    end
    stub_system("not a version string\n", true)

    assert.has_no.errors(health.check)
  end)

  it("does not error when node --version itself fails", function()
    vim.fn.executable = function(name)
      return (name == "npx" or name == "node") and 1 or 0
    end
    stub_system("", false)

    assert.has_no.errors(health.check)
  end)
end)
