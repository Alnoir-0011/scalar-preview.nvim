local stub = require("tests.helpers.stub")

describe("bind option", function()
  local sp, jobs, notifications, file_a, original_node_options

  before_each(function()
    package.loaded["scalar-preview"] = nil
    sp = require("scalar-preview")
    jobs, notifications = stub.install()
    file_a = stub.tempfile("a.yaml")
    original_node_options = vim.env.NODE_OPTIONS
    vim.env.NODE_OPTIONS = nil
  end)

  after_each(function()
    vim.env.NODE_OPTIONS = original_node_options
    stub.restore()
  end)

  local function start_with(opts)
    sp.setup(opts)
    vim.cmd.edit(file_a)
    sp.start()
    return jobs.started[1]
  end

  it("leaves the job environment untouched when bind is not set", function()
    local job = start_with({ port = 8000 })

    assert.is_nil(job.opts.env)
    assert.is_nil(sp.config.bind)
  end)

  it("passes the bind address to the job through SCALAR_PREVIEW_BIND_HOST", function()
    local job = start_with({ port = 8000, bind = "127.0.0.1" })

    assert.are.equal("127.0.0.1", job.opts.env.SCALAR_PREVIEW_BIND_HOST)
  end)

  it("preloads an existing script through NODE_OPTIONS --import", function()
    local job = start_with({ port = 8000, bind = "127.0.0.1" })

    local url = job.opts.env.NODE_OPTIONS:match("%-%-import=(file://%S+)")
    assert.truthy(url)
    assert.are.equal(1, vim.fn.filereadable(vim.uri_to_fname(url)))
  end)

  it("keeps the NODE_OPTIONS the user already has", function()
    vim.env.NODE_OPTIONS = "--max-old-space-size=512"

    local job = start_with({ port = 8000, bind = "127.0.0.1" })

    assert.truthy(vim.startswith(job.opts.env.NODE_OPTIONS, "--max-old-space-size=512 "))
    assert.truthy(job.opts.env.NODE_OPTIONS:find("--import=", 1, true))
  end)

  it("hands npm the same NODE_OPTIONS through npm_config_node_options", function()
    vim.env.NODE_OPTIONS = "--max-old-space-size=512"

    local job = start_with({ port = 8000, bind = "127.0.0.1" })

    assert.are.equal(job.opts.env.NODE_OPTIONS, job.opts.env.npm_config_node_options)
  end)

  it("does not put the bind address on the command line", function()
    local job = start_with({ port = 8000, bind = "127.0.0.1" })

    for _, arg in ipairs(job.cmd) do
      assert.is_nil(arg:find("127.0.0.1", 1, true))
    end
  end)

  it("accepts IPv4 and IPv6 addresses", function()
    for _, good in ipairs({ "127.0.0.1", "::1", "0.0.0.0" }) do
      package.loaded["scalar-preview"] = nil
      sp = require("scalar-preview")
      jobs, notifications = stub.install()

      local job = start_with({ port = 8000, bind = good })

      assert.are.equal(good, job.opts.env.SCALAR_PREVIEW_BIND_HOST, good .. " should be accepted as-is")
      assert.are.equal(0, #stub.errors(notifications), good .. " should not be rejected")

      stub.restore()
    end
  end)

  it("rejects a value that is not an IP address and falls back to unset", function()
    for _, bad in ipairs({ 123, false, "", "localhost", "my-host.local" }) do
      package.loaded["scalar-preview"] = nil
      sp = require("scalar-preview")
      jobs, notifications = stub.install()

      local job = start_with({ port = 8000, bind = bad })

      assert.are.equal(1, #jobs.started, vim.inspect(bad) .. " should still start")
      assert.is_nil(job.opts.env, vim.inspect(bad) .. " should fall back to unset")
      assert.are.equal(1, #stub.errors(notifications), vim.inspect(bad) .. " should be rejected")

      stub.restore()
    end
  end)

  it("says the server will listen on all network interfaces when it rejects a value", function()
    sp.setup({ port = 8000, bind = "localhost" })

    local errors = stub.errors(notifications)
    assert.are.equal(1, #errors)
    assert.truthy(errors[1].msg:find("all network interfaces", 1, true))
  end)
end)
