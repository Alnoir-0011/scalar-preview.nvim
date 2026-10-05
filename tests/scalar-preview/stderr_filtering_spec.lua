local stub = require("tests.helpers.stub")

describe("stderr filtering", function()
  local sp, jobs, notifications, file_a

  before_each(function()
    package.loaded["scalar-preview"] = nil
    sp = require("scalar-preview")
    jobs, notifications = stub.install()
    file_a = stub.tempfile("a.yaml")
    vim.cmd.edit(file_a)
    sp.start()
  end)

  after_each(function()
    stub.restore()
  end)

  it("does not warn on npm's own warnings (EBADENGINE, deprecated, ...)", function()
    local job = jobs.started[1]

    job.opts.on_stderr(job.id, {
      "npm warn EBADENGINE Unsupported engine {",
      "npm warn EBADENGINE   package: 'nanoid@6.0.1',",
      "npm warn deprecated inflight@1.0.6: this module is not supported",
    })

    assert.are.same({}, stub.warnings(notifications))
  end)

  it("still warns once on real warnings from @scalar/cli", function()
    local job = jobs.started[1]

    job.opts.on_stderr(job.id, { "npm warn EBADENGINE ..." })
    job.opts.on_stderr(job.id, { "[WARN] Could not find any paths in the OpenAPI file." })
    job.opts.on_stderr(job.id, { "another real warning line" })

    assert.are.equal(1, #stub.warnings(notifications))
  end)

  it("ignores lines that are purely cursor-visibility ANSI codes", function()
    local job = jobs.started[1]

    job.opts.on_stderr(job.id, { "\27[?25l", "\27[?25h" })

    assert.are.same({}, stub.warnings(notifications))
  end)
end)
