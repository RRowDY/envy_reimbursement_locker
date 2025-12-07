ESX = exports['es_extended']:getSharedObject()

local RATE_LIMIT_SEC = 1
local RATE_LIMIT_CLEANUP_INTERVAL = 300000
local MAX_LICENSE_LENGTH = 64
local MAX_IDENTIFIER_LENGTH = 128
local DISTANCE_MULTIPLIER = 1.2
local CACHE_TTL = 300

local lastInteractionTime = {}
local adminCallbackTimes = {}
local characterCache = {}
local cacheTimestamps = {}

local function ValidateInput(input, maxLength)
    if type(input) ~= 'string' or #input == 0 or #input > maxLength then
        return false
    end
    return string.match(input, '^[%w:]+$') ~= nil
end

local function SanitizeLicense(license)
    local baseLicense = string.match(license, ':([%w]+)$')
    if not baseLicense then
        baseLicense = string.match(license, '^([%w]+)$')
    end
    return baseLicense
end

local function LogAdminAction(source, action, details)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return end
    
    print(string.format(
        "^3[envy_reimbursement_locker]^7 Admin Action: ^5%s^7 (%s) - %s - %s",
        xPlayer.getName(),
        xPlayer.identifier,
        action,
        details or 'N/A'
    ))
end

local function LogSecurityEvent(source, event, details)
    if not Config.LogSecurityEvents then
        return
    end
    
    local xPlayer = ESX.GetPlayerFromId(source)
    local identifier = xPlayer and xPlayer.identifier or 'Unknown'
    
    print(string.format(
        "^1[envy_reimbursement_locker]^7 Security Event: Player ^5%s^7 (%s) - %s - %s",
        source,
        identifier,
        event,
        details or 'N/A'
    ))
end

local function IsPlayerStaff(source)
    if type(source) ~= 'number' then return false end
    
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return false end
    
    local group = xPlayer.getGroup()
    return type(group) == 'string' and Config.AllowedGroups[group] == true
end

local function IsPlayerNearLocker(source)
    if type(source) ~= 'number' then return false end
    
    local playerPed = GetPlayerPed(source)
    if not playerPed or playerPed == 0 then return false end
    
    local playerCoords = GetEntityCoords(playerPed)
    if not playerCoords then return false end
    
    local nearestDistance = math.huge
    local foundLocation = false
    
    for _, location in ipairs(Config.LockerLocations) do
        if location.coords and location.distance then
            local distance = #(playerCoords - location.coords)
            local maxDistance = location.distance * DISTANCE_MULTIPLIER
            
            if distance < maxDistance then
                foundLocation = true
                if distance < nearestDistance then
                    nearestDistance = distance
                end
            end
        end
    end
    
    return foundLocation, nearestDistance
end

local function RegisterAndOpenStash(source, stashId, stashLabel)
    local success, err = pcall(function()
        exports.ox_inventory:RegisterStash(stashId, stashLabel, Config.Stash.Slots, Config.Stash.MaxWeight, false, nil, nil)
    end)
    
    if not success then
        print(string.format("^1[envy_reimbursement_locker]^7 Failed to register stash: %s", tostring(err)))
        return false, 'Failed to register stash'
    end
    
    local openSuccess = exports.ox_inventory:forceOpenInventory(source, 'stash', stashId)
    return openSuccess, openSuccess and nil or 'Failed to open stash'
end

local function GetCachedCharacters(license)
    local cached = characterCache[license]
    local timestamp = cacheTimestamps[license]
    
    if cached and timestamp and (os.time() - timestamp) < CACHE_TTL then
        return cached
    end
    
    return nil
end

local function SetCachedCharacters(license, characters)
    characterCache[license] = characters
    cacheTimestamps[license] = os.time()
end

CreateThread(function()
    while true do
        Wait(RATE_LIMIT_CLEANUP_INTERVAL)
        local currentTime = os.time()
        local cleaned = 0
        
        for source, time in pairs(lastInteractionTime) do
            if currentTime - time > 300 then
                lastInteractionTime[source] = nil
                cleaned = cleaned + 1
            end
        end
        
        for source, time in pairs(adminCallbackTimes) do
            if currentTime - time > 300 then
                adminCallbackTimes[source] = nil
            end
        end
        
        for key, timestamp in pairs(cacheTimestamps) do
            if currentTime - timestamp >= CACHE_TTL then
                characterCache[key] = nil
                cacheTimestamps[key] = nil
            end
        end
        
        if cleaned > 0 then
            print(string.format("^2[envy_reimbursement_locker]^7 Cleaned up ^5%d^7 rate limit entries", cleaned))
        end
    end
end)

ESX.RegisterServerCallback('envy_reimbursement_locker:getCharactersByLicense', function(source, cb, license)
    if not IsPlayerStaff(source) then
        LogSecurityEvent(source, 'UNAUTHORIZED_ACCESS', 'getCharactersByLicense')
        cb({ error = 'Permission denied' })
        return
    end
    
    local currentTime = os.time()
    if adminCallbackTimes[source] and (currentTime - adminCallbackTimes[source]) < RATE_LIMIT_SEC then
        LogSecurityEvent(source, 'RATE_LIMIT_EXCEEDED', 'getCharactersByLicense')
        cb({ error = 'Please wait a moment before searching again' })
        return
    end
    adminCallbackTimes[source] = currentTime
    
    if not ValidateInput(license, MAX_LICENSE_LENGTH) then
        LogSecurityEvent(source, 'INVALID_INPUT', 'License validation failed')
        cb({ error = 'Invalid license identifier' })
        return
    end
    
    local cached = GetCachedCharacters(license)
    if cached then
        cb({ characters = cached })
        return
    end
    
    local baseLicense = SanitizeLicense(license)
    if not baseLicense then
        LogSecurityEvent(source, 'SANITIZATION_FAILED', 'License sanitization failed')
        cb({ error = 'Invalid license format' })
        return
    end
    
    MySQL.query(
        'SELECT identifier, firstname, lastname, dateofbirth, job FROM users WHERE identifier LIKE ? ORDER BY identifier LIMIT 50',
        { '%:' .. baseLicense },
        function(result)
            if not result or #result == 0 then
                cb({ error = 'No characters found for this license.' })
                return
            end
            
            local characters = {}
            for i = 1, #result do
                local char = result[i]
                
                if char and char.identifier and ValidateInput(char.identifier, MAX_IDENTIFIER_LENGTH) then
                    local targetPlayer = ESX.GetPlayerFromIdentifier(char.identifier)
                    
                    table.insert(characters, {
                        identifier = char.identifier,
                        firstname = char.firstname or 'Unknown',
                        lastname = char.lastname or 'Unknown',
                        dateofbirth = char.dateofbirth or 'N/A',
                        job = char.job or 'Unemployed',
                        online = targetPlayer ~= nil
                    })
                end
            end
            
            if #characters == 0 then
                cb({ error = 'No valid characters found for this license.' })
                return
            end
            
            SetCachedCharacters(license, characters)
            LogAdminAction(source, 'SEARCH_CHARACTERS', string.format('License: %s, Found: %d characters', license, #characters))
            cb({ characters = characters })
        end,
        function(err)
            print(string.format("^1[envy_reimbursement_locker]^7 Database error in getCharactersByLicense: %s", tostring(err)))
            cb({ error = 'Database error occurred' })
        end
    )
end)

ESX.RegisterServerCallback('envy_reimbursement_locker:openStashForCharacter', function(source, cb, characterIdentifier)
    if not IsPlayerStaff(source) then
        LogSecurityEvent(source, 'UNAUTHORIZED_ACCESS', 'openStashForCharacter')
        cb({ success = false, error = 'Permission denied' })
        return
    end
    
    local currentTime = os.time()
    if adminCallbackTimes[source] and (currentTime - adminCallbackTimes[source]) < RATE_LIMIT_SEC then
        LogSecurityEvent(source, 'RATE_LIMIT_EXCEEDED', 'openStashForCharacter')
        cb({ success = false, error = 'Please wait a moment before opening another stash' })
        return
    end
    adminCallbackTimes[source] = currentTime
    
    if not ValidateInput(characterIdentifier, MAX_IDENTIFIER_LENGTH) then
        LogSecurityEvent(source, 'INVALID_INPUT', 'Identifier validation failed')
        cb({ success = false, error = 'Invalid character identifier' })
        return
    end
    
    local targetPlayer = ESX.GetPlayerFromIdentifier(characterIdentifier)
    local playerName = targetPlayer and targetPlayer.getName() or characterIdentifier
    
    local stashId = Config.Stash.IdPrefix .. characterIdentifier
    local stashLabel = string.format(Config.Stash.LabelFormat, characterIdentifier)
    
    local openSuccess, errorMsg = RegisterAndOpenStash(source, stashId, stashLabel)
    
    if openSuccess then
        LogAdminAction(source, 'OPEN_STASH', string.format('Character: %s (%s)', playerName, characterIdentifier))
        cb({ success = true, message = string.format('Opened reimbursement locker for %s', playerName) })
    else
        cb({ success = false, error = errorMsg or 'Failed to open stash' })
    end
end)

RegisterCommand(Config.Command, function(source, args, rawCommand)
    if not IsPlayerStaff(source) then
        LogSecurityEvent(source, 'UNAUTHORIZED_COMMAND', Config.Command)
        TriggerClientEvent('esx:showNotification', source, 'You do not have permission to use this command.', 'error')
        return
    end
    
    LogAdminAction(source, 'OPEN_ADMIN_UI', 'Command executed')
    TriggerClientEvent('envy_reimbursement_locker:openAdminUI', source)
end, false)

RegisterNetEvent('envy_reimbursement_locker:openLocker', function()
    local source = source
    
    local currentTime = os.time()
    if lastInteractionTime[source] and (currentTime - lastInteractionTime[source]) < RATE_LIMIT_SEC then
        LogSecurityEvent(source, 'RATE_LIMIT_EXCEEDED', 'openLocker')
        return
    end
    lastInteractionTime[source] = currentTime
    
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        LogSecurityEvent(source, 'PLAYER_NOT_FOUND', 'openLocker')
        return
    end
    
    local isNear = IsPlayerNearLocker(source)
    if not isNear then
        LogSecurityEvent(source, 'DISTANCE_VIOLATION', 'Player not near locker')
        return
    end
    
    local stashId = Config.Stash.IdPrefix .. xPlayer.identifier
    local stashLabel = string.format(Config.Stash.LabelFormat, xPlayer.identifier)
    
    TriggerClientEvent('envy_reimbursement_locker:playAnimation', source)
    
    local openSuccess, errorMsg = RegisterAndOpenStash(source, stashId, stashLabel)
    if not openSuccess then
        TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = errorMsg or 'You do not have a reimbursement locker. Contact an administrator.'
        })
    end
end)

local function CleanupEmptyStashes()
    local prefix = Config.Stash.IdPrefix
    
    MySQL.query(
        "SELECT name FROM ox_inventory WHERE name LIKE ? AND (data IS NULL OR data = '' OR data = '[]' OR data = 'null' OR JSON_LENGTH(COALESCE(data, '[]')) = 0) LIMIT 50",
        { prefix .. '%' },
        function(result)
            if not result or #result == 0 then
                return
            end
            
            for i = 1, #result do
                local stashId = result[i].name
                if stashId then
                    pcall(function()
                        local inventory = exports.ox_inventory:GetInventory(stashId)
                        if inventory and inventory.id then
                            exports.ox_inventory:RemoveInventory(inventory)
                        end
                    end)
                end
            end
            
            Wait(1000)
            
            local function deleteStashes(attempt)
                attempt = attempt or 1
                local maxAttempts = 3
                
                MySQL.query(
                    "DELETE FROM ox_inventory WHERE name LIKE ? AND (data IS NULL OR data = '' OR data = '[]' OR data = 'null' OR JSON_LENGTH(COALESCE(data, '[]')) = 0) LIMIT 50",
                    { prefix .. '%' },
                    function(deleteResult)
                        if deleteResult and deleteResult.affectedRows and deleteResult.affectedRows > 0 then
                            print(string.format("^2[envy_reimbursement_locker]^7 Cleaned up ^5%d^7 empty reimbursement locker(s)", deleteResult.affectedRows))
                        end
                    end,
                    function(err)
                        local errStr = tostring(err)
                        if (string.find(errStr, "Deadlock") or string.find(errStr, "Lock wait timeout")) and attempt < maxAttempts then
                            Wait(2000 * attempt)
                            deleteStashes(attempt + 1)
                        else
                            print(string.format("^1[envy_reimbursement_locker]^7 Error cleaning up stashes: %s", errStr))
                        end
                    end
                )
            end
            
            deleteStashes()
        end,
        function(err)
            print(string.format("^1[envy_reimbursement_locker]^7 Error querying empty stashes: %s", tostring(err)))
        end
    )
end

CreateThread(function()
    Wait(10000)
    CleanupEmptyStashes()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        characterCache = {}
        cacheTimestamps = {}
    end
end)
