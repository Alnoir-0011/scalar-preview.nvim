local stub = require("tests.helpers.stub")

describe("buffer guards", function()
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

  it("refuses to start on an unnamed buffer", function()
    vim.cmd("enew")

    sp.start()

    assert.are.equal(0, #jobs.started)
    local errors = stub.errors(notifications)
    assert.are.equal(1, #errors)
    assert.truthy(errors[1].msg:lower():match("unnamed"))
  end)

  -- Isolated from the unnamed-buffer case: this buffer has a real, readable path, so only the
  -- buftype branch of the guard should be able to refuse it.
  it("refuses to start on a special buffer with a real file path (e.g. a terminal)", function()
    vim.cmd.edit(file_a)
    vim.bo.buftype = "nofile"

    sp.start()

    assert.are.equal(0, #jobs.started)
    local errors = stub.errors(notifications)
    assert.are.equal(1, #errors)
    assert.truthy(errors[1].msg:match("buftype=nofile"))
  end)

  it("refuses to start when the file doesn't exist on disk", function()
    vim.cmd.edit(vim.fn.fnamemodify(file_a, ":h") .. "/does-not-exist.yaml")

    sp.start()

    assert.are.equal(0, #jobs.started)
    assert.are.equal(1, #stub.errors(notifications))
  end)

  it("mentions the still-running preview when refusing on an invalid buffer", function()
    vim.cmd.edit(file_a)
    sp.start()
    assert.are.equal(1, #jobs.started)

    vim.cmd("enew")
    sp.start()

    local errors = stub.errors(notifications)
    assert.are.equal(1, #errors)
    assert.truthy(errors[1].msg:match("still running"))
  end)

  it("warns but still starts when the buffer has unsaved changes", function()
    vim.cmd.edit(file_a)
    vim.api.nvim_buf_set_lines(0, -1, -1, false, { "# unsaved" })
    assert.is_true(vim.bo.modified)

    sp.start()

    assert.are.equal(1, #jobs.started)
    assert.are.equal(1, #stub.warnings(notifications))
    assert.are.equal(0, #stub.errors(notifications))
  end)

  it("does not warn when the buffer has no unsaved changes", function()
    vim.cmd.edit(file_a)

    sp.start()

    assert.are.equal(1, #jobs.started)
    assert.are.equal(0, #stub.warnings(notifications))
  end)

  it("warns again on unsaved changes even when re-invoked on the file already being previewed", function()
    vim.cmd.edit(file_a)
    sp.start()
    assert.are.equal(1, #jobs.started)

    vim.api.nvim_buf_set_lines(0, -1, -1, false, { "# unsaved" })
    sp.start() -- same file, already previewing: this is a no-op for the job, but the
    -- buffer-vs-disk warning should still fire since that's still true right now.

    assert.are.equal(1, #jobs.started) -- no restart happened
    assert.are.equal(1, #stub.warnings(notifications))
  end)
end)
