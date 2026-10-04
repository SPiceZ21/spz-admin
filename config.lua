Config = {}

-- Ace that unlocks the whole menu. Every action is re-checked on the server.
--   add_ace group.admin spz.admin allow
--   add_principal identifier.license:<yours> group.admin
Config.Ace = 'spz.admin'

-- Keybinds (players can rebind in Settings > Key Bindings > FiveM).
-- Registry: Docs/keybinds.md
Config.MenuKey   = 'F1'
Config.NoclipKey = ''          -- unbound by default; /noclip or the menu

-- Hide the admin's ped from everyone while spectating / riding along, so a
-- racer never sees a body sitting in their passenger seat.
Config.HideWhileViewing = true

-- Car trolls (player page → Troll). Timed effects last `duration` seconds.
-- Off in races by default: trolling a racer wrecks the race for everyone.
Config.Troll = {
    duration    = 15,
    allowInRace = false,
}

Config.Noclip = {
    speeds  = { 0.5, 1.5, 4.0, 10.0 },  -- scroll wheel cycles these
    default = 2,
    fast    = 3.0,                      -- Shift multiplier
    slow    = 0.25,                     -- Alt multiplier
}

-- Giving admin from the menu. Grants are saved to admins.json (by license) and
-- added to this group at runtime, which needs in server.cfg:
--   add_ace resource.spz-admin command.add_principal allow
--   add_ace resource.spz-admin command.remove_principal allow
-- Without those lines a grant still unlocks this menu, just not other resources.
Config.Grant = {
    group = 'group.admin',
}

-- spz-log category for admin actions (if spz-log is running).
Config.LogCategory = 'system'

-- Decimal places for copied coordinates.
Config.Precision = 2

Config.Weather = {
    'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'OVERCAST', 'SMOG', 'FOGGY',
    'RAIN', 'THUNDER', 'CLEARING', 'NEUTRAL', 'SNOW', 'BLIZZARD', 'XMAS', 'HALLOWEEN',
}
