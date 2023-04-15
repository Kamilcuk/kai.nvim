---@class Indicator
---@field buffer {}
---@field accumulated_text string
---@field start_row integer
---@field start_col integer
---@field end_row integer
---@field end_col integer
local Indicator = {}
Indicator.__index = Indicator

function Indicator:new(buffer, start_row, start_col, end_row, end_col)
    local o = setmetatable({
        buffer = buffer,
        accumulated_text = "",
        start_row = start_row,
        start_col = start_col,
        end_row = end_row,
        end_col = end_col
    }, Indicator)
    return o
end

function Indicator:set_text()
    local lines = vim.split(self.accumulated_text, "\n")
    vim.api.nvim_buf_set_text(self.buffer, self.start_row, self.start_col,
                              self.end_row, self.end_col, lines)
    self.end_row = self.start_row + #lines - 1
    self.end_col = lines[#lines]:len()
    vim.api.nvim_win_set_cursor(0, {self.end_row + 1, self.end_col})
end

---@param data string
function Indicator:add_preview_text(data)
    self.accumulated_text = self.accumulated_text .. data
    self:set_text()
    vim.api.nvim_command("redraw")
end

return Indicator
