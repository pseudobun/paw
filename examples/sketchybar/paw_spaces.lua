-- paw workspaces for sketchybar (SbarLua: https://github.com/FelixKratz/SbarLua).
-- require("paw_spaces") from your sketchybar init.lua, and in ~/.config/paw/config.json5:
--
--   hooks: {
--     workspaceChanged: "sketchybar --trigger paw_workspace_change",
--     windowsChanged: "sketchybar --trigger paw_windows_change",
--   },
--
-- One item per paw workspace: its name plus the apps on it (app names here; with
-- sketchybar-app-font, swap app_label for that font's icon map). Click switches, right-click
-- closes the workspace.

local SLOTS = 12 -- most workspaces shown
local colors = { fg = 0xfffbfbf9, dim = 0xff5f5f52, accent = 0xffead186, hi = 0xff2b2b22 }

local function app_label(app) return app end

sbar.add("event", "paw_workspace_change")
sbar.add("event", "paw_windows_change")

local slots, names = {}, {}
for i = 1, SLOTS do
  local item = sbar.add("item", "paw.space." .. i, {
    position = "left",
    drawing = false,
    icon = { string = tostring(i), color = colors.dim, highlight_color = colors.accent, padding_left = 7, padding_right = 4 },
    label = { color = colors.dim, highlight_color = colors.fg, padding_right = 8 },
    background = { color = 0x00000000, corner_radius = 7, height = 22 },
  })
  item:subscribe("mouse.clicked", function(env)
    local name = names[i]
    if not name then return end
    if env.BUTTON == "right" then
      sbar.exec("paw 'workspace " .. name .. "; workspace close'")
    else
      sbar.exec("paw workspace " .. name)
    end
  end)
  slots[i] = item
end

local function refresh()
  sbar.exec("paw query --json 2>/dev/null", function(workspaces)
    if type(workspaces) ~= "table" then return end
    for i = 1, SLOTS do
      local ws = workspaces[i]
      names[i] = ws and ws.name or nil
      if ws then
        local seen, apps = {}, {}
        for _, w in ipairs(ws.windows or {}) do
          if not seen[w.app] then seen[w.app] = true; apps[#apps + 1] = app_label(w.app) end
        end
        local label = table.concat(apps, " ")
        slots[i]:set({
          drawing = true,
          icon = { string = ws.name, highlight = ws.focused },
          label = { string = label, drawing = label ~= "", highlight = ws.focused },
          background = { color = ws.visible and colors.hi or 0x00000000 },
        })
      else
        slots[i]:set({ drawing = false })
      end
    end
  end)
end

local watcher = sbar.add("item", "paw.watcher", { drawing = false, updates = true })
watcher:subscribe({ "paw_workspace_change", "paw_windows_change", "system_woke", "display_change" }, refresh)
refresh()
