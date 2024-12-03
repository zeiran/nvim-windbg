
vim.g.my_project="nvim-windbg"
vim.cmd.cd(vim.fn.expand('<script>:h:p'))

local test_term = nil
function TestInTerm()
    vim.cmd.wall()
    pcall(vim.api.nvim_buf_delete, test_term, {force=true})
    test_term = vim.api.nvim_create_buf(true, true)
    vim.cmd(test_term..'b')
    vim.fn.termopen('nvim.exe -l test\\test.lua')
    vim.api.nvim_buf_set_name(test_term, '[TEST]')
end

vim.cmd.edit('test/test.lua')
vim.cmd.edit('lua/windbg.lua')

