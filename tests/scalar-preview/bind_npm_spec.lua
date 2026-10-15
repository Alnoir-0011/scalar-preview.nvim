local stub = require("tests.helpers.stub")
local tools = require("tests.helpers.tools")

local on_unix = vim.fn.has("win32") == 0
local npm_it = tools.it_requiring("npm on a unix-like system", tools.executable("npm") and on_unix)
local node_it = tools.it_requiring("node", tools.executable("node"))

describe("bind under npm", function()
  local sp, jobs, project_dir

  before_each(function()
    package.loaded["scalar-preview"] = nil
    sp = require("scalar-preview")
    jobs = stub.install()
    project_dir = vim.fn.tempname()
    vim.fn.mkdir(project_dir, "p")
    vim.fn.writefile({ '{ "name": "bind-npm-spec", "version": "1.0.0" }' }, project_dir .. "/package.json")
  end)

  after_each(function()
    vim.fn.delete(project_dir, "rf")
    stub.restore()
  end)

  -- Goes through `npm exec` instead of spawning node directly because the override being
  -- guarded against happens inside npm, so a direct spawn could never reproduce it.
  local function node_options_seen_by_child_of_npm()
    vim.cmd.edit(stub.tempfile("a.yaml"))
    sp.setup({ port = 8000, bind = "127.0.0.1" })
    sp.start()

    local result = vim
      .system(
        { "npm", "exec", "-c", [[node -e "console.log(process.env.NODE_OPTIONS)"]] },
        { cwd = project_dir, env = jobs.started[1].opts.env, text = true, timeout = 30000 }
      )
      :wait()
    return vim.trim(result.stdout)
  end

  npm_it("keeps the preload when the project's .npmrc sets node-options", function()
    vim.fn.writefile({ "node-options=--max-old-space-size=512" }, project_dir .. "/.npmrc")

    assert.truthy(node_options_seen_by_child_of_npm():find("--import=", 1, true))
  end)

  -- The URL is built from this checkout's path, so a node that rejects it would fail here
  -- before any server is involved.
  node_it("lets node load the preload from the environment the plugin builds", function()
    vim.cmd.edit(stub.tempfile("a.yaml"))
    sp.setup({ port = 8000, bind = "127.0.0.1" })
    sp.start()

    local result = vim
      .system(
        { "node", "-e", [[console.log("loaded")]] },
        { cwd = project_dir, env = jobs.started[1].opts.env, text = true, timeout = 30000 }
      )
      :wait()

    assert.are.equal(0, result.code, result.stderr)
    assert.are.equal("loaded", vim.trim(result.stdout))
  end)

  npm_it("keeps the preload when nothing sets node-options", function()
    assert.truthy(node_options_seen_by_child_of_npm():find("--import=", 1, true))
  end)
end)
