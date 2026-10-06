local M = {}

M.config = {
  port = 8000,
  host = "localhost",
}

M.job_id = nil
M.stopped_jobs = {}
M.file_being_previewed = nil
M.log_path = vim.fn.stdpath("state") .. "/scalar-preview.log"
M.warned = false
M.stderr_tail = ""

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- If a guard below refuses to (re)start, say so plainly, and if a previous preview is still
-- running say that too: refusing doesn't stop it, so whatever it's serving (see the note on
-- $ref in README's "Known limitations") stays reachable on the network regardless. `path` is
-- the file the current call is refusing to (re)start on, so when it's the very file already
-- being previewed (e.g. it was deleted out from under a still-running preview), say that
-- explicitly instead of the generic "previous preview of <same file> is still running", which
-- reads as if two different files were involved.
local function notify_refused(reason, path)
  local suffix = ""
  if M.job_id then
    if path ~= nil and path == M.file_being_previewed then
      suffix = " (the running preview of this file is unaffected and keeps serving its last-known contents)"
    else
      suffix = " (previous preview of " .. M.file_being_previewed .. " is still running)"
    end
  end
  vim.notify("ScalarPreview: " .. reason .. suffix, vim.log.levels.ERROR)
end

function M.start()
  local path = vim.fn.expand("%:p")

  if path == "" then
    notify_refused("no file to preview in this buffer (unnamed buffer)", nil)
    return
  end

  -- Special buffers (terminal, help, quickfix, scratch, ...) have a 'buftype', and while some
  -- of them do point at a real file on disk, serving it generally isn't what was intended.
  if vim.bo.buftype ~= "" then
    notify_refused("no file to preview in this buffer (buftype=" .. vim.bo.buftype .. ")", path)
    return
  end

  if vim.fn.filereadable(path) == 0 then
    notify_refused("file is not readable on disk: " .. path, path)
    return
  end

  -- The preview always reflects what's on disk, not the buffer's in-memory contents, so warn
  -- (but don't block) whenever they can currently differ -- including when :ScalarPreview is
  -- called again on the file it's already previewing, since the warning is about the buffer
  -- being out of sync with disk right now, not about (re)starting the job below.
  if vim.bo.modified then
    vim.notify("ScalarPreview: previewing the version on disk; unsaved changes aren't shown", vim.log.levels.WARN)
  end

  if path == M.file_being_previewed then
    return
  end

  if M.job_id then
    M.stop()
  end

  vim.fn.writefile({}, M.log_path)
  M.warned = false
  -- on_stderr's data may split a single line across multiple calls (see the comment there);
  -- this holds whatever's been received so far of the not-yet-newline-terminated last line.
  M.stderr_tail = ""

  -- @scalar/cli's watchFile does `path.join(process.cwd(), file)` without checking whether
  -- `file` is already absolute, so an absolute path gets double-prefixed with cwd and always
  -- "does not exist". Run with cwd = the file's own directory and pass just the basename so
  -- that join produces the right path regardless of Neovim's cwd.
  local dir = vim.fn.fnamemodify(path, ":h")
  local basename = vim.fn.fnamemodify(path, ":t")
  local cmd =
    string.format("npx --yes @scalar/cli document serve %s -w -p %d", vim.fn.shellescape(basename), M.config.port)

  local id = vim.fn.jobstart(cmd, {
    cwd = dir,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line:find("listening on") then
          vim.ui.open(string.format("http://%s:%d", M.config.host, M.config.port))
        end
      end
    end,
    -- Multi-line stack traces come through as one on_stderr line per frame; notifying each
    -- individually floods the UI with dozens of popups, so log them to a file and surface a
    -- single warning instead. Lines that are purely cursor-visibility or color ANSI codes
    -- (the CLI's spinner, or `npm`'s own colored output if the user has `color=always` in
    -- their npmrc) aren't real warnings on their own, so strip those before deciding whether
    -- to notify. Specific `npm warn` lines we know are just noise (EBADENGINE, deprecated
    -- subdependencies) are logged but don't trigger the notification either -- but anything
    -- else from npm, e.g. `npm warn tarball ... corrupted`, still does, since blanket-ignoring
    -- every `npm warn` line would silently swallow ones actually worth seeing.
    on_stderr = function(id, data)
      -- Ignore a stale job: jobstop() only sends SIGTERM and doesn't guarantee immediate
      -- termination, so a fast restart (switching the file being previewed) can have the old
      -- job's trailing stderr arrive after M.job_id already points at the new job. Without
      -- this check, M.warned and the just-truncated M.log_path (see M.start()) would end up
      -- mixing the old and new jobs' output and incorrectly suppressing/triggering the new
      -- job's own notification.
      if id ~= M.job_id then
        return
      end

      -- on_stderr's `data` may split a single line across multiple calls, so a line like
      -- "npm warn EBADENGINE ..." could otherwise arrive as "npm wa" then "rn EBADENGINE ...",
      -- with the first half failing the `npm warn` match below and wrongly triggering the
      -- notification. Per :help channel-lines: every element but the last in `data` is a
      -- complete line; the last one may still be partial unless this call is EOF (`data` is
      -- exactly `{ "" }`), so only the confirmed-complete ones are processed each time.
      local eof = #data == 1 and data[1] == ""
      data = { M.stderr_tail .. data[1], unpack(data, 2) }
      local complete_lines = data
      if not eof then
        complete_lines = { unpack(data, 1, #data - 1) }
        M.stderr_tail = data[#data]
      end
      if #complete_lines == 0 then
        return
      end

      vim.fn.writefile(complete_lines, M.log_path, "a")
      if not M.warned then
        for _, line in ipairs(complete_lines) do
          local stripped = line:gsub("\27%[[%d:;?]*[a-zA-Z]", ""):gsub("\27%][^\7]*\7", "")
          local is_noisy_npm_warning = stripped:lower():match("^npm warn ebadengine")
            or stripped:lower():match("^npm warn deprecated")
          if stripped:match("%S") and not is_noisy_npm_warning then
            M.warned = true
            vim.notify("ScalarPreview: warnings in output, see " .. M.log_path, vim.log.levels.WARN)
            break
          end
        end
      end
    end,
    -- on_exit fires asynchronously, so after a restart the old job's exit can arrive once
    -- the new job is already running. Only clear state that still belongs to this job. We
    -- suppress the error notification purely based on whether *we* called stop() for this
    -- job id, not the exit code (SIGTERM is 143 on POSIX, but jobstop()'s behavior on
    -- Windows isn't guaranteed to match), so a deliberate stop never reports as a failure
    -- regardless of platform.
    on_exit = function(id, code)
      local stopped = M.stopped_jobs[id]
      M.stopped_jobs[id] = nil
      if code ~= 0 and not stopped then
        vim.notify("ScalarPreview exited with code " .. code, vim.log.levels.ERROR)
      end
      if M.job_id == id then
        M.job_id = nil
        M.file_being_previewed = nil
      end
    end,
  })

  -- jobstart returns 0 (invalid arguments) or -1 (cmd[0]/'shell' not executable) on failure.
  -- With a string {cmd} this practically can't happen from a missing `npx` (the shell itself
  -- starts fine; a missing command surfaces later as a nonzero on_exit), but it can occur if
  -- the job table is full or 'shell' is misconfigured, and either return value is truthy in
  -- Lua, so an unguarded assignment below would treat a failed start as a running job id and
  -- leave an orphaned M.stopped_jobs entry if stop() is ever called for it.
  if id <= 0 then
    vim.notify("ScalarPreview: failed to start (jobstart returned " .. id .. ")", vim.log.levels.ERROR)
    return
  end

  M.job_id = id
  M.file_being_previewed = path
end

function M.stop()
  if M.job_id then
    M.stopped_jobs[M.job_id] = true
    vim.fn.jobstop(M.job_id)
  end
  M.job_id = nil
  M.file_being_previewed = nil
end

function M.toggle()
  if M.job_id then
    M.stop()
  else
    M.start()
  end
end

return M
