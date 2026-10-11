-- Copyright (C) 2026 sbtl.dev. shtl is free software under the GNU GPL v3 or later; see LICENSE.
-- shtl: keyboard-first window placement for Hyprland. Open the panel (the trigger: a key combo, a held key
-- via keyd, or a key your keyboard's firmware sends); the left hand picks where (slots, workspaces, screens),
-- the right hand picks what (windows, apps). panel/shell.qml draws what this publishes.
--
-- Every slot is a stack of windows (its layers); the last one is on top. Workspaces nobody has arranged
-- yet tile themselves (1 window = full, 2 = halves, 3+ = thirds) until the first G or assign.
--
-- Constellations: Super+S while the panel is open saves the current workspace (then 1-9 picks its key);
-- 1-9 recalls one, rebuilt from its definition on its own workspace (★Name), borrowing windows.
--
-- Load it from your Hyprland Lua config: dofile("<shtl>/hypr/shtl.lua") (see README).

-- rxi's json.lua (MIT), bundled next to this file so shtl doesn't depend on any one shell's dotfiles
local here_dir = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local json = dofile(here_dir .. "json.lua")
local P = {}
shtl = P -- global, so `hyprctl eval` can reach it
P.version = "0.1.1"

-- Blueprints are split trees: a leaf is a slot ({}); a node splits its box side by side ("h") or
-- stacked ("v") at `ratio`. Slots are the leaves in order (A S D F), at most four. The settings window
-- edits the trees; Lua turns them into slot boxes as fractions of the workspace: { x, y, w, h }.
local function leaf() return {} end
local function h(ratio, a, b) return { split = "h", ratio = ratio, a = a, b = b } end
local function v(ratio, a, b) return { split = "v", ratio = ratio, a = a, b = b } end
local L = leaf

P.presets = {
    { name = "full",            tree = L() },
    { name = "halves",          tree = h(.5, L(), L()) },
    { name = "half + quarters", tree = h(.5, L(), h(.5, L(), L())) },
    { name = "thirds",          tree = h(1 / 3, L(), h(.5, L(), L())) },
    { name = "main + side",     tree = h(2 / 3, L(), L()) },
    { name = "wide center",     tree = h(.25, L(), h(2 / 3, L(), L())) },
    { name = "quarters",        tree = h(.25, L(), h(1 / 3, L(), h(.5, L(), L()))) },
    { name = "top / bottom",    tree = v(.5, L(), L()) },
    { name = "main + stack",    tree = h(.5, L(), v(.5, L(), L())) },
    { name = "main + 3 stack",  tree = h(.5, L(), v(1 / 3, L(), v(.5, L(), L()))) },
    { name = "grid",            tree = v(.5, h(.5, L(), L()), h(.5, L(), L())) },
}

local function tree_slots(t, box, out)
    box, out = box or { 0, 0, 1, 1 }, out or {}
    if not t.split then
        table.insert(out, box)
    elseif t.split == "h" then
        local w = box[3] * t.ratio
        tree_slots(t.a, { box[1], box[2], w, box[4] }, out)
        tree_slots(t.b, { box[1] + w, box[2], box[3] - w, box[4] }, out)
    else
        local hh = box[4] * t.ratio
        tree_slots(t.a, { box[1], box[2], box[3], hh }, out)
        tree_slots(t.b, { box[1], box[2] + hh, box[3], box[4] - hh }, out)
    end
    return out
end

local function make_blueprint(b) return { name = b.name, tree = b.tree, slots = tree_slots(b.tree) } end

-- Defaults until ~/.config/shtl/settings.json says otherwise.
P.blueprints = {}
for k = 1, 4 do table.insert(P.blueprints, make_blueprint(P.presets[k])) end -- G cycles these, in order
P.auto_names = { "full", "halves", "thirds" } -- untouched workspaces: window count -> blueprint

P.slot_keys      = { "A", "S", "D", "F" }
P.workspace_keys = { "Z", "X", "C", "V", "B" } -- this screen's five workspaces; Tab = kick back
-- Screens left to right own workspaces 1-5, 6-10, ... (matches the workspace rules in hypr-user.lua).
-- Q: tap = next screen, hold = pick one.
P.window_keys = { "H", "J", "K", "L", "semicolon" } -- windows on this workspace, oldest first
-- The app pool: right-hand top and bottom rows. Starred apps keep their key; the free keys fill with
-- the most recently used apps that have windows on other workspaces.
P.app_keys    = { "Y", "U", "I", "O", "P", "N", "M", "comma", "period", "slash" }
P.starred     = {} -- run-or-raise favorites pinned to a pool key ({ key, class, cmd }); set in Settings

local HELD = "CTRL + ALT + SHIFT + "

-- Settings (to move into a settings UI later).
-- When a screen that yielded a lent window gets it back: "top" puts it back on top if that slot
-- still has the top it was left with; "stay" leaves it wherever it is in the stack.
P.yield_return = "top"
-- Taking (single tap) a window that's lent out: "full" makes here its only place (home and every
-- borrower drop it); "copy" takes just the copy you took it from (from its home: you become the
-- home and the borrowers keep theirs; from a borrower: you borrow it instead of them).
P.steal_mode = "full"
-- What a single tap on an app key (or a picker label) does; a double tap does the other one.
P.tap_takes = "steal" -- "steal" | "borrow"
-- Which windows a recalled constellation may use. "share": its own window if it's still open, else any window
-- of that app (most recently used first; borrowed, never stolen), launching only when there's none.
-- "own": only the windows it remembers (ones it launched or was saved with); otherwise it launches new.
P.constellation_windows = "share" -- "share" | "own"
-- Panel colors: a built-in palette, or the desktop shell's (falls back where it'd be hard to read).
P.theme = "catppuccin" -- catppuccin | tokyonight | kanagawa | rosepine | gruvbox | everforest | nord | dracula | shell
-- The rest of the look (Settings → Look):
P.material = "solid"       -- solid | frosted | glass   (how much of the blurred desktop shows through)
P.shape    = "soft"        -- sharp | soft | round | hyprland   (corner rounding; hyprland = decoration:rounding)
P.edge     = "line"        -- line | gradient | none
P.typeface = "fira"        -- fira | shell | mono
P.density  = "comfortable" -- comfortable | compact
-- Key hints in the panel, for learning the keys; turn them off once you know them.
P.hints = "show" -- "show" | "hide"
-- Section labels in the panel (Workspaces, Constellations, Apps, On this workspace).
P.labels = "show" -- "show" | "hide"
-- How the panel opens. "combo": a key combo toggles it (no extra software). "hold": hold a key, via keyd (the
-- optional extras/keyd/shtl.conf, root). "firmware": your keyboard sends a key while you hold one (F13 by default;
-- Wooting / QMK / ZMK can do this), so shtl opens on press and closes or sticks on release.
P.trigger          = "combo"         -- combo | hold | firmware
P.trigger_combo    = "SUPER + space"
P.trigger_firmware = "F13"
-- Where the panel sits: "top", "center" or "bottom", and how far from that edge (pixels; for bars and docks).
P.panel_position = "top"
P.panel_offset   = 10
-- Letting go of Space: "sticky" leaves the panel open (Space / Esc closes it); "auto" leaves it open
-- only if no key was pressed while holding; "hold" closes it. An open picker always stays.
P.panel_mode = "sticky" -- "sticky" | "auto" | "hold"

-- workspace name -> { bp, sel, manual, stacks = { [slot] = { address, ..., top } } }
-- A config reload starts Lua fresh (Caelestia reloads on every wallpaper change), so the arrangement
-- lives in a file in the session's runtime dir. Window addresses stay valid while Hyprland runs.
P.store = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/shtl-arrangement.json"

local function load_store()
    local f = io.open(P.store, "r")
    if not f then return {} end
    local ok, data = pcall(json.decode, f:read("*a"))
    f:close()
    if not ok or type(data) ~= "table" then return {} end
    for _, s in pairs(data.ws or {}) do -- JSON object keys are strings; slots are numbers
        local stacks = {}
        for i, st in pairs(s.stacks or {}) do stacks[tonumber(i)] = st end
        s.stacks = stacks
    end
    return data
end

local stored = load_store()
P.ws      = stored.ws or {}
P.mode    = "closed" -- closed | held | sticky
P.used    = false    -- a key was pressed during the current hold
P.pending = {}       -- { class, ws, slot } for apps that are launching into a slot
-- Lending: a lent window has one home and any number of borrowers, and sits in all their stacks.
-- It can only be drawn once, so where it's physically shown is worked out by settle().
-- address -> { home = workspace, at = { [workspace] = true } }
P.loans = stored.loans or {}
for address, b in pairs(stored.borrowed or {}) do -- from the constellation-only borrow before loans
    P.loans[address] = { home = b.home, at = { [b.at] = true } }
end
-- Screens that gave way: workspace -> address -> { slot, top = what was on top right after yielding }
P.yields = stored.yields or {}
P.quiet  = false -- while an action moves windows itself, settle() waits for it to finish
P.incoming = {} -- address -> workspace, while a swap is moving windows
P.here    = stored.here or (hl.get_active_workspace() or {}).name
P.last    = stored.last
P.origin  = nil      -- where the panel was opened from (and on which screen); Kick returns there
P.origin_screen = nil
-- Each screen's own history, so Tab flips the screen you're on between its last two workspaces.
-- monitor name -> { here, last }
P.screen_hist = stored.screen_hist or {}
for _, m in ipairs(hl.get_monitors()) do
    if m.active_workspace and not P.screen_hist[m.name] then P.screen_hist[m.name] = { here = m.active_workspace.name } end
end
P.saving  = nil      -- nil | { confirm = n }: Super+S pressed, waiting for a number

local function letter(i) return P.slot_keys[i] or tostring(i) end

-- Rare oddities worth knowing about, appended to $XDG_RUNTIME_DIR/shtl-debug.log.
function P.debug(line)
    local f = io.open((os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/shtl-debug.log", "a")
    if not f then return end
    f:write(os.date("%H:%M:%S "), line, "\n")
    f:close()
end

local function state(name)
    local s = P.ws[name]
    if not s then
        s = { bp = 1, sel = 1, manual = false, stacks = {} }
        P.ws[name] = s
    end
    if not s.stacks then -- from the earliest one-window-per-slot format
        s.stacks = {}
        for i, a in pairs(s.slots or {}) do s.stacks[i] = { a } end
        s.slots, s.manual = nil, true
    end
    return s
end

function P.save()
    local out = {}
    for name, s in pairs(P.ws) do
        local stacks = {}
        for i, st in pairs(s.stacks) do
            if #st > 0 then stacks[tostring(i)] = st end
        end
        out[name] = { bp = s.bp, sel = s.sel, manual = s.manual, constellation = s.constellation, stacks = stacks, area = s.area }
    end
    local f = io.open(P.store .. ".tmp", "w")
    if not f then return end
    -- fullscreen and maximized windows too: a config reload re-adds every window to the layout, which drops them
    local full = {}
    for _, w in ipairs(hl.get_windows()) do
        if (w.fullscreen or 0) > 0 then full[w.address] = w.fullscreen end
    end
    f:write(json.encode({ ws = out, here = P.here, last = P.last, loans = P.loans, yields = P.yields, screen_hist = P.screen_hist,
                          fullscreen = full }))
    f:close()
    os.rename(P.store .. ".tmp", P.store)
end

local function is_managed(ws)
    return ws ~= nil and not ws.name:find("^special:")
end

local function current()
    local ws = hl.get_active_workspace()
    if is_managed(ws) then return ws, state(ws.name) end
end

local function slot_count(s) return #P.blueprints[s.bp].slots end

-- Settings --------------------------------------------------------------------------------------
-- ~/.config/shtl/settings.json, edited by the settings window (Super+, while the panel is open, or
-- the gear). It sends the whole settings table back on every change: P.apply_settings(json).

P.settings_file = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/shtl/settings.json"
local BEHAVIOR = {
    yield_return  = { "top", "stay" },
    steal_mode    = { "full", "copy" },
    tap_takes     = { "steal", "borrow" },
    constellation_windows = { "share", "own" },
    panel_mode    = { "sticky", "auto", "hold" },
    trigger       = { "combo", "hold", "firmware" },
    panel_position = { "top", "center", "bottom" },
    hints         = { "show", "hide" },
    labels        = { "show", "hide" },
    material      = { "solid", "frosted", "glass" },
    shape         = { "soft", "sharp", "round", "hyprland" },
    edge          = { "line", "gradient", "none" },
    typeface      = { "fira", "shell", "mono" },
    density       = { "comfortable", "compact" },
    theme         = { "catppuccin", "tokyonight", "kanagawa", "rosepine", "gruvbox", "everforest", "nord", "dracula", "shell" },
}

-- A blueprint by name, else the first with the same number of slots (else the nearest count).
function P.blueprint_index(name, nslots)
    for i, b in ipairs(P.blueprints) do
        if b.name == name then return i end
    end
    local best, bestd = 1, math.huge
    for i, b in ipairs(P.blueprints) do
        local d = math.abs(#b.slots - (nslots or 1))
        if d < bestd then best, bestd = i, d end
    end
    return best
end

function P.auto_blueprint(count)
    local n = math.min(math.max(count, 1), #P.auto_names)
    return P.blueprint_index(P.auto_names[n], n)
end

local function valid_tree(t, depth)
    if type(t) ~= "table" or depth > 4 then return false end
    if t.split == nil then return true end
    if (t.split ~= "h" and t.split ~= "v") or type(t.ratio) ~= "number" or t.ratio <= 0.05 or t.ratio >= 0.95 then
        return false
    end
    return valid_tree(t.a, depth + 1) and valid_tree(t.b, depth + 1)
end

function P.settings_table()
    local out = { starred = P.starred, blueprints = {}, auto = P.auto_names,
                  trigger_combo = P.trigger_combo, trigger_firmware = P.trigger_firmware, panel_offset = P.panel_offset }
    for k in pairs(BEHAVIOR) do out[k] = P[k] end
    for _, b in ipairs(P.blueprints) do table.insert(out.blueprints, { name = b.name, tree = b.tree }) end
    return out
end

-- Apply a settings table (anything invalid keeps its current value) and, unless loading, save it.
local function apply(cfg, loading)
    if type(cfg) ~= "table" then return false end
    local was_trigger = P.trigger .. P.trigger_combo .. P.trigger_firmware
    for _, k in ipairs({ "trigger_combo", "trigger_firmware" }) do -- key names, e.g. "SUPER + space", "F13"
        if type(cfg[k]) == "string" and cfg[k]:match("^[%w%s%+_]+$") then P[k] = cfg[k] end
    end
    if type(cfg.panel_offset) == "number" then P.panel_offset = math.max(0, math.min(600, math.floor(cfg.panel_offset))) end
    for k, allowed in pairs(BEHAVIOR) do
        for _, a in ipairs(allowed) do
            if cfg[k] == a then P[k] = a end
        end
    end
    if type(cfg.starred) == "table" then
        local starred, used = {}, {}
        for _, fav in ipairs(cfg.starred) do
            local ok_key = false
            for _, key in ipairs(P.app_keys) do ok_key = ok_key or key == fav.key end
            if ok_key and not used[fav.key] and type(fav.class) == "string" and fav.class ~= "" then
                used[fav.key] = true
                table.insert(starred, { key = fav.key, class = fav.class, cmd = fav.cmd ~= "" and fav.cmd or nil })
            end
        end
        P.starred = starred
    end
    if type(cfg.blueprints) == "table" and #cfg.blueprints > 0 then
        local list, names = {}, {}
        for _, b in ipairs(cfg.blueprints) do
            if type(b.name) == "string" and b.name ~= "" and not names[b.name] and valid_tree(b.tree, 0) then
                local made = make_blueprint(b)
                if #made.slots <= #P.slot_keys then
                    names[b.name] = true
                    table.insert(list, made)
                end
            end
        end
        if #list > 0 and loading then
            P.blueprints = list -- saved arrangements already point into this list
        elseif #list > 0 then
            -- workspaces keep their blueprint by name; a removed one falls back to the same slot count
            local before = {}
            for name, st in pairs(P.ws) do
                local b = P.blueprints[st.bp]
                before[name] = b and { b.name, #b.slots } or { "full", 1 }
            end
            P.blueprints = list
            for name, st in pairs(P.ws) do
                st.bp = P.blueprint_index(before[name][1], before[name][2])
                st.sel = math.min(st.sel or 1, #P.blueprints[st.bp].slots)
            end
        end
    end
    if type(cfg.auto) == "table" and #cfg.auto > 0 then P.auto_names = cfg.auto end
    if not loading and was_trigger ~= nil then
        P.trigger_changed = was_trigger ~= P.trigger .. P.trigger_combo .. P.trigger_firmware
    end
    if not loading then
        os.execute("mkdir -p '" .. P.settings_file:match("^(.*)/[^/]*$") .. "'")
        local f = io.open(P.settings_file .. ".tmp", "w")
        if f then
            f:write(json.encode(P.settings_table()))
            f:close()
            os.rename(P.settings_file .. ".tmp", P.settings_file)
        end
    end
    return true
end

-- For the "hold" trigger: what keyd setup is in place (Settings shows what's missing and the commands).
local function exists(path)
    local f = io.open(path, "r")
    if f then f:close() end
    return f ~= nil
end

function P.keyd_status()
    local user = os.getenv("USER") or ""
    local in_group = false
    local g = io.open("/etc/group", "r")
    if g then
        for line in g:lines() do
            local name, members = line:match("^([^:]*):[^:]*:[^:]*:(.*)$")
            if name == "keyd" then
                for m in (members .. ","):gmatch("([^,]*),") do in_group = in_group or m == user end
            end
        end
        g:close()
    end
    return {
        installed = exists("/usr/bin/keyd") or exists("/usr/local/bin/keyd"),
        config = exists("/etc/keyd/shtl.conf"),
        running = (function() -- its socket can't be opened like a file, and exit codes don't reach Lua here
            local f = io.popen("systemctl is-active keyd 2>/dev/null")
            local out = f and f:read("*l")
            if f then pcall(f.close, f) end
            return out == "active"
        end)(),
        group = in_group,
        conf = P.root and (P.root .. "extras/keyd/shtl.conf") or "extras/keyd/shtl.conf",
    }
end

-- The settings window has the keyboard while it's open, so shtl steps out of its submap.
P.settings_open = false

function P.open_settings()
    P.settings_open = true
    P.used = true
    hl.dispatch(hl.dsp.submap("reset"))
    P.publish()
end

function P.close_settings()
    P.settings_open = false
    if P.mode ~= "closed" then -- carry on in sticky (Space may have been let go meanwhile)
        P.mode = "sticky"
        hl.dispatch(hl.dsp.submap("shtl"))
    end
    P.publish()
end

function P.apply_settings(text)
    local ok, cfg = pcall(json.decode, text)
    if not ok or not apply(cfg) then return P.publish("settings not saved: couldn't read them") end
    P.save()
    hl.dispatch(hl.dsp.layout("refresh"))
    if P.trigger_changed then -- new keys: reload so the right binds (and listener) are set up
        P.trigger_changed = false
        P.publish("settings saved; reloading for the new trigger")
        return hl.dispatch(hl.dsp.exec_cmd("hyprctl reload"))
    end
    P.publish("settings saved")
end

do -- load at startup
    local f = io.open(P.settings_file, "r")
    if f then
        local ok, cfg = pcall(json.decode, f:read("*a"))
        f:close()
        if ok then apply(cfg, true) end
    end
end

-- Stacks ---------------------------------------------------------------------------------------

local function top(s, i)
    local st = s.stacks[i]
    return st and st[#st]
end

local function find(s, address)
    for i, st in pairs(s.stacks) do
        for k, a in ipairs(st) do
            if a == address then return i, k end
        end
    end
end

local function remove(s, address)
    local i, k = find(s, address)
    if i then table.remove(s.stacks[i], k) end
    return i
end

local function push(s, i, address)
    s.stacks[i] = s.stacks[i] or {}
    table.insert(s.stacks[i], address)
end

local function max_slot(s)
    local m = 0
    for i in pairs(s.stacks) do m = math.max(m, i) end
    return m
end

-- Panel feed ------------------------------------------------------------------------------------
-- Everything the panel draws, rewritten on every change; panel/shell.qml watches this file.

P.state_file = (os.getenv("XDG_RUNTIME_DIR") or "/tmp") .. "/shtl-state.json"

local function short(class) return (class or "?"):match("([^.]+)$") end
local LABELS = { semicolon = ";", comma = ",", period = ".", slash = "/" }
P.shelf = "special:shtl-shelf" -- Backspace tap parks windows here (shtl's minimize)
local function ws_label(name)
    if name == P.shelf then return "shelf" end
    return name
end
local function key_label(key) return LABELS[key] or key end

-- away: the workspace it's shown on, when that isn't `here` (a lent window shown elsewhere)
local function win_info(address, here)
    local w = address and hl.get_window("address:" .. address)
    if not w then return false end
    local away = here and w.workspace and w.workspace.name ~= here and ws_label(w.workspace.name) or false
    return { class = short(w.class), title = w.title or "", away = away }
end

-- Screens, left to right.
local function screens()
    local list = hl.get_monitors()
    table.sort(list, function(a, b) return a.x == b.x and a.y < b.y or a.x < b.x end)
    return list
end

local function screen_index(name)
    for i, m in ipairs(screens()) do
        if m.name == name then return i end
    end
    return 1
end

-- "Acme Inc. Acme U27 #A1B2..." -> "Acme U27" (maker prefix and serial dropped)
local function screen_label(m)
    local d = (m.description or ""):gsub("^%S+ Inc%. ", ""):gsub("%s+%S+$", "")
    return d ~= "" and d or m.name
end

-- Workspace k of the screen you're on.
local function screen_workspace(k)
    local mon = hl.get_active_monitor()
    return (screen_index(mon and mon.name) - 1) * #P.workspace_keys + k
end

-- Z X C V B are "this screen's five workspaces": screens left to right own 1-5, 6-10, ... so tie each workspace
-- to its screen (and open each screen on its first). Plugging screens in or out takes a config reload.
for i, m in ipairs(screens()) do
    for k = 1, #P.workspace_keys do
        hl.workspace_rule({ workspace = tostring((i - 1) * #P.workspace_keys + k), monitor = m.name, default = k == 1 })
    end
end

-- All windows (optionally only one app's), most recently used first.
local function mru_windows(class)
    local wins = {}
    for _, w in ipairs(hl.get_windows()) do
        if not class or w.class == class then table.insert(wins, w) end
    end
    local function age(w) return (w.focus_history_id or -1) < 0 and math.huge or w.focus_history_id end
    table.sort(wins, function(a, b) return age(a) < age(b) end)
    return wins
end

local function is_starred(class)
    for _, fav in ipairs(P.starred) do
        if fav.class == class then return true end
    end
    return false
end

-- Apps with windows on other workspaces that aren't starred, most recently used first.
local function elsewhere_apps(here)
    local seen, apps = {}, {}
    for _, w in ipairs(mru_windows()) do
        local wsn = w.workspace and w.workspace.name
        if wsn ~= here and not is_starred(w.class) and not seen[w.class] then
            seen[w.class] = true
            table.insert(apps, w.class)
        end
    end
    return apps
end

-- Which app each pool key means right now: { key = { class, fav? } }.
local function app_pool(here)
    local pool, taken = {}, {}
    for _, fav in ipairs(P.starred) do
        pool[fav.key] = { class = fav.class, fav = fav }
        taken[fav.key] = true
    end
    local apps, k = elsewhere_apps(here), 1
    for _, key in ipairs(P.app_keys) do
        if not taken[key] and apps[k] then
            pool[key] = { class = apps[k] }
            k = k + 1
        end
    end
    return pool
end

local function workspace_windows(name)
    local wins = hl.get_workspace_windows(name)
    table.sort(wins, function(a, b) return a.stable_id < b.stable_id end)
    return wins
end

-- A workspace's windows: the ones on it plus lent ones shown elsewhere for now (they keep their slots
-- here, so the workspace isn't empty). Returns the windows and how many of them are away.
local function held_windows(name)
    local list, seen, away = {}, {}, 0
    for _, w in ipairs(hl.get_workspace(name) and hl.get_workspace_windows(name) or {}) do
        seen[w.address] = true
        table.insert(list, w)
    end
    local s = P.ws[name]
    for _, st in pairs(s and s.stacks or {}) do
        for _, a in ipairs(st) do
            local w = not seen[a] and hl.get_window("address:" .. a)
            if w then
                seen[a] = true
                away = away + 1
                table.insert(list, w)
            end
        end
    end
    return list, away
end

function P.publish(message)
    local ws  = hl.get_active_workspace()
    local mon = hl.get_active_monitor()
    local out = {
        mode      = P.mode,
        hints     = P.hints ~= "hide",
        labels    = P.labels ~= "hide",
        theme     = P.theme,
        position  = { edge = P.panel_position, offset = P.panel_offset },
        look      = {
            material = P.material, edge = P.edge, typeface = P.typeface, density = P.density,
            -- corner radius of the card; everything else scales from it
            radius = P.shape == "sharp" and 3 or P.shape == "round" and 20
                or P.shape == "hyprland" and (tonumber(hl.get_config("decoration.rounding")) or 12) or 12,
        },
        message   = message or "",
        monitor   = mon and mon.name or "",
        aspect    = mon and mon.height > 0 and mon.width / mon.height or 16 / 9,
        workspace = ws and ws.name or "",
        managed   = is_managed(ws),
    }

    if out.managed then
        local s = state(ws.name)
        local bp = P.blueprints[s.bp]
        local n = #bp.slots
        out.blueprint = { name = bp.name, index = s.bp, count = #P.blueprints, auto = not s.manual }
        out.sel = s.sel

        out.slots = {}
        for i, f in ipairs(bp.slots) do
            local behind = math.max(#(s.stacks[i] or {}) - 1, 0)
            if i == n then -- stacks of slots this blueprint lacks wait behind its last slot
                for j = n + 1, max_slot(s) do behind = behind + #(s.stacks[j] or {}) end
                if not top(s, i) and behind > 0 then behind = behind - 1 end
            end
            out.slots[i] = {
                key = letter(i), x = f[1], y = f[2], w = f[3], h = f[4],
                window = win_info(top(s, i), ws.name),
                behind = behind,
            }
        end

        out.windows = {}
        for k, key in ipairs(P.window_keys) do
            local w = workspace_windows(ws.name)[k]
            if not w then break end
            local i, pos = find(s, w.address)
            out.windows[k] = {
                key = key_label(key), class = short(w.class), title = w.title or "",
                slot = i and letter(math.min(i, n)) or false,
                behind = i ~= nil and pos ~= #s.stacks[i],
            }
        end
    end

    local list = screens()
    local idx = screen_index(mon and mon.name)
    local nxt = list[idx % #list + 1]
    out.screen = {
        name = mon and screen_label(mon) or "", index = idx, count = #list,
        next = #list > 1 and screen_label(nxt) or false,
    }

    out.workspaces = {}
    for k, key in ipairs(P.workspace_keys) do
        local name = tostring(screen_workspace(k))
        local held, away = held_windows(name)
        out.workspaces[k] = {
            key = key, name = name,
            windows = #held, away = away,
            active = ws ~= nil and ws.name == name,
        }
    end
    out.kick = P.kick_target() or false

    -- a constellation is lit only inside its own ★ workspace, never on the one it was saved from
    local here_constellation = P.here_constellation()
    out.constellations = {}
    for k, t in ipairs(P.constellations) do
        local active = here_constellation == k
        out.constellations[k] = { key = tostring(k), name = t.name, active = active, changed = active and P.constellation_changed(k) }
    end
    out.saving = P.saving and (P.saving.confirm or true) or false
    out.renaming = P.renaming or false

    if P.picker then
        local items = {}
        for k, it in ipairs(P.picker.items) do
            if P.picker.display then
                local d = P.picker.display(it.address)
                items[k] = { key = key_label(it.label), class = d.class, title = d.title, where = d.where }
                goto continue
            end
            local w = hl.get_window("address:" .. it.address)
            local where = w and w.workspace and ws_label(w.workspace.name) or "?"
            if w and w.workspace and P.ws[where] then
                local i = find(P.ws[where], w.address)
                if i then where = where .. " · " .. letter(i) end
            end
            items[k] = {
                key = key_label(it.label), class = w and short(w.class) or "?",
                title = w and w.title or "", where = where,
            }
            ::continue::
        end
        local extras = {}
        for k, x in ipairs(P.picker.extras or {}) do extras[k] = { key = key_label(x.label), text = x.text } end
        out.picker = { title = P.picker.title, items = items, extras = extras }
    end

    -- the app pool, in key order (top row, then bottom row)
    out.apps = {}
    local pool = app_pool(ws and ws.name)
    for row, keys in ipairs({ { 1, 5 }, { 6, 10 } }) do
        out.apps[row] = {}
        for k = keys[1], keys[2] do
            local key = P.app_keys[k]
            local app = pool[key]
            local entry = { key = key_label(key), empty = not app }
            if app then
                local count, where = 0, nil
                for _, w in ipairs(mru_windows(app.class)) do
                    count = count + 1
                    where = where or (w.workspace and w.workspace.name)
                end
                entry.name, entry.starred, entry.count = short(app.class), app.fav ~= nil, count
                entry.where = where and ws_label(where) or ""
                entry.here = where ~= nil and ws ~= nil and where == ws.name
            end
            table.insert(out.apps[row], entry)
        end
    end

    if P.settings_open then
        local cfg = P.settings_table()
        cfg.presets = {}
        for _, b in ipairs(P.presets) do table.insert(cfg.presets, { name = b.name, tree = b.tree }) end
        cfg.keys = {}
        for _, key in ipairs(P.app_keys) do table.insert(cfg.keys, { key = key, label = key_label(key) }) end
        cfg.apps, cfg.slot_keys, cfg.version = {}, P.slot_keys, P.version
        cfg.keyd = P.keyd_status()
        local seen = {}
        for _, w in ipairs(mru_windows()) do
            if not seen[w.class] and w.class ~= "" then
                seen[w.class] = true
                table.insert(cfg.apps, { class = w.class, name = short(w.class), cmd = P.launch_command and P.launch_command(w) or "" })
            end
        end
        out.settings = cfg
    end

    out.placeholders = P.placeholders and P.placeholders() or {}
    P.save()
    local tmp = P.state_file .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then return end
    f:write(json.encode(out))
    f:close()
    os.rename(tmp, P.state_file)
end

-- Layout ---------------------------------------------------------------------------------------

local function slot_box(area, frac, gap)
    local x, y = area.x + frac[1] * area.w, area.y + frac[2] * area.h
    local w, h = frac[3] * area.w, frac[4] * area.h
    -- half a gap on every inner edge, none against the workspace border
    local l = frac[1] > 0 and gap / 2 or 0
    local r = frac[1] + frac[3] < 0.999 and gap / 2 or 0
    local t = frac[2] > 0 and gap / 2 or 0
    local b = frac[2] + frac[4] < 0.999 and gap / 2 or 0
    return { x = x + l, y = y + t, w = w - l - r, h = h - t - b }
end

local function gaps_in()
    local g = hl.get_config("general.gaps_in")
    if type(g) == "table" then g = g.top or g[1] end
    return tonumber(g) or 10
end

local function place_all(ctx)
    local first = ctx.targets[1]
    local ws = first and first.window and first.window.workspace
    if not ws then return end
    local s = state(ws.name)

    -- forget windows that left this workspace, except lent ones it holds (their place is kept)
    local here = {}
    for _, t in ipairs(ctx.targets) do
        if t.window then here[t.window.address] = true end
    end
    -- Only forget a window that's really gone or on another workspace: a pass may not list every window
    -- (seen around config reloads), and forgetting it would re-add it later in some other slot.
    for i, st in pairs(s.stacks) do
        for k = #st, 1, -1 do
            local a = st[k]
            local l = P.loans[a]
            local holds = l and (l.home == ws.name or l.at[ws.name])
            local coming = P.incoming[a] == ws.name
            if not here[a] and not holds and not coming then
                local w = hl.get_window("address:" .. a)
                if w and w.workspace and w.workspace.name == ws.name then
                    P.debug("partial pass on " .. ws.name .. ": kept " .. a .. " (" .. #ctx.targets .. " targets)")
                else
                    table.remove(st, k)
                end
            end
        end
        if #st == 0 then s.stacks[i] = nil end
    end

    if not s.manual then
        -- untouched workspace: one window per slot, blueprint sized to the window count
        local order = {}
        for i = 1, max_slot(s) do
            for _, a in ipairs(s.stacks[i] or {}) do table.insert(order, a) end
        end
        for _, t in ipairs(ctx.targets) do
            local a = t.window and t.window.address
            if a and not find(s, a) then table.insert(order, a) end
        end
        s.bp = P.auto_blueprint(#order)
        local n = slot_count(s)
        s.stacks = {}
        for k, a in ipairs(order) do push(s, math.min(k, n), a) end
        s.sel = math.min(s.sel, n)
    else
        -- newcomers fill the first empty slot; once full they go on top of the selected slot
        local n = slot_count(s)
        for _, t in ipairs(ctx.targets) do
            local a = t.window and t.window.address
            if a and not find(s, a) then
                local slot = s.sel
                for j = 1, n do
                    if not top(s, j) then slot = j break end
                end
                push(s, slot, a)
            end
        end
    end

    -- Only each slot's top window is on screen. Layers behind it are parked far off-screen so the
    -- mouse can't hover them into focus. Stacks of slots the blueprint lacks wait under its last slot.
    s.area = { x = ctx.area.x, y = ctx.area.y, w = ctx.area.w, h = ctx.area.h } -- for placeholders
    local n, gap = slot_count(s), gaps_in()
    local shown = {}
    for i = 1, n do shown[i] = top(s, i) end
    for j = n + 1, max_slot(s) do shown[n] = shown[n] or top(s, j) end
    local visible = {}
    for _, a in pairs(shown) do visible[a] = true end

    for _, t in ipairs(ctx.targets) do
        local a = t.window and t.window.address
        local i = a and find(s, a)
        local box = slot_box(ctx.area, P.blueprints[s.bp].slots[math.min(i or s.sel, n)], gap)
        if a and not visible[a] then box.y = box.y - 100000 end
        t:place(box)
    end
    P.save()
end

-- Placeholders: on every screen's visible workspace, slots whose top is a lent window shown somewhere
-- else. Drawn by panel/shell.qml under the windows, in monitor-local pixels.
function P.placeholders()
    local out = {}
    for _, m in ipairs(hl.get_monitors()) do
        local aw = m.active_workspace
        local st = aw and is_managed(aw) and P.ws[aw.name]
        if st then
            for i = 1, slot_count(st) do
                local a = top(st, i)
                local w = a and P.loans[a] and hl.get_window("address:" .. a)
                if w and w.workspace and w.workspace.name ~= aw.name then
                    local area = st.area or { x = m.x, y = m.y, w = m.width, h = m.height }
                    local box = slot_box(area, P.blueprints[st.bp].slots[i], gaps_in())
                    table.insert(out, {
                        monitor = m.name, x = box.x - m.x, y = box.y - m.y, w = box.w, h = box.h,
                        class = short(w.class), at = ws_label(w.workspace.name),
                    })
                end
            end
        end
    end
    return out
end

hl.layout.register("shtl", {
    recalculate = place_all,
    -- "refresh": state lives in P.ws, so just place everything again
    layout_msg = function(ctx, msg)
        if ctx then place_all(ctx) end
        return true
    end,
})

hl.config({ general = { layout = "lua:shtl" } })

-- Panel (panel/shell.qml): blur what's behind the card, like the mock; skip its transparent margin
hl.layer_rule({ match = { namespace = "^shtl(-settings)?$" }, blur = true, ignore_alpha = 0.3 })

local function refresh(s)
    P.settle() -- a lent window may want another screen now (e.g. you buried it here)
    hl.dispatch(hl.dsp.layout("refresh"))
    -- each slot's top window above its layers; slots the blueprint lacks first, so the last slot wins
    for i = max_slot(s), 1, -1 do
        local a = top(s, i)
        if a then hl.dispatch(hl.dsp.window.bring_to_top({ window = "address:" .. a })) end
    end
    local a = top(s, s.sel)
    local w = a and hl.get_window("address:" .. a)
    local here = hl.get_active_workspace()
    if w and here and w.workspace and w.workspace.name == here.name then -- away (borrowed): stay put
        hl.dispatch(hl.dsp.focus({ window = "address:" .. a }))
    end
end

-- Keyboard focus follows the selection: the selected slot's top window, if it's on this workspace.
local function focus_selected()
    local ws, s = current()
    local a = ws and top(s, s.sel)
    local w = a and hl.get_window("address:" .. a)
    if w and w.workspace and w.workspace.name == ws.name then
        hl.dispatch(hl.dsp.focus({ window = "address:" .. a }))
    end
end

-- Actions --------------------------------------------------------------------------------------

-- steal_mode "copy": take over only the copy on `from` (its home, or one borrower's).
local function take_copy(address, from, here)
    local l = P.loans[address]
    if P.ws[from] then remove(P.ws[from], address) end
    if P.yields[from] then P.yields[from][address] = nil end
    if from == l.home then
        l.home = here
        l.at[here] = nil
    else
        l.at[from] = nil
        if here ~= l.home then l.at[here] = true end
    end
    if next(l.at) == nil then P.end_loan(address, here) end
end

-- Put a window on top of the selected slot; whatever was there becomes the layer behind it.
local function assign(ws, s, address)
    -- remember where it came from, so a second tap can turn this steal into a borrow
    local win0 = hl.get_window("address:" .. address)
    local from = win0 and win0.workspace and win0.workspace.name
    if from and from ~= ws.name then
        local places = {}
        for name, st in pairs(P.ws) do
            local i, k = find(st, address)
            if i and name ~= ws.name then table.insert(places, { ws = name, slot = i, pos = k }) end
        end
        local l = P.loans[address]
        local loan = l and { home = l.home, at = {} }
        if l then for n in pairs(l.at) do loan.at[n] = true end end
        P.last_assign = { address = address, from = from, places = places, loan = loan, class = win0.class }
    end
    s.manual = true
    if from and from ~= ws.name and P.loans[address] then -- taken on purpose from another workspace
        if P.steal_mode == "copy" then take_copy(address, from, ws.name) else P.end_loan(address, ws.name) end
    end
    remove(s, address)
    push(s, s.sel, address)
    local win = hl.get_window("address:" .. address)
    if win and win.workspace and win.workspace.name ~= ws.name then
        hl.dispatch(hl.dsp.window.move({ workspace = ws.name, window = "address:" .. address, follow = false }))
    end
    hl.dispatch(hl.dsp.focus({ window = "address:" .. address }))
    -- advance only to an empty slot (filling a fresh layout A -> S -> D); otherwise stay put
    for step = 1, slot_count(s) - 1 do
        local j = (s.sel + step - 1) % slot_count(s) + 1
        if not top(s, j) then
            s.sel = j
            break
        end
    end
    refresh(s)
end

-- Take a specific window into the selected slot (a single tap's steal); for the panel and tests.
function P.take(address)
    local ws, s = current()
    if ws then assign(ws, s, address) end
    P.publish()
end

-- Slot key: select it, or if it is already selected, flip through its layers.
function P.slot_key(i, back)
    local ws, s = current()
    if not ws then return P.publish() end
    if i > slot_count(s) then return P.publish(P.blueprints[s.bp].name .. " has no slot " .. letter(i)) end

    local st = s.stacks[i]
    if i == s.sel and st and #st > 1 then
        if back then
            table.insert(st, table.remove(st, 1))
        else
            table.insert(st, 1, table.remove(st))
        end
        refresh(s)
        local w = win_info(top(s, i))
        return P.publish(letter(i) .. " layer → " .. (w and w.class or "?") .. " (" .. #st .. " stacked)")
    end

    s.sel = i
    refresh(s)
    P.publish()
end

function P.cycle_blueprint()
    local ws, s = current()
    if not ws then return P.publish() end
    s.manual = true
    s.bp = s.bp % #P.blueprints + 1
    s.sel = math.min(s.sel, slot_count(s))
    refresh(s)
    P.publish()
end

function P.put_window(k)
    local ws, s = current()
    if not ws then return P.publish() end
    local w = workspace_windows(ws.name)[k]
    if not w then return P.publish("no window " .. k .. " on this workspace") end
    local slot = s.sel
    assign(ws, s, w.address)
    P.publish(short(w.class) .. " → " .. letter(slot) .. (s.sel ~= slot and " · next " .. letter(s.sel) or ""))
end

-- Put an app's window in the selected slot: the given window, else its most recently used one
-- (only_elsewhere: skip windows already on this workspace), else launch cmd.
local function put_app(class, cmd, address, only_elsewhere)
    local ws, s = current()
    if not ws then return P.publish() end
    local found = address and hl.get_window("address:" .. address)
    if not found then
        for _, w in ipairs(mru_windows(class)) do
            if not only_elsewhere or (w.workspace and w.workspace.name) ~= ws.name then found = w break end
        end
    end
    if found then
        local slot = s.sel
        assign(ws, s, found.address)
        return P.publish(short(class) .. " → " .. letter(slot) .. (s.sel ~= slot and " · next " .. letter(s.sel) or ""))
    end
    if not cmd then return P.publish("no " .. short(class) .. " window to bring") end
    table.insert(P.pending, { class = class, ws = ws.name, slot = s.sel })
    P.last_assign = { launch = true }
    hl.exec_cmd(cmd)
    P.publish("launching " .. cmd .. " into " .. letter(s.sel))
end

-- Pool key tap: a starred app's most recent window (or launch it); any other app's most recent
-- window from another workspace. From the picker: that exact window.
function P.put_pool(key, address)
    local app = app_pool((hl.get_active_workspace() or {}).name)[key]
    if not app then return P.publish("nothing on " .. key_label(key)) end
    if app.fav then return put_app(app.class, app.fav.cmd, address) end
    put_app(app.class, nil, address, true)
end

-- Single vs double tap (P.tap_takes picks which is which). The first tap acts at once; a second tap of
-- the same key within P.double_ms turns its steal into a borrow, or its borrow into a steal.
P.double_ms   = 300
P.last_assign = nil -- set by assign(): where the window it just took came from
P.tapped      = nil -- { key, undo } for P.double_ms after a tap that took a window

local function borrow_instead(u)
    if not u then return end
    P.debug("borrow: " .. tostring(u.class) .. " " .. tostring(u.address) .. " from " .. tostring(u.from)
        .. " to " .. tostring((hl.get_active_workspace() or {}).name))
    if u.launch then return P.publish("launching: nothing to borrow yet") end
    local here = (hl.get_active_workspace() or {}).name
    if not here or not is_managed({ name = u.from }) then
        return P.publish(short(u.class) .. " came from " .. ws_label(u.from or "?") .. ": it's yours now")
    end
    for _, p in ipairs(u.places) do
        if p.ws ~= here then
            local s = state(p.ws)
            s.stacks[p.slot] = s.stacks[p.slot] or {}
            table.insert(s.stacks[p.slot], math.min(p.pos, #s.stacks[p.slot] + 1), u.address)
        end
    end
    local l = u.loan or { home = u.from, at = {} }
    if l.home ~= here then l.at[here] = true end
    P.loans[u.address] = l
    P.settle(nil, { [u.address] = here })
    P.publish(short(u.class) .. " borrowed from " .. ws_label(l.home))
end

-- Turn a borrow (made from `u`, see borrow_instead) into a steal, by the same rule as a single-tap steal.
local function steal_instead(u)
    if not u or u.launch then return end
    local here = (hl.get_active_workspace() or {}).name
    if not (here and P.loans[u.address]) then return end
    if P.steal_mode == "copy" and u.loan then take_copy(u.address, u.from, here) else P.end_loan(u.address, here) end
    P.settle()
    P.publish(short(u.class) .. " is yours now")
end

-- After a tap that took a window: with tap_takes "borrow" lend it now; a second press of `key`
-- soon after does the other one.
local function tapped(key)
    local u = P.last_assign
    P.last_assign = nil
    if not u then return false end
    local t = { key = key, undo = u }
    if P.tap_takes == "borrow" and not u.launch then
        borrow_instead(u)
        t.borrowed = true
    end
    P.tapped = t
    hl.timer(function()
        if P.tapped ~= t then return end
        P.tapped = nil
        if t.close then P.close() end
    end, { timeout = P.double_ms, type = "oneshot" })
    return t
end

-- Pickers ------------------------------------------------------------------------------------------
-- Holding a starred key lists that app's windows; holding a slot key lists that slot's layers.
-- Never a list of everything. While a picker is up its labels take over those keys.

P.picker      = nil -- { title, items = { { label, address } }, choose = fn(address) }
P.pick_labels = { "A", "S", "D", "F", "J", "K", "L", "semicolon", "Z", "X", "C", "V" }

-- ids are window addresses unless opts.display(id) says how to show something else;
-- opts.labels overrides the keys, opts.cancel runs if the picker closes without a choice.
local function open_picker(title, addresses, choose, opts)
    opts = opts or {}
    local labels = opts.labels or P.pick_labels
    local items = {}
    for k, a in ipairs(addresses) do
        if k > #labels then break end
        items[k] = { label = labels[k], address = a }
    end
    -- opts.extras: fixed rows after the items ({ label, text, run }); opts.also: other keys -> run
    P.picker = { title = title, items = items, choose = choose, display = opts.display, cancel = opts.cancel,
                 extras = opts.extras or {}, also = opts.also or {} }
    P.publish()
end

local function cancel_picker()
    local p = P.picker
    P.picker = nil
    if p and p.cancel then p.cancel() end
end

function P.screen_picker()
    local list = screens()
    if #list < 2 then return P.publish("only one screen") end
    local mon, names = hl.get_active_monitor(), {}
    for _, m in ipairs(list) do table.insert(names, m.name) end
    open_picker("Which screen?", names, P.go_screen, { display = function(name)
        local m = hl.get_monitor(name)
        return {
            class = m and screen_label(m) or name,
            title = m and m.active_workspace and ("workspace " .. m.active_workspace.name) or "",
            where = mon and mon.name == name and "you're here" or "",
        }
    end })
end

local function pick(key)
    local p = P.picker
    local run = p.also[key]
    for _, x in ipairs(p.extras) do
        if x.label == key then run = x.run end
    end
    if run then
        P.picker = nil
        run()
        if P.close_after_pick then P.close() end
        return
    end
    for _, it in ipairs(p.items) do
        if it.label == key then
            P.picker = nil
            P.last_assign = nil
            p.choose(it.address)
            local t = tapped(key)
            if P.close_after_pick then
                if t then t.close = true else P.close() end -- wait a moment for a second tap
            end
            return
        end
    end
end

-- A new window of an app, launched into the selected slot.
local function launch_new(class, cmd)
    local ws, s = current()
    if not (ws and cmd) then return P.publish("don't know how to start " .. short(class)) end
    table.insert(P.pending, { class = class, ws = ws.name, slot = s.sel })
    hl.exec_cmd(cmd)
    P.publish("new " .. short(class) .. " → " .. letter(s.sel))
end

-- Holding an app key: its windows by label, plus N (or the app's own key again) for a new one.
local function app_picker(class, put, cmd, app_key)
    local wins = mru_windows(class)
    if #wins == 0 then return put() end -- nothing open: tap and hold both launch it
    if not cmd and #wins <= 1 then return put() end -- nothing to choose between
    local addrs = {}
    for _, w in ipairs(wins) do table.insert(addrs, w.address) end
    local new = cmd and function() launch_new(class, cmd) end
    open_picker("Which " .. short(class) .. "?", addrs, put, {
        extras = new and { { label = "N", text = "New " .. short(class), run = new } } or nil,
        also = new and app_key and { [app_key] = new } or nil,
    })
end

function P.pool_picker(key)
    local app = app_pool((hl.get_active_workspace() or {}).name)[key]
    if not app then return P.put_pool(key) end
    local cmd = app.fav and app.fav.cmd
    if not cmd then
        local w = mru_windows(app.class)[1]
        cmd = w and P.launch_command(w)
    end
    app_picker(app.class, function(a) P.put_pool(key, a) end, cmd, key)
end

function P.slot_picker(i)
    local ws, s = current()
    if not ws then return P.publish() end
    local st = s.stacks[i]
    if i > slot_count(s) or not st or #st <= 1 then return P.slot_key(i) end
    local addrs = {}
    for k = #st, 1, -1 do table.insert(addrs, st[k]) end -- top first
    open_picker("Slot " .. letter(i) .. " layers", addrs, function(a)
        remove(s, a)
        push(s, i, a)
        s.sel = i
        refresh(s)
        local w = win_info(a)
        P.publish(letter(i) .. " → " .. (w and w.class or "?"))
    end)
end

-- Backspace: tap shelves the selected slot's top window (the next layer moves up); hold closes it.
-- A lent window is given back instead of shelved.
local function selected_top()
    local ws, s = current()
    if not ws then return end
    local a = top(s, s.sel)
    return ws, s, a
end

-- A lent window isn't shelved: a borrowed copy goes home (it leaves this stack), and at home the
-- loans end (it leaves every borrower). Works on its placeholder layer too.
local function give_back(ws, s, a)
    local l = P.loans[a]
    local w = win_info(a)
    local name = w and w.class or "window"
    for holder in pairs(l.at) do
        if holder == ws.name or l.home == ws.name then
            l.at[holder] = nil
            if P.ws[holder] and holder ~= l.home then remove(P.ws[holder], a) end
            if P.yields[holder] then P.yields[holder][a] = nil end
        end
    end
    P.settle(nil, { [a] = l.home == ws.name and ws.name or nil })
    refresh(s)
    if l.home == ws.name then return P.publish(name .. ": loans ended, it's only here now") end
    local now = hl.get_window("address:" .. a)
    P.publish(name .. " went back to " .. ws_label(now and now.workspace and now.workspace.name or l.home))
end

function P.shelve()
    local ws, s, a = selected_top()
    if not ws then return P.publish() end
    if not a then return P.publish(letter(s.sel) .. " is empty") end
    if P.loans[a] then return give_back(ws, s, a) end
    local w = win_info(a)
    remove(s, a)
    hl.dispatch(hl.dsp.window.move({ workspace = P.shelf, window = "address:" .. a, follow = false }))
    refresh(s)
    P.publish((w and w.class or "window") .. " → shelf (its pool key brings it back)")
end

-- Enter on a lent window's placeholder: show it here; the screen that had it yields instead.
function P.pull_here()
    local ws, s, a = selected_top()
    if not ws then return P.publish() end
    local w = a and hl.get_window("address:" .. a)
    if not (w and P.loans[a] and w.workspace and w.workspace.name ~= ws.name) then
        return P.publish("Enter brings a lent window here from its placeholder")
    end
    local there = w.workspace.name
    P.settle(nil, { [a] = ws.name })
    refresh(s)
    P.publish(short(w.class) .. " is shown here now (" .. ws_label(there) .. " gave way)")
end

function P.close_window()
    local ws, s, a = selected_top()
    if not ws then return P.publish() end
    if not a then return P.publish(letter(s.sel) .. " is empty") end
    local w = win_info(a)
    hl.dispatch(hl.dsp.window.close({ window = "address:" .. a }))
    P.publish("closed " .. (w and w.class or "window"))
end

function P.go_workspace(k)
    local n = screen_workspace(k)
    hl.dispatch(hl.dsp.focus({ workspace = n }))
    P.publish() -- the lit chip says where you are
end

-- W: trade this workspace's whole arrangement with one on the other screen (picked there).
function P.swap_workspaces(a, b, follow)
    if a == b then return end
    local wa, wb = hl.get_workspace_windows(a), hl.get_workspace_windows(b)
    P.ws[a], P.ws[b] = P.ws[b], P.ws[a]
    P.yields[a], P.yields[b] = P.yields[b], P.yields[a]
    for _, l in pairs(P.loans) do
        if l.home == a then l.home = b elseif l.home == b then l.home = a end
        l.at[a], l.at[b] = l.at[b], l.at[a]
    end
    P.quiet = true
    for _, w in ipairs(wa) do P.incoming[w.address] = b end
    for _, w in ipairs(wb) do P.incoming[w.address] = a end
    for _, w in ipairs(wa) do
        hl.dispatch(hl.dsp.window.move({ workspace = b, window = "address:" .. w.address, follow = false }))
    end
    for _, w in ipairs(wb) do
        hl.dispatch(hl.dsp.window.move({ workspace = a, window = "address:" .. w.address, follow = false }))
    end
    P.incoming = {}
    P.quiet = false
    if follow ~= false then
        hl.dispatch(hl.dsp.focus({ workspace = follow or b })) -- go with your stuff
    end
    hl.dispatch(hl.dsp.layout("refresh"))
    P.save()
end

-- Dragging one workspace chip onto another in the panel: swap them; you go with your windows if
-- either was the one you're on, otherwise you stay where you are.
function P.drag_workspace(a, b)
    a, b = tostring(a), tostring(b)
    local here = (hl.get_active_workspace() or {}).name
    local follow = here == a and b or here == b and a or false
    P.swap_workspaces(a, b, follow)
    P.publish(a .. " ⇄ " .. b)
end

function P.start_swap()
    local list = screens()
    if #list < 2 then return P.publish("only one screen") end
    local from = hl.get_active_workspace()
    local mon = hl.get_active_monitor()
    if not (from and mon) then return end
    local other = list[screen_index(mon.name) % #list + 1]
    hl.dispatch(hl.dsp.focus({ monitor = other.name }))

    local base, names = (screen_index(other.name) - 1) * #P.workspace_keys, {}
    for k = 1, #P.workspace_keys do table.insert(names, tostring(base + k)) end
    open_picker("Swap workspace " .. from.name .. " with", names, function(name)
        P.swap_workspaces(from.name, name)
        P.publish("swapped " .. from.name .. " ⇄ " .. name)
    end, {
        labels = P.workspace_keys,
        cancel = function() hl.dispatch(hl.dsp.focus({ workspace = from.name })) end,
        display = function(name)
            local apps = {}
            for _, w in ipairs((held_windows(name))) do table.insert(apps, short(w.class)) end
            return {
                class = "workspace " .. name,
                title = #apps > 0 and table.concat(apps, ", ") or "empty",
                where = other.active_workspace and other.active_workspace.name == name and "showing" or "",
            }
        end,
    })
end

function P.go_screen(name)
    hl.dispatch(hl.dsp.focus({ monitor = name }))
    focus_selected() -- type into what that screen has selected
    P.publish() -- the header names the screen
end

function P.next_screen()
    local list = screens()
    if #list < 2 then return P.publish("only one screen") end
    local mon = hl.get_active_monitor()
    P.go_screen(list[screen_index(mon and mon.name) % #list + 1].name)
end

-- Kick (Tab), per screen: back to where the panel was opened from if that was on this screen; once
-- there, to this screen's last workspace (so it ping-pongs). Q changes screens; Tab never does.
function P.kick_target()
    local mon = hl.get_active_monitor()
    local name = mon and mon.name
    local h = name and P.screen_hist[name] or {}
    local here = h.here or P.here
    if P.origin and P.origin_screen == name and P.origin ~= here then return P.origin end
    return h.last
end

function P.kick()
    local target = P.kick_target()
    if not target then return P.publish("nothing to go back to on this screen") end
    -- back into a constellation: rebuild it like its number key would (its borrowed windows went home when you left)
    for n, t in ipairs(P.constellations) do
        if "★" .. t.name == target then return P.recall(n) end
    end
    hl.dispatch(hl.dsp.focus({ workspace = tonumber(target) and target or "name:" .. target }))
    P.publish()
end

-- Lending ---------------------------------------------------------------------------------------

local function ws_target(name) return tonumber(name) and name or "name:" .. name end

local function shown_workspaces()
    local shown = {}
    for _, m in ipairs(hl.get_monitors()) do
        if m.active_workspace then shown[m.active_workspace.name] = true end
    end
    return shown
end

-- A screen gives way: if the lent window is that slot's top, it rotates to the bottom so the next
-- layer shows; flipping layers reaches it again as a placeholder.
local function yield(name, address)
    local s = P.ws[name]
    local i = s and find(s, address)
    if not i then return end
    P.yields[name] = P.yields[name] or {}
    if P.yields[name][address] then return end
    local st = s.stacks[i]
    local r = { slot = i }
    if st[#st] == address and #st > 1 then
        table.insert(st, 1, table.remove(st))
        r.top = st[#st]
    end
    P.yields[name][address] = r
end

-- It's back on a screen that gave it way: on top again if nothing else was put on top meanwhile.
local function unyield(name, address)
    local r = P.yields[name] and P.yields[name][address]
    if not r then return end
    P.yields[name][address] = nil
    local s = P.ws[name]
    if not s then return end
    local i, k = find(s, address)
    if not i or not r.top or P.yield_return ~= "top" or top(s, i) ~= r.top then return end
    table.insert(s.stacks[i], table.remove(s.stacks[i], k))
end

-- The loan is over: the window stays only in `keep`'s stacks (nil = wherever it is now).
function P.end_loan(address, keep)
    local l = P.loans[address]
    if not l then return end
    P.loans[address] = nil
    for name, ys in pairs(P.yields) do
        if name ~= keep then ys[address] = nil end
    end
    for name, st in pairs(P.ws) do
        if keep and name ~= keep and (name == l.home or l.at[name]) then remove(st, address) end
    end
end

-- Put every lent window where it belongs. A constellation only borrows while a screen shows it. A window is
-- shown where it's a slot's top layer: the screen already showing it keeps it while it's on top there;
-- buried there, it moves to another screen whose slot has it on top (no point in a lone placeholder).
-- Other screens showing a holder yield. `arrived` is the workspace that just came on screen (it yields
-- rather than taking the window); `pull` = address -> workspace for explicit moves (recall, borrow,
-- Enter), which win instead.
function P.settle(arrived, pull)
    if P.quiet then return end
    pull = pull or {}
    local shown = shown_workspaces()
    for address, l in pairs(P.loans) do
        local w = hl.get_window("address:" .. address)
        if not w then
            P.end_loan(address)
            goto next
        end
        for name in pairs(l.at) do
            if name:find("^★") and not shown[name] then
                l.at[name] = nil
                if P.ws[name] then remove(P.ws[name], address) end
                if P.yields[name] then P.yields[name][address] = nil end
            end
        end
        do
            local cur = w.workspace and w.workspace.name
            local holders = { l.home }
            for name in pairs(l.at) do table.insert(holders, name) end
            local holds = {}
            for _, name in ipairs(holders) do holds[name] = true end

            local function on_top(name)
                local st = P.ws[name]
                local i = st and find(st, address)
                return i ~= nil and top(st, i) == address
            end
            -- first a screen not just arrived, then the arrived one
            local function first_shown(want_top)
                for _, pass in ipairs({ false, true }) do
                    for _, name in ipairs(holders) do
                        if shown[name] and (name == arrived) == pass and (not want_top or on_top(name)) then
                            return name
                        end
                    end
                end
            end

            local keep
            if next(l.at) == nil then -- nobody borrows it any more: home it goes
                keep = l.home
            elseif pull[address] and holds[pull[address]] then
                keep = pull[address]
            elseif cur and holds[cur] and shown[cur] and on_top(cur) then
                keep = cur
            else
                keep = first_shown(true) -- a screen that has it on top
                if not keep and cur and holds[cur] and shown[cur] then keep = cur end
                keep = keep or first_shown(false) or (not holds[cur] and l.home) or nil
            end

            if keep and keep ~= cur then
                P.debug("settle: " .. address .. " " .. tostring(cur) .. " -> " .. keep .. (arrived and (" (arrived " .. arrived .. ")") or ""))
                hl.dispatch(hl.dsp.window.move({ workspace = ws_target(keep), window = "address:" .. address, follow = false }))
            end
            local at = keep or cur
            unyield(at, address)
            if next(l.at) == nil then
                P.end_loan(address, at)
            else
                for _, name in ipairs(holders) do
                    if name ~= at and shown[name] then yield(name, address) end
                end
            end
        end
        ::next::
    end
    hl.dispatch(hl.dsp.layout("refresh"))
end

hl.on("workspace.active", function(ws)
    P.settle(ws and ws.name)
    P.publish()
end)

-- Stacks follow the window. Empty workspaces never get a layout pass, so moves and closes are cleaned
-- up here, not in place_all. A lent window keeps its place in every workspace that holds it.
local function forget_elsewhere(address, keep)
    local l = P.loans[address]
    for name, st in pairs(P.ws) do
        if name ~= keep and not (l and (l.home == name or l.at[name])) then remove(st, address) end
    end
end

hl.on("window.close", function(win)
    if not (win and win.address) then return end
    P.end_loan(win.address)
    forget_elsewhere(win.address, nil)
    P.save()
end)

hl.on("window.move_to_workspace", function(win)
    local w = win and win.address and hl.get_window("address:" .. win.address)
    local dest = w and w.workspace and w.workspace.name
    if not dest then return end
    local l = P.loans[w.address]
    if l and dest ~= l.home and not l.at[dest] then
        P.end_loan(w.address, dest) -- moved somewhere else on purpose: the loan is over
    end
    forget_elsewhere(w.address, dest)
    P.publish()
end)

hl.on("workspace.active", function(ws)
    local name = ws and ws.name or (hl.get_active_workspace() or {}).name
    if not name or name:find("^special:") then return end
    local mon = hl.get_active_monitor()
    if mon then
        local h = P.screen_hist[mon.name] or {}
        if h.here ~= name then h.last, h.here = h.here, name end
        P.screen_hist[mon.name] = h
    end
    if name == P.here then return end
    P.last, P.here = P.here, name
    if P.mode ~= "closed" then P.publish() end
end)

-- Constellations -------------------------------------------------------------------------------------------
-- A constellation is a definition: blueprint + each slot's stack as apps (class + launch command).
-- Recalling rebuilds it from that definition every time, so nothing done to the live workspace
-- can damage it; only a deliberate save (Super+S, number, confirm) rewrites it.

P.constellations_file = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/shtl/constellations.json"
P.constellations      = {}

function P.load_constellations()
    local f = io.open(P.constellations_file, "r")
    if not f then P.constellations = {} return end
    local ok, data = pcall(json.decode, f:read("*a"))
    f:close()
    P.constellations = ok and type(data) == "table" and data.constellations or {}
end

local function write_constellations()
    os.execute("mkdir -p '" .. P.constellations_file:match("^(.*)/[^/]*$") .. "'")
    local f = io.open(P.constellations_file .. ".tmp", "w")
    if not f then return end
    f:write(json.encode({ constellations = P.constellations }))
    f:close()
    os.rename(P.constellations_file .. ".tmp", P.constellations_file)
end

P.load_constellations()

-- Dragging a constellation chip in the panel lands here: its position is its number key.
function P.move_constellation(from, to)
    local t = P.constellations[from]
    if not t or from == to then return end
    to = math.max(1, math.min(to, #P.constellations))
    table.remove(P.constellations, from)
    table.insert(P.constellations, to, t)
    write_constellations()
    P.publish("★" .. t.name .. " is now " .. to)
end

local function constellation_workspace(t) return "★" .. t.name end

-- The number of the constellation whose ★ workspace you're on, if any.
function P.here_constellation()
    local ws = hl.get_active_workspace()
    local s = ws and ws.name:find("^★") and P.ws[ws.name]
    if not (s and s.constellation) then return nil end
    for k, t in ipairs(P.constellations) do
        if t.id == s.constellation then return k end
    end
end

-- Does the live ★ workspace differ from its definition (blueprint, or any slot's apps and their order)?
function P.constellation_changed(n)
    local t = P.constellations[n]
    local s = t and P.ws[constellation_workspace(t)]
    if not s then return false end
    if P.blueprints[s.bp].name ~= t.blueprint then return true end
    for i = 1, math.max(#t.slots, slot_count(s)) do
        local live, def = {}, {}
        for _, a in ipairs(s.stacks[i] or {}) do
            local w = hl.get_window("address:" .. a)
            if w then table.insert(live, w.class) end
        end
        for _, app in ipairs(t.slots[i] or {}) do table.insert(def, app.class) end
        if table.concat(live, "\0") ~= table.concat(def, "\0") then return true end
    end
    return false
end

-- Rename: the panel takes the keyboard to type, so shtl steps out of its submap until it's done.
P.renaming = nil

function P.start_rename(n)
    if not P.constellations[n] then return end
    P.renaming = n
    hl.dispatch(hl.dsp.submap("reset"))
    P.publish("type a name · Enter keeps it · Esc cancels")
end

function P.rename_constellation(n, name)
    P.renaming = nil
    if P.mode ~= "closed" then -- Space may have been let go while typing: carry on in sticky
        P.mode = "sticky"
        hl.dispatch(hl.dsp.submap("shtl"))
    end
    local t = P.constellations[n]
    name = name and name:gsub("^%s+", ""):gsub("%s+$", "") or ""
    if not t or name == "" or name == t.name then return P.publish() end
    for k, other in ipairs(P.constellations) do
        if k ~= n and other.name == name then return P.publish("★" .. name .. " already exists") end
    end
    local old, new = constellation_workspace(t), "★" .. name
    t.name = name
    write_constellations()
    -- a recalled copy keeps working under its new name
    for _, w in ipairs(hl.get_workspaces()) do
        if w.name == old then hl.dispatch(hl.dsp.workspace.rename({ workspace = tostring(w.id), name = new })) end
    end
    if P.ws[old] then P.ws[new], P.ws[old] = P.ws[old], nil end
    P.yields[new], P.yields[old] = P.yields[old], nil
    for _, l in pairs(P.loans) do
        if l.at[old] then l.at[new], l.at[old] = true, nil end
    end
    if P.here == old then P.here = new end
    if P.last == old then P.last = new end
    if P.origin == old then P.origin = new end
    for _, h in pairs(P.screen_hist) do
        if h.here == old then h.here = new end
        if h.last == old then h.last = new end
    end
    P.save()
    P.publish("renamed to ★" .. name)
end

-- Delete only the definition: a recalled copy stays as an ordinary workspace until you leave it.
function P.delete_constellation(n)
    local t = P.constellations[n]
    if not t then return end
    table.remove(P.constellations, n)
    write_constellations()
    for _, s in pairs(P.ws) do
        if s.constellation == t.id then s.constellation = nil end
    end
    P.publish("deleted ★" .. t.name)
end

-- How to start an app again: the starred command if it is one, else the process's own command line.
local function launch_command(w)
    for _, fav in ipairs(P.starred) do
        if fav.class == w.class then return fav.cmd end
    end
    local f = io.open("/proc/" .. tostring(w.pid) .. "/cmdline", "rb")
    if not f then return nil end
    local args = {}
    local raw = f:read("*a")
    f:close()
    local parts = {}
    for arg in raw:gmatch("[^%z]+") do table.insert(parts, arg) end
    -- some apps (Electron ones like Signal) rewrite their command line into one string: run it as written
    if #parts == 1 and parts[1]:find(" ") then return parts[1] end
    for _, arg in ipairs(parts) do
        -- quote only what a shell would misread, so the command reads like one you'd type
        if arg:match("^[%w%._/%-=:,+@]+$") then
            table.insert(args, arg)
        else
            table.insert(args, "'" .. arg:gsub("'", [['"'"']]) .. "'")
        end
    end
    return #args > 0 and table.concat(args, " ") or nil
end
P.launch_command = launch_command


function P.start_save()
    local ws = current()
    if not ws then return P.publish() end
    P.saving = {}
    local n = P.here_constellation()
    if n then return P.publish("press " .. n .. " to update ★" .. P.constellations[n].name .. ", another number for a new constellation (Esc cancels)") end
    P.publish("save as constellation: press 1-9 (Esc cancels)")
end

local function save_constellation(n)
    local ws, s = current()
    if not ws then return end
    local def = { blueprint = P.blueprints[s.bp].name, slots = {} }
    local names = {}
    for i = 1, slot_count(s) do
        def.slots[i] = {}
        for _, a in ipairs(s.stacks[i] or {}) do
            local w = hl.get_window("address:" .. a)
            if w then
                table.insert(def.slots[i], { class = w.class, cmd = launch_command(w), address = a, title = w.title })
            end
        end
        local t = top(s, i)
        local w = t and hl.get_window("address:" .. t)
        if w then table.insert(names, short(w.class)) end
    end

    local old = P.constellations[n]
    def.id   = old and old.id or tostring(os.time()) .. tostring(n)
    def.name = old and old.name or (#names > 0 and table.concat(names, " + ") or "empty")
    while #P.constellations < n - 1 do table.insert(P.constellations, { id = "blank" .. #P.constellations, name = "(empty)", blueprint = "full", slots = { {} } }) end
    P.constellations[n] = def
    write_constellations()
    P.publish("saved ★" .. n .. " " .. def.name)
end

-- Number while saving: free number saves; the constellation you're in updates at once; any other taken
-- number asks to press it again.
local function save_number(n)
    if P.constellations[n] and P.saving.confirm ~= n and P.here_constellation() ~= n then
        P.saving.confirm = n
        return P.publish("★" .. n .. " " .. P.constellations[n].name .. " exists: press " .. n .. " again to replace it")
    end
    P.saving = nil
    save_constellation(n)
end

function P.recall(n)
    if P.saving then return save_number(n) end
    local t = P.constellations[n]
    if not t then return P.publish("no constellation on " .. n .. " yet: Super+S saves one") end

    local name = constellation_workspace(t)
    local from = P.here
    P.quiet = true -- windows move in below; settle once they have
    local claimed, moves, launches = {}, {}, {}
    local dirty = false -- the definition learned which windows it uses now
    local stacks = {}

    -- pick a window for every app in the definition (each window serves one entry):
    -- the very window that was saved, then one of that app already here, then the same title,
    -- then any normal workspace, then a scratchpad; ties go to the most recently used.
    -- With constellation_windows "own", only the very window counts.
    local function rank(w, app)
        if w.address == app.address then return 5 end
        local wsn = w.workspace and w.workspace.name or ""
        if wsn == name then return 4 end
        if app.title and w.title == app.title then return 3 end
        return wsn:find("^special:") and 1 or 2
    end
    for i, stack in ipairs(t.slots) do
        stacks[i] = {}
        for _, app in ipairs(stack) do
            local found, best
            for _, w in ipairs(mru_windows(app.class)) do
                if not claimed[w.address] and (P.constellation_windows ~= "own" or w.address == app.address) then
                    local r = rank(w, app)
                    if not best or r > best then found, best = w, r end
                end
            end
            if found then
                local where = found.workspace and found.workspace.name
                if where and where ~= name and is_managed(found.workspace) then -- borrow it, never steal
                    local l = P.loans[found.address] or { home = where, at = {} }
                    if l.home ~= name then
                        l.at[name] = true
                        P.loans[found.address] = l
                    end
                end
                if app.address ~= found.address or app.title ~= found.title then
                    app.address, app.title, dirty = found.address, found.title, true
                end
                claimed[found.address] = true
                table.insert(stacks[i], found.address)
                if (found.workspace and found.workspace.name) ~= name then table.insert(moves, found.address) end
            elseif app.cmd then
                table.insert(launches, { class = app.class, cmd = app.cmd, slot = i, app = app })
            end
        end
    end

    if dirty then write_constellations() end

    -- anything else on the constellation's workspace goes back where we came from
    local existing = hl.get_workspace(name)
    if existing then
        for _, w in ipairs(hl.get_workspace_windows(name)) do
            if not claimed[w.address] and from and from ~= name then
                hl.dispatch(hl.dsp.window.move({ workspace = from, window = "address:" .. w.address, follow = false }))
            end
        end
    end

    hl.dispatch(hl.dsp.focus({ workspace = "name:" .. name }))
    for _, a in ipairs(moves) do
        hl.dispatch(hl.dsp.window.move({ workspace = "name:" .. name, window = "address:" .. a, follow = false }))
    end

    -- the windows are in; now lay them out exactly as defined
    local s = state(name)
    s.manual, s.constellation, s.bp, s.sel = true, t.id, P.blueprint_index(t.blueprint, #t.slots), 1
    s.stacks = stacks
    P.yields[name] = nil
    P.quiet = false
    local pull = {}
    for _, a in ipairs(moves) do pull[a] = name end
    P.settle(nil, pull) -- screens showing their homes give way
    for _, l in ipairs(launches) do
        table.insert(P.pending, { class = l.class, ws = name, slot = l.slot, app = l.app })
        hl.exec_cmd(l.cmd)
    end
    refresh(s)
    P.publish("★" .. n .. " " .. t.name .. (#launches > 0 and (" · launching " .. #launches) or ""))
end

hl.on("window.open", function(win)
    if not win then return end
    local p
    for k, q in ipairs(P.pending) do
        if q.class == win.class then p = table.remove(P.pending, k) break end
    end
    if not p then return end
    if p.app then -- launched for a constellation: that window is the constellation's from now on
        p.app.address = win.address
        write_constellations()
    end
    local ws = hl.get_workspace(p.ws)
    if not ws then return end
    local s = state(p.ws)
    s.sel = p.slot
    assign(ws, s, win.address)
    P.publish(short(win.class) .. " → " .. letter(p.slot))
end)

-- Focusing a window another way (mouse, Super+arrows) brings it to the top of its stack and selects
-- its slot, so the state matches what is on screen.
hl.on("window.active", function(win)
    if P.mode ~= "closed" or not (win and win.workspace and is_managed(win.workspace)) then return end
    local s = state(win.workspace.name)
    local i, k = find(s, win.address)
    if not i then return end
    s.sel = math.min(i, slot_count(s))
    if k ~= #s.stacks[i] then -- e.g. Alt+Tab onto a parked layer: bring it into its slot
        table.insert(s.stacks[i], table.remove(s.stacks[i], k))
        hl.dispatch(hl.dsp.layout("refresh"))
    end
end)

-- keep the open panel current while windows come, go and retitle
for _, ev in ipairs({ "window.open", "window.close", "window.title", "workspace.active" }) do
    hl.on(ev, function()
        if P.mode ~= "closed" then P.publish() end
    end)
end

-- Hold / sticky --------------------------------------------------------------------------------

function P.hold()
    if P.mode == "closed" then P.mode = "held" end
    if not P.origin then
        P.origin = P.here
        local mon = hl.get_active_monitor()
        P.origin_screen = mon and mon.name
    end
    P.publish()
end

-- Trigger "combo": the combo toggles the panel, opening it sticky.
function P.toggle()
    if P.mode ~= "closed" then return P.close() end
    P.hold()
    P.mode = "sticky"
    hl.dispatch(hl.dsp.submap("shtl"))
    P.publish()
end

-- Trigger "firmware": open on press with plain keys working while held; release decides like a held Space.
function P.firmware_down()
    P.hold()
    hl.dispatch(hl.dsp.submap("shtl"))
end

function P.release()
    if P.renaming or P.settings_open then return end -- typing; don't close under it
    if P.press then -- Space let go before the key: that was a tap
        local p = P.press
        P.press = nil
        p.tap()
    end
    if P.picker then -- keep a picker up after letting go; choose with plain keys
        P.mode, P.used, P.close_after_pick = "sticky", false, true
        hl.dispatch(hl.dsp.submap("shtl"))
        return P.publish()
    end
    local close = P.panel_mode == "hold" or (P.panel_mode == "auto" and P.used)
    if close then
        P.close()
    else
        P.mode = "sticky"
        hl.dispatch(hl.dsp.submap("shtl"))
        P.publish()
    end
    P.used = false
end

function P.close()
    P.renaming, P.settings_open = nil, false
    if P.picker then cancel_picker() end
    P.mode, P.used, P.origin, P.origin_screen, P.saving = "closed", false, nil, nil, nil
    P.picker, P.press, P.close_after_pick = nil, nil, false
    hl.dispatch(hl.dsp.submap("reset"))
    focus_selected() -- what's lit is what you type into
    P.publish()
end

-- Keys -----------------------------------------------------------------------------------------

-- An action is a function, or { tap, long } for keys that also do something when held.
local actions = {}
for i, key in ipairs(P.slot_keys) do
    actions[key] = { tap = function() P.slot_key(i) end, long = function() P.slot_picker(i) end }
end
for k, key in ipairs(P.window_keys) do actions[key] = function() P.put_window(k) end end
for _, key in ipairs(P.app_keys) do
    actions[key] = {
        tap = function()
            P.last_assign = nil
            P.put_pool(key)
            tapped(key)
        end,
        long = function() P.pool_picker(key) end,
    }
end
for k, key in ipairs(P.workspace_keys) do actions[key] = function() P.go_workspace(k) end end
for n = 1, 9 do actions[tostring(n)] = function() P.recall(n) end end
actions.BackSpace = { tap = P.shelve, long = P.close_window, long_ms = 600 }
actions.Q = { tap = P.next_screen, long = P.screen_picker }
actions.W = P.start_swap
actions.G   = P.cycle_blueprint
actions.Return = P.pull_here
actions.Tab = P.kick

-- A held Space arrives as Ctrl+Alt+Shift, so shtl takes over Caelestia's binds on that chord
-- (group cycle back on Tab, paste latest clipboard on V).
if P.trigger == "hold" then
    for _, chord in ipairs({ "CTRL + SHIFT + ALT + TAB", "CTRL + SHIFT + ALT + V" }) do
        hl.unbind(chord)
    end
end

-- Tap vs hold: released within long_ms is a tap; still down when the timer fires is a hold.
P.long_ms = 320
P.press   = nil -- { key, tap } while a tap/hold key is down

local function key_down(key, held)
    if held or P.mode == "held" then
        P.used = true
        if not P.origin then
        P.origin = P.here
        local mon = hl.get_active_monitor()
        P.origin_screen = mon and mon.name
    end
    end
    if P.tapped and P.tapped.key == key then -- second tap: the other of steal / borrow
        local t = P.tapped
        P.tapped = nil
        if t.borrowed then steal_instead(t.undo) else borrow_instead(t.undo) end
        if t.close then P.close() end
        return
    end
    if P.picker then return pick(key) end
    local a = actions[key]
    if type(a) ~= "table" then return a() end
    local p = { key = key, tap = a.tap }
    P.press = p
    hl.timer(function()
        if P.press == p then
            P.press = nil
            a.long()
        end
    end, { timeout = a.long_ms or P.long_ms, type = "oneshot" })
end

local function key_up(key)
    local p = P.press
    if p and p.key == key then
        P.press = nil
        p.tap()
    end
end

-- Esc cancels a save in progress, otherwise closes.
local function escape()
    if P.picker and not P.close_after_pick then
        cancel_picker()
        return P.publish("picker closed")
    end
    if P.saving then
        P.saving = nil
        return P.publish("save canceled")
    end
    P.close()
end

-- The trigger's own binds. Only "hold" claims Ctrl+Alt+Shift chords (keyd sends those while the key is held).
if P.trigger == "combo" then
    hl.bind(P.trigger_combo, P.toggle, { submap_universal = true, description = "shtl: open / close" })
elseif P.trigger == "firmware" then
    hl.bind(P.trigger_firmware, P.firmware_down, { submap_universal = true, description = "shtl: open (held)" })
    hl.bind(P.trigger_firmware, P.release, { submap_universal = true, release = true, description = "shtl: release" })
end

-- While the trigger key is held via keyd (Ctrl+Alt+Shift); work inside the sticky submap too.
if P.trigger == "hold" then
for key, a in pairs(actions) do
    hl.bind(HELD .. key, function() key_down(key, true) end,
        { submap_universal = true, description = "shtl (held): " .. key })
    if type(a) == "table" then
        hl.bind(HELD .. key, function() key_up(key) end,
            { submap_universal = true, release = true, description = "shtl (held, release): " .. key })
    end
end
-- Saving a constellation is rare, so it gets Super on top (only while the panel is open).
hl.bind(HELD .. "SUPER + S", function()
    P.used = true
    P.start_save()
end, { submap_universal = true, description = "shtl (held): save constellation" })
hl.bind(HELD .. "SUPER + comma", P.open_settings, { submap_universal = true, description = "shtl (held): settings" })

hl.bind(HELD .. "Escape", escape, { submap_universal = true, description = "shtl: close" })
end

-- Sticky: plain keys until Space or Esc. Everything else is swallowed so it doesn't type into windows.
hl.define_submap("shtl", function()
    for key, a in pairs(actions) do
        hl.bind(key, function() key_down(key, false) end, { description = "shtl (sticky): " .. key })
        if type(a) == "table" then
            hl.bind(key, function() key_up(key) end, { release = true, description = "shtl (sticky, release): " .. key })
        end
    end
    for i, key in ipairs(P.slot_keys) do -- Shift + slot key = previous layer
        hl.bind("SHIFT + " .. key, function() P.slot_key(i, true) end, { description = "shtl (sticky): previous layer" })
    end
    hl.bind("SUPER + S", P.start_save, { description = "shtl (sticky): save constellation" })
    hl.bind("SUPER + comma", P.open_settings, { description = "shtl (sticky): settings" })
    hl.bind("space", P.close, { description = "shtl: close" })
    hl.bind("Escape", escape, { description = "shtl: close" })
    hl.bind("catchall", function() end)
end)

-- A config reload (Caelestia's wallpaper rotation does one every few minutes) drops fullscreen and maximized
-- windows back into the layout; put them back once the layout has taken the windows again.
if next(stored.fullscreen or {}) then
    hl.timer(function()
        for address, mode in pairs(stored.fullscreen) do
            local w = hl.get_window("address:" .. address)
            if w and (w.fullscreen or 0) == 0 then
                hl.dispatch(hl.dsp.window.fullscreen({ window = "address:" .. address,
                                                       mode = mode == 1 and "maximized" or "fullscreen", action = "set" }))
            end
        end
        P.save()
    end, { timeout = 400, type = "oneshot" })
end

-- Start the panel (and, for a held trigger key, the keyd listener) with Hyprland. A config reload keeps them.
P.root = here_dir:gsub("hypr/$", "")
hl.on("hyprland.start", function()
    hl.exec_cmd("qs -n -p '" .. P.root .. "panel'")
end)
if P.trigger == "hold" then
    hl.exec_cmd("pgrep -x shtl-listen >/dev/null || '" .. P.root .. "bin/shtl-listen'")
else
    hl.exec_cmd("pkill -x shtl-listen") -- not needed without a held key
end

return P
