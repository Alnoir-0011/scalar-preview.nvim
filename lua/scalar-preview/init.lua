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

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

function M.start()
  local path = vim.fn.expand("%:p")

  -- Special buffers (terminal, help, quickfix, scratch, ...) and unnamed buffers either have
  -- no real file on disk or a path that doesn't mean what it looks like; refuse clearly
  -- instead of letting @scalar/cli fail later with a confusing "file not found".
  if vim.bo.buftype ~= "" or path == "" then
    vim.notify("ScalarPreview: no file to preview in this buffer", vim.log.levels.ERROR)
    return
  end

  if vim.fn.filereadable(path) == 0 then
    vim.notify("ScalarPreview: file does not exist on disk: " .. path, vim.log.levels.ERROR)
    return
  end

  if path == M.file_being_previewed then
    return
  end

  if M.job_id then
    M.stop()
  end

  -- The preview always reflects what's on disk, not the buffer's in-memory contents, so warn
  -- (but don't block) when they can currently differ.
  if vim.bo.modified then
    vim.notify("ScalarPreview: previewing the version on disk; unsaved changes aren't shown", vim.log.levels.WARN)
  end

  vim.fn.writefile({}, M.log_path)
  M.warned = false

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
    -- single warning instead. Lines that are purely cursor-visibility ANSI codes (the CLI's
    -- spinner) aren't real warnings, so strip those before deciding whether to notify. `npm
    -- warn` lines (EBADENGINE, deprecated subdependencies, ...) come from npx/npm itself, not
    -- from @scalar/cli, and show up on practically every run, so they're logged but don't
    -- trigger the notification either.
    on_stderr = function(_, data)
      vim.fn.writefile(data, M.log_path, "a")
      if not M.warned then
        for _, line in ipairs(data) do
          local stripped = line:gsub("\27%[%?25[lh]", "")
          if stripped:match("%S") and not stripped:lower():match("^npm warn") then
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
