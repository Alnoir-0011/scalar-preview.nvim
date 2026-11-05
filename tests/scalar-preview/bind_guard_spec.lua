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

  it("does not accept a confirmation for a different port", function()
    local job = start_job({ bind = "127.0.0.1" })

    job.opts.on_stdout(job.id, { "scalar-preview: bound 127.0.0.1:9999", listening, "" })

    assert.are.same({}, opened)
    assert.are.same({ job.id }, jobs.stopped)
    assert.are.equal(1, #stub.errors(notifications))
  end)

  it("accepts a confirmation that writes an IPv6 address in brackets", function()
    local job = start_job({ bind = "::1" })

    job.opts.on_stdout(job.id, { "scalar-preview: bound [::1]:8000", listening, "" })

    assert.are.same({ "http://localhost:8000" }, opened)
    assert.are.same({}, jobs.stopped)
  end)

  it("opens the browser on a listening line that has no newline after it when bind is not set", function()
    local job = start_job({})

    job.opts.on_stdout(job.id, { listening })

    assert.are.same({ "http://localhost:8000" }, opened)
  end)

  it("opens the browser on a listening line split across chunks when bind is not set", function()
    local job = start_job({})

    job.opts.on_stdout(job.id, { "\27[32m➜ API Reference server\27[39m listen" })
    job.opts.on_stdout(job.id, { "ing on http://localhost:8000", "" })

    assert.are.same({ "http://localhost:8000" }, opened)
  end)

  it("opens the browser only once for a listening line that is completed after it was first seen", function()
    local job = start_job({})

    job.opts.on_stdout(job.id, { listening })
    job.opts.on_stdout(job.id, { "", "" })

    assert.are.same({ "http://localhost:8000" }, opened)
  end)

  it("opens the browser again for a later listening line when bind is not set", function()
    local job = start_job({})

    job.opts.on_stdout(job.id, { listening, "" })
    job.opts.on_stdout(job.id, { listening, "" })

    assert.are.same({ "http://localhost:8000", "http://localhost:8000" }, opened)
  end)

  -- Lines as @scalar/cli 2.11.0 wrote them with the preload loaded (the banner trimmed): its
  -- cursor-show escape ends up in front of the confirmation, so the confirmation does not begin
  -- the line.
  local real_stream = {
    "\27[?25l\27[?25l\27[1m \27[37m\27[1mDemo\27[1m\27[39m \27[90m(OpenAPI v3.1)\27[39m\27[22m",
    "\27[?25h",
    "\27[?25h" .. confirmed,
    "\27[?25l\27[?25l\27[32m\27[1m➜ API Reference server\27[22m\27[39m \27[37mlistening on\27[39m"
      .. " \27[36mhttp://localhost:8000\27[39m",
    "\27[?25h",
    "",
  }

  it("accepts the confirmation as the CLI actually prints it, behind a cursor escape", function()
    local job = start_job({ bind = "127.0.0.1" })

    job.opts.on_stdout(job.id, vim.deepcopy(real_stream))

    assert.are.same({ "http://localhost:8000" }, opened)
    assert.are.same({}, jobs.stopped)
  end)

  -- Feeds `stream` as two chunks cut after `position` characters, the way a pipe may cut it.
  local function feed_in_two(job, stream, position)
    local whole = table.concat(stream, "\n")
    local first = vim.split(whole:sub(1, position), "\n", { plain = true })
    local second = vim.split(whole:sub(position + 1), "\n", { plain = true })
    job.opts.on_stdout(job.id, first)
    job.opts.on_stdout(job.id, second)
  end

  it("opens the browser once however the CLI's output is cut into chunks, with bind", function()
    local length = #table.concat(real_stream, "\n")
    for position = 1, length - 1 do
      opened = {}
      jobs.started, jobs.stopped = {}, {}
      local job = start_job({ bind = "127.0.0.1" })

      feed_in_two(job, real_stream, position)

      assert.are.same({ "http://localhost:8000" }, opened, "cut after " .. position)
      assert.are.same({}, jobs.stopped, "cut after " .. position)
      sp.stop()
    end
  end)

  it("opens the browser once however the CLI's output is cut into chunks, without bind", function()
    local length = #table.concat(real_stream, "\n")
    for position = 1, length - 1 do
      opened = {}
      jobs.started, jobs.stopped = {}, {}
      local job = start_job({})

      feed_in_two(job, real_stream, position)

      assert.are.same({ "http://localhost:8000" }, opened, "cut after " .. position)
      sp.stop()
    end
  end)

  it("opens the address the job was started with even if setup() changes it afterwards", function()
    local job = start_job({})

    sp.setup({ host = "elsewhere", port = 9000 })
    job.opts.on_stdout(job.id, { listening, "" })

    assert.are.same({ "http://localhost:8000" }, opened)
  end)

  it("opens the address the job was started with even if setup() changes it afterwards, with bind", function()
    local job = start_job({ bind = "127.0.0.1" })

    sp.setup({ host = "elsewhere", port = 9000, bind = "::1" })
    job.opts.on_stdout(job.id, { confirmed, listening, "" })

    assert.are.same({ "http://localhost:8000" }, opened)
    assert.are.same({}, jobs.stopped)
  end)

  -- Neovim hands over everything that arrived in one read, so a burst can be thousands of
  -- lines; LuaJIT's unpack() raises "too many results to unpack" at around 8000.
  local function lines(count)
    local out = {}
    for i = 1, count do
      out[i] = "line " .. i
    end
    return out
  end

  it("still opens the browser when thousands of lines arrive in one chunk, without bind", function()
    local job = start_job({})
    local data = lines(9000)
    table.insert(data, listening)
    table.insert(data, "")

    local ok = pcall(job.opts.on_stdout, job.id, data)

    assert.is_true(ok)
    assert.are.same({ "http://localhost:8000" }, opened)
  end)

  it("still opens the browser when thousands of lines arrive in one chunk, with bind", function()
    local job = start_job({ bind = "127.0.0.1" })
    local data = lines(9000)
    table.insert(data, confirmed)
    table.insert(data, listening)
    table.insert(data, "")

    local ok = pcall(job.opts.on_stdout, job.id, data)

    assert.is_true(ok)
    assert.are.same({ "http://localhost:8000" }, opened)
  end)

  it("still stops the server when thousands of lines arrive in one chunk and none confirms the bind", function()
    local job = start_job({ bind = "127.0.0.1" })
    local data = lines(9000)
    table.insert(data, listening)
    table.insert(data, "")

    local ok = pcall(job.opts.on_stdout, job.id, data)

    assert.is_true(ok)
    assert.are.same({}, opened)
    assert.are.same({ job.id }, jobs.stopped)
  end)
end)
