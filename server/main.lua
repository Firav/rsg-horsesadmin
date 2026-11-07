local RSGCore = exports['rsg-core']:GetCoreObject()
lib.locale()

-- helper to load shared lua tables from another resource
local function LoadSharedFile(resource, path)
    local file = LoadResourceFile(resource, path)
    if not file then
        error(('Unable to load %s from %s'):format(path, resource))
    end
    local chunk, err = load(file, ('@%s/%s'):format(resource, path))
    if not chunk then
        error(('Failed to compile %s/%s: %s'):format(resource, path, err))
    end
    return chunk()
end

local HorseSettings = LoadSharedFile('rsg-horses', 'shared/horse_settings.lua')
local HorseComp     = LoadSharedFile('rsg-horses', 'shared/horse_comp.lua')

----------------------------------
-- utilities
----------------------------------
local function HasPermission(src)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return false end
    for _, perm in ipairs(Config.Permissions) do
        if RSGCore.Functions.HasPermission(src, perm) then return true end
    end
    return false
end

local function GenerateHorseid()
    local UniqueFound = false
    local horseid = nil
    while not UniqueFound do
        horseid = tostring(RSGCore.Shared.RandomStr(3) .. RSGCore.Shared.RandomInt(3)):upper()
        local result = MySQL.prepare.await('SELECT COUNT(*) as count FROM player_horses WHERE horseid = ?', { horseid })
        if result == 0 then
            UniqueFound = true
        end
    end
    return horseid
end

local function LogEvent(title, message, color)
    color = color or 'default'
    TriggerEvent('rsg-log:server:CreateLog', Config.LogChannel, title, color, message)
end

local function Notify(src, title, type)
    if not Config.NotifyAdmin then return end
    TriggerClientEvent('ox_lib:notify', src, { title = title, type = type or 'info', duration = 7000 })
end

local function ValidateHorseName(name)
    if not name or type(name) ~= 'string' then return false end
    name = string.gsub(name, '[^%w%s%-_]', '')
    return #name >= 1 and #name <= 50, name
end

local PlayerHorsesColumns = {}

local function RefreshTableColumns()
    local result = MySQL.query.await([[
        SELECT COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'player_horses'
    ]])
    PlayerHorsesColumns = {}
    for _, row in ipairs(result or {}) do
        PlayerHorsesColumns[row.COLUMN_NAME] = true
    end
end

local function HasColumn(name)
    return PlayerHorsesColumns[name] == true
end

-- Build a dynamic INSERT for player_horses using only columns that exist
local function BuildInsertQuery(values)
    local columns = {}
    local placeholders = {}
    local params = {}
    local ordered = { 'stable', 'citizenid', 'horseid', 'name', 'horse', 'gender', 'active', 'born', 'components', 'horsexp', 'dirt' }

    for _, col in ipairs(ordered) do
        if values[col] ~= nil and HasColumn(col) then
            columns[#columns + 1] = '`' .. col .. '`'
            placeholders[#placeholders + 1] = '?'
            params[#params + 1] = values[col]
        end
    end

    local query = 'INSERT INTO player_horses (' .. table.concat(columns, ', ') .. ') VALUES (' .. table.concat(placeholders, ', ') .. ')'
    return query, params
end

-- Build a dynamic UPDATE for player_horses using only columns that exist
local function BuildUpdateQuery(id, citizenid, values)
    local sets = {}
    local params = {}
    local ordered = { 'name', 'stable', 'components', 'horsexp', 'dirt', 'gender' }

    for _, col in ipairs(ordered) do
        if values[col] ~= nil and HasColumn(col) then
            sets[#sets + 1] = '`' .. col .. '` = ?'
            params[#params + 1] = values[col]
        end
    end

    if #sets == 0 then return nil, {} end

    local query = 'UPDATE player_horses SET ' .. table.concat(sets, ', ') .. ' WHERE id = ? AND citizenid = ?'
    params[#params + 1] = id
    params[#params + 1] = citizenid
    return query, params
end

local function SanitizeComponents(components)
    if type(components) ~= 'table' then return '{}' end
    local out = {}
    for category, value in pairs(components) do
        if HorseComp[category] and type(value) == 'number' and value >= 0 and value <= #HorseComp[category] then
            out[category] = value
        end
    end
    return json.encode(out)
end

----------------------------------
-- database: recovery table + trigger
----------------------------------
CreateThread(function()
    RefreshTableColumns()
    MySQL.query.await([[
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
    ]])

    -- Build trigger dynamically using only player_horses columns that exist.
    -- Note: `died_at` is added separately because it only exists in the recovery table.
    MySQL.query.await('DROP TRIGGER IF EXISTS `trg_player_horses_before_delete`')

    local recoveryColumns = {
        'citizenid', 'horseid', 'name', 'horse', 'gender', 'stable',
        'components', 'horsexp', 'dirt', 'active', 'born'
    }
    local targetCols = {}
    local values = {}

    for _, col in ipairs(recoveryColumns) do
        if HasColumn(col) then
            targetCols[#targetCols + 1] = '`' .. col .. '`'
            values[#values + 1] = (col == 'horsexp' or col == 'dirt' or col == 'active') and 'IFNULL(OLD.`' .. col .. '`, 0)' or 'OLD.`' .. col .. '`'
        end
    end

    if #targetCols > 0 then
        targetCols[#targetCols + 1] = '`died_at`'
        values[#values + 1] = 'UNIX_TIMESTAMP()'

        local triggerSql = ([[
            CREATE TRIGGER `trg_player_horses_before_delete`
            BEFORE DELETE ON `player_horses`
            FOR EACH ROW
            BEGIN
                INSERT INTO `player_horses_recovery` (%s)
                VALUES (%s);
            END
        ]]):format(table.concat(targetCols, ', '), table.concat(values, ', '))

        MySQL.query.await(triggerSql)
    end
end)

----------------------------------
-- death watcher (logging only)
----------------------------------
-- The actual recovery copy is handled by the MySQL BEFORE DELETE trigger on
-- player_horses. This listener is kept for admin logging/notification only.
RegisterNetEvent('rsg-horses:server:HorseDied', function(horseid, horsename)
    local src = source
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player then return end

    local message = locale('sv_horsesadmin_log_horse_death_message'):format(horsename or locale('sv_horsesadmin_unknown'), horseid, Player.PlayerData.citizenid)
    LogEvent(locale('sv_horsesadmin_log_horse_death_title'), message, 'red')
end)

----------------------------------
-- callbacks
----------------------------------

-- list online players with basic horse count
lib.callback.register('rsg-horsesadmin:server:GetOnlinePlayers', function(source)
    if not HasPermission(source) then return {} end
    local players = {}
    for _, playerId in ipairs(GetPlayers()) do
        local id = tonumber(playerId)
        local Player = RSGCore.Functions.GetPlayer(id)
        if Player then
            local count = MySQL.scalar.await('SELECT COUNT(*) FROM player_horses WHERE citizenid = ?', { Player.PlayerData.citizenid })
            players[#players + 1] = {
                serverId = id,
                citizenid = Player.PlayerData.citizenid,
                name = GetPlayerName(id),
                charinfo = Player.PlayerData.charinfo,
                horseCount = count or 0,
            }
        end
    end
    return players
end)

-- search offline players by first/last name or citizenid
lib.callback.register('rsg-horsesadmin:server:SearchOfflinePlayers', function(source, query)
    if not HasPermission(source) then return {} end
    if not query or #query < 2 then return {} end
    query = '%' .. query .. '%'

    local results = MySQL.query.await([[
        SELECT citizenid, charinfo, JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) AS firstname,
               JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) AS lastname
        FROM players
        WHERE citizenid LIKE ? OR charinfo LIKE ?
        ORDER BY citizenid
        LIMIT 50
    ]], { query, query })

    local out = {}
    for _, row in ipairs(results or {}) do
        local ok, info = pcall(json.decode, row.charinfo)
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM player_horses WHERE citizenid = ?', { row.citizenid })
        out[#out + 1] = {
            citizenid = row.citizenid,
            name = (info and (info.firstname .. ' ' .. info.lastname)) or locale('cl_horsesadmin_cid_prefix'):format(row.citizenid),
            horseCount = count or 0,
        }
    end
    return out
end)

-- get all horses for a citizenid
lib.callback.register('rsg-horsesadmin:server:GetPlayerHorses', function(source, citizenid)
    if not HasPermission(source) then return {} end
    local horses = MySQL.query.await('SELECT * FROM player_horses WHERE citizenid = ?', { citizenid })
    return horses or {}
end)

-- get recovery records for a citizenid
lib.callback.register('rsg-horsesadmin:server:GetRecoveryHorses', function(source, citizenid)
    if not HasPermission(source) then return {} end
    local horses = MySQL.query.await('SELECT * FROM player_horses_recovery WHERE citizenid = ? ORDER BY died_at DESC', { citizenid })
    return horses or {}
end)

-- get all available horse models
lib.callback.register('rsg-horsesadmin:server:GetHorseModels', function(source)
    if not HasPermission(source) then return {} end
    local models = {}
    local seen = {}
    for _, v in ipairs(HorseSettings) do
        if not seen[v.horsemodel] then
            seen[v.horsemodel] = true
            models[#models + 1] = {
                model = v.horsemodel,
                name = v.horsename,
                stable = v.stableid,
                price = v.horseprice,
            }
        end
    end
    return models
end)

-- get unique stable ids from horse settings
lib.callback.register('rsg-horsesadmin:server:GetStables', function(source)
    if not HasPermission(source) then return {} end
    local stables = {}
    local seen = {}
    for _, v in ipairs(HorseSettings) do
        if not seen[v.stableid] then
            seen[v.stableid] = true
            stables[#stables + 1] = v.stableid
        end
    end
    return stables
end)

----------------------------------
-- net events
----------------------------------

-- create a brand new horse for a citizenid
RegisterNetEvent('rsg-horsesadmin:server:CreateHorse', function(data)
    local src = source
    if not HasPermission(src) then
        Notify(src, locale('sv_horsesadmin_no_permission'), 'error')
        return
    end

    local citizenid = data.citizenid
    local model = data.model
    local stable = data.stable or Config.DefaultStable
    local gender = data.gender or 'male'
    local name = data.name or locale('sv_horsesadmin_default_horse_name')

    local valid, cleanName = ValidateHorseName(name)
    if not valid then
        Notify(src, locale('sv_horsesadmin_invalid_name'), 'error')
        return
    end

    local horseInfo = nil
    for _, v in pairs(HorseSettings) do
        if v.horsemodel == model then
            horseInfo = v
            break
        end
    end

    if not horseInfo then
        Notify(src, locale('sv_horsesadmin_invalid_model'), 'error')
        return
    end

    local horseid = GenerateHorseid()
    local components = SanitizeComponents(data.components)

    local query, params = BuildInsertQuery({
        stable = stable,
        citizenid = citizenid,
        horseid = horseid,
        name = cleanName,
        horse = model,
        gender = gender,
        active = 0,
        born = os.time(),
        components = components,
        horseexp = tonumber(data.horseexp) or 0,
        dirt = tonumber(data.dirt) or 0,
    })

    MySQL.insert(query, params)

    local adminName = GetPlayerName(src) or locale('sv_horsesadmin_console_name')
    local message = locale('sv_horsesadmin_log_created_message'):format(adminName, cleanName, horseid, citizenid, stable)
    LogEvent(locale('sv_horsesadmin_log_created_title'), message, 'green')
    Notify(src, locale('sv_horsesadmin_horse_created'), 'success')
end)

-- recover a horse from the recovery table into player_horses
RegisterNetEvent('rsg-horsesadmin:server:RecoverHorse', function(data)
    local src = source
    if not HasPermission(src) then
        Notify(src, locale('sv_horsesadmin_no_permission'), 'error')
        return
    end

    local recovery = MySQL.query.await('SELECT * FROM player_horses_recovery WHERE id = ?', { data.id })
    if not recovery or not recovery[1] then
        Notify(src, locale('sv_horsesadmin_recovery_record_not_found'), 'error')
        return
    end

    local h = recovery[1]
    local newHorseid = GenerateHorseid()
    local stable = data.stable or h.stable or Config.DefaultStable

    local query, params = BuildInsertQuery({
        stable = stable,
        citizenid = h.citizenid,
        horseid = newHorseid,
        name = h.name,
        horse = h.horse,
        gender = h.gender,
        active = 0,
        born = h.born or os.time(),
        components = h.components,
        horseexp = h.horsexp or 0,
        dirt = h.dirt or 0,
    })

    MySQL.insert(query, params)
    MySQL.update('DELETE FROM player_horses_recovery WHERE id = ?', { data.id })

    local adminName = GetPlayerName(src) or locale('sv_horsesadmin_console_name')
    local message = locale('sv_horsesadmin_log_recovered_message'):format(adminName, h.name or locale('sv_horsesadmin_unknown'), h.horseid, newHorseid, h.citizenid, stable)
    LogEvent(locale('sv_horsesadmin_log_recovered_title'), message, 'green')
    Notify(src, locale('sv_horsesadmin_horse_recovered'), 'success')
end)

-- delete a horse from player_horses
RegisterNetEvent('rsg-horsesadmin:server:DeleteHorse', function(data)
    local src = source
    if not HasPermission(src) then
        Notify(src, locale('sv_horsesadmin_no_permission'), 'error')
        return
    end

    local horse = MySQL.query.await('SELECT * FROM player_horses WHERE id = ? AND citizenid = ?', { data.id, data.citizenid })
    if not horse or not horse[1] then
        Notify(src, locale('sv_horsesadmin_horse_not_found'), 'error')
        return
    end

    local h = horse[1]
    local horsestash = h.name .. ' ' .. h.horseid
    MySQL.update('DELETE FROM inventories WHERE identifier = ?', { horsestash })
    MySQL.update('DELETE FROM player_horses WHERE id = ?', { data.id })

    local adminName = GetPlayerName(src) or locale('sv_horsesadmin_console_name')
    local message = locale('sv_horsesadmin_log_deleted_message'):format(adminName, h.name or locale('sv_horsesadmin_unknown'), h.horseid, h.citizenid)
    LogEvent(locale('sv_horsesadmin_log_deleted_title'), message, 'red')
    Notify(src, locale('sv_horsesadmin_horse_deleted'), 'success')
end)

-- set horse active (spawn target to current active)
RegisterNetEvent('rsg-horsesadmin:server:SetHorseActive', function(data)
    local src = source
    if not HasPermission(src) then
        Notify(src, locale('sv_horsesadmin_no_permission'), 'error')
        return
    end

    local citizenid = data.citizenid
    local id = data.id

    local current = MySQL.scalar.await('SELECT id FROM player_horses WHERE citizenid = ? AND active = ?', { citizenid, 1 })
    if current then
        MySQL.update('UPDATE player_horses SET active = ? WHERE id = ?', { 0, current })
    end

    MySQL.update('UPDATE player_horses SET active = ? WHERE id = ? AND citizenid = ?', { 1, id, citizenid })

    local adminName = GetPlayerName(src) or locale('sv_horsesadmin_console_name')
    LogEvent(locale('sv_horsesadmin_log_set_active_title'), locale('sv_horsesadmin_log_set_active_message'):format(adminName, id, citizenid), 'blue')
    Notify(src, locale('sv_horsesadmin_horse_set_active'), 'success')
end)

-- delete a recovery record
RegisterNetEvent('rsg-horsesadmin:server:DeleteRecoveryRecord', function(data)
    local src = source
    if not HasPermission(src) then
        Notify(src, locale('sv_horsesadmin_no_permission'), 'error')
        return
    end

    MySQL.update('DELETE FROM player_horses_recovery WHERE id = ?', { data.id })

    local adminName = GetPlayerName(src) or locale('sv_horsesadmin_console_name')
    LogEvent(locale('sv_horsesadmin_log_recovery_deleted_title'), locale('sv_horsesadmin_log_recovery_deleted_message'):format(adminName, data.id), 'red')
    Notify(src, locale('sv_horsesadmin_recovery_record_deleted'), 'success')
end)

-- update horse details (name, stable, components, xp, dirt)
RegisterNetEvent('rsg-horsesadmin:server:UpdateHorse', function(data)
    local src = source
    if not HasPermission(src) then
        Notify(src, locale('sv_horsesadmin_no_permission'), 'error')
        return
    end

    local valid, cleanName = ValidateHorseName(data.name)
    if not valid then
        Notify(src, locale('sv_horsesadmin_invalid_name'), 'error')
        return
    end

    local components = SanitizeComponents(data.components)

    local query, params = BuildUpdateQuery(data.id, data.citizenid, {
        name = cleanName,
        stable = data.stable,
        components = components,
        horseexp = tonumber(data.horseexp) or 0,
        dirt = tonumber(data.dirt) or 0,
        gender = data.gender,
    })

    if query then
        MySQL.update(query, params)
    end

    local adminName = GetPlayerName(src) or locale('sv_horsesadmin_console_name')
    LogEvent(locale('sv_horsesadmin_log_updated_title'), locale('sv_horsesadmin_log_updated_message'):format(adminName, data.id, data.citizenid), 'blue')
    Notify(src, locale('sv_horsesadmin_horse_updated'), 'success')
end)

-- server-side permission gate for the menu
RegisterNetEvent('rsg-horsesadmin:server:RequestMenu', function()
    local src = source
    if not HasPermission(src) then
        Notify(src, locale('sv_horsesadmin_no_permission'), 'error')
        return
    end
    TriggerClientEvent('rsg-horsesadmin:client:OpenMenu', src)
end)

-- command
RSGCore.Commands.Add(Config.Command, locale('sv_horsesadmin_command_desc'), {}, false, function(source)
    TriggerClientEvent('rsg-horsesadmin:client:OpenMenu', source)
end, 'admin')
