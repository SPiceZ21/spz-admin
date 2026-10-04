# spz-admin

> ox_lib admin menu · `v1.0.0`

## Overview

`spz-admin` is a lightweight admin tool built on `ox_lib` context menus. Every action is
ace-gated on the server. The menu only displays things; the server decides what is allowed.

- **Spectate any player in any routing bucket.** The server moves you into the target's
  bucket, follows them if they change buckets (race start/end), and puts you back when you stop.
- **Ride along.** You sit hidden in a free seat of the target's car, with your own camera.
  If the target is on foot or the car is full, you get the spectator camera instead. When they
  get a new car (for example a race respawn), you are put back in it.
- **Players:** go to, bring, freeze, heal/revive, repair/flip their car, message, send to a
  bucket, DNF from a race, remove from the queue, kill, kick, and copy their position or license.
- **Troll:**
  - **Possess:** spectate a player in any bucket and drive their car (or walk them) with your
    own WASD. Space is handbrake or jump, Shift is sprint, Backspace stops.
  - **Car:** launch, boost, brake wall, spin out, flip upside down, bunny hop, pop tyres, stall,
    stuck throttle, brake failure, wobbly steering, ice tyres, speed limit, moon gravity,
    invisible car, eject, lock in, smoking engine, random paint, stuck horn, disco lights, explode.
  - **Player:** invert controls (WASD flipped), drunk, look backwards, blackout, ragdoll, fling,
    set on fire.
  - Timed trolls last `Config.Troll.duration` seconds and undo themselves. Trolls and possess
    are off for racers unless `Config.Troll.allowInRace` is set.
- **Buckets:** list every bucket with its spz-core label and players, join one, or spectate
  only the players in it.
- **Self:** noclip, god mode, invisibility, heal, teleport to the waypoint or to coords
  (you can paste a `vec3`/`vec4`), return to bucket 0, repair/flip your car.
- **Dev tools:** copy `vec3`, `vec4`, heading, `x, y, z`, a Lua table or JSON. Also copy the
  camera coords/rot/FOV or your vehicle model, turn on a live coords overlay, or use the
  entity inspector.
- **Admins:** give admin to any online player from their player page, and see or remove
  everyone given admin that way. Admins from server.cfg are never touched.
- **Server:** announcements, weather, time, and clearing empty vehicles nearby.

Admin actions are logged to the console and, if it is running, to `spz-log` (`Config.LogCategory`).

## Permissions

```cfg
add_ace group.admin spz.admin allow
add_principal identifier.license:<yours> group.admin
```

### Giving admin from the menu

Grants are saved by license in `admins.json` (gitignored) and re-applied on every join, so they
survive restarts. spz-admin always honours them. To make the grant a real `spz.admin` ace that
other resources see too, let the resource add principals:

```cfg
add_ace resource.spz-admin command.add_principal allow
add_ace resource.spz-admin command.remove_principal allow
```

Without these lines, a granted player can use this menu only, and the menu tells you so.

## Structure

| Side | File | Purpose |
|---|---|---|
| Shared | `config.lua` | Ace, keys, noclip speeds, precision, weather list |
| Client | `client/utils.lua` | Callback wrapper, formatting, teleport, events aimed at a target player |
| Client | `client/view.lua` | Spectate + ride-along |
| Client | `client/noclip.lua` | Noclip |
| Client | `client/dev.lua` | Coord copy, overlay, entity inspector |
| Client | `client/troll.lua` | Trolls + possess, run on the target's client |
| Client | `client/menu.lua` | ox_lib menus + commands |
| Server | `server/main.lua` | Permission check, queries, player/server actions, logging |
| Server | `server/admins.lua` | Give / remove admin, `admins.json` |
| Server | `server/view.lua` | Bucket moves for spectate / ride-along |

## Commands

| Command | Effect |
|---|---|
| `/admin` (`F1`) | Open the menu |
| `/noclip` | Toggle noclip (unbound by default) |
| `/revive [id]` | Revive yourself, or a player (works while you're dead) |
| `/spec <id>` | Spectate a player |
| `/ride <id>` | Ride along with a player |
| `/vec3` · `/vec4` · `/heading` | Copy your position to the clipboard |

While spectating: `←/→` switch player · `↑` toggle spectate/ride · `Backspace` stop.
Entity inspector: `E` copy vec4 · `G` copy model · `DEL` delete the entity.

## Exports

| Side | Export | Returns |
|---|---|---|
| Server | `IsAdmin(src)` | `boolean` |

## Dependencies

`ox_lib` · optional: `spz-core` (bucket registry, weather/time), `spz-races` (DNF, queue), `spz-log`
