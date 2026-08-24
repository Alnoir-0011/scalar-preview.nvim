if vim.g.loaded_scalar_preview then
  return
end
vim.g.loaded_scalar_preview = true

vim.api.nvim_create_user_command("ScalarPreview", function()
  require("scalar-preview").start()
end, {})

vim.api.nvim_create_user_command("ScalarPreviewStop", function()
  require("scalar-preview").stop()
end, {})

vim.api.nvim_create_user_command("ScalarPreviewToggle", function()
  require("scalar-preview").toggle()
end, {})
