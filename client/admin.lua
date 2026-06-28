-- ─────────────────────────────────────────────────────────────
-- Admin tablet client: opens a separate NUI view. The server re-checks
-- the ACE permission on every callback regardless of how this opened,
-- so there's nothing sensitive to protect client-side here.
-- ─────────────────────────────────────────────────────────────
local isOpen = false

RegisterNetEvent('cipher:client:openAdmin', function()
    if isOpen then return end
    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'openAdmin' })
end)

RegisterNUICallback('admin:close', function(_, cb)
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    cb({})
end)

local adminAllowed = {
    ['cipher:admin:getOverview']  = true,
    ['cipher:admin:getMembers']   = true,
    ['cipher:admin:kickMember']   = true,
    ['cipher:admin:setMemberGrade'] = true,
    ['cipher:admin:createGang']  = true,
    ['cipher:admin:updateGang']  = true,
    ['cipher:admin:disbandGang'] = true,
    ['cipher:admin:adjustRep']     = true,
    ['cipher:admin:adjustNotoriety'] = true,
    ['cipher:admin:setBank']      = true,
    ['cipher:admin:setTerritory'] = true,
    ['cipher:admin:createZone']   = true,
    ['cipher:admin:setZoneCoords'] = true,
    ['cipher:admin:updateZone']   = true,
    ['cipher:admin:deleteZone']   = true,
    ['cipher:admin:boostSearch']      = true,
    ['cipher:admin:boostSetStats']    = true,
    ['cipher:admin:boostResetStats']  = true,
    ['cipher:admin:boostDashboard']   = true,
    ['cipher:admin:chatGetWorld']        = true,
    ['cipher:admin:chatDeleteWorld']     = true,
    ['cipher:admin:chatResolveHandle']   = true,
    ['cipher:admin:dealerGetStock']        = true,
    ['cipher:admin:dealerReroll']          = true,
    ['cipher:admin:dealerClearCooldown']   = true,
    ['cipher:admin:dealerGetStatus']       = true,
    ['cipher:admin:getDashboard']          = true,
}

RegisterNUICallback('admin:call', function(payload, cb)
    local name = payload.name
    if not adminAllowed[name] then return cb({ ok = false, error = 'unknown action' }) end
    local args = payload.args or {}
    local res = lib.callback.await(name, false, table.unpack(args))
    cb(res or {})
end)
