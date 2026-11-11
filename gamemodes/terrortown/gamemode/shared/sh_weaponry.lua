---
-- This is the <code>WEPS</code> module
-- @author BadKingUrgrain
-- @author Alf21
-- @author LeBroomer
-- @module WEPS

WEPS = {}

local pairs = pairs
local IsValid = IsValid
local wepGetList = weapons.GetList
local scriptedEntsGetList = scripted_ents.GetList

---
-- Get the type (<code>kind</code>) of a weapon class
-- @param string class weapon class
-- @return boolean weapon type (<code>kind</code>)
-- @realm shared
function WEPS.TypeForWeapon(class)
    local tbl = util.WeaponForClass(class)

    return tbl and tbl.Kind or WEAPON_NONE
end

---
-- Checks whether the table is a valid equipment (weapon)
-- @param table wep table that needs to be checked
-- @return boolean whether the table is a valid equipment (weapon)
-- @realm shared
function WEPS.IsEquipment(wep)
    return wep and wep.Kind and wep.Kind >= WEAPON_EQUIP
end

---
-- Get the class of the weapon
-- @param Weapon wep
-- @return nil|string weapon's class
-- @realm shared
function WEPS.GetClass(wep)
    if istable(wep) then
        return wep.ClassName or wep.Classname or wep.id or wep.name
    elseif IsValid(wep) then
        return wep:GetClass()
    end
end

local primaryAmmoKey = "ttt2_primary_ammo"
local ammoEntityKey = "ttt2_ammo_entity"

---
-- Applies the server's ammo settings to an existing client weapon.
-- @param Weapon wep Weapon instance
-- @param[opt] string key Changed network variable
-- @param[opt] string oldValue Previous value
-- @param[opt] string newValue New value
-- @realm client
-- @internal
local function ApplyNetworkedWeaponAmmo(wep, key, oldValue, newValue)
    local ammo = key == primaryAmmoKey and newValue or wep:GetNWString(primaryAmmoKey, "")

    if ammo == "" then
        return
    end

    wep.Primary = table.Copy(wep.Primary or {})
    wep.Primary.Ammo = ammo
    wep.AmmoEnt = key == ammoEntityKey and newValue or wep:GetNWString(ammoEntityKey, "")
end

---
-- Synchronizes an instance's ammo independently of the current equipment editor setting.
-- This also handles late joins and weapons networked before the equipment database arrives.
-- @param Weapon wep Weapon instance
-- @param[default=false] boolean force Track an existing weapon before its class settings change
-- @realm shared
-- @internal
function WEPS.SyncWeaponAmmo(wep, force)
    if not IsValid(wep) or not wep:IsWeapon() or not wep:IsScripted() then
        return
    end

    if SERVER then
        if
            not force
            and (not wep.PrimaryAmmo or wep.PrimaryAmmo == "")
            and wep:GetNWString(primaryAmmoKey, "") == ""
        then
            return
        end

        if not wep.Primary or not isstring(wep.Primary.Ammo) then
            return
        end

        wep:SetNWString(ammoEntityKey, wep.AmmoEnt or "")
        wep:SetNWString(primaryAmmoKey, wep.Primary.Ammo)
    else
        wep:SetNWVarProxy(primaryAmmoKey, ApplyNetworkedWeaponAmmo)
        wep:SetNWVarProxy(ammoEntityKey, ApplyNetworkedWeaponAmmo)
        ApplyNetworkedWeaponAmmo(wep)
    end
end

hook.Add("OnEntityCreated", "TTT2SyncWeaponAmmo", function(ent)
    if not IsValid(ent) or not ent:IsWeapon() then
        return
    end

    -- Wait until the SWEP table and Initialize have been processed.
    timer.Simple(0, function()
        WEPS.SyncWeaponAmmo(ent)
    end)
end)

hook.Add("OnReloaded", "TTT2SyncWeaponAmmo", function()
    for _, ent in ipairs(ents.GetAll()) do
        WEPS.SyncWeaponAmmo(ent)
    end
end)

---
-- Returns a table of weapons sorted by the available spawn types.
-- @return table A table with all weapons sorted by their spawn type
-- @return table An indexed table with all spawnable weapons including those with invalid spawn types
-- @realm shared
function WEPS.GetWeaponsForSpawnTypes()
    local wepsForSpawns = {}
    local wepsTable = {}
    local weps = wepGetList()

    for i = 1, #weps do
        local wep = weps[i]
        local spawnType = wep.spawnType

        if not wep.AutoSpawnable then
            continue
        end

        -- add these entities to the random weapon table even if they might
        -- not have a spawn type defined
        wepsTable[#wepsTable + 1] = wep

        if not spawnType then
            continue
        end

        wepsForSpawns[spawnType] = wepsForSpawns[spawnType] or {}
        wepsForSpawns[spawnType][#wepsForSpawns[spawnType] + 1] = wep
    end

    return wepsForSpawns, wepsTable
end

---
-- Returns a table of ammo sorted by the available spawn types.
-- @return table A table with all ammo sorted by their spawn type
-- @return table An indexed table with all spawnable ammo including those with invalid spawn types
-- @realm shared
function WEPS.GetAmmoForSpawnTypes()
    local ammoForSpawns = {}
    local ammoTable = {}

    local allEnts = scriptedEntsGetList()

    for _, entData in pairs(allEnts) do
        if entData.Base ~= "base_ammo_ttt" then
            continue
        end

        local ammo = entData.t
        local spawnType = ammo.spawnType

        if not ammo.AutoSpawnable then
            continue
        end

        -- add these entities to the random ammo table even if they might
        -- not have a spawn type defined
        ammoTable[#ammoTable + 1] = ammo

        if not spawnType then
            continue
        end

        ammoForSpawns[spawnType] = ammoForSpawns[spawnType] or {}
        ammoForSpawns[spawnType][#ammoForSpawns[spawnType] + 1] = ammo
    end

    return ammoForSpawns, ammoTable
end

---
-- Toggles the <code>disguised</code>
-- @param Player ply
-- @realm shared
function WEPS.DisguiseToggle(ply)
    if not IsValid(ply) or not ply:IsActive() then
        return
    end

    if not ply:GetNWBool("disguised", false) then
        RunConsoleCommand("ttt_set_disguise", "1")
    else
        RunConsoleCommand("ttt_set_disguise", "0")
    end
end
concommand.Add("ttt_toggle_disguise", WEPS.DisguiseToggle)
