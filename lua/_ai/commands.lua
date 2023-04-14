local M = {}

local openai = require("_ai/openai")
local config = require("_ai/config")
local Indicator = require("_ai/indicator")

local function get_row_length(buffer, num)
    return vim.api.nvim_buf_get_lines(buffer, num, num + 1, true)[1]:len()
end

-- Get the text from the buffer between the start and end points.
local function buffer_get_text(buffer, start_row, start_col, end_row, end_col)
    return table.concat(vim.api.nvim_buf_get_text(buffer, start_row, start_col,
                                                  end_row, end_col, {}), "\n")
end

---@param args { args: string, range: integer, line1: integer, line2: integer, bang: boolean }
function M.ai(args)
    -- print(vim.inspect(args))
    local prompt = args.args
    local visual_mode = args.range > 0

    local buffer = vim.api.nvim_get_current_buf()

    local start_row, start_col
    local end_row, end_col
    if visual_mode then
        -- Use the visual selection
        start_row, start_col = unpack(vim.api.nvim_buf_get_mark(buffer, "<"))
        if start_row == 0 and args.range == 2 then
            -- No visual selection, but called in range mode.
            start_row = args.line1 - 1
            start_col = 0
            end_row = args.line2 - 1
            end_col = get_row_length(buffer, end_row)
        else
            start_row = start_row - 1
            end_row, end_col = unpack(vim.api.nvim_buf_get_mark(buffer, ">"))
            end_row = end_row - 1
        end
    else
        -- Use the cursor position
        start_row, start_col = unpack(vim.api.nvim_win_get_cursor(0))
        start_row = start_row - 1
        start_col = start_col + 1
        end_row = start_row
        end_col = start_col
    end

    -- Limit col positions, nvim_buf_get_mark outputs end of universe.
    local start_line_length = get_row_length(buffer, start_row)
    start_col = math.min(start_col, start_line_length)
    local end_line_length = get_row_length(buffer, end_row)
    end_col = math.min(end_col, end_line_length)

    -- print("AA", start_row, start_col, end_row, end_col)

    local indicator = Indicator:new(buffer, start_row, start_col, end_row,
                                    end_col)
    local accumulated_text = ""
    local callbacks = {
        on_data = function(data)
            accumulated_text = accumulated_text .. data
            vim.schedule(function()
                indicator:set_preview_text(accumulated_text)
                vim.api.nvim_command("redraw")
            end)
        end,
        on_complete = function()
            vim.schedule(function()
                indicator:set_buffer_text(accumulated_text)
                indicator:finish()
                vim.api.nvim_command("redraw")
            end)
        end,
        on_error = function(err)
            vim.schedule(function()
                vim.api.nvim_err_writeln("ai.vim: " .. err)
                indicator:finish()
                vim.api.nvim_command("redraw")
            end)
        end
    }

    if visual_mode then
        local selected_text = buffer_get_text(buffer, start_row, start_col,
                                              end_row, end_col)
        if prompt == "" then
            -- Replace the selected text, also using it as a prompt.
            openai.completions({prompt = selected_text}, callbacks)
        else
            -- Edit selected text
            openai.edits({input = selected_text, instruction = prompt},
                         callbacks)
        end
    else
        if not args.bang then
            -- Insert some text generated using surrounding context.
            local start_row_before = math.max(0,
                                              start_row - config.context_before)
            local prefix = buffer_get_text(buffer, start_row_before, 0,
                                           start_row, start_col)
            local line_count = vim.api.nvim_buf_line_count(buffer)
            local end_row_after = math.min(end_row + config.context_after,
                                           line_count - 1)
            local suffix = buffer_get_text(buffer, end_row, end_col,
                                           end_row_after, get_row_length(buffer,
                                                                         end_row_after))
            if prompt then
                -- Pass prompt with the prefix.
                prompt = prefix .. "\n\n" .. prompt
            else
                prompt = prefix
            end
            openai.completions({prompt = prompt, suffix = suffix}, callbacks)
        else
            -- Insert text generated from executing the prompt.
            if not prompt then
                vim.api.nvim_err_writeln("ai.vim: empty prompt")
            else
                openai.completions({prompt = prompt}, callbacks)
            end
        end
    end
end

return M
