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

  it("does not leave a leading space when the user's NODE_OPTIONS is empty", function()
    vim.env.NODE_OPTIONS = ""

    local job = start_with({ port = 8000, bind = "127.0.0.1" })

    assert.truthy(vim.startswith(job.opts.env.NODE_OPTIONS, "--import="))
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

  for _, good in ipairs({ "127.0.0.1", "::1", "0.0.0.0", "192.168.1.20", "255.255.255.255" }) do
    it("accepts " .. good, function()
      local job = start_with({ port = 8000, bind = good })

      assert.are.equal(good, job.opts.env.SCALAR_PREVIEW_BIND_HOST)
      assert.are.equal(0, #stub.errors(notifications))
    end)
  end

  -- "fe80::1%en0" is a valid address to node, but a zone id is not something this check
  -- tries to recognize.
  local invalid_values = { 123, false, "", "localhost", "my-host.local", "999.1.1.1", "01.2.3.4", "fe80::1%en0" }

  for _, bad in ipairs(invalid_values) do
    it("refuses to start rather than listen on every interface when bind is " .. vim.inspect(bad), function()
      local job = start_with({ port = 8000, bind = bad })

      assert.is_nil(job)
      local errors = stub.errors(notifications)
      assert.are.equal(2, #errors) -- one from setup(), one from the refused start
      assert.truthy(errors[2].msg:find("config.bind", 1, true))
    end)
  end

  it("tells the user at setup that ScalarPreview will not start until bind is fixed", function()
    sp.setup({ port = 8000, bind = "localhost" })

    local errors = stub.errors(notifications)
    assert.are.equal(1, #errors)
    assert.truthy(errors[1].msg:find("will not start", 1, true))
  end)

  it("still refuses to start when an invalid bind follows a valid one", function()
    sp.setup({ port = 8000, bind = "127.0.0.1" })
    sp.setup({ bind = "localhost" })
    vim.cmd.edit(file_a)

    sp.start()

    assert.are.equal(0, #jobs.started)
  end)

  it("starts again once a valid bind is set after an invalid one", function()
    sp.setup({ port = 8000, bind = "localhost" })
    sp.setup({ bind = "127.0.0.1" })
    vim.cmd.edit(file_a)

    sp.start()

    assert.are.equal(1, #jobs.started)
    assert.are.equal("127.0.0.1", jobs.started[1].opts.env.SCALAR_PREVIEW_BIND_HOST)
  end)

  it("does not let a setup() that leaves bind out clear an invalid bind", function()
    sp.setup({ port = 8000, bind = "localhost" })
    sp.setup({ port = 8001 })
    vim.cmd.edit(file_a)

    sp.start()

    assert.are.equal(0, #jobs.started)
  end)
end)
