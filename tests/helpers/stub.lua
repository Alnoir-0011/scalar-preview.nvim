-- Replaces the Neovim APIs scalar-preview touches with recorders, so specs can drive
-- job callbacks by hand without spawning npx or opening a browser.
local M = {}

local originals = {}
local tempdir

function M.install()
  originals = {
    jobstart = vim.fn.jobstart,
    jobstop = vim.fn.jobstop,
    notify = vim.notify,
    open = vim.ui.open,
  }

  local jobs = { started = {}, stopped = {}, next_failure = nil }
  local notifications = {}
  -- Start well above any id a real jobstart/jobstop call in the same test process could
  -- return, so an assertion can't accidentally match a stray real job id.
  local next_id = 100

  vim.fn.jobstart = function(cmd, opts)
    if jobs.next_failure then
      local failure = jobs.next_failure
      jobs.next_failure = nil
      return failure
    end
    next_id = next_id + 1
    table.insert(jobs.started, { id = next_id, cmd = cmd, opts = opts })
    return next_id
  end
  -- The real jobstop() only sends SIGTERM; on_exit still arrives later, asynchronously, via
  -- the job's own on_exit callback. This stub mirrors that split: it just records the call,
  -- so specs must invoke `job.opts.on_exit(job.id, code)` themselves to simulate the exit.
  vim.fn.jobstop = function(id)
    table.insert(jobs.stopped, id)
    return 1
  end
  vim.notify = function(msg, level)
    table.insert(notifications, { msg = msg, level = level })
  end
  vim.ui.open = function() end

  tempdir = vim.fn.tempname()
  vim.fn.mkdir(tempdir, "p")

  return jobs, notifications
end

function M.restore()
  vim.fn.jobstart = originals.jobstart
  vim.fn.jobstop = originals.jobstop
  vim.notify = originals.notify
  vim.ui.open = originals.open
  vim.cmd("silent! %bwipeout!")
  if tempdir then
    vim.fn.delete(tempdir, "rf")
    tempdir = nil
  end
end

function M.tempfile(name)
  local path = tempdir .. "/" .. name
  vim.fn.writefile({ "openapi: 3.1.0" }, path)
  return path
end

function M.errors(notifications)
  return vim.tbl_filter(function(n)
    return n.level == vim.log.levels.ERROR
  end, notifications)
end

return M
