local M = {}
M.__index = M

local config = require("_ai/config")

local ns_id = vim.api.nvim_create_namespace("_ai")

local function get_default_extmark_opts()
    local extmark_opts = {
        hl_group = "AIHighlight"
        -- right_gravity = false,
        -- end_right_gravity = true,
    }
    if config.indicator_style ~= "none" then
        extmark_opts.sign_text = config.indicator_text
        extmark_opts.sign_hl_group = "AIIndicator"
    end
    return extmark_opts
end

function M:new(buffer, start_row, start_col, end_row, end_col)
    local extmark_opts = get_default_extmark_opts()
    if end_row ~= start_row or end_col ~= start_col then
        extmark_opts.end_row = end_row
        extmark_opts.end_col = end_col
    end
    local extmark_id = vim.api.nvim_buf_set_extmark(buffer, ns_id, start_row,
                                                    start_col, extmark_opts)
    return setmetatable({buffer = buffer, extmark_id = extmark_id}, M)
end

function M:get()
    if not self.extmark_id then return nil end
    return vim.api.nvim_buf_get_extmark_by_id(self.buffer, ns_id,
                                              self.extmark_id, {details = true})
end

function M:set_preview_text(text)
    local extmark = self:get()
    if not extmark then return end
    local start_row = extmark[1]
    local start_col = extmark[2]

    if extmark[3].end_row or extmark[3].end_col then
        return -- We don't support preview text on indicators over a range
    end

    local extmark_opts = get_default_extmark_opts()
    extmark_opts.id = self.extmark_id
    extmark_opts.virt_text_pos = "overlay"

    local lines = vim.split(text, "\n")
    extmark_opts.virt_text = {{lines[1], "Comment"}}

    if #lines > 1 then
        extmark_opts.virt_lines = vim.tbl_map(function(line)
            return {{line, "Comment"}}
        end, vim.list_slice(lines, 2))
    end
    vim.api.nvim_buf_set_extmark(self.buffer, ns_id, start_row, start_col,
                                 extmark_opts)
end

function M:set_buffer_text(text)
    local extmark = self:get()
    if not extmark then return end
    local start_row = extmark[1]
    local start_col = extmark[2]

    local end_row = extmark[3].end_row
    if not end_row then end_row = start_row end

    local end_col = extmark[3].end_col
    if not end_col then end_col = start_col end

    local lines = vim.split(text, "\n")
    vim.api.nvim_buf_set_text(self.buffer, start_row, start_col, end_row,
                              end_col, lines)
end

function M:finish()
    if self.extmark_id then
        vim.api.nvim_buf_del_extmark(self.buffer, ns_id, self.extmark_id)
    end
    self.extmark_id = nil
end

return M
