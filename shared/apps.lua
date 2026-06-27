-- ─────────────────────────────────────────────────────────────
-- App registry
-- The device is a shell. Each app registers itself here so the UI can
-- list it and route to it. This is what makes Cipher a platform:
-- ship "Dark Web Market", "Contracts Board", etc. later as new apps
-- without touching the shell. Server owners enable/disable per app.
-- ─────────────────────────────────────────────────────────────
Cipher = Cipher or {}
Cipher.Apps = {}

-- Register an app.
-- @param app table: { id, label, icon, enabled, minNotorietyTier? }
function Cipher.RegisterApp(app)
    assert(app.id, 'Cipher app requires an id')
    Cipher.Apps[app.id] = {
        id = app.id,
        label = app.label or app.id,
        icon = app.icon or 'square',
        enabled = app.enabled ~= false,
        order = app.order or 100,
    }
end

-- Returns a sorted list of enabled apps for the UI.
function Cipher.GetEnabledApps()
    local list = {}
    for _, app in pairs(Cipher.Apps) do
        if app.enabled then list[#list + 1] = app end
    end
    table.sort(list, function(a, b) return a.order < b.order end)
    return list
end

-- First app: Gang Ops.
Cipher.RegisterApp({
    id = 'gangops',
    label = 'Gang Ops',
    icon = 'users',
    order = 10,
    enabled = true,
})
