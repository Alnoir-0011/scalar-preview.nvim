local stub = require("tests.helpers.stub")

describe("cli command construction", function()
  local sp, jobs, notifications, file_a

  before_each(function()
    package.loaded["scalar-preview"] = nil
    sp = require("scalar-preview")
    jobs, notifications = stub.install()
    file_a = stub.tempfile("a.yaml")
  end)

  after_each(function()
    stub.restore()
  end)

  it("runs the command as a list, not a shell string", function()
    sp.setup({ port = 8000 })
    vim.cmd.edit(file_a)

    sp.start()

    assert.are.equal("table", type(jobs.started[1].cmd))
  end)

  it("defaults to @scalar/cli@latest and passes port/watch", function()
    sp.setup({ port = 8123 })
    vim.cmd.edit(file_a)

    sp.start()

    assert.are.same({
      "npx",
      "--yes",
      "@scalar/cli@latest",
      "document",
      "serve",
      "./a.yaml",
      "-w",
      "-p",
      "8123",
    }, jobs.started[1].cmd)
  end)

  it("pins the @scalar/cli version when cli_version is configured", function()
    sp.setup({ port = 8000, cli_version = "2.8.0" })
    vim.cmd.edit(file_a)

    sp.start()

    assert.truthy(vim.tbl_contains(jobs.started[1].cmd, "@scalar/cli@2.8.0"))
    assert.falsy(vim.tbl_contains(jobs.started[1].cmd, "@scalar/cli@latest"))
  end)

  it("appends -c <path> when config is set to a readable file", function()
    local config_file = stub.tempfile("scalar.config.json")
    sp.setup({ port = 8000, config = config_file })
    vim.cmd.edit(file_a)

    sp.start()

    local cmd = jobs.started[1].cmd
    local c_index
    for i, arg in ipairs(cmd) do
      if arg == "-c" then
        c_index = i
      end
    end
    assert.truthy(c_index)
    assert.are.equal(config_file, cmd[c_index + 1])
  end)

  it("does not pass -c at all when config is unset", function()
    sp.setup({ port = 8000 })
    vim.cmd.edit(file_a)

    sp.start()

    assert.falsy(vim.tbl_contains(jobs.started[1].cmd, "-c"))
  end)

  it("refuses to start when config points at an unreadable file", function()
    sp.setup({ port = 8000, config = vim.fn.fnamemodify(file_a, ":h") .. "/no-such-config.json" })
    vim.cmd.edit(file_a)

    sp.start()

    assert.are.equal(0, #jobs.started)
    assert.are.equal(1, #stub.errors(notifications))
  end)

  it("prefixes a basename starting with '-' with './' so it isn't parsed as a flag", function()
    local dashed = stub.tempfile("-dashed.yaml")
    sp.setup({ port = 8000 })
    vim.cmd.edit(dashed)

    sp.start()

    assert.truthy(vim.tbl_contains(jobs.started[1].cmd, "./-dashed.yaml"))
  end)
end)
