local M = {}

-- function borrowed from chmod.yazi plugin
local selected_or_hovered = ya.sync(function()
	local tab = cx.active
	local paths = {}

	-- count up selected files
	for _, url in pairs(tab.selected) do
		paths[#paths + 1] = tostring(url)
	end

	-- if no files are selected use the hovered file
	-- a tab has folders which have files which have urls
	if #paths == 0 and tab.current.hovered then
		-- lua so we are 1 indexed
		paths[1] = tostring(tab.current.hovered.url)
	end
	return paths
end)

-- `setup()` writes to the sync context's state, while `entry()` runs in an async
-- context with a state table of its own, so config has to be fetched over a sync
-- block rather than read off `self`.
local get_config = ya.sync(function(st)
	local targets = {}
	for _, t in ipairs(st.targets or {}) do
		targets[#targets + 1] = { on = t.on, desc = t.desc, url = t.url }
	end
	return {
		targets = targets,
		mkpath = st.mkpath ~= false,
		extra_args = st.extra_args or {},
	}
end)

-- Renders the progress bar shown in the status line. Runs in the sync context
-- only, so `th` and `ui` are available. Must return a Line: `Status` collects
-- its children's return values into one, so a widget like `ui.Gauge` won't do.
function M.render_bar(st)
	local p = st.progress
	if not p then
		return ui.Line({})
	end

	local width = st.bar_width or 10
	local percent = math.max(0, math.min(100, p.percent or 0))
	local filled = math.floor(width * percent / 100 + 0.5)

	local label = st.progress_label_style or ui.Style():bold()
	local normal = st.progress_normal_style or ui.Style():fg("green")

	local text = string.format(" %3d%%", percent)
	if p.rate then
		text = text .. " " .. p.rate
	end
	if p.xfer and p.total then
		text = text .. string.format(" %d/%d", p.xfer, p.total)
	end

	return ui.Line({
		ui.Span(" rsync "):style(label),
		ui.Span(string.rep("█", filled)):style(normal),
		ui.Span(string.rep("░", width - filled)):style(ui.Style():fg("darkgray")),
		ui.Span(text .. " "):style(label),
	})
end

-- Adds the bar to the status line on the first update and takes it back off when
-- passed nil, so an idle yazi looks exactly like a stock one -- and so the bar
-- still works for anyone who never calls `setup()`.
local set_progress = ya.sync(function(st, p)
	st.progress = p

	if p and not st.status_id then
		-- cache theme lookups; a flavor may not define them
		st.progress_label_style = th.status and th.status.progress_label
		st.progress_normal_style = th.status and th.status.progress_normal
		st.status_id = Status:children_add(function()
			return M.render_bar(st)
		end, st.status_order or 1500, Status.RIGHT)
	elseif not p and st.status_id then
		Status:children_remove(st.status_id, Status.RIGHT)
		st.status_id = nil
	end

	ui.render()
end)

-- Helper function to expand tilde (~) in a path
local function expand_tilde(path)
	if not path then
		return nil
	end

	if path:sub(1, 1) == "~" then
		local home = os.getenv("HOME") -- Get HOME environment variable
		if not home then
			-- Fallback for Windows-specific environment variables
			home = os.getenv("USERPROFILE") -- Primary user profile directory on Windows
		end
		if home then
			return home .. path:sub(2) -- Concatenate home path with the rest of the path
		else
			-- Fallback if HOME is not set
			ya.notify({
				title = "Rsync Plugin",
				content = "Could not expand '~': HOME environment variable not set.",
				level = "warn",
				timeout = 5,
			})
			return path -- Return original path if home cannot be determined
		end
	end
	return path -- Return original path if no tilde
end

-- The destination is always a directory to copy *into*, so it needs a trailing
-- slash. `user@host:` already means "home directory" and is left alone.
local function as_dir(dest)
	dest = (dest or ""):match("^%s*(.-)%s*$")
	if dest == "" then
		return nil
	end

	-- Only expand tilde if it's a local path (doesn't contain ':')
	if not dest:match(":") then
		dest = expand_tilde(dest)
		if not dest then
			return nil
		end
	end

	if not dest:match("/$") and not dest:match(":$") then
		dest = dest .. "/"
	end
	return dest
end

local function cache_file()
	-- `~/.local/state/yazi` already exists (yazi.log lives there) and, unlike the
	-- plugin directory, survives `ya pkg upgrade`
	return os.getenv("HOME") .. "/.local/state/yazi/rsync.yazi.last_target"
end

local function read_cache()
	for _, path in ipairs({ cache_file(), os.getenv("HOME") .. "/.config/yazi/plugins/rsync.yazi/.last_target" }) do
		local f = io.open(path, "r")
		if f then
			local value = f:read("*a"):match("^%s*(.-)%s*$")
			f:close()
			if value ~= "" then
				return value
			end
		end
	end
	return ""
end

local function write_cache(dest)
	local f = io.open(cache_file(), "w")
	if f then
		f:write(dest)
		f:close()
	end
end

-- Offers the configured targets as a one-keypress menu. Escape returns nil and
-- the caller falls back to the plain input, which is how a destination that
-- isn't preconfigured stays reachable.
local function pick_target(targets)
	if #targets == 0 then
		return nil
	end

	local cands = {}
	for _, t in ipairs(targets) do
		cands[#cands + 1] = { on = t.on, desc = t.desc or t.url }
	end

	local idx = ya.which({ cands = cands })
	return idx and targets[idx] or nil
end

-- `Child:read()` hands back an array of byte values rather than a string, so it
-- has to be reassembled. Unpacked in slices to keep off Lua's stack limit.
local function bytes_to_string(t)
	local n = #t
	if n == 0 then
		return ""
	end

	local parts = {}
	for i = 1, n, 256 do
		parts[#parts + 1] = string.char(table.unpack(t, i, math.min(i + 255, n)))
	end
	return table.concat(parts)
end

-- rsync's `--info=progress2` output is \r-delimited, so this splits on both
-- terminators and hands back whatever trailing fragment is still incomplete.
local function drain(buf, fn)
	local rest = 1
	for line, pos in buf:gmatch("([^\r\n]*)[\r\n]()") do
		fn(line)
		rest = pos
	end
	return buf:sub(rest)
end

-- e.g. "  4,214,784  62%   11.30MB/s    0:00:14"
-- and  "377.49M 100%   38.87MB/s    0:00:09 (xfr#3, to-chk=0/4)"
local function parse_progress(line)
	local percent, rate = line:match("(%d+)%%%s+(%S+)")
	if not percent then
		return nil
	end

	local xfer, _, total = line:match("xfr#(%d+),%s*to%-chk=(%d+)/(%d+)")
	return {
		percent = tonumber(percent),
		rate = rate,
		xfer = tonumber(xfer),
		total = tonumber(total),
	}
end

local function run_rsync(files, dest, config, mkpath)
	local args = { "-ah", "--partial", "--no-motd", "--info=progress2", "--no-inc-recursive", "--outbuf=L" }
	if mkpath then
		args[#args + 1] = "--mkpath"
	end
	for _, a in ipairs(config.extra_args) do
		args[#args + 1] = a
	end

	local child, err = Command("rsync")
		:arg(args)
		:arg(files)
		:arg(dest)
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:spawn()

	if not child then
		return nil, tostring(err)
	end

	local buf, stderr = "", ""
	-- carried across updates: the file counts only appear on file boundaries
	local xfer, total, last_percent = nil, nil, nil

	set_progress({ percent = 0 })
	while true do
		local chunk, event = child:read(4096)
		if event == 2 or not chunk then
			break -- 2 means both streams are done
		end

		local data = bytes_to_string(chunk)
		if event == 1 then
			stderr = stderr .. data
		else
			buf = drain(buf .. data, function(line)
				local p = parse_progress(line)
				if not p then
					return
				end

				xfer, total = p.xfer or xfer, p.total or total
				if p.percent ~= last_percent then
					last_percent = p.percent
					set_progress({ percent = p.percent, rate = p.rate, xfer = xfer, total = total })
				end
			end)
		end
	end

	local status = child:wait()
	return { code = status and status.code or -1, stderr = stderr }, nil
end

function M:setup(opts)
	opts = opts or {}
	self.targets = opts.targets or {}
	self.mkpath = opts.mkpath ~= false
	self.bar_width = opts.bar_width or 10
	self.status_order = opts.status_order or 1500
	self.extra_args = opts.extra_args or {}
end

function M:entry(job)
	ya.emit("escape", { visual = true })

	local args = job.args or {}
	local remote_target = args[1]
	local remember = args.remember
	local config = get_config()

	local files = selected_or_hovered()
	if #files == 0 then
		return ya.notify({ title = "Rsync", content = "No files selected", level = "warn", timeout = 3 })
	end

	local picked
	if not args.no_pick then -- yazi normalizes `--no-pick` to `no_pick`
		picked = pick_target(config.targets)
	end

	local default_dest = picked and picked.url or remote_target
	if not default_dest and remember then
		default_dest = read_cache()
	end

	local dest, ok = ya.input({
		title = "Rsync - [user]@[remote]:<destination folder>",
		value = default_dest or nil,
		pos = { "top-center", y = 3, w = 45 },
	})
	if ok ~= 1 then
		return
	end

	dest = as_dir(dest)
	if not dest then
		return
	end

	-- guarded so that an error mid-transfer can't leave the bar pinned to the
	-- status line with no way to clear it
	local okay, result, err = pcall(function()
		local res, e = run_rsync(files, dest, config, config.mkpath)

		-- an rsync too old for --mkpath (locally or on the far end) is worth one
		-- silent retry rather than an error the user can't act on
		if res and res.code ~= 0 and config.mkpath and res.stderr:match("mkpath") then
			return run_rsync(files, dest, config, false)
		end
		return res, e
	end)

	set_progress(nil)

	if not okay then
		return ya.notify({
			title = "Rsync Plugin",
			content = string.format("Rsync failed: %s", result),
			level = "error",
			timeout = 10,
		})
	end

	if not result then
		return ya.notify({
			title = "Rsync Plugin",
			content = string.format("Failed to start rsync: %s", err),
			level = "error",
			timeout = 10,
		})
	end

	if result.code ~= 0 then
		ya.err(string.format("rsync exited with %s: %s", result.code, result.stderr))
		return ya.notify({
			title = "Rsync Plugin",
			content = string.format("stderr below, exit code %s\n\n%s", result.code, result.stderr),
			level = "error",
			timeout = 10,
		})
	end

	ya.notify({
		title = "Rsync Plugin",
		content = string.format("Rsync Completed! %d item(s) -> %s", #files, dest),
		timeout = 3,
	})

	if remember then
		write_cache(dest)
	end
end

return M
