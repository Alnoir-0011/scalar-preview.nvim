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
    assert.are.equal(1, #stub.errors(notifications))
  end)

  it("refuses to start on a special buffer (e.g. a terminal)", function()
    vim.cmd("enew")
    vim.bo.buftype = "nofile"

    sp.start()

    assert.are.equal(0, #jobs.started)
    assert.are.equal(1, #stub.errors(notifications))
  end)

  it("refuses to start when the file doesn't exist on disk", function()
    vim.cmd.edit(vim.fn.fnamemodify(file_a, ":h") .. "/does-not-exist.yaml")

    sp.start()

    assert.are.equal(0, #jobs.started)
    assert.are.equal(1, #stub.errors(notifications))
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
end)
