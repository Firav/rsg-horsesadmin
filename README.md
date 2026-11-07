# rsg-horsesadmin

![License](https://img.shields.io/badge/license-GPL--3.0-blue) ![RedM](https://img.shields.io/badge/game-RedM-orange) ![Version](https://img.shields.io/badge/version-1.0.0-green)

Admin management UI for the horse data owned by **rsg-horses** (`player_horses` table).

This is the **legacy edition** for the deprecated `rsg-horses` resource. Its successor for **rsg-stables** horse data (RSG Core v3) is [firav-stablesadmin](https://github.com/Firav/firav-stablesadmin).

> [!IMPORTANT]
> This script is meant for **rsg-core v2** (RSG Core v2, the `rsg-horses` era). It does **not** support RSG Core v3 / `rsg-stables`.

> [!NOTE]
> AI was used to assist in the creation of this script.

Everything is presented through ox_lib context menus and dialogs, so there is no NUI to install.

## Dependencies

- [rsg-core](https://github.com/Rexshack-RedM/rsg-core) — **v2** (this resource is not built for RSG Core v3)
- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- **rsg-horses** (owns the `player_horses` table — deprecated upstream)
- rsg-essentials (provides `rsg-log`)

rsg-horses must start before rsg-horsesadmin (the `dependency` entry in `fxmanifest.lua` handles this).

## Installation

1. Drop `rsg-horsesadmin` into your resources folder.
2. Add `ensure rsg-horsesadmin` to your `server.cfg` **after** `ensure rsg-horses`.
3. (Optional) Add an entry to `rsg-adminmenu` that triggers `rsg-horsesadmin:client:OpenMenu`.

No manual SQL is required. On every server start the resource syncs:

- table `player_horses_recovery` — archive of deleted horses
- trigger `trg_player_horses_before_delete` — rebuilt from the columns that actually exist in your `player_horses` table; copies every deleted row into the recovery table (avoids any Lua-side race condition with rsg-horses)

Writes to `player_horses` are built dynamically from the existing columns, so different rsg-horses table layouts are tolerated.

## Usage

Use the `horseadmin` command (default, renameable in `shared/config.lua`). Players need one of the RSGCore permission levels listed in `Config.Permissions` (default: `admin`, `god`).

1. **Pick a player** — online players are listed with horse counts; offline characters are found in the `players` table by citizenid or name.
2. **View Horses** — lists every `player_horses` row of the character with stable and active status.
3. Pick a horse to edit it, force it active, or delete it — or add a brand-new horse for the character.

### Horse actions

| Action | Description |
| --- | --- |
| Edit Horse | Modify an existing horse's data (schema-aware update against `player_horses`) |
| Set Active | Forces a horse `active = 1` |
| Create Horse | Places a brand-new horse into a stable for the character |
| Delete Horse | Removes the row (auto-archived into `player_horses_recovery`) |

### Recovery

Deleted horses land in `player_horses_recovery` and can be restored into `player_horses` with a new horseid, or purged permanently.

## Configuration (`shared/config.lua`)

| Option | Default | Description |
| --- | --- | --- |
| `Config.Permissions` | `{ 'admin', 'god' }` | RSGCore permission levels allowed to use the tool |
| `Config.Command` | `'horseadmin'` | Command that opens the menu |
| `Config.LogChannel` | `'adminmenu'` | rsg-log channel for all actions |
| `Config.DefaultStable` | `'valentine'` | Stable preselected in pickers |
| `Config.NotifyAdmin` | `true` | Send success/error notifications back to the acting admin |

## Locales

All user-facing text is loaded through ox_lib locales. Edit `locales/en.json` (or add `locales/<lang>.json`) to translate the resource.

## Database

The resource creates and maintains these objects automatically:

```sql
CREATE TABLE IF NOT EXISTS `player_horses_recovery` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(50) NOT NULL,
  `horseid` VARCHAR(50) NOT NULL,
  `name` VARCHAR(50) DEFAULT NULL,
  `horse` VARCHAR(100) DEFAULT NULL,
  `gender` VARCHAR(10) DEFAULT NULL,
  `stable` VARCHAR(50) DEFAULT NULL,
  `components` LONGTEXT DEFAULT NULL,
  `horsexp` INT(11) DEFAULT 0,
  `dirt` INT(11) DEFAULT 0,
  `active` TINYINT(1) DEFAULT 0,
  `born` INT(11) DEFAULT NULL,
  `died_at` INT(11) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `citizenid` (`citizenid`),
  KEY `horseid` (`horseid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

A `BEFORE DELETE` trigger on `player_horses` (`trg_player_horses_before_delete`) copies each removed row into the recovery table.

## Logging

Every action emits `rsg-log:server:CreateLog` on the configured channel (`adminmenu` by default). `HorseDied` events are logged as well.

## License

Licensed under the [GNU General Public License v3.0](LICENSE) — the same license used by the RSG framework ([rsg-core](https://github.com/Rexshack-RedM/rsg-core)).
