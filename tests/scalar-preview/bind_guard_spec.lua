local stub = require("tests.helpers.stub")

describe("bind guard", function()
  local sp, jobs, notifications, file_a, opened

  local confirmed = "scalar-preview: bound 127.0.0.1:8000"
  local listening = "\27[32m➜ API Reference server\27[39m listening on http://localhost:8000"

  before_each(function()
    package.loaded["scalar-preview"] = nil
    sp = require("scalar-preview")
    jobs, notifications = stub.install()
    file_a = stub.tempfile("a.yaml")
    opened = {}
    vim.ui.open = function(url)
      table.insert(opened, url)
    end
  end)

  after_each(function()
    stub.restore()
  end)

  local function start_job(opts)
    sp.setup(vim.tbl_extend("force", { port = 8000 }, opts))
    vim.cmd.edit(file_a)
    sp.start()
    return jobs.started[1]
  end

  it("opens the browser once the server has confirmed it is bound to the bind address", function()
    local job = start_job({ bind = "127.0.0.1" })

    job.opts.on_stdout(job.id, { confirmed, listening, "" })

    assert.are.same({ "http://localhost:8000" }, opened)
  end)

  it("accepts the confirmation arriving in an earlier chunk than the listening line", function()
    local job = start_job({ bind = "127.0.0.1" })

    job.opts.on_stdout(job.id, { confirmed, "" })
    job.opts.on_stdout(job.id, { listening, "" })

    assert.are.same({ "http://localhost:8000" }, opened)
  end)

  it("accepts a confirmation line split across chunks", function()
    local job = start_job({ bind = "127.0.0.1" })

    job.opts.on_stdout(job.id, { "scalar-preview: bo" })
    job.opts.on_stdout(job.id, { "und 127.0.0.1:8000", listening, "" })

    assert.are.same({ "http://localhost:8000" }, opened)
  end)

  it("stops the server and reports an error when it says it is listening without confirming the bind", function()
    local job = start_job({ bind = "127.0.0.1" })

    job.opts.on_stdout(job.id, { listening, "" })

    assert.are.same({}, opened)
    assert.are.same({ job.id }, jobs.stopped)
    local errors = stub.errors(notifications)
    assert.are.equal(1, #errors)
    assert.truthy(errors[1].msg:find("not confirm", 1, true))
    assert.is_nil(sp.job_id)
  end)

  it("does not report a second error when the stopped server then exits", function()
    local job = start_job({ bind = "127.0.0.1" })

    job.opts.on_stdout(job.id, { listening, "" })
    job.opts.on_exit(job.id, 143)

    assert.are.equal(1, #stub.errors(notifications))
  end)

  it("opens the browser on the listening line alone when bind is not set", function()
    local job = start_job({})

    job.opts.on_stdout(job.id, { listening, "" })

    assert.are.same({ "http://localhost:8000" }, opened)
    assert.are.same({}, jobs.stopped)
  end)
end)
