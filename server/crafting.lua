-- ─────────────────────────────────────────────────────────────
-- Crafting: simple item conversions available at any placed bench. Open
-- to any gang member (not permission-gated) — the bench itself is the
-- gate for being there at all, and a recipe's `tier` requirement (if any)
-- gates which recipes that bench can actually make right now. Server is
-- the sole authority on both the tier check and whether the player
-- actually has the inputs.
-- ─────────────────────────────────────────────────────────────
Crafting = {}

local byId = {}
for _, r in ipairs(Config.Recipes) do byId[r.id] = r end

local function tierIndex(tierName)
    for i, t in ipairs(Config.Notoriety.tiers) do
        if t.name == tierName then return i end
    end
    return 1
end

local function hasItems(src, inputs)
    for _, inp in ipairs(inputs) do
        local count = exports.ox_inventory:Search(src, 'count', inp.item)
        if (count or 0) < inp.count then return false, inp end
    end
    return true
end

-- Every recipe, with a `locked` flag for ones the gang's tier doesn't
-- reach yet — same pattern as the Unlocks tab's placeables list.
function Crafting.GetRecipes(src)
    local cid = Framework.GetCitizenId(src)
    local gang = cid and Gangs.GetByCitizen(cid)
    local myTierIdx = gang and tierIndex(Notoriety.Tier(gang.notoriety)) or 0

    local list = {}
    for _, r in ipairs(Config.Recipes) do
        local reqTier = r.tier or Config.Notoriety.tiers[1].name
        local reqIdx = tierIndex(reqTier)
        list[#list + 1] = {
            id = r.id, label = r.label, inputs = r.inputs, output = r.output, time = r.time,
            locked = reqIdx > myTierIdx, tierName = reqTier,
        }
    end
    return list
end

function Crafting.Craft(src, recipeId)
    local recipe = byId[recipeId]
    if not recipe then return false, 'unknown recipe' end

    local cid = Framework.GetCitizenId(src)
    local gang = cid and Gangs.GetByCitizen(cid)
    if not gang then return false, 'no gang' end

    local reqTier = recipe.tier or Config.Notoriety.tiers[1].name
    if tierIndex(Notoriety.Tier(gang.notoriety)) < tierIndex(reqTier) then
        return false, ('requires %s tier'):format(reqTier)
    end

    local ok, missing = hasItems(src, recipe.inputs)
    if not ok then return false, ('missing %s'):format(missing.item) end

    for _, inp in ipairs(recipe.inputs) do
        exports.ox_inventory:RemoveItem(src, inp.item, inp.count)
    end
    exports.ox_inventory:AddItem(src, recipe.output.item, recipe.output.count)
    Gangs.Log(gang.id, ('%s crafted %dx %s'):format(Framework.GetName(src) or cid, recipe.output.count, recipe.output.item))
    return true
end

lib.callback.register('cipher:crafting:getRecipes', function(src)
    return Crafting.GetRecipes(src)
end)

lib.callback.register('cipher:crafting:craft', function(src, recipeId)
    local ok, err = Crafting.Craft(src, recipeId)
    return { ok = ok, error = err }
end)
