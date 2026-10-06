local stub = require("tests.helpers.stub")

describe("job lifecycle", function()
  local sp, jobs, notifications, file_a, file_b

  before_each(function()
    package.loaded["scalar-preview"] = nil
    sp = require("scalar-preview")
    jobs, notifications = stub.install()
    file_a = stub.tempfile("a.yaml")
    file_b = stub.tempfile("b.yaml")
  end)

  after_each(function()
    stub.restore()
  end)

  it("keeps tracking the new job when the previous job exits after a restart", function()
    vim.cmd.edit(file_a)
    sp.start()
    local first = jobs.started[1]

    vim.cmd.edit(file_b)
    sp.start()
    local second = jobs.started[2]

    -- The old job's on_exit arrives asynchronously, after the new job has started.
    first.opts.on_exit(first.id, 143)

    assert.are.equal(second.id, sp.job_id)
    assert.are.equal(vim.fn.fnamemodify(file_b, ":p"), sp.file_being_previewed)
  end)

  it("does not report an error when the job was stopped by the user", function()
    vim.cmd.edit(file_a)
    sp.start()
    local job = jobs.started[1]

    sp.stop()
    job.opts.on_exit(job.id, 143)

    assert.are.same({}, stub.errors(notifications))
  end)

  it("does not report an error for the previous job when restarting with another file", function()
    vim.cmd.edit(file_a)
    sp.start()
    local first = jobs.started[1]

    vim.cmd.edit(file_b)
    sp.start()
    first.opts.on_exit(first.id, 143)

    assert.are.same({}, stub.errors(notifications))
  end)

  it("reports an error and clears state when the job exits unexpectedly", function()
    vim.cmd.edit(file_a)
    sp.start()
    local job = jobs.started[1]

    job.opts.on_exit(job.id, 1)

    assert.are.equal(1, #stub.errors(notifications))
    assert.is_nil(sp.job_id)
    assert.is_nil(sp.file_being_previewed)
  end)

  it("stops the running job on stop()", function()
    vim.cmd.edit(file_a)
    sp.start()
    local job = jobs.started[1]

    sp.stop()

    assert.are.same({ job.id }, jobs.stopped)
    assert.is_nil(sp.job_id)
  end)

  it("does not call jobstop a second time when stop() is called with no job running", function()
    vim.cmd.edit(file_a)
    sp.start()

    sp.stop()
    sp.stop()

    assert.are.equal(1, #jobs.stopped)
  end)

  it("clears state and reports no error on a normal exit", function()
    vim.cmd.edit(file_a)
    sp.start()
    local job = jobs.started[1]

    job.opts.on_exit(job.id, 0)

    assert.are.same({}, stub.errors(notifications))
    assert.is_nil(sp.job_id)
    assert.is_nil(sp.file_being_previewed)
  end)

  it("does not leak a stopped_jobs entry past the matching on_exit", function()
    vim.cmd.edit(file_a)
    sp.start()
    local job = jobs.started[1]

    sp.stop()
    job.opts.on_exit(job.id, 143)

    assert.is_nil(sp.stopped_jobs[job.id])
  end)

  it("reports an error and does not start a job when jobstart fails", function()
    vim.cmd.edit(file_a)
    jobs.next_failure = -1

    sp.start()

    assert.are.equal(0, #jobs.started)
    assert.are.equal(1, #stub.errors(notifications))
    assert.is_nil(sp.job_id)
    assert.is_nil(sp.file_being_previewed)
  end)

  -- Some Neovim versions raise a Lua error from jobstart (observed: nightly v0.13.0-dev, for
  -- a list {cmd} whose cmd[0] -- e.g. `npx` -- isn't on $PATH) instead of returning -1 for
  -- that same failure, so this must be handled the same way as the -1 case above.
  it("reports an error and does not start a job when jobstart raises an error", function()
    vim.cmd.edit(file_a)
    jobs.next_error = "Vim:E475: Invalid value for argument cmd: 'npx' is not executable"

    sp.start()

    assert.are.equal(0, #jobs.started)
    assert.are.equal(1, #stub.errors(notifications))
    assert.is_nil(sp.job_id)
    assert.is_nil(sp.file_being_previewed)
  end)
end)
