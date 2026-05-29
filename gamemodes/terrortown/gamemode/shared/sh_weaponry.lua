---
-- This is the <code>WEPS</code> module
-- @author BadKingUrgrain
-- @author Alf21
-- @author LeBroomer
-- @module WEPS

WEPS = {}

local pairs = pairs
local IsValid = IsValid
local GetConVar = GetConVar
local mathMax = math.max
local hook = hook
local stringGsub = string.gsub
local stringLower = string.lower
local tableSortByMember = table.SortByMember
local wepGetList = weapons.GetList
local scriptedEntsGetList = scripted_ents.GetList

local ammoEntitySettingRegistry = {}
local ammoTypeSettingRegistry = {}
local dynamicAmmoReserveConVarName = "ttt2_ammo_dynamic_reserve"
local RegisterAmmoEntitySettings
local RegisterAmmoTypeSettings
local cvDynamicAmmoReserve

local function GetAmmoClassIdentifier(class)
    return stringLower(stringGsub(class or "", "[^%w_]", "_"))
end

local function GetAmmoTypeIdentifier(ammoType)
    return GetAmmoClassIdentifier(ammoType)
end

local function GetAmmoTypeLangIdentifier(ammoType)
    return "ammo_" .. stringLower(ammoType or "")
end

local function GetAmmoDefaultBoxAmount(ammo)
    return mathMax(1, ammo.AmmoAmount or 1)
end

local ammoTypeDefaultReserveMax = {
    ["357"] = 20,
    AlyxGun = 36,
    Buckshot = 24,
    Pistol = 60,
    SMG1 = 60,
}

local function GetAmmoDefaultReserveMax(ammoType, ammo)
    return mathMax(ammoTypeDefaultReserveMax[ammoType] or 0, mathMax(0, ammo.AmmoMax or 0))
end

local function GetWeaponAmmoType(wep)
    if not IsValid(wep) or not wep.Primary then
        return
    end

    local ammoType = wep.Primary.Ammo

    if not ammoType or ammoType == "" or ammoType == "none" then
        return
    end

    return ammoType
end

local function GetWeaponClipMax(wep)
    if not IsValid(wep) then
        return 0
    end

    local clipMax = wep.Primary and wep.Primary.ClipMax or wep:GetMaxClip1()

    return mathMax(0, clipMax or 0)
end

local function BuildAmmoEntityData()
    local ammoEntities = {}
    local ammoLookup = {}
    local ammoTypes = {}
    local ammoTypeLookup = {}
    local allEnts = scriptedEntsGetList()

    for class, entData in pairs(allEnts) do
        if entData.Base ~= "base_ammo_ttt" then
            continue
        end

        local ammo = entData.t
        local ammoType = ammo.AmmoType or class
        local ammoTypeData = ammoTypeLookup[ammoType]
        local defaultReserveMax = GetAmmoDefaultReserveMax(ammoType, ammo)

        if not ammoTypeData then
            ammoTypeData = {
                ammoType = ammoType,
                name = GetAmmoTypeLangIdentifier(ammoType),
                reserveMax = defaultReserveMax,
                entities = {},
            }

            ammoTypes[#ammoTypes + 1] = ammoTypeData
            ammoTypeLookup[ammoType] = ammoTypeData
        end

        local ammoData = {
            class = class,
            ammoType = ammoType,
            typeName = ammoTypeData.name,
            boxAmount = GetAmmoDefaultBoxAmount(ammo),
            reserveMax = defaultReserveMax,
        }

        ammoEntities[#ammoEntities + 1] = ammoData
        ammoLookup[class] = ammoData
        ammoTypeData.entities[#ammoTypeData.entities + 1] = ammoData
        ammoTypeData.reserveMax = mathMax(ammoTypeData.reserveMax, ammoData.reserveMax)
    end

    tableSortByMember(ammoEntities, "class", true)
    tableSortByMember(ammoTypes, "ammoType", true)

    for i = 1, #ammoTypes do
        tableSortByMember(ammoTypes[i].entities, "class", true)
    end

    return ammoEntities, ammoLookup, ammoTypes, ammoTypeLookup
end

if SERVER then
    -- @realm server
    cvDynamicAmmoReserve = CreateConVar(
        dynamicAmmoReserveConVarName,
        "0",
        { FCVAR_NOTIFY, FCVAR_ARCHIVE }
    )

    ---
    -- @param table ammoTypeData
    -- @return nil|string
    -- @realm server
    local function GetLegacyAmmoTypeReserveMax(ammoTypeData)
        for i = 1, #ammoTypeData.entities do
            local legacyConVar = GetConVar(
                WEPS.GetAmmoSettingsConVarName(ammoTypeData.entities[i].class, "reserve_max")
            )

            if legacyConVar then
                return tostring(mathMax(0, legacyConVar:GetInt()))
            end
        end
    end

    RegisterAmmoEntitySettings = function(ammoData)
        local class = ammoData.class

        if ammoEntitySettingRegistry[class] then
            return ammoEntitySettingRegistry[class]
        end

        -- @realm server
        local enabledConVar = CreateConVar(
            WEPS.GetAmmoSettingsConVarName(class, "enabled"),
            "1",
            { FCVAR_NOTIFY, FCVAR_ARCHIVE }
        )
        -- @realm server
        local boxAmountConVar = CreateConVar(
            WEPS.GetAmmoSettingsConVarName(class, "box_amount"),
            tostring(ammoData.boxAmount),
            { FCVAR_NOTIFY, FCVAR_ARCHIVE }
        )

        ammoEntitySettingRegistry[class] = {
            enabled = enabledConVar,
            boxAmount = boxAmountConVar,
        }

        return ammoEntitySettingRegistry[class]
    end

    RegisterAmmoTypeSettings = function(ammoTypeData)
        local ammoType = ammoTypeData.ammoType

        if ammoTypeSettingRegistry[ammoType] then
            return ammoTypeSettingRegistry[ammoType]
        end

        local defaultReserveMax = GetLegacyAmmoTypeReserveMax(ammoTypeData)
            or tostring(ammoTypeData.reserveMax)
        -- @realm server
        local reserveMaxConVar = CreateConVar(
            WEPS.GetAmmoTypeSettingsConVarName(ammoType, "reserve_max"),
            defaultReserveMax,
            { FCVAR_NOTIFY, FCVAR_ARCHIVE }
        )
        local conVars = {
            reserveMax = reserveMaxConVar,
        }

        ammoTypeSettingRegistry[ammoType] = conVars

        return conVars
    end

    hook.Add("InitPostEntity", "TTT2RegisterAmmoSettings", function()
        local ammoEntities, _, ammoTypes = BuildAmmoEntityData()

        for i = 1, #ammoEntities do
            RegisterAmmoEntitySettings(ammoEntities[i])
        end

        for i = 1, #ammoTypes do
            RegisterAmmoTypeSettings(ammoTypes[i])
        end
    end)
end

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

---
-- Returns the shared list of all ammo entities that inherit from base_ammo_ttt.
-- @return table An indexed list of ammo entity data tables
-- @return table A lookup table keyed by entity class
-- @realm shared
function WEPS.GetAmmoEntities()
    return BuildAmmoEntityData()
end

---
-- Returns the translation key used for a given ammo type.
-- @param string ammoType The ammo type string
-- @return string
-- @realm shared
function WEPS.GetAmmoTypeLangIdentifier(ammoType)
    return GetAmmoTypeLangIdentifier(ammoType)
end

---
-- Returns the generated convar name for a specific ammo setting.
-- @param string class The ammo entity class
-- @param string suffix The setting suffix
-- @return string
-- @realm shared
function WEPS.GetAmmoSettingsConVarName(class, suffix)
    return "ttt2_ammo_" .. GetAmmoClassIdentifier(class) .. "_" .. suffix
end

---
-- Returns the generated convar name for a specific ammo-type setting.
-- @param string ammoType The ammo type string
-- @param string suffix The setting suffix
-- @return string
-- @realm shared
function WEPS.GetAmmoTypeSettingsConVarName(ammoType, suffix)
    return "ttt2_ammo_type_" .. GetAmmoTypeIdentifier(ammoType) .. "_" .. suffix
end

---
-- Returns the generated convar name for the global dynamic reserve toggle.
-- @return string
-- @realm shared
function WEPS.GetDynamicAmmoReserveConVarName()
    return dynamicAmmoReserveConVarName
end

---
-- Returns whether dynamic reserve ammo is enabled.
-- @return boolean
-- @realm shared
function WEPS.IsDynamicAmmoReserveEnabled()
    return SERVER and cvDynamicAmmoReserve and cvDynamicAmmoReserve:GetBool() or false
end

---
-- Returns the current shared settings for a specific ammo type.
-- @param string ammoType The ammo type string
-- @return nil|table
-- @realm shared
function WEPS.GetAmmoTypeSettings(ammoType)
    local _, _, _, ammoTypeLookup = BuildAmmoEntityData()
    local ammoTypeData = ammoTypeLookup[ammoType]

    if not ammoTypeData then
        return
    end

    local settings = {
        reserveMax = ammoTypeData.reserveMax,
    }

    if not SERVER then
        return settings
    end

    local conVars = ammoTypeSettingRegistry[ammoTypeData.ammoType]

    if not conVars then
        conVars = RegisterAmmoTypeSettings(ammoTypeData)
    end

    settings.reserveMax = mathMax(0, conVars.reserveMax:GetInt())

    return settings
end

---
-- Returns the current ammo settings for a specific ammo entity class.
-- @param string class The ammo entity class
-- @return nil|table
-- @realm shared
function WEPS.GetAmmoSettings(class)
    local _, ammoLookup, _, ammoTypeLookup = BuildAmmoEntityData()
    local ammoData = ammoLookup[class]

    if not ammoData then
        return
    end

    local ammoTypeData = ammoTypeLookup[ammoData.ammoType]

    local settings = {
        ammoType = ammoData.ammoType,
        enabled = true,
        boxAmount = ammoData.boxAmount,
        reserveMax = ammoTypeData and ammoTypeData.reserveMax or ammoData.reserveMax,
    }

    if not SERVER then
        return settings
    end

    local entityConVars = ammoEntitySettingRegistry[class]

    if not entityConVars then
        entityConVars = RegisterAmmoEntitySettings(ammoData)
    end

    local typeConVars

    if ammoTypeData then
        typeConVars = ammoTypeSettingRegistry[ammoTypeData.ammoType]

        if not typeConVars then
            typeConVars = RegisterAmmoTypeSettings(ammoTypeData)
        end
    end

    settings.enabled = entityConVars.enabled:GetBool()
    settings.boxAmount = mathMax(1, entityConVars.boxAmount:GetInt())

    if typeConVars then
        settings.reserveMax = mathMax(0, typeConVars.reserveMax:GetInt())
    end

    return settings
end

---
-- @param string class The ammo entity class
-- @param[opt] number fallback Fallback value if no settings are registered
-- @return boolean
-- @realm shared
function WEPS.IsAmmoEnabled(class, fallback)
    local settings = WEPS.GetAmmoSettings(class)

    if not settings then
        return fallback == nil and true or fallback
    end

    return settings.enabled
end

---
-- @param string class The ammo entity class
-- @param[opt] number fallback Fallback value if no settings are registered
-- @return number
-- @realm shared
function WEPS.GetAmmoBoxAmount(class, fallback)
    local settings = WEPS.GetAmmoSettings(class)

    if not settings then
        return fallback
    end

    return settings.boxAmount
end

local function GetAmmoTypeForIdentifier(ammoIdentifier)
    local settings = WEPS.GetAmmoSettings(ammoIdentifier)

    if settings then
        return settings.ammoType
    end

    return ammoIdentifier
end

local function GetStaticAmmoReserveMax(ammoIdentifier)
    local settings = WEPS.GetAmmoTypeSettings(ammoIdentifier)

    if not settings then
        settings = WEPS.GetAmmoSettings(ammoIdentifier)
    end

    if not settings then
        return
    end

    return settings.reserveMax
end

---
-- Returns the dynamic reserve max for a player based on equipped weapons.
-- @param Player ply The player whose current loadout should be checked
-- @param string ammoIdentifier The ammo entity class or ammo type string
-- @param[opt] Weapon excludedWeapon A weapon to ignore for the calculation
-- @return nil|number
-- @realm shared
function WEPS.GetDynamicAmmoReserveMax(ply, ammoIdentifier, excludedWeapon)
    if not SERVER or not IsValid(ply) or not ply:IsPlayer() then
        return GetStaticAmmoReserveMax(ammoIdentifier)
    end

    local ammoType = GetAmmoTypeForIdentifier(ammoIdentifier)

    if not ammoType then
        return
    end

    local reserveMax = 0
    local weps = ply:GetWeapons()

    for i = 1, #weps do
        local wep = weps[i]

        if wep == excludedWeapon or GetWeaponAmmoType(wep) ~= ammoType then
            continue
        end

        reserveMax = reserveMax + GetWeaponClipMax(wep)
    end

    return reserveMax
end

---
-- @param string ammoIdentifier The ammo entity class or ammo type string
-- @param[opt] Player ply The player whose dynamic reserve should be calculated
-- @param[opt] Weapon excludedWeapon A weapon to ignore for dynamic reserve calculations
-- @return nil|number
-- @realm shared
function WEPS.GetAmmoReserveMax(ammoIdentifier, ply, excludedWeapon)
    if WEPS.IsDynamicAmmoReserveEnabled() and IsValid(ply) and ply:IsPlayer() then
        return WEPS.GetDynamicAmmoReserveMax(ply, ammoIdentifier, excludedWeapon)
    end

    return GetStaticAmmoReserveMax(ammoIdentifier)
end

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

    for class, entData in pairs(allEnts) do
        if entData.Base ~= "base_ammo_ttt" then
            continue
        end

        local ammo = entData.t
        local spawnType = ammo.spawnType

        if not ammo.AutoSpawnable or not WEPS.IsAmmoEnabled(class) then
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
