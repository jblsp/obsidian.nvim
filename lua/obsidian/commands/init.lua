local iter = require("obsidian.itertools").iter
local log = require "obsidian.log"
local legacycommands = require "obsidian.commands.init-legacy"

local command_lookups = {
  check = "obsidian.commands.check",
  togglecheckbox = "obsidian.commands.toggle_checkbox",
  today = "obsidian.commands.today",
  yesterday = "obsidian.commands.yesterday",
  tomorrow = "obsidian.commands.tomorrow",
  dailies = "obsidian.commands.dailies",
  new = "obsidian.commands.new",
  open = "obsidian.commands.open",
  backlinks = "obsidian.commands.backlinks",
  search = "obsidian.commands.search",
  tags = "obsidian.commands.tags",
  template = "obsidian.commands.template",
  newfromtemplate = "obsidian.commands.new_from_template",
  quickswitch = "obsidian.commands.quick_switch",
  linknew = "obsidian.commands.link_new",
  link = "obsidian.commands.link",
  links = "obsidian.commands.links",
  followlink = "obsidian.commands.follow_link",
  workspace = "obsidian.commands.workspace",
  rename = "obsidian.commands.rename",
  pasteimg = "obsidian.commands.paste_img",
  extractnote = "obsidian.commands.extract_note",
  debug = "obsidian.commands.debug",
  toc = "obsidian.commands.toc",
}

local M = setmetatable({
  commands = {},
}, {
  __index = function(t, k)
    local require_path = command_lookups[k]
    if not require_path then
      return
    end

    local mod = require(require_path)
    t[k] = mod

    return mod
  end,
})

---@class obsidian.CommandConfig
---@field complete function|string|?
---@field nargs string|integer|?
---@field range boolean|?
---@field func function|? (obsidian.Client, table) -> nil

---Register a new command.
---@param name string
---@param config obsidian.CommandConfig
M.register = function(name, config)
  if not config.func then
    config.func = function(client, data)
      return M[name](client, data)
    end
  end
  M.commands[name] = config
end

---Install all commands.
---
---@param client obsidian.Client
M.install = function(client)
  vim.api.nvim_create_user_command("Obsidian", function(data)
    M.handle_command(client, data)
  end, {
    nargs = "+",
    complete = function(_, cmdline, _)
      return M.get_completions(client, cmdline)
    end,
    range = 2,
  })
end

M.install_legacy = legacycommands.install

---@param client obsidian.Client
M.handle_command = function(client, data)
  local cmd = data.fargs[1]
  table.remove(data.fargs, 1)
  data.args = table.concat(data.fargs, " ")
  local nargs = #data.fargs

  local cmdconfig = M.commands[cmd]
  if cmdconfig == nil then
    log.err("Command '" .. cmd .. "' not found")
    return
  end

  local exp_nargs = cmdconfig.nargs
  local range_allowed = cmdconfig.range

  if exp_nargs == "?" then
    if nargs > 1 then
      log.err("Command '" .. cmd .. "' expects 0 or 1 arguments, but " .. nargs .. " were provided")
      return
    end
  elseif exp_nargs == "+" then
    if nargs == 0 then
      log.err("Command '" .. cmd .. "' expects at least one argument, but none were provided")
      return
    end
  elseif exp_nargs ~= "*" and exp_nargs ~= nargs then
    log.err("Command '" .. cmd .. "' expects " .. exp_nargs .. " arguments, but " .. nargs .. " were provided")
    return
  end

  if not range_allowed and data.range > 0 then
    log.error("Command '" .. cmd .. "' does not accept a range")
    return
  end

  cmdconfig.func(client, data)
end

---@param client obsidian.Client
---@param cmdline string
M.get_completions = function(client, cmdline)
  local obspat = "^['<,'>]*Obsidian[!]?"
  local splitcmd = vim.split(cmdline, " ", { plain = true, trimempty = true })
  local obsidiancmd = splitcmd[2]
  if cmdline:match(obspat .. "%s$") then
    return vim.tbl_keys(M.commands)
  end
  if cmdline:match(obspat .. "%s%S+$") then
    return vim.tbl_filter(function(s)
      return s:sub(1, #obsidiancmd) == obsidiancmd
    end, vim.tbl_keys(M.commands))
  end
  local cmdconfig = M.commands[obsidiancmd]
  if cmdconfig == nil then
    return
  end
  if cmdline:match(obspat .. "%s%S*%s%S*$") then
    local cmd_arg = table.concat(vim.list_slice(splitcmd, 3), " ")
    local complete_type = type(cmdconfig.complete)
    if complete_type == "function" then
      return cmdconfig.complete(client, cmd_arg)
    end
    if complete_type == "string" then
      return vim.fn.getcompletion(cmd_arg, cmdconfig.complete)
    end
  end
end

--TODO: Note completion is currently broken (see: https://github.com/epwalsh/obsidian.nvim/issues/753)
---@param client obsidian.Client
---@return string[]
M.note_complete = function(client, cmd_arg)
  local query
  if string.len(cmd_arg) > 0 then
    if string.find(cmd_arg, "|", 1, true) then
      return {}
    else
      query = cmd_arg
    end
  else
    local _, csrow, cscol, _ = unpack(assert(vim.fn.getpos "'<"))
    local _, cerow, cecol, _ = unpack(assert(vim.fn.getpos "'>"))
    local lines = vim.fn.getline(csrow, cerow)
    assert(type(lines) == "table")

    if #lines > 1 then
      lines[1] = string.sub(lines[1], cscol)
      lines[#lines] = string.sub(lines[#lines], 1, cecol)
    elseif #lines == 1 then
      lines[1] = string.sub(lines[1], cscol, cecol)
    else
      return {}
    end

    query = table.concat(lines, " ")
  end

  local completions = {}
  local query_lower = string.lower(query)
  for note in iter(client:find_notes(query, { search = { sort = true } })) do
    local note_path = assert(client:vault_relative_path(note.path, { strict = true }))
    if string.find(string.lower(note:display_name()), query_lower, 1, true) then
      table.insert(completions, note:display_name() .. "  " .. note_path)
    else
      for _, alias in pairs(note.aliases) do
        if string.find(string.lower(alias), query_lower, 1, true) then
          table.insert(completions, alias .. "  " .. note_path)
          break
        end
      end
    end
  end

  return completions
end

M.register("check", { nargs = 0 })

M.register("today", { nargs = "?" })

M.register("yesterday", { nargs = 0 })

M.register("tomorrow", { nargs = 0 })

M.register("dailies", { nargs = "*" })

M.register("new", { nargs = "?", complete = "file" })

M.register("open", { nargs = "?", complete = M.note_complete })

M.register("backlinks", { nargs = 0 })

M.register("tags", { nargs = "*", range = true })

M.register("search", { nargs = "?" })

M.register("template", { nargs = "?" })

M.register("newfromtemplate", { nargs = "?" })

M.register("quickswitch", { nargs = "?" })

M.register("linknew", { nargs = "?", range = true })

M.register("link", { nargs = "?", range = true, complete = M.note_complete })

M.register("links", { nargs = 0 })

M.register("followlink", { nargs = "?" })

M.register("togglecheckbox", { nargs = 0 })

M.register("workspace", { nargs = "?" })

M.register("rename", { nargs = "?", complete = "file" })

M.register("pasteimg", { nargs = "?", complete = "file" })

M.register("extractnote", { nargs = "?", range = true })

M.register("debug", { nargs = 0 })

M.register("toc", { nargs = 0 })

return M
