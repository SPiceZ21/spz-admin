-- client/menu.lua
-- ox_lib context menus. Pages are rebuilt on every open so the data is live.

local self_ = { god = false, invisible = false }

local function confirm(header, content)
    return lib.alertDialog({ header = header, content = content, centered = true, cancel = true }) == 'confirm'
end

local function done(ok, msg, fail)
    if ok then Admin.Notify(msg, 'success') else Admin.Notify(fail or 'Action failed', 'error') end
end

local openMain, openPlayers, openPlayer, openBuckets

local function allIds(players)
    local me, ids = GetPlayerServerId(PlayerId()), {}
    for _, p in ipairs(players) do if p.id ~= me then ids[#ids + 1] = p.id end end
    return ids
end

local function viewPlayer(id, mode)
    local players = Admin.Call('players') or {}
    Admin.StartView(id, mode, allIds(players))
end

-- ── Troll ────────────────────────────────────────────────────────────────────
-- { action, label, icon, description, needsVehicle, dangerous }

local CAR_TROLLS = {
    { 'launch',   'Launch',           'rocket',             'Throw the car into the air' },
    { 'boost',    'Boost',            'forward-fast',       '+160 km/h forward, instantly' },
    { 'brake',    'Brake wall',       'hand',               'Stop dead' },
    { 'spin',     'Spin out',         'rotate-right',       'Spin the car around' },
    { 'upside',   'Flip upside down', 'arrows-rotate',      'Roof on the ground' },
    { 'hop',      'Bunny hop',        'arrow-up',           'Car keeps hopping (timed)' },
    { 'tires',    'Pop tyres',        'circle-exclamation', 'Burst all tyres' },
    { 'stall',    'Stall engine',     'power-off',          'Engine dead (timed)' },
    { 'throttle', 'Stuck throttle',   'gauge-high',         'Pedal to the floor (timed)' },
    { 'nobrakes', 'Brake failure',    'ban',                'No brake, no handbrake (timed)' },
    { 'wobble',   'Wobbly steering',  'wave-square',      'Steering drifts side to side (timed)' },
    { 'slippery', 'Ice tyres',        'snowflake',          'No grip (timed)' },
    { 'limiter',  'Speed limit',      'gauge-simple-min',   'Capped at ~30 km/h (timed)' },
    { 'moon',     'Moon gravity',     'moon',               'Floaty low gravity (timed)' },
    { 'ghostcar', 'Invisible car',    'eye-slash',          'Car vanishes, driver floats (timed)' },
    { 'eject',    'Eject',            'person-falling',     'Throw them out of the car' },
    { 'lockin',   'Lock in',          'lock',               "Can't get out (timed)" },
    { 'smoke',    'Smoking engine',   'smog',               'Heavy engine smoke' },
    { 'paint',    'Random paint',     'palette',            'Random primary + secondary colour' },
    { 'horn',     'Stuck horn',       'bullhorn',           'Horn held down (timed)' },
    { 'lights',   'Disco lights',     'lightbulb',          'Headlights + indicators flash (timed)' },
    { 'explode',  'Explode car',      'bomb',               'Kills them too', true, true },
}

local PLAYER_TROLLS = {
    { 'invert',   'Invert controls',  'right-left',         'WASD flipped — left is right, W brakes (timed)' },
    { 'drunk',    'Drunk',            'wine-glass',         'Blurry, shaky, steering drifts (timed)' },
    { 'lookback', 'Look backwards',   'eye',                'Camera stuck facing behind (timed)' },
    { 'blind',    'Blackout',         'moon',               'Screen goes black for a few seconds' },
    { 'ragdoll',  'Ragdoll',          'person-falling-burst', 'Knock them over (ejects from a car)' },
    { 'fling',    'Fling',            'wind',               'Launch them through the air' },
    { 'fire',     'Set on fire',      'fire',               'Will probably kill them', false, true },
}

local function openTroll(p, backTo)
    local blocked = p.inRace and not Config.Troll.allowInRace
    local opts = {}
    if blocked then
        opts[1] = { title = 'Racing — trolls are off', description = 'Config.Troll.allowInRace', icon = 'flag-checkered', readOnly = true }
    end

    local function section(title, list, needsVeh)
        opts[#opts + 1] = { title = title, readOnly = true,
            description = (needsVeh and not p.vehicle) and (p.name .. ' is not in a vehicle') or nil }
        for _, t in ipairs(list) do
            local action, label, icon, desc, _, dangerous = t[1], t[2], t[3], t[4], t[5], t[6]
            opts[#opts + 1] = {
                title = label, description = desc, icon = icon,
                iconColor = dangerous and '#e05252' or nil,
                disabled = blocked or (needsVeh and not p.vehicle),
                onSelect = function()
                    if dangerous and not confirm(label .. '?', desc .. '.') then return openTroll(p, backTo) end
                    local ok, msg = Admin.Call('troll', p.id, action)
                    done(ok, ('%s → %s'):format(msg or label, p.name), msg)
                    openTroll(p, backTo)
                end,
            }
        end
    end

    local possessing = Admin.IsPossessing and Admin.IsPossessing() == p.id
    opts[#opts + 1] = {
        title = possessing and 'Stop possessing' or 'Possess',
        description = possessing and 'Hand the controls back'
            or 'Spectate them and drive with your WASD — works in any bucket',
        icon = 'ghost', iconColor = '#a86bf0',
        disabled = blocked or not Admin.StartPossess,   -- client/troll.lua not loaded
        onSelect = function()
            if possessing then return Admin.StopPossess() end
            local players = Admin.Call('players') or {}
            Admin.StartPossess(p.id, allIds(players))
        end,
    }

    section('Car', CAR_TROLLS, true)
    section('Player', PLAYER_TROLLS, false)

    lib.registerContext({ id = 'spz_admin_troll', title = 'Troll · ' .. p.name, menu = backTo, options = opts })
    lib.showContext('spz_admin_troll')
end

-- ── Player ───────────────────────────────────────────────────────────────────

function openPlayer(id, backTo)
    local p = Admin.Call('player', id)
    if not p then return Admin.Notify('Player is offline', 'error') end
    local isMe = id == GetPlayerServerId(PlayerId())
    local tag  = p.inRace and 'racing' or (p.inQueue and 'queued' or 'freeroam')

    local c = p.coords
    local opts = {
        {
            title = ('%s  [%d]'):format(p.name, p.id),
            description = ('Bucket %d · %s · %dms · HP %d'):format(p.bucket, tag, p.ping, p.health),
            icon = 'user', readOnly = true,
            metadata = {
                { label = 'FiveM name', value = p.steam },
                { label = 'Vehicle', value = p.vehicle and ('%s (%s)'):format(GetDisplayNameFromVehicleModel(p.vehicle), p.plate) or 'on foot' },
                { label = 'Admin', value = p.admin == 'config' and 'yes (server.cfg)' or (p.admin == 'granted' and 'yes (given in menu)' or 'no') },
                { label = 'Crew', value = p.crew or '-' },
                { label = 'License', value = p.ids.license or '-' },
                { label = 'Discord', value = p.ids.discord or '-' },
            },
        },
    }

    local function add(o) opts[#opts + 1] = o end

    if not isMe then
        add({ title = 'Spectate', icon = 'eye', description = 'Watch from their camera — works in any bucket',
            onSelect = function() viewPlayer(id, 'spectate') end })
        add({ title = 'Ride along', icon = 'car-side', description = 'Sit in a free seat of their car (hidden)',
            onSelect = function() viewPlayer(id, 'ride') end })
        add({ title = 'Go to', icon = 'person-walking-arrow-right', description = 'Teleport to them (joins their bucket)',
            onSelect = function()
                if Admin.IsViewing() then Admin.StopView() end
                local pos = Admin.Call('goto', id)
                if pos then Admin.Teleport(pos.x, pos.y, pos.z + 1.0, pos.w) else Admin.Notify('Failed', 'error') end
            end })
        add({ title = 'Bring', icon = 'person-walking-arrow-loop-left', description = 'Teleport them to you (joins your bucket)',
            onSelect = function()
                if p.inRace and not confirm('Bring racer?', 'They are in a race — bringing them pulls them out of the race bucket.') then return end
                done(Admin.Call('bring', id), 'Brought ' .. p.name)
            end })
    end

    add({ title = p.frozen and 'Unfreeze' or 'Freeze', icon = 'snowflake',
        onSelect = function()
            local frozen = Admin.Call('freeze', id)
            Admin.Notify(('%s %s'):format(p.name, frozen and 'frozen' or 'unfrozen'))
        end })
    add({ title = 'Heal / revive', icon = 'heart-pulse',
        onSelect = function() done(Admin.Call('action', id, 'heal'), 'Healed ' .. p.name) end })
    add({ title = 'Repair vehicle', icon = 'wrench', disabled = not p.vehicle,
        onSelect = function() done(Admin.Call('action', id, 'repair'), 'Repaired') end })
    add({ title = 'Flip vehicle', icon = 'rotate', disabled = not p.vehicle,
        onSelect = function() done(Admin.Call('action', id, 'flip'), 'Flipped') end })
    add({ title = 'Troll', icon = 'face-grin-squint-tears', arrow = true,
        description = 'Possess, invert controls, launch, pop tyres, drunk…',
        onSelect = function() openTroll(p, 'spz_admin_player') end })
    add({ title = 'Send message', icon = 'message',
        onSelect = function()
            local r = lib.inputDialog('Message ' .. p.name, { { type = 'textarea', label = 'Message', required = true, max = 300 } })
            if r then done(Admin.Call('message', id, r[1]), 'Sent') end
        end })
    add({ title = 'Copy their position', icon = 'location-dot', disabled = not c,
        onSelect = function() Admin.Copy(Admin.Format('vec4', c, c.w), p.name .. ' vec4') end })
    add({ title = 'Copy license', icon = 'id-card', disabled = not p.ids.license,
        onSelect = function() Admin.Copy(p.ids.license, 'license') end })

    if not p.admin then
        add({ title = 'Give admin', icon = 'user-shield', iconColor = '#3dbf7a', description = 'Saved by license, survives restarts',
            onSelect = function()
                if not confirm('Give admin to ' .. p.name .. '?', 'They get full access to this admin menu.') then return end
                local ok, msg = Admin.Call('grantAdmin', id)
                done(ok, msg, msg)
            end })
    elseif p.admin == 'granted' then
        add({ title = 'Remove admin', icon = 'user-slash', iconColor = '#e05252',
            onSelect = function()
                if not confirm('Remove admin from ' .. p.name .. '?', 'Their menu access is revoked immediately.') then return end
                local ok, msg = Admin.Call('revokeAdmin', p.ids.license)
                done(ok, msg, msg)
            end })
    end

    add({ title = 'Send to bucket…', icon = 'layer-group', description = ('Currently in %d'):format(p.bucket),
        onSelect = function()
            local r = lib.inputDialog('Send ' .. p.name .. ' to bucket', { { type = 'number', label = 'Bucket', default = 0, min = 0, required = true } })
            if r then done(Admin.Call('sendBucket', id, r[1]), ('Moved to bucket %d'):format(r[1])) end
        end })

    if p.inRace then
        add({ title = 'Remove from race (DNF)', icon = 'flag-checkered', iconColor = '#e8a33d',
            onSelect = function()
                if confirm('DNF ' .. p.name .. '?', 'They will be marked DNF and removed from the race.') then
                    done(Admin.Call('dnf', id), 'DNF\'d ' .. p.name)
                end
            end })
    end
    if p.inQueue then
        add({ title = 'Remove from queue', icon = 'list-check',
            onSelect = function() done(Admin.Call('unqueue', id), 'Removed from queue') end })
    end

    add({ title = 'Kill', icon = 'skull', iconColor = '#e05252',
        onSelect = function()
            if confirm('Kill ' .. p.name .. '?', 'Sets their health to zero.') then done(Admin.Call('action', id, 'kill'), 'Killed') end
        end })
    if not isMe then
        add({ title = 'Kick', icon = 'right-from-bracket', iconColor = '#e05252',
            onSelect = function()
                local r = lib.inputDialog('Kick ' .. p.name, { { type = 'input', label = 'Reason', placeholder = 'Kicked by an admin' } })
                if r then done(Admin.Call('kick', id, r[1]), 'Kicked ' .. p.name) end
            end })
    end

    lib.registerContext({ id = 'spz_admin_player', title = p.name, menu = backTo or 'spz_admin_players', options = opts })
    lib.showContext('spz_admin_player')
end

-- ── Players ──────────────────────────────────────────────────────────────────

function openPlayers()
    local players = Admin.Call('players') or {}
    local opts = {}
    for _, p in ipairs(players) do
        local tag = p.inRace and 'racing' or (p.inQueue and 'queued' or 'freeroam')
        opts[#opts + 1] = {
            title = ('[%d] %s'):format(p.id, p.name),
            description = ('Bucket %d · %s · %dms%s'):format(p.bucket, tag, p.ping, p.inVeh and ' · in vehicle' or ''),
            icon = p.inRace and 'flag-checkered' or 'user',
            iconColor = p.inRace and '#e8a33d' or nil,
            arrow = true,
            onSelect = function() openPlayer(p.id, 'spz_admin_players') end,
        }
    end
    if #opts == 0 then opts[1] = { title = 'No players online', readOnly = true } end

    lib.registerContext({ id = 'spz_admin_players', title = ('Players (%d)'):format(#players), menu = 'spz_admin_main', options = opts })
    lib.showContext('spz_admin_players')
end

-- ── Buckets ──────────────────────────────────────────────────────────────────

local function openBucket(b)
    local opts = {
        { title = 'Join this bucket', icon = 'right-to-bracket', description = 'Move yourself here (stay where you are)',
            onSelect = function() done(Admin.Call('joinBucket', b.id), ('Joined bucket %d'):format(b.id)) end },
    }
    local ids = {}
    for _, p in ipairs(b.players) do ids[#ids + 1] = p.id end
    if #ids > 0 then
        opts[#opts + 1] = { title = 'Spectate this bucket', icon = 'eye', description = 'Cycle only the players in here',
            onSelect = function() Admin.StartView(ids[1], 'spectate', ids) end }
    end
    for _, p in ipairs(b.players) do
        opts[#opts + 1] = { title = ('[%d] %s'):format(p.id, p.name), icon = 'user', arrow = true,
            onSelect = function() openPlayer(p.id, 'spz_admin_bucket') end }
    end

    lib.registerContext({ id = 'spz_admin_bucket', title = ('Bucket %d%s'):format(b.id, b.label and (' · ' .. b.label) or ''),
        menu = 'spz_admin_buckets', options = opts })
    lib.showContext('spz_admin_bucket')
end

function openBuckets()
    local buckets = Admin.Call('buckets') or {}
    local mine = Admin.Call('myBucket')
    local opts = {}
    for _, b in ipairs(buckets) do
        opts[#opts + 1] = {
            title = ('Bucket %d%s'):format(b.id, b.label and (' · ' .. b.label) or ''),
            description = ('%d player(s)%s'):format(#b.players, b.id == mine and ' · you are here' or ''),
            icon = b.id == 0 and 'earth-europe' or 'layer-group',
            arrow = true,
            onSelect = function() openBucket(b) end,
        }
    end
    lib.registerContext({ id = 'spz_admin_buckets', title = 'Routing buckets', menu = 'spz_admin_main', options = opts })
    lib.showContext('spz_admin_buckets')
end

-- ── Self ─────────────────────────────────────────────────────────────────────

local function openSelf()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    lib.registerContext({
        id = 'spz_admin_self', title = 'Self', menu = 'spz_admin_main',
        options = {
            { title = ('Noclip: %s'):format(Admin.IsNoclip() and 'ON' or 'off'), icon = 'feather',
                onSelect = function() Admin.ToggleNoclip() end },
            { title = ('God mode: %s'):format(self_.god and 'ON' or 'off'), icon = 'shield',
                onSelect = function()
                    self_.god = not self_.god
                    SetEntityInvincible(PlayerPedId(), self_.god)
                    SetPlayerInvincible(PlayerId(), self_.god)
                    openSelf()
                end },
            { title = ('Invisible: %s'):format(self_.invisible and 'ON' or 'off'), icon = 'ghost',
                onSelect = function()
                    self_.invisible = not self_.invisible
                    SetEntityVisible(PlayerPedId(), not self_.invisible, false)
                    openSelf()
                end },
            { title = 'Heal / revive', icon = 'heart-pulse', onSelect = function() Admin.Heal() end },
            { title = 'Teleport to waypoint', icon = 'map-pin', onSelect = function() Admin.TeleportWaypoint() end },
            { title = 'Teleport to coords…', icon = 'location-crosshairs',
                onSelect = function()
                    local r = lib.inputDialog('Teleport', { { type = 'input', label = 'x, y, z [, h]  (vec3/vec4 paste works)', required = true } })
                    if not r then return end
                    local n = {}
                    for v in r[1]:gmatch('-?%d+%.?%d*') do n[#n + 1] = tonumber(v) end
                    -- Strip the 3/4 from a pasted "vec3(" / "vec4(".
                    if r[1]:match('vec[34]%s*%(') then table.remove(n, 1) end
                    if #n < 3 then return Admin.Notify('Need at least x, y, z', 'error') end
                    Admin.Teleport(n[1], n[2], n[3], n[4])
                end },
            { title = 'Return to freeroam (bucket 0)', icon = 'earth-europe',
                onSelect = function() done(Admin.Call('joinBucket', 0), 'Back in bucket 0') end },
            { title = 'Repair my vehicle', icon = 'wrench', disabled = veh == 0,
                onSelect = function() Admin.RepairVehicle(GetVehiclePedIsIn(PlayerPedId(), false)) end },
            { title = 'Flip my vehicle', icon = 'rotate', disabled = veh == 0,
                onSelect = function() Admin.FlipVehicle(GetVehiclePedIsIn(PlayerPedId(), false)) end },
        },
    })
    lib.showContext('spz_admin_self')
end

-- ── Dev ──────────────────────────────────────────────────────────────────────

local function openDev()
    local function copy(kind, label, desc)
        return { title = 'Copy ' .. label, description = desc, icon = 'copy', onSelect = function() Admin.CopyCoords(kind) end }
    end
    lib.registerContext({
        id = 'spz_admin_dev', title = 'Dev tools', menu = 'spz_admin_main',
        options = {
            copy('vec3', 'vector3', 'vec3(x, y, z)'),
            copy('vec4', 'vector4', 'vec4(x, y, z, heading)'),
            copy('heading', 'heading', 'Heading only'),
            copy('xyz', 'x, y, z', 'Plain numbers'),
            copy('table', 'Lua table', '{ x =, y =, z =, w = }'),
            copy('json', 'JSON', '{"x":..,"y":..,"z":..,"w":..}'),
            { title = 'Copy camera', icon = 'camera', description = 'Cam coords, rotation and FOV',
                onSelect = function() Admin.CopyCamera() end },
            { title = 'Copy vehicle model', icon = 'car', onSelect = function() Admin.CopyVehicle() end },
            { title = ('Coords overlay: %s'):format(Admin.Dev.overlay and 'ON' or 'off'), icon = 'ruler-combined',
                onSelect = function() Admin.ToggleOverlay(); openDev() end },
            { title = ('Entity inspector: %s'):format(Admin.Dev.inspector and 'ON' or 'off'), icon = 'magnifying-glass',
                description = 'Aim: [E] copy vec4 · [G] copy model · [DEL] delete',
                onSelect = function() Admin.ToggleInspector() end },
        },
    })
    lib.showContext('spz_admin_dev')
end

-- ── Server ───────────────────────────────────────────────────────────────────

local function openServer()
    local weather = {}
    for _, w in ipairs(Config.Weather) do weather[#weather + 1] = { value = w, label = w } end

    lib.registerContext({
        id = 'spz_admin_server', title = 'Server', menu = 'spz_admin_main',
        options = {
            { title = 'Announcement', icon = 'bullhorn',
                onSelect = function()
                    local r = lib.inputDialog('Announcement', { { type = 'textarea', label = 'Message', required = true, max = 300 } })
                    if r then done(Admin.Call('announce', r[1]), 'Announced') end
                end },
            { title = 'Set weather', icon = 'cloud-sun',
                onSelect = function()
                    local r = lib.inputDialog('Weather', { { type = 'select', label = 'Weather', options = weather, required = true } })
                    if r then done(Admin.Call('weather', r[1]), 'Weather: ' .. r[1], 'spz-core not running') end
                end },
            { title = 'Set time', icon = 'clock',
                onSelect = function()
                    local r = lib.inputDialog('Time', {
                        { type = 'number', label = 'Hour', min = 0, max = 23, default = 12, required = true },
                        { type = 'number', label = 'Minute', min = 0, max = 59, default = 0 },
                    })
                    if r then done(Admin.Call('time', r[1], r[2] or 0), ('Time: %02d:%02d'):format(r[1], r[2] or 0), 'spz-core not running') end
                end },
            { title = 'Clear empty vehicles nearby', icon = 'broom',
                onSelect = function()
                    local r = lib.inputDialog('Clear vehicles', { { type = 'slider', label = 'Radius (m)', min = 10, max = 500, default = 50, step = 10 } })
                    if r then Admin.Notify(('Deleted %d vehicle(s)'):format(Admin.Call('clearVehicles', r[1]) or 0), 'success') end
                end },
        },
    })
    lib.showContext('spz_admin_server')
end

-- ── Admins ───────────────────────────────────────────────────────────────────

local function openAdmins()
    local list = Admin.Call('grantedAdmins') or {}
    local opts = {
        { title = 'Give admin to a player', icon = 'user-plus', description = 'Pick someone from the player list',
            onSelect = openPlayers },
    }
    for _, a in ipairs(list) do
        opts[#opts + 1] = {
            title = a.name or a.license,
            description = ('%s · given by %s on %s'):format(a.online and ('online [' .. a.online .. ']') or 'offline', a.by or '?', a.at or '?'),
            icon = 'user-shield', iconColor = a.online and '#3dbf7a' or nil,
            metadata = { { label = 'License', value = a.license } },
            onSelect = function()
                if not confirm('Remove admin from ' .. (a.name or a.license) .. '?', 'Their menu access is revoked immediately.') then return end
                local ok, msg = Admin.Call('revokeAdmin', a.license)
                done(ok, msg, msg)
                openAdmins()
            end,
        }
    end
    if #list == 0 then
        opts[#opts + 1] = { title = 'No admins given from the menu', description = 'server.cfg admins are not listed here', readOnly = true }
    end
    lib.registerContext({ id = 'spz_admin_admins', title = 'Admins', menu = 'spz_admin_main', options = opts })
    lib.showContext('spz_admin_admins')
end

-- ── Main ─────────────────────────────────────────────────────────────────────

function openMain()
    local opts = {}
    if Admin.IsPossessing and Admin.IsPossessing() then
        opts[#opts + 1] = { title = 'Stop possessing', icon = 'ghost', iconColor = '#e05252',
            onSelect = function() Admin.StopPossess() end }
    end
    if Admin.IsViewing() then
        opts[#opts + 1] = { title = 'Stop spectating', icon = 'eye-slash', iconColor = '#e05252',
            onSelect = function() Admin.StopView() end }
    end
    opts[#opts + 1] = { title = 'Players', icon = 'users', arrow = true, description = 'Manage, spectate, ride along', onSelect = openPlayers }
    opts[#opts + 1] = { title = 'Buckets', icon = 'layer-group', arrow = true, description = 'Browse routing buckets', onSelect = openBuckets }
    opts[#opts + 1] = { title = 'Self', icon = 'user-shield', arrow = true, description = 'Noclip, god mode, teleport', onSelect = openSelf }
    opts[#opts + 1] = { title = 'Dev tools', icon = 'code', arrow = true, description = 'Copy coords, overlay, inspector', onSelect = openDev }
    opts[#opts + 1] = { title = 'Admins', icon = 'user-shield', arrow = true, description = 'Give / remove admin', onSelect = openAdmins }
    opts[#opts + 1] = { title = 'Server', icon = 'server', arrow = true, description = 'Announce, weather, time, cleanup', onSelect = openServer }

    lib.registerContext({ id = 'spz_admin_main', title = 'SPiceZ Admin', options = opts })
    lib.showContext('spz_admin_main')
end

-- Admin removed while online: drop everything admin-only straight away.
RegisterNetEvent('spz-admin:revoked', function()
    if Admin.IsViewing() then Admin.StopView() end
    Admin.StopNoclip()
    Admin.Dev.overlay, Admin.Dev.inspector = false, false
    lib.hideContext(false)
end)

RegisterCommand('admin', function()
    if not Admin.Call('isAdmin') then return Admin.Notify('No permission', 'error') end
    openMain()
end, false)
RegisterKeyMapping('admin', 'Admin: open menu', 'keyboard', Config.MenuKey)

-- Quick dev commands.
RegisterCommand('vec3', function() if Admin.Call('isAdmin') then Admin.CopyCoords('vec3') end end, false)
RegisterCommand('vec4', function() if Admin.Call('isAdmin') then Admin.CopyCoords('vec4') end end, false)
RegisterCommand('heading', function() if Admin.Call('isAdmin') then Admin.CopyCoords('heading') end end, false)
-- /revive [id] — typeable while dead, when the menu is the last thing you want.
RegisterCommand('revive', function(_, args)
    if not Admin.Call('isAdmin') then return end
    local id = tonumber(args[1])
    if not id or id == GetPlayerServerId(PlayerId()) then return Admin.Heal() end
    done(Admin.Call('action', id, 'heal'), 'Revived ' .. id)
end, false)

RegisterCommand('spec', function(_, args)
    local id = tonumber(args[1])
    if not id or not Admin.Call('isAdmin') then return end
    viewPlayer(id, 'spectate')
end, false)
RegisterCommand('ride', function(_, args)
    local id = tonumber(args[1])
    if not id or not Admin.Call('isAdmin') then return end
    viewPlayer(id, 'ride')
end, false)
