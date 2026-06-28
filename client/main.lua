-- ─────────────────────────────────────────────────────────────
-- Client init + invite handling.
-- ─────────────────────────────────────────────────────────────
CreateThread(function()
    while not LocalPlayer.state.isLoggedIn and not (Framework and Framework.name) do Wait(250) end
    if Config.Debug then print('^2[cipher]^0 client ready') end
end)

-- ox_inventory client-side usable item: item.client.export = 'cipher.useDevice'
exports('useDevice', function(data, slot)
    TriggerEvent('cipher:client:openDevice')
end)

-- ── friendly-fire report ──
-- Self-reports our own death + whoever killed us, so the server can dock
-- the killer's rep if we're both in the same gang. Debounced so it only
-- fires once per actual death, not on every tick while dead.
CreateThread(function()
    local wasDead = false
    while true do
        Wait(500)
        local ped = PlayerPedId()
        local dead = IsEntityDead(ped)
        if dead and not wasDead then
            local killer = GetPedSourceOfDeath(ped)
            if killer and killer ~= 0 and IsPedAPlayer(killer) and killer ~= ped then
                local killerPlayer = NetworkGetPlayerIndexFromPed(killer)
                if killerPlayer and killerPlayer ~= -1 then
                    TriggerServerEvent('cipher:server:reportGangKill', GetPlayerServerId(killerPlayer))
                end
            end
        end
        wasDead = dead
    end
end)

-- ── task blip / carry prop / kill target / pickup+dropoff / escort / heist ──
-- Server is the sole authority on stage/completion; this just shows
-- where to go, runs the actual target interactions, and handles purely
-- visual flavor (carried prop, spawned NPCs) for whatever the server says
-- the job currently is. For co-op jobs, only the crew leader's client ever
-- spawns an entity (killPed/escortPed/dropoffPed) — every crew member's
-- client independently runs this same handler, so spawning unconditionally
-- would create duplicate networked peds.
local hasTarget = GetResourceState('ox_target') == 'started'
local taskBlip = nil
local carryProp = nil
local killPed = nil
local killThread = false
local pickupZoneId = nil
local dropoffPed = nil
local escortPed = nil
local escortThread = false
local heistZoneId = nil
local fallbackPrompt = nil -- { coords, label, action } when ox_target isn't handling the current step

local function clearTaskBlip()
    if taskBlip then RemoveBlip(taskBlip); taskBlip = nil end
end

local function clearCarryProp()
    if carryProp then DeleteEntity(carryProp); carryProp = nil end
end

local function clearKillPed()
    if killPed then DeleteEntity(killPed); killPed = nil end
end

local function clearPickupZone()
    if pickupZoneId then
        pcall(function() exports.ox_target:removeZone(pickupZoneId) end)
        pickupZoneId = nil
    end
end

local function clearDropoffPed()
    if dropoffPed then DeleteEntity(dropoffPed); dropoffPed = nil end
end

local function clearEscortPed()
    if escortPed then DeleteEntity(escortPed); escortPed = nil end
end

local function clearHeistZone()
    if heistZoneId then
        pcall(function() exports.ox_target:removeZone(heistZoneId) end)
        heistZoneId = nil
    end
end

local function clearFallbackPrompt()
    if fallbackPrompt then lib.hideTextUI(); fallbackPrompt = nil end
end

local function clearAllTaskVisuals()
    clearCarryProp()
    clearKillPed()
    clearPickupZone()
    clearDropoffPed()
    clearEscortPed()
    clearHeistZone()
    clearFallbackPrompt()
end

-- Single proximity+[E] loop backing whichever interaction ox_target isn't
-- covering right now (no ox_target installed, or the zone/target call failed).
CreateThread(function()
    local shown = false
    while true do
        Wait(300)
        if fallbackPrompt then
            local near = #(GetEntityCoords(PlayerPedId()) - fallbackPrompt.coords) <= 2.0
            if near then
                if not shown then lib.showTextUI('[E] ' .. fallbackPrompt.label); shown = true end
                if IsControlJustReleased(0, 38) then fallbackPrompt.action() end
            elseif shown then
                lib.hideTextUI(); shown = false
            end
        elseif shown then
            lib.hideTextUI(); shown = false
        end
    end
end)

local function attachCarryProp(model)
    clearCarryProp()
    if not model or not IsModelValid(model) then return end
    lib.requestModel(model)
    local ped = PlayerPedId()
    carryProp = CreateObject(model, 0.0, 0.0, 0.0, true, true, false)
    AttachEntityToEntity(carryProp, ped, GetPedBoneIndex(ped, 28422), 0.1, 0.02, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
end

local function spawnKillTarget(spawn, model, weapon, isLeader)
    clearKillPed()
    if isLeader == false then
        taskBlip = AddBlipForCoord(spawn.x, spawn.y, spawn.z)
        SetBlipSprite(taskBlip, 84)
        SetBlipColour(taskBlip, 1)
        SetBlipRoute(taskBlip, true)
        return
    end
    if not IsModelValid(model) then
        lib.notify({ description = ('Bad ped model for this task (%s) — tell an admin to fix config.lua'):format(model), type = 'error' })
        return
    end
    lib.requestModel(model)
    killPed = CreatePed(4, model, spawn.x, spawn.y, spawn.z, 0.0, true, true)

    AddRelationshipGroup('cipher_hitcontract')
    local hostileGroup = GetHashKey('cipher_hitcontract')
    SetRelationshipBetweenGroups(5, hostileGroup, `PLAYER`) -- 5 = hate
    SetRelationshipBetweenGroups(5, `PLAYER`, hostileGroup)
    SetPedRelationshipGroupHash(killPed, hostileGroup)

    GiveWeaponToPed(killPed, GetHashKey(weapon or 'WEAPON_PISTOL'), 250, false, true)
    SetPedCombatAttributes(killPed, 46, true) -- can fight armed peds while unarmed
    SetPedCombatAttributes(killPed, 5, true)  -- always fight
    SetPedFleeAttributes(killPed, 0, false)
    SetPedSeeingRange(killPed, 100.0)
    SetPedHearingRange(killPed, 100.0)
    TaskCombatPed(killPed, PlayerPedId(), 0, 16)

    taskBlip = AddBlipForEntity(killPed)
    SetBlipSprite(taskBlip, 84)
    SetBlipColour(taskBlip, 1)
    SetBlipRoute(taskBlip, true)

    if killThread then return end
    killThread = true
    CreateThread(function()
        while killPed do
            Wait(1000)
            if not killPed then break end
            if not DoesEntityExist(killPed) or IsEntityDead(killPed) then
                local res = lib.callback.await('cipher:tasks:reportKill', false)
                if res and res.ok then
                    lib.notify({ description = 'Target eliminated.', type = 'success' })
                end
                break
            end
        end
        killThread = false
    end)
end

local function doPickup()
    local res = lib.callback.await('cipher:tasks:doPickup', false)
    if res and not res.ok then lib.notify({ description = res.error or 'Failed', type = 'error' }) end
end

local function doDropoff()
    local res = lib.callback.await('cipher:tasks:doDropoff', false)
    if res and not res.ok then lib.notify({ description = res.error or 'Failed', type = 'error' }) end
end

local function setupPickupTarget(coords)
    clearPickupZone()
    clearFallbackPrompt()
    local zoneOk = false
    if hasTarget then
        local ok, id = pcall(function()
            return exports.ox_target:addSphereZone({
                coords = coords, radius = 1.2, debug = false,
                options = {
                    { name = 'cipher_pickup_task', label = 'Pick up Package', icon = 'fas fa-box',
                      onSelect = doPickup },
                },
            })
        end)
        if ok and id then pickupZoneId = id; zoneOk = true end
    end
    if not zoneOk then
        fallbackPrompt = { coords = coords, label = 'Pick up Package', action = doPickup }
    end
end

local function spawnEscort(spawn, destination, model, radius, isLeader)
    clearEscortPed()
    if isLeader == false then
        taskBlip = AddBlipForCoord(destination.x, destination.y, destination.z)
        SetBlipSprite(taskBlip, 280)
        SetBlipColour(taskBlip, 5)
        SetBlipRoute(taskBlip, true)
        return
    end
    if not IsModelValid(model) then
        lib.notify({ description = ('Bad escort ped model (%s) — tell an admin to fix config.lua'):format(model), type = 'error' })
        return
    end
    lib.requestModel(model)
    escortPed = CreatePed(4, model, spawn.x, spawn.y, spawn.z, 0.0, true, true)
    SetBlockingOfNonTemporaryEvents(escortPed, true)
    SetPedCanRagdoll(escortPed, true)

    local ped = PlayerPedId()
    TaskFollowToOffsetOfEntity(escortPed, ped, ped, 0.0, -1.5, 0.0, 1.0, -1, 2.0, true)

    taskBlip = AddBlipForCoord(destination.x, destination.y, destination.z)
    SetBlipSprite(taskBlip, 280)
    SetBlipColour(taskBlip, 5)
    SetBlipRoute(taskBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Escort destination')
    EndTextCommandSetBlipName(taskBlip)

    if escortThread then return end
    escortThread = true
    CreateThread(function()
        while escortPed do
            Wait(1000)
            if not escortPed then break end
            if not DoesEntityExist(escortPed) or IsEntityDead(escortPed) then
                lib.notify({ description = 'The escort was killed — job failed.', type = 'error' })
                lib.callback.await('cipher:tasks:cancel', false)
                break
            end
            local playerCoords = GetEntityCoords(PlayerPedId())
            if #(playerCoords - destination) <= (radius or 5.0) and #(GetEntityCoords(escortPed) - destination) <= (radius or 5.0) + 3.0 then
                local res = lib.callback.await('cipher:tasks:doEscortComplete', false)
                if res and res.ok then
                    lib.notify({ description = 'Escort delivered safely.', type = 'success' })
                elseif res and res.error then
                    lib.notify({ description = res.error, type = 'error' })
                end
                break
            end
        end
        escortThread = false
    end)
end

local function setupHeistTarget(coords, label, radius, onArrive)
    clearHeistZone()
    clearFallbackPrompt()
    local zoneOk = false
    if hasTarget then
        local ok, id = pcall(function()
            return exports.ox_target:addSphereZone({
                coords = coords, radius = radius or 2.5, debug = false,
                options = {
                    { name = 'cipher_heist_stage', label = label, icon = 'fas fa-user-secret', onSelect = onArrive },
                },
            })
        end)
        if ok and id then heistZoneId = id; zoneOk = true end
    end
    if not zoneOk then
        fallbackPrompt = { coords = coords, label = label, action = onArrive }
    end
end

local function setupDropoffTarget(coords, model, isLeader)
    clearDropoffPed()
    clearFallbackPrompt()
    if isLeader == false then return end
    if not IsModelValid(model) then
        lib.notify({ description = ('Bad dropoff ped model (%s) — tell an admin to fix config.lua'):format(model), type = 'error' })
        return
    end
    lib.requestModel(model)
    dropoffPed = CreatePed(4, model, coords.x, coords.y, coords.z, 0.0, true, true)
    SetEntityInvincible(dropoffPed, true)
    SetBlockingOfNonTemporaryEvents(dropoffPed, true)
    FreezeEntityPosition(dropoffPed, true)
    TaskStartScenarioInPlace(dropoffPed, 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)

    local zoneOk = false
    if hasTarget then
        local ok = pcall(function()
            exports.ox_target:addLocalEntity(dropoffPed, {
                { name = 'cipher_dropoff_task', label = 'Make Delivery', icon = 'fas fa-handshake',
                  onSelect = doDropoff },
            })
        end)
        zoneOk = ok
    end
    if not zoneOk then
        fallbackPrompt = { coords = coords, label = 'Make Delivery', action = doDropoff }
    end
end

-- Car boosting is its own standalone system now — see client/boosting.lua.

local function doHeistStage(callbackName)
    local res = lib.callback.await(callbackName, false)
    if res and not res.ok then lib.notify({ description = res.error or 'Failed', type = 'error' }) end
end

local function doInfiltrate(holdSeconds)
    if lib.progressBar({ duration = (holdSeconds or 6) * 1000, label = 'Working the lock...', useWhileDead = false, canCancel = true }) then
        doHeistStage('cipher:tasks:doInfiltrate')
    end
end

RegisterNetEvent('cipher:client:taskUpdate', function(job)
    clearTaskBlip()
    if not job then
        clearAllTaskVisuals()
        return
    end

    if job.type == 'kill' then
        clearCarryProp(); clearPickupZone(); clearDropoffPed(); clearEscortPed(); clearHeistZone(); clearFallbackPrompt()
        spawnKillTarget(job.spawn, job.pedModel, job.weapon, job.isLeader)
        return
    end

    if job.type == 'escort' then
        clearCarryProp(); clearPickupZone(); clearDropoffPed(); clearKillPed(); clearHeistZone(); clearFallbackPrompt()
        spawnEscort(job.spawn, job.destination, job.pedModel, job.radius, job.isLeader)
        return
    end

    if job.type == 'heist' then
        clearCarryProp(); clearPickupZone(); clearDropoffPed(); clearKillPed(); clearEscortPed()
        local label, action
        if job.stage == 'infiltrate' then
            label, action = 'Infiltrate', function() doInfiltrate(job.holdSeconds) end
        elseif job.stage == 'grab' then
            label, action = 'Grab It', function() doHeistStage('cipher:tasks:doGrab') end
        else
            label, action = 'Escape', function() doHeistStage('cipher:tasks:doEscape') end
        end
        setupHeistTarget(job.point, label, job.radius, action)

        taskBlip = AddBlipForCoord(job.point.x, job.point.y, job.point.z)
        SetBlipSprite(taskBlip, 511)
        SetBlipColour(taskBlip, job.stage == 'escape' and 1 or 5)
        SetBlipRoute(taskBlip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(label)
        EndTextCommandSetBlipName(taskBlip)
        return
    end

    -- delivery
    clearKillPed(); clearEscortPed(); clearHeistZone()

    if job.stage == 'pickup' then
        clearCarryProp()
        clearDropoffPed()
        setupPickupTarget(job.pickup)
    elseif job.stage == 'dropoff' then
        clearPickupZone()
        if job.carryProp then attachCarryProp(job.carryProp) else clearCarryProp() end
        setupDropoffTarget(job.dropoff, job.dropoffPedModel or 'g_m_y_lost_01', job.isLeader)
    end

    local coords = job.stage == 'pickup' and job.pickup or job.dropoff
    taskBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(taskBlip, job.stage == 'pickup' and 1 or 358)
    SetBlipColour(taskBlip, job.stage == 'pickup' and 5 or 2)
    SetBlipRoute(taskBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(job.stage == 'pickup' and 'Pickup' or 'Dropoff')
    EndTextCommandSetBlipName(taskBlip)
end)

-- Incoming task co-op invite -> ox_lib confirm dialog.
RegisterNetEvent('cipher:client:taskCoopInvite', function(info)
    local accepted = lib.alertDialog({
        header = 'Crew Invite',
        content = ('**%s** invited you to crew up on a task.\n\nAccept?'):format(info.fromName),
        centered = true,
        cancel = true,
        labels = { confirm = 'Accept', cancel = 'Decline' },
    })
    if accepted == 'confirm' then
        TriggerServerEvent('cipher:server:acceptTaskCoopInvite')
    end
end)

-- ── model test helper ──
-- Lets an admin try candidate prop/ped names live and see if they're
-- actually valid on this build, instead of guessing from config.lua and
-- restarting blind. /testmodel <name> [ped]
RegisterCommand('testmodel', function(_, args)
    if not lib.callback.await('cipher:admin:checkAccess', false) then return end
    local name = args[1]
    if not name then
        lib.notify({ description = 'Usage: /testmodel <model_name> [ped]', type = 'error' })
        return
    end
    local hash = GetHashKey(name)
    if not IsModelValid(hash) then
        lib.notify({ description = ('Invalid model: %s'):format(name), type = 'error' })
        return
    end
    lib.notify({ description = ('Valid! Spawning %s for 6s in front of you.'):format(name), type = 'success' })
    lib.requestModel(hash)
    local ped = PlayerPedId()
    local fwd = GetEntityForwardVector(ped)
    local pos = GetEntityCoords(ped) + fwd * 2.0
    local isPed = args[2] == 'ped'
    local handle = isPed
        and CreatePed(4, hash, pos.x, pos.y, pos.z, 0.0, false, false)
        or CreateObject(hash, pos.x, pos.y, pos.z, false, false, false)
    SetEntityCoordsNoOffset(handle, pos.x, pos.y, pos.z)
    SetTimeout(6000, function()
        if DoesEntityExist(handle) then DeleteEntity(handle) end
    end)
end, false)

-- Crafting bench interaction now lives in client/crafting.lua as a
-- dedicated NUI panel (RegisterNetEvent('cipher:client:openCraftBench', ...)).

-- Dealer interaction: rotating stock, server validates funds + gives
-- the item. "This is what I got right now" — stock and prices change
-- on Config.Dealer.rotateMinutes.
RegisterNetEvent('cipher:client:talkToDealer', function()
    local stock = lib.callback.await('cipher:dealer:getStock', false)
    if not stock or #stock == 0 then
        lib.notify({ description = "Nothing in stock right now — check back later.", type = 'inform' })
        return
    end

    local options = {}
    for _, s in ipairs(stock) do
        options[#options + 1] = {
            title = s.label,
            description = ('$%d'):format(s.price),
            icon = 'fas fa-bag-shopping',
            onSelect = function()
                local res = lib.callback.await('cipher:dealer:buy', false, s.item)
                if res and res.ok then
                    lib.notify({ description = ('Bought %s for $%d.'):format(s.label, res.price), type = 'success' })
                else
                    lib.notify({ description = (res and res.error) or 'Failed to buy', type = 'error' })
                end
            end,
        }
    end

    lib.registerContext({ id = 'cipher_dealer', title = "What I got right now", options = options })
    lib.showContext('cipher_dealer')
end)

-- Incoming gang invite -> ox_lib confirm dialog.
RegisterNetEvent('cipher:client:gangInvite', function(info)
    local accepted = lib.alertDialog({
        header = 'Gang Invite',
        content = ('**%s** invited you to join **%s**.\n\nAccept?'):format(info.from, info.gang),
        centered = true,
        cancel = true,
        labels = { confirm = 'Accept', cancel = 'Decline' },
    })
    if accepted == 'confirm' then
        TriggerServerEvent('cipher:server:acceptInvite')
    end
end)
