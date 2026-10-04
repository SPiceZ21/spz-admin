-- server/admins.lua
-- Give / remove admin from the menu.
--
-- Two layers, because runtime ace changes aren't guaranteed:
--   1. admins.json (by license) — spz-admin's own list. Always works, persists
--      across restarts, and Admin.IsAdmin honours it.
--   2. add_principal <license> <Config.Grant.group> — so every other resource
--      that checks `spz.admin` (spz-core, spz-races …) sees it too. This needs
--         add_ace resource.spz-admin command.add_principal allow
--         add_ace resource.spz-admin command.remove_principal allow
--      in server.cfg; without it the grant is menu-only (the admin is told).
--
-- Admins from server.cfg are never touched: the menu can't remove them.

local FILE = 'admins.json'
local Granted = {}   -- [license] = { name, by, at }

local function load()
    local raw = LoadResourceFile(GetCurrentResourceName(), FILE)
    local ok, data = pcall(json.decode, raw or '')
    Granted = (ok and type(data) == 'table') and data or {}
end

local function save()
    SaveResourceFile(GetCurrentResourceName(), FILE, json.encode(Granted, { indent = true }), -1)
end

local function licenseOf(src)
    return GetPlayerIdentifierByType(src, 'license')
end

local function principal(cmd, license)
    ExecuteCommand(('%s identifier.%s %s'):format(cmd, license, Config.Grant.group))
end

local function applyGrant(src)
    local lic = licenseOf(src)
    if lic and Granted[lic] then principal('add_principal', lic) end
end

--- 'config' (server.cfg ace), 'granted' (via the menu) or nil.
function Admin.AdminStatus(src)
    local lic = licenseOf(src)
    if lic and Granted[lic] then return 'granted' end
    if IsPlayerAceAllowed(src, Config.Ace) then return 'config' end
    return nil
end

-- Widen the permission check to include menu grants.
local aceCheck = Admin.IsAdmin
function Admin.IsAdmin(src)
    if aceCheck(src) then return true end
    local lic = licenseOf(tonumber(src))
    return lic ~= nil and Granted[lic] ~= nil
end

Admin.Callback('grantAdmin', function(src, target)
    target = tonumber(target)
    if not Admin.Online(target) then return false, 'Player is offline' end
    local lic = licenseOf(target)
    if not lic then return false, 'Player has no license identifier' end
    if Admin.AdminStatus(target) then return false, 'Already an admin' end

    Granted[lic] = { name = Admin.NameOf(target), by = GetPlayerName(src), at = os.date('%Y-%m-%d %H:%M') }
    save()
    principal('add_principal', lic)

    local full = IsPlayerAceAllowed(target, Config.Ace)
    Admin.Notify(target, 'You have been given admin. Press ' .. Config.MenuKey .. ' or use /admin.', 'success')
    Admin.Log(src, 'Grant admin', ('%s gave admin to %s (%s)%s'):format(
        GetPlayerName(src), Admin.NameOf(target), lic, full and '' or ' — menu only'))
    return true, full and 'Admin given' or
        'Admin given (menu only — allow add_principal for resource.spz-admin in server.cfg for full ace)'
end)

Admin.Callback('revokeAdmin', function(src, license)
    if type(license) ~= 'string' or not Granted[license] then return false, 'Not a menu-granted admin' end
    local name = Granted[license].name
    Granted[license] = nil
    save()
    principal('remove_principal', license)

    for _, sid in ipairs(GetPlayers()) do
        local s = tonumber(sid)
        if licenseOf(s) == license then
            Admin.Notify(s, 'Your admin has been removed', 'warning')
            TriggerClientEvent('spz-admin:revoked', s)
        end
    end
    Admin.Log(src, 'Revoke admin', ('%s removed admin from %s (%s)'):format(GetPlayerName(src), name, license))
    return true, 'Admin removed from ' .. name
end)

Admin.Callback('grantedAdmins', function()
    local online = {}
    for _, sid in ipairs(GetPlayers()) do
        local lic = licenseOf(tonumber(sid))
        if lic then online[lic] = tonumber(sid) end
    end
    local out = {}
    for lic, g in pairs(Granted) do
        out[#out + 1] = { license = lic, name = g.name, by = g.by, at = g.at, online = online[lic] }
    end
    table.sort(out, function(a, b) return (a.name or '') < (b.name or '') end)
    return out
end)

-- Re-apply grants: principals live only as long as the server process.
AddEventHandler('playerJoining', function()
    applyGrant(source)
end)

load()
for _, sid in ipairs(GetPlayers()) do applyGrant(tonumber(sid)) end
