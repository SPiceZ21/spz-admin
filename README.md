# spz-admin

> Admin menu: players, spectate / ride along, buckets, noclip and dev tools.

![version](https://img.shields.io/badge/version-1.5.0-ff6200) ![SPiceZ-Core](https://img.shields.io/badge/SPiceZ--Core-beta-18181b)

## Overview

An ox_lib admin menu (`F1`) for player management, spectating or riding along with anyone in any bucket, a bucket browser, self tools, noclip and dev helpers.

## Features

- Player management
- Spectate / ride along across buckets
- Bucket browser
- Noclip
- Coordinate and entity tools

## Requirements

| Resource | Type |
|---|---|
| `ox_lib` | third-party |

## Installation

Included in the [txAdmin recipe](https://github.com/SPiceZ21/spz-txrecipe). Manual install:

1. Download `spz-admin` from GitHub (latest release, or the repository) into your `resources` folder.
2. Add to `server.cfg`, after its requirements:

```cfg
ensure spz-admin
```

## Configuration

- `config.lua`

See the file for every option.

## Commands

| Command | Who | Description |
|---|---|---|
| `/admin` | admin | Open the admin menu |
| `/noclip` | admin | Toggle noclip |
| `/revive` | admin | `/revive [id]` |
| `/ride` | admin | `/ride <id>` ride along |
| `/spec` | admin | `/spec <id>` spectate a player |
| `/carcode` | dev | Copy your car's spawn code |
| `/heading` | dev | Copy your heading |
| `/vec3` | dev | Copy your coords |
| `/vec4` | dev | Copy your coords + heading |

## Key binds

Rebindable in **Settings → Key Bindings → FiveM**.

| Action | Default |
|---|---|
| Admin: open menu | `F1` |
| Admin: toggle noclip | _unbound_ |

## Exports

| Export | Side |
|---|---|
| `IsAdmin` | server |

```lua
exports["spz-admin"]:IsAdmin(...)
```

---

Part of **SPiceZ-Core** — [documentation](https://github.com/SPiceZ21/Docs) · [all modules](https://github.com/SPiceZ21/Docs/blob/main/modules/README.md)
