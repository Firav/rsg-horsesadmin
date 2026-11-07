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

local CurrentTarget = nil
local HorseModels = {}
local StableList = {}

-- format unix timestamp into a human-readable date/time string
local function FormatDateTime(timestamp)
    if not timestamp or type(timestamp) ~= 'number' then return locale('cl_horsesadmin_unknown_date') end

    if os and os.date then
        return os.date('%m/%d/%Y %H:%M', timestamp)
    end

    -- fallback pure Lua formatter (UTC)
    local daysInMonth = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
    local function isLeap(year)
        return (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
    end

    local days = math.floor(timestamp / 86400)
    local seconds = timestamp % 86400
    local hour = math.floor(seconds / 3600)
    local minute = math.floor((seconds % 3600) / 60)

    local year = 1970
    while true do
        local leap = isLeap(year) and 1 or 0
        local yearDays = 365 + leap
        if days < yearDays then break end
        days = days - yearDays
        year = year + 1
    end

    daysInMonth[2] = isLeap(year) and 29 or 28
    local month = 1
    while days >= daysInMonth[month] do
        days = days - daysInMonth[month]
        month = month + 1
    end

    local day = days + 1
    return string.format('%02d/%02d/%04d %02d:%02d', month, day, year, hour, minute)
end

local function OpenMenu()
    TriggerEvent('rsg-horsesadmin:client:MainMenu')
end

RegisterNetEvent('rsg-horsesadmin:client:OpenMenu', OpenMenu)

RegisterCommand(Config.Command, function()
    TriggerServerEvent('rsg-horsesadmin:server:RequestMenu')
end, false)

----------------------------------
-- menus
----------------------------------

RegisterNetEvent('rsg-horsesadmin:client:MainMenu', function()
    lib.registerContext({
        id = 'horsesadmin_main',
        title = locale('cl_horsesadmin_main_title'),
        options = {
            {
                title = locale('cl_horsesadmin_manage_online_title'),
                description = locale('cl_horsesadmin_manage_online_desc'),
                icon = 'fa-solid fa-users',
                onSelect = OpenOnlinePlayersMenu,
            },
            {
                title = locale('cl_horsesadmin_manage_offline_title'),
                description = locale('cl_horsesadmin_manage_offline_desc'),
                icon = 'fa-solid fa-user-slash',
                onSelect = OpenOfflineSearchMenu,
            },
        }
    })
    lib.showContext('horsesadmin_main')
end)

----------------------------------
-- online players
----------------------------------

function OpenOnlinePlayersMenu()
    lib.callback('rsg-horsesadmin:server:GetOnlinePlayers', false, function(players)
        local options = {}

        if not players or #players == 0 then
            options[#options + 1] = { title = locale('cl_horsesadmin_no_players'), disabled = true }
        else
            for _, p in ipairs(players) do
                local label = locale('cl_horsesadmin_player_label'):format(p.name, p.serverId, p.citizenid)
                options[#options + 1] = {
                    title = label,
                    description = locale('cl_horsesadmin_horses_count_desc'):format(p.horseCount),
                    icon = 'fa-solid fa-user',
                    onSelect = function()
                        CurrentTarget = { citizenid = p.citizenid, name = p.name }
                        OpenCharacterMenu()
                    end,
                }
            end
        end

        lib.registerContext({
            id = 'horsesadmin_online',
            title = locale('cl_horsesadmin_online_title'),
            menu = 'horsesadmin_main',
            options = options,
        })
        lib.showContext('horsesadmin_online')
    end)
end

----------------------------------
-- offline search
----------------------------------

function OpenOfflineSearchMenu()
    local dialog = lib.inputDialog(locale('cl_horsesadmin_find_offline_title'), {
        { type = 'input', label = locale('cl_horsesadmin_search_label'), description = locale('cl_horsesadmin_search_desc'), required = true },
    })

    if not dialog or not dialog[1] or #dialog[1] < 2 then
        lib.showContext('horsesadmin_main')
        return
    end

    lib.callback('rsg-horsesadmin:server:SearchOfflinePlayers', false, function(players)
        local options = {}

        if not players or #players == 0 then
            options[#options + 1] = { title = locale('cl_horsesadmin_no_characters'), disabled = true }
        else
            for _, p in ipairs(players) do
                options[#options + 1] = {
                    title = locale('cl_horsesadmin_player_offline_label'):format(p.name, p.citizenid),
                    description = locale('cl_horsesadmin_horses_count_desc'):format(p.horseCount),
                    icon = 'fa-solid fa-user',
                    onSelect = function()
                        CurrentTarget = { citizenid = p.citizenid, name = p.name }
                        OpenCharacterMenu()
                    end,
                }
            end
        end

        lib.registerContext({
            id = 'horsesadmin_offline',
            title = locale('cl_horsesadmin_offline_title'),
            menu = 'horsesadmin_main',
            options = options,
        })
        lib.showContext('horsesadmin_offline')
    end, dialog[1])
end

----------------------------------
-- character horse management
----------------------------------

function OpenCharacterMenu()
    if not CurrentTarget then return end

    lib.registerContext({
        id = 'horsesadmin_character',
        title = locale('cl_horsesadmin_character_title'):format(CurrentTarget.name),
        menu = 'horsesadmin_main',
        options = {
            {
                title = locale('cl_horsesadmin_view_horses_title'),
                description = locale('cl_horsesadmin_view_horses_desc'),
                icon = 'fa-solid fa-eye',
                onSelect = OpenHorsesListMenu,
            },
            {
                title = locale('cl_horsesadmin_add_horse_title'),
                description = locale('cl_horsesadmin_add_horse_desc'),
                icon = 'fa-solid fa-plus',
                onSelect = OpenCreateHorseMenu,
            },
            {
                title = locale('cl_horsesadmin_recovery_title'),
                description = locale('cl_horsesadmin_recovery_desc'),
                icon = 'fa-solid fa-trash-arrow-up',
                onSelect = OpenRecoveryMenu,
            },
        }
    })
    lib.showContext('horsesadmin_character')
end

----------------------------------
-- list horses
----------------------------------

function OpenHorsesListMenu()
    if not CurrentTarget then return end

    lib.callback('rsg-horsesadmin:server:GetPlayerHorses', false, function(horses)
        local options = {}

        if not horses or #horses == 0 then
            options[#options + 1] = { title = locale('cl_horsesadmin_no_horses'), disabled = true }
        else
            for _, h in ipairs(horses) do
                local active = tonumber(h.active) == 1 and locale('cl_horsesadmin_active_suffix') or ''
                options[#options + 1] = {
                    title = locale('cl_horsesadmin_horse_name_active'):format(h.name or locale('cl_horsesadmin_unnamed'), active),
                    description = locale('cl_horsesadmin_horse_desc'):format(h.horse, h.horsexp or 0, h.stable or locale('cl_horsesadmin_none')),
                    icon = 'fa-solid fa-horse',
                    onSelect = function()
                        OpenHorseActionMenu(h)
                    end,
                }
            end
        end

        lib.registerContext({
            id = 'horsesadmin_horses',
            title = locale('cl_horsesadmin_horses_title'):format(CurrentTarget.name),
            menu = 'horsesadmin_character',
            options = options,
        })
        lib.showContext('horsesadmin_horses')
    end, CurrentTarget.citizenid)
end

----------------------------------
-- horse actions
----------------------------------

function OpenHorseActionMenu(horse)
    if not CurrentTarget then return end

    lib.registerContext({
        id = 'horsesadmin_horseactions',
        title = locale('cl_horsesadmin_actions_title'):format(horse.name or locale('cl_horsesadmin_unnamed')),
        menu = 'horsesadmin_horses',
        options = {
            {
                title = locale('cl_horsesadmin_edit_horse_title'),
                description = locale('cl_horsesadmin_edit_horse_desc'),
                icon = 'fa-solid fa-pen-to-square',
                onSelect = function()
                    OpenEditHorseMenu(horse)
                end,
            },
            {
                title = locale('cl_horsesadmin_set_active_title'),
                description = locale('cl_horsesadmin_set_active_desc'),
                icon = 'fa-solid fa-check',
                onSelect = function()
                    TriggerServerEvent('rsg-horsesadmin:server:SetHorseActive', {
                        id = horse.id,
                        citizenid = horse.citizenid,
                    })
                    OpenHorsesListMenu()
                end,
            },
            {
                title = locale('cl_horsesadmin_delete_horse_title'),
                description = locale('cl_horsesadmin_delete_horse_desc'),
                icon = 'fa-solid fa-trash',
                onSelect = function()
                    local confirm = lib.alertDialog({
                        header = locale('cl_horsesadmin_delete_header'),
                        content = locale('cl_horsesadmin_delete_confirm_content'):format(horse.name or locale('cl_horsesadmin_delete_fallback')),
                        centered = true,
                        cancel = true,
                    })
                    if confirm == 'confirm' then
                        TriggerServerEvent('rsg-horsesadmin:server:DeleteHorse', {
                            id = horse.id,
                            citizenid = horse.citizenid,
                        })
                        OpenHorsesListMenu()
                    end
                end,
            },
        }
    })
    lib.showContext('horsesadmin_horseactions')
end

----------------------------------
-- edit horse
----------------------------------

function OpenEditHorseMenu(horse)
    if not CurrentTarget then return end

    local components = {}
    if horse.components and horse.components ~= '' then
        local ok, decoded = pcall(json.decode, horse.components)
        if ok and type(decoded) == 'table' then
            components = decoded
        end
    end

    local gender = horse.gender or 'male'

    -- working copy of values
    local updated = {
        id = horse.id,
        citizenid = horse.citizenid,
        name = horse.name,
        stable = horse.stable,
        gender = gender,
        horseexp = tonumber(horse.horsexp) or 0,
        dirt = tonumber(horse.dirt) or 0,
        components = components,
    }

    local function refreshMenu()
        local editTitle = locale('cl_horsesadmin_edit_horse_title'):format(updated.name or locale('cl_horsesadmin_unnamed'))
        lib.registerContext({
            id = 'horsesadmin_edit',
            title = editTitle,
            menu = 'horsesadmin_horseactions',
            options = {
                {
                    title = locale('cl_horsesadmin_name_display'):format(updated.name or ''),
                    icon = 'fa-solid fa-signature',
                    onSelect = function()
                        local input = lib.inputDialog(locale('cl_horsesadmin_horse_name_title'), {
                            { type = 'input', label = locale('cl_horsesadmin_name_label'), default = updated.name, required = true },
                        })
                        if input and input[1] then
                            updated.name = input[1]
                        end
                        refreshMenu()
                    end,
                },
                {
                    title = locale('cl_horsesadmin_stable_display'):format(updated.stable or ''),
                    icon = 'fa-solid fa-warehouse',
                    onSelect = function()
                        OpenStablePicker(function(stable)
                            updated.stable = stable
                            refreshMenu()
                        end)
                    end,
                },
                {
                    title = locale('cl_horsesadmin_gender_display'):format(updated.gender),
                    icon = 'fa-solid fa-venus-mars',
                    onSelect = function()
                        updated.gender = updated.gender == 'male' and 'female' or 'male'
                        refreshMenu()
                    end,
                },
                {
                    title = locale('cl_horsesadmin_xp_display'):format(updated.horseexp),
                    icon = 'fa-solid fa-arrow-trend-up',
                    onSelect = function()
                        local input = lib.inputDialog(locale('cl_horsesadmin_horse_xp_title'), {
                            { type = 'number', label = locale('cl_horsesadmin_xp_label'), default = updated.horseexp, required = true },
                        })
                        if input and input[1] then
                            updated.horseexp = tonumber(input[1]) or 0
                        end
                        refreshMenu()
                    end,
                },
                {
                    title = locale('cl_horsesadmin_dirt_display'):format(updated.dirt),
                    icon = 'fa-solid fa-soap',
                    onSelect = function()
                        local input = lib.inputDialog(locale('cl_horsesadmin_horse_dirt_title'), {
                            { type = 'number', label = locale('cl_horsesadmin_dirt_range_label'), default = updated.dirt, required = true },
                        })
                        if input and input[1] then
                            updated.dirt = math.min(100, math.max(0, tonumber(input[1]) or 0))
                        end
                        refreshMenu()
                    end,
                },
                {
                    title = locale('cl_horsesadmin_edit_components_title'),
                    description = locale('cl_horsesadmin_custom_components_desc'),
                    icon = 'fa-solid fa-screwdriver-wrench',
                    onSelect = function()
                        OpenComponentsMenu(updated, function(newComponents)
                            updated.components = newComponents
                            refreshMenu()
                        end)
                    end,
                },
                {
                    title = locale('cl_horsesadmin_save_changes_title'),
                    description = locale('cl_horsesadmin_save_changes_desc'),
                    icon = 'fa-solid fa-floppy-disk',
                    onSelect = function()
                        TriggerServerEvent('rsg-horsesadmin:server:UpdateHorse', updated)
                        OpenHorsesListMenu()
                    end,
                },
            }
        })
        lib.showContext('horsesadmin_edit')
    end

    refreshMenu()
end

----------------------------------
-- create new horse
----------------------------------

function OpenCreateHorseMenu()
    if not CurrentTarget then return end

    lib.callback('rsg-horsesadmin:server:GetHorseModels', false, function(models)
        HorseModels = models or {}
        local options = {}

        if #HorseModels == 0 then
            options[#options + 1] = { title = locale('cl_horsesadmin_no_models'), disabled = true }
        else
            for _, m in ipairs(HorseModels) do
                options[#options + 1] = {
                    title = locale('cl_horsesadmin_model_name_label'):format(m.name, m.model),
                    description = locale('cl_horsesadmin_stable_desc'):format(m.stable),
                    icon = 'fa-solid fa-horse',
                    onSelect = function()
                        OpenCreateDetailsMenu(m.model, m.stable)
                    end,
                }
            end
        end

        lib.registerContext({
            id = 'horsesadmin_create',
            title = locale('cl_horsesadmin_create_title'),
            menu = 'horsesadmin_character',
            options = options,
        })
        lib.showContext('horsesadmin_create')
    end)
end

function OpenCreateDetailsMenu(model, defaultStable)
    if not CurrentTarget then return end

    EnsureStableList(function()
        local input = lib.inputDialog(locale('cl_horsesadmin_create_title'), {
            { type = 'input', label = locale('cl_horsesadmin_horse_name_label'), required = true },
            { type = 'select', label = locale('cl_horsesadmin_gender_label'), options = { { value = 'male', label = locale('cl_horsesadmin_male') }, { value = 'female', label = locale('cl_horsesadmin_female') } }, required = true },
            { type = 'select', label = locale('cl_horsesadmin_stable_label'), options = BuildStableOptions(defaultStable), required = true },
            { type = 'number', label = locale('cl_horsesadmin_starting_xp_label'), default = 0 },
        })

        if not input then
            OpenCreateHorseMenu()
            return
        end

        local name = input[1]
        local gender = input[2]
        local stable = input[3]
        local xp = tonumber(input[4]) or 0

        TriggerServerEvent('rsg-horsesadmin:server:CreateHorse', {
            citizenid = CurrentTarget.citizenid,
            model = model,
            name = name,
            gender = gender,
            stable = stable,
            horseexp = xp,
        })

        OpenCharacterMenu()
    end)
end

----------------------------------
-- recovery menu
----------------------------------

function OpenRecoveryMenu()
    if not CurrentTarget then return end

    lib.callback('rsg-horsesadmin:server:GetRecoveryHorses', false, function(horses)
        local options = {}

        if not horses or #horses == 0 then
            options[#options + 1] = { title = locale('cl_horsesadmin_no_recovery'), disabled = true }
        else
            for _, h in ipairs(horses) do
                local died = FormatDateTime(h.died_at)
                options[#options + 1] = {
                    title = locale('cl_horsesadmin_model_name_label'):format(h.name or locale('cl_horsesadmin_unnamed'), h.horse),
                    description = locale('cl_horsesadmin_recovery_record_desc'):format(died),
                    icon = 'fa-solid fa-trash-arrow-up',
                    onSelect = function()
                        OpenRecoveryActionMenu(h)
                    end,
                }
            end
        end

        lib.registerContext({
            id = 'horsesadmin_recovery',
            title = locale('cl_horsesadmin_recovery_menu_title'):format(CurrentTarget.name),
            menu = 'horsesadmin_character',
            options = options,
        })
        lib.showContext('horsesadmin_recovery')
    end, CurrentTarget.citizenid)
end

function OpenRecoveryActionMenu(horse)
    if not CurrentTarget then return end

    lib.registerContext({
        id = 'horsesadmin_recoveryactions',
        title = locale('cl_horsesadmin_recovery_actions_title'):format(horse.name or locale('cl_horsesadmin_unnamed')),
        menu = 'horsesadmin_recovery',
        options = {
            {
                title = locale('cl_horsesadmin_recover_to_stable_title'),
                description = locale('cl_horsesadmin_recover_to_stable_desc'),
                icon = 'fa-solid fa-rotate-left',
                onSelect = function()
                    OpenStablePicker(function(stable)
                        TriggerServerEvent('rsg-horsesadmin:server:RecoverHorse', {
                            id = horse.id,
                            stable = stable,
                        })
                        OpenRecoveryMenu()
                    end)
                end,
            },
            {
                title = locale('cl_horsesadmin_delete_record_title'),
                description = locale('cl_horsesadmin_delete_record_desc'),
                icon = 'fa-solid fa-trash',
                onSelect = function()
                    local confirm = lib.alertDialog({
                        header = locale('cl_horsesadmin_delete_record_header'),
                        content = locale('cl_horsesadmin_delete_record_content'),
                        centered = true,
                        cancel = true,
                    })
                    if confirm == 'confirm' then
                        TriggerServerEvent('rsg-horsesadmin:server:DeleteRecoveryRecord', { id = horse.id })
                        OpenRecoveryMenu()
                    end
                end,
            },
        }
    })
    lib.showContext('horsesadmin_recoveryactions')
end

----------------------------------
-- helpers
----------------------------------

function EnsureStableList(cb)
    if #StableList > 0 then
        cb()
        return
    end

    lib.callback('rsg-horsesadmin:server:GetStables', false, function(stables)
        StableList = stables or {}
        cb()
    end)
end

function OpenStablePicker(cb)
    EnsureStableList(function()
        if #StableList == 0 then
            lib.notify({ title = locale('cl_horsesadmin_stable_list_not_ready'), type = 'error', duration = 5000 })
            return
        end

        local options = {}
        for _, stable in ipairs(StableList) do
            options[#options + 1] = { value = stable, label = stable }
        end

        local input = lib.inputDialog(locale('cl_horsesadmin_select_stable_title'), {
            { type = 'select', label = locale('cl_horsesadmin_stable_label'), options = options, required = true },
        })

        if input and input[1] then
            cb(input[1])
        end
    end)
end

function BuildStableOptions(defaultStable)
    local options = {}
    for _, s in ipairs(StableList) do
        options[#options + 1] = { value = s, label = s, default = s == defaultStable }
    end
    if #options == 0 then
        options[#options + 1] = { value = Config.DefaultStable, label = Config.DefaultStable, default = true }
    end
    return options
end

function OpenComponentsMenu(data, cb)
    local HorseComp = LoadSharedFile('rsg-horses', 'shared/horse_comp.lua')
    local options = {}

    for category, list in pairs(HorseComp) do
        local current = data.components and data.components[category] or 0
        options[#options + 1] = {
            title = category,
            icon = 'fa-solid fa-sliders',
            onSelect = function()
                local input = lib.inputDialog(locale('cl_horsesadmin_edit_category_title'):format(category), {
                    { type = 'slider', label = category, min = 0, max = #list, default = current, required = true },
                })
                if input and input[1] then
                    data.components = data.components or {}
                    data.components[category] = tonumber(input[1]) or 0
                end
                OpenComponentsMenu(data, cb)
            end,
        }
    end

    options[#options + 1] = {
        title = locale('cl_horsesadmin_save_components_title'),
        description = locale('cl_horsesadmin_save_components_desc'),
        icon = 'fa-solid fa-check',
        onSelect = function()
            cb(data.components or {})
        end,
    }

    lib.registerContext({
        id = 'horsesadmin_components',
        title = locale('cl_horsesadmin_edit_components_title'),
        menu = 'horsesadmin_edit',
        options = options,
    })
    lib.showContext('horsesadmin_components')
end

----------------------------------
-- preload stables lazily when needed
----------------------------------
-- StableList is populated on demand by EnsureStableList() so the callback has a
-- valid player source and passes the server-side permission check.
