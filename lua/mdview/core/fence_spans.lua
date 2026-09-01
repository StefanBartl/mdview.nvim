---@module 'mdview.core.fence_spans'
--- Collect the buffer's own syntax highlighting for fenced code blocks, so the
--- preview can paint them with exactly what Neovim shows instead of guessing
--- the language again with a JavaScript highlighter
--- (`browser.highlighter = "nvim"`).
---
--- The colors come from `color_my_ascii.nvim` through its public read-back API
--- (`color_my_ascii.highlight`), which returns the spans it painted plus their
--- resolved `#rrggbb`. That plugin is a **soft** dependency: without it there
--- are no spans, the payload is nil, and the client keeps using its JavaScript
--- highlighter — which is also what happens per block for a language
--- color_my_ascii does not paint (its `fence_language_map` covers 31 tags, so
--- that case is routine, not exceptional).
---
--- Wire format, kept compact because it rides every content push:
---
--- ```
--- { v = 1, blocks = { { line = <1-based source line of the block's FIRST
---   CONTENT line>, rows = { [i] = { { c = <1-based byte column>,
---   n = <byte length>, f = "#rrggbb", b/i/u/s = true, g = "#rrggbb" } } } } } }
--- ```
---
--- `line` addresses the first *content* line rather than the fence, because
--- that is what the client can compute for a `<pre>` without knowing whether
--- the block was fenced or indented (see `src/client/render/sourcePos.ts`).

local M = {}

--- Payload format version. The client refuses anything else rather than
--- guessing at a shape it does not know.
local VERSION = 1

--- color_my_ascii's public API, or nil when the plugin isn't installed.
---@return table|nil fences, table|nil highlight
local function api()
  local ok, cma = pcall(require, "color_my_ascii")
  if not ok or type(cma) ~= "table" then
    return nil, nil
  end
  local fences, highlight = cma.fences, cma.highlight
  if type(fences) ~= "table" or type(highlight) ~= "table" then
    return nil, nil -- an older color_my_ascii, before the read-back API
  end
  if type(fences.list_blocks) ~= "function" or type(highlight.runs_for_block) ~= "function" then
    return nil, nil
  end
  return fences, highlight
end

--- Turn one block's runs into the wire rows, or nil when the block carries no
--- highlighting at all — an unpainted block must fall through to the client's
--- own highlighter rather than being rendered flat.
---@param rows table[] runs per content row, from runs_for_block
---@param attrs_of fun(group: string): table memoized attribute resolution
---@return table[]|nil
local function rows_for(rows, attrs_of)
  local out = {}
  local painted = false
  for i, runs in ipairs(rows) do
    local spans = {}
    local col = 1 -- 1-based byte column, matching the renderer's own columns
    for _, run in ipairs(runs) do
      local len = #run.text
      if run.group and len > 0 then
        local a = attrs_of(run.group)
        if a.fg or a.bg or a.bold or a.italic or a.underline or a.strikethrough then
          painted = true
          spans[#spans + 1] = {
            c = col,
            n = len,
            f = a.fg,
            g = a.bg,
            b = a.bold,
            i = a.italic,
            u = a.underline,
            s = a.strikethrough,
          }
        end
      end
      col = col + len
    end
    out[i] = spans
  end
  if not painted then
    return nil
  end
  return out
end

--- The highlighting of every painted fenced block in `bufnr`.
---
--- Returns nil when there is nothing to send: no color_my_ascii, no fenced
--- blocks, or no block it painted. Nil means "leave the client's highlighter
--- alone", not "render these blocks blank".
---@param bufnr integer
---@return table|nil payload
function M.collect(bufnr)
  local fences, highlight = api()
  if not fences or not highlight then
    return nil
  end

  local ok, blocks = pcall(fences.list_blocks, bufnr)
  if not ok or type(blocks) ~= "table" or #blocks == 0 then
    return nil
  end

  -- One resolution per group per collect: a block of Lua hits the same dozen
  -- groups on every line, and this runs on every push.
  local cache = {}
  local function attrs_of(group)
    local a = cache[group]
    if a == nil then
      local resolved_ok, resolved = pcall(highlight.attrs_for_group, group)
      a = (resolved_ok and type(resolved) == "table") and resolved or {}
      cache[group] = a
    end
    return a
  end

  local out = {}
  for _, block in ipairs(blocks) do
    local runs_ok, runs = pcall(highlight.runs_for_block, bufnr, block)
    if runs_ok and type(runs) == "table" then
      local rows = rows_for(runs, attrs_of)
      if rows then
        out[#out + 1] = { line = block.content_start + 1, rows = rows }
      end
    end
  end

  if #out == 0 then
    return nil
  end
  return { v = VERSION, blocks = out }
end

--- Collect `bufnr`'s fence highlighting and push it to `key`'s room.
---
--- A no-op unless `browser.highlighter` is "nvim": collecting walks every
--- fenced block on every push, and nothing else consumes the result. Sends
--- `null` when there is nothing to paint, so a tab that had spans and no longer
--- should drops back to its own highlighter instead of keeping stale colors.
---@param bufnr integer
---@param key string # room key the tab watches
---@return nil
function M.push(bufnr, key)
  if require("mdview.config.browser").defaults.highlighter ~= "nvim" then
    return
  end
  if type(key) ~= "string" or key == "" then
    return
  end
  local payload = M.collect(bufnr)
  local json = nil
  if payload then
    local ok, encoded = pcall(vim.json.encode, payload)
    json = ok and encoded or nil
  end
  require("mdview.adapter.ws_client").send_spans(key, json)
end

return M
