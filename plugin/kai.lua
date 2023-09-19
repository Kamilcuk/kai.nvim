-- kai.lua
if vim.g.kai_loaded then
    return
end
vim.g.kai_loaded = true

require("kai").setup()
