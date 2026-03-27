-- SSL-format smartlog parser for Sapling VCS
-- Parses `sl smartlog -T '{ssl}'` output into classified lines with
-- commit metadata, highlights, and a line map.
--
-- Unlike the pipe-delimited parser (smartlog.lua), this module works with
-- the raw ssl display format where graph characters are prepended by the
-- Sapling graph engine and fields are separated by double spaces.

local M = {}

-- SSL template for use with sl smartlog -T
M.SSL_TEMPLATE = "{ssl}"

---@class SslCommit
---@field node string 10-char hex hash
---@field graphnode string Graph character (o, @, x, possibly with * suffix)
---@field date string Relative or absolute date
---@field author string|nil Author (nil for public commits)
---@field desc string|nil Commit message (set on commit_message lines, nil on header)
---@field phabdiff string|nil e.g., "D92670841"
---@field phabstatus string|nil e.g., "Accepted", "Needs Review"
---@field signal string|nil "✓" or "✗"
---@field local_changes boolean Whether "(local changes)" is present
---@field remote_bookmarks string[] Remote bookmark names
---@field is_public boolean Whether this is a public commit

---@class SslParsedLine
---@field type "commit_header"|"commit_message"|"graph_only"
---@field raw string The original line
---@field graph_prefix string The graph prefix portion
---@field content string Content after graph prefix
---@field commit SslCommit|nil Commit data (for commit_header and commit_message)

--- Classify a single ssl output line
---@param line string
---@param prev_commit SslCommit|nil The most recent commit header's data
---@return SslParsedLine
function M.classify_line(line, prev_commit)
  -- Empty/nil line
  if not line or line == "" then
    return { type = "graph_only", raw = line or "", graph_prefix = "", content = "" }
  end

  -- Try to find graphnode + hash pattern
  -- Pattern: {any graph prefix}{graphnode: o|@|x|O possibly with *}{2 spaces}{hex hash (8-12 chars)}{optional annotation}{2 spaces}{metadata}
  -- Broadened graphnode set and flexible hash length for robustness
  -- Some commits have annotations like "(Not backed up)" between hash and metadata
  local prefix, graphnode, hash, metadata = line:match("^(.-)([o@xO]%*?)  (%x%x%x%x%x%x%x%x%x?%x?%x?%x?)  (.+)$")

  -- Fallback: hash followed by parenthesized annotation then double-space metadata
  -- e.g. "@ e5c143173d (Not backed up)  Monday at 15:59  vmakaev"
  if not hash then
    local p, gn, h, annotation, md = line:match("^(.-)([o@xO]%*?)  (%x%x%x%x%x%x%x%x%x?%x?%x?%x?) (%b())  (.+)$")
    if h then
      prefix, graphnode, hash = p, gn, h
      -- Prepend annotation to metadata so parse_commit_metadata can handle it
      metadata = annotation .. "  " .. md
    end
  end

  -- Fallback: try matching with single space separators (some Sapling configs)
  if not hash then
    prefix, graphnode, hash, metadata = line:match("^(.-)([o@xO]%*?) (%x%x%x%x%x%x%x%x%x?%x?%x?%x?)  (.+)$")
  end

  if hash then
    -- This is a commit header line
    local commit = M.parse_commit_metadata(hash, graphnode, metadata)
    return {
      type = "commit_header",
      raw = line,
      graph_prefix = prefix,
      content = line:sub(#prefix + 1),
      commit = commit,
    }
  end

  -- Also check for commit header with no metadata after hash (public anchor with just date)
  -- Pattern: {prefix}{graphnode}{2 spaces}{10 hex}{2 spaces}{date-only at end}
  -- The main pattern already handles this IF metadata is present. But if the line ends right
  -- after a minimal metadata, the (.+) pattern requires at least one char, which is fine.
  -- However, we also need to check a pattern where hash is followed by 2 spaces + remaining text
  -- that doesn't have further double-space separators. The (.+) match above handles that.

  -- Not a commit header — check if it has content after graph characters
  -- Graph-only lines contain only graph characters (Unicode box-drawing) and whitespace
  -- Strategy: Remove 3-byte UTF-8 sequences, then remove known ASCII graph chars and whitespace
  -- If nothing remains, it's graph-only
  local stripped = line
  -- Remove 3-byte UTF-8 sequences (all Unicode box-drawing chars are 3 bytes)
  stripped = stripped:gsub("[\xc0-\xff][\x80-\xbf]+", "")
  -- Remove known ASCII graph characters and whitespace
  stripped = stripped:gsub("[|/\\~%s]", "")

  if #stripped == 0 then
    return { type = "graph_only", raw = line, graph_prefix = line, content = "" }
  else
    return {
      type = "commit_message",
      raw = line,
      graph_prefix = "",
      content = line,
      commit = prev_commit,
    }
  end
end

--- Parse metadata portion of a commit header line
---@param hash string 10-char hex hash
---@param graphnode string o, @, x (possibly with * suffix)
---@param metadata string Everything after the hash + double-space
---@return SslCommit
function M.parse_commit_metadata(hash, graphnode, metadata)
  -- Strip leading parenthesized annotations like "(Not backed up)" from metadata
  metadata = metadata:gsub("^%b()  ", "")

  local commit = {
    node = hash,
    graphnode = graphnode,
    date = "",
    author = nil,
    desc = nil,
    phabdiff = nil,
    phabstatus = nil,
    signal = nil,
    local_changes = false,
    remote_bookmarks = {},
    is_public = false,
  }

  -- Strip (local changes) from end if present
  if metadata:match("%(local changes%)") then
    commit.local_changes = true
    metadata = metadata:gsub("%s*%(local changes%)%s*$", "")
  end

  -- Strip signal status (✓ or ✗) from end if present
  -- ✓ = \xe2\x9c\x93, ✗ = \xe2\x9c\x97
  local signal_match = metadata:match("[\xe2][\x9c][\x93\x97]%s*$")
  if signal_match then
    commit.signal = vim.trim(signal_match)
    metadata = metadata:gsub("%s*[\xe2][\x9c][\x93\x97]%s*$", "")
  end

  -- Check for remote/ bookmarks (public commit pattern)
  if metadata:match("remote/") then
    -- Public commit with bookmarks: "Today at 03:55  remote/master"
    local date_part, bookmarks_part = metadata:match("^(.-)  (remote/.+)$")
    if date_part and bookmarks_part then
      commit.date = date_part
      commit.is_public = true
      for bm in bookmarks_part:gmatch("%S+") do
        table.insert(commit.remote_bookmarks, bm)
      end
      return commit
    end
  end

  -- Split by double-space to get fields
  local fields = vim.split(metadata, "  ", { plain = true, trimempty = true })

  if #fields >= 1 then
    commit.date = fields[1]
  end

  -- If only 1 field (just date), it's a public anchor commit
  if #fields == 1 then
    commit.is_public = true
    return commit
  end

  -- Draft commit: date  author  [phabdiff phabstatus]
  if #fields >= 2 then
    commit.author = fields[2]
  end

  -- Parse phabricator diff + status from remaining fields
  if #fields >= 3 then
    local phab_part = fields[3]
    local diff_id = phab_part:match("^(D%d+)")
    if diff_id then
      commit.phabdiff = diff_id
      local status = phab_part:sub(#diff_id + 1)
      status = vim.trim(status)
      if status and status ~= "" then
        commit.phabstatus = status
      end
    end
  end

  return commit
end

--- Add highlights for a commit header line
---@param highlights table[] Highlight accumulator
---@param line_0idx number 0-indexed line number
---@param line string The raw line text
---@param commit SslCommit Parsed commit data
local function add_commit_highlights(highlights, line_0idx, line, commit)
  -- Full-line background highlight for current commit (@)
  if commit.graphnode == "@" then
    table.insert(highlights, {
      line = line_0idx,
      col_start = 0,
      col_end = 0,
      hl = "NeoSaplingCurrentLine",
      line_hl_group = "NeoSaplingCurrentLine",
    })
  end

  -- Find hash position (byte offsets from string.find, 1-indexed)
  local hash_start, hash_end = line:find(commit.node, 1, true)
  if hash_start then
    table.insert(highlights, {
      line = line_0idx,
      col_start = hash_start - 1,
      col_end = hash_end,
      hl = commit.graphnode == "@" and "NeoSaplingCurrent" or "NeoSaplingHash",
    })
  end

  -- Find date position (search after hash to avoid false matches)
  if commit.date and commit.date ~= "" then
    local date_start, date_end = line:find(commit.date, (hash_end or 0) + 1, true)
    if date_start then
      table.insert(highlights, {
        line = line_0idx,
        col_start = date_start - 1,
        col_end = date_end,
        hl = "NeoSaplingDate",
      })
    end
  end

  -- Find author
  if commit.author then
    local search_from = 1
    -- Search after date to avoid matching author substring in other fields
    if commit.date and commit.date ~= "" then
      local _, date_end_pos = line:find(commit.date, 1, true)
      if date_end_pos then
        search_from = date_end_pos + 1
      end
    end
    local author_start, author_end = line:find(commit.author, search_from, true)
    if author_start then
      table.insert(highlights, {
        line = line_0idx,
        col_start = author_start - 1,
        col_end = author_end,
        hl = "NeoSaplingAuthor",
      })
    end
  end

  -- Find phabdiff
  if commit.phabdiff then
    local phab_start, phab_end = line:find(commit.phabdiff, 1, true)
    if phab_start then
      table.insert(highlights, {
        line = line_0idx,
        col_start = phab_start - 1,
        col_end = phab_end,
        hl = "NeoSaplingPhabDiff",
      })
    end
  end

  -- Find phabstatus
  if commit.phabstatus then
    local status_start, status_end = line:find(commit.phabstatus, 1, true)
    if status_start then
      table.insert(highlights, {
        line = line_0idx,
        col_start = status_start - 1,
        col_end = status_end,
        hl = "NeoSaplingPhabStatus",
      })
    end
  end

  -- Find signal
  if commit.signal then
    local sig_start, sig_end = line:find(commit.signal, 1, true)
    if sig_start then
      local sig_hl = "NeoSaplingSignalPass"
      -- ✗ = \xe2\x9c\x97
      if commit.signal:byte(3) == 0x97 then
        sig_hl = "NeoSaplingSignalFail"
      end
      table.insert(highlights, {
        line = line_0idx,
        col_start = sig_start - 1,
        col_end = sig_end,
        hl = sig_hl,
      })
    end
  end

  -- Find (local changes)
  if commit.local_changes then
    local lc_start, lc_end = line:find("(local changes)", 1, true)
    if lc_start then
      table.insert(highlights, {
        line = line_0idx,
        col_start = lc_start - 1,
        col_end = lc_end,
        hl = "NeoSaplingLocalChanges",
      })
    end
  end

  -- Find remote bookmarks
  for _, bm in ipairs(commit.remote_bookmarks) do
    local bm_start, bm_end = line:find(bm, 1, true)
    if bm_start then
      table.insert(highlights, {
        line = line_0idx,
        col_start = bm_start - 1,
        col_end = bm_end,
        hl = "NeoSaplingBranch",
      })
    end
  end
end

--- Add highlights for a commit message line
---@param highlights table[] Highlight accumulator
---@param line_0idx number 0-indexed line number
---@param line string The raw line text
---@param commit SslCommit|nil Commit associated with this message line
local function add_message_highlights(highlights, line_0idx, line, commit)
  -- Full-line background highlight for current commit (@) message lines
  if commit and commit.graphnode == "@" then
    table.insert(highlights, {
      line = line_0idx,
      col_start = 0,
      col_end = 0,
      hl = "NeoSaplingCurrentLine",
      line_hl_group = "NeoSaplingCurrentLine",
    })
  end

  -- Find the start of actual message content (after graph prefix)
  -- Graph prefix consists of Unicode box-drawing chars + spaces
  -- Find first non-graph, non-space character
  local content_start = 1
  local i = 1
  while i <= #line do
    local byte = line:byte(i)
    if byte >= 0xC0 then
      -- Multi-byte UTF-8 sequence - skip it (graph character)
      if byte >= 0xF0 then
        i = i + 4
      elseif byte >= 0xE0 then
        i = i + 3
      else
        i = i + 2
      end
    elseif byte == 0x20 or byte == 0x7C or byte == 0x2F or byte == 0x5C or byte == 0x7E then
      -- space, |, /, \, ~
      i = i + 1
    else
      -- Found content start
      content_start = i
      break
    end
  end

  if content_start <= #line then
    table.insert(highlights, {
      line = line_0idx,
      col_start = content_start - 1,
      col_end = #line,
      hl = "NeoSaplingDesc",
    })
  end
end

--- Build classified lines, highlights, and line map from ssl output
---@param ssl_lines string[] Raw lines from sl smartlog -T '{ssl}'
---@return string[] ssl_lines The unmodified input lines (for buffer)
---@return table[] highlights Highlight definitions with line, col_start, col_end, hl
---@return table line_map Maps line number (1-indexed) to { type, commit }
function M.build(ssl_lines)
  local highlights = {}
  local line_map = {}

  if not ssl_lines or #ssl_lines == 0 then
    return ssl_lines or {}, highlights, line_map
  end

  local current_commit = nil

  for i, line in ipairs(ssl_lines) do
    local parsed = M.classify_line(line, current_commit)

    if parsed.type == "commit_header" then
      current_commit = parsed.commit
      line_map[i] = { type = "commit", commit = current_commit }
      add_commit_highlights(highlights, i - 1, line, current_commit)
    elseif parsed.type == "commit_message" then
      -- Associate message with preceding commit and set desc
      if current_commit then
        -- Strip graph prefix to get the message content
        local msg = parsed.content
        -- Remove leading graph chars and whitespace to get pure message
        local pure_msg = msg:gsub("^[%s│╷╭╮╯╰├┤─|/\\~]*", "")
        -- Also try removing multi-byte UTF-8 prefix chars
        local cleaned = msg
        local ci = 1
        while ci <= #cleaned do
          local byte = cleaned:byte(ci)
          if byte >= 0xC0 then
            if byte >= 0xF0 then ci = ci + 4
            elseif byte >= 0xE0 then ci = ci + 3
            else ci = ci + 2 end
          elseif byte == 0x20 or byte == 0x7C or byte == 0x2F or byte == 0x5C or byte == 0x7E then
            ci = ci + 1
          else
            break
          end
        end
        if ci <= #cleaned then
          pure_msg = cleaned:sub(ci)
        end
        current_commit.desc = pure_msg
      end
      line_map[i] = { type = "message", commit = current_commit }
      add_message_highlights(highlights, i - 1, line, current_commit)
    end
    -- graph_only lines: no line_map entry, no special highlights
  end

  return ssl_lines, highlights, line_map
end

return M
