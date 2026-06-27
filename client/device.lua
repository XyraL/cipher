-- ─────────────────────────────────────────────────────────────
-- Device UI controller. Opens the NUI, fetches a snapshot, and relays
-- every UI action to a server callback, returning the result to the UI.
-- ─────────────────────────────────────────────────────────────
local isOpen = false
local ANIM_DICT = 'amb@code_human_in_bus_passenger_idles@female@tablet@base'
local ANIM_CLIP = 'base'

local function playDeviceAnim()
    RequestAnimDict(ANIM_DICT)
    local waited = 0
    while not HasAnimDictLoaded(ANIM_DICT) and waited < 1000 do Wait(50); waited = waited + 50 end
    if HasAnimDictLoaded(ANIM_DICT) then
        TaskPlayAnim(PlayerPedId(), ANIM_DICT, ANIM_CLIP, 3.0, 3.0, -1, 49, 0, false, false, false)
    end
end

local function stopDeviceAnim()
    ClearPedTasks(PlayerPedId())
end

local function openDevice()
    if isOpen then return end
    local snapshot = lib.callback.await('cipher:getSnapshot', false)
    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'open', data = snapshot })
    playDeviceAnim()
end

local function closeDevice()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    stopDeviceAnim()
end

RegisterNetEvent('cipher:client:openDevice', openDevice)

RegisterNUICallback('close', function(_, cb)
    closeDevice()
    cb({})
end)

-- Generic relay: the UI names a server callback + args; we await + return.
-- Keeps the JS side tiny and the server the single source of truth.
local allowed = {
    ['cipher:getSnapshot']   = true,
    ['cipher:invite']        = true,
    ['cipher:kick']          = true,
    ['cipher:setGrade']      = true,
    ['cipher:bankDeposit']   = true,
    ['cipher:bankWithdraw']  = true,
    ['cipher:setDues']       = true,
    ['cipher:tasks:getAvailable'] = true,
    ['cipher:tasks:accept']       = true,
    ['cipher:tasks:cancel']       = true,
    ['cipher:placeables:getAvailable'] = true,
    ['cipher:placeables:remove']       = true,
    ['cipher:dealer:getStatus']        = true,
    ['cipher:dealer:contact']          = true,
}

RegisterNUICallback('call', function(payload, cb)
    local name = payload.name
    if not allowed[name] then return cb({ ok = false, error = 'unknown action' }) end
    local args = payload.args or {}
    local res = lib.callback.await(name, false, table.unpack(args))
    cb(res or {})
end)

-- Placement is a client-native flow (move a ghost prop, confirm in world),
-- so it closes the tablet and hands off to client/placeables.lua rather
-- than going through the generic server-callback relay above.
RegisterNUICallback('placeObject', function(data, cb)
    closeDevice()
    local model = Placeables.ResolveModel(data.kind, data.id)
    if model then Placeables.StartPlacement(data.kind, data.id, model) end
    cb({})
end)

-- ESC closes from the page.
RegisterNUICallback('escape', function(_, cb)
    closeDevice()
    cb({})
end)
