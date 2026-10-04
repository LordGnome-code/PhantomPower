local ADDON_NAME, ns = ...

local PP = CreateFrame("Frame")
ns.PP = PP

local VERSION = "0.1.1"
local PREFIX = "|cffffd200PhantomPower|r: "

-- WoW: Forever currently uses the modern UI API family and Interface 16001.
-- This first release intentionally avoids combat-log logic and only changes
-- protected button attributes while out of combat.

local CLASS_ORDER = {
    "WARRIOR",
    "PALADIN",
    "HUNTER",
    "ROGUE",
    "PRIEST",
    "SHAMAN",
    "MAGE",
    "WARLOCK",
    "DRUID",
}

local BLESSINGS = {
    { key = "NONE",       label = "None" },
    { key = "MIGHT",      spellID = 19740, greaterSpellID = 25782, fallback = "Blessing of Might",      greaterFallback = "Greater Blessing of Might" },
    { key = "WISDOM",     spellID = 19742, greaterSpellID = 25894, fallback = "Blessing of Wisdom",     greaterFallback = "Greater Blessing of Wisdom" },
    { key = "KINGS",      spellID = 20217, greaterSpellID = 25898, fallback = "Blessing of Kings",      greaterFallback = "Greater Blessing of Kings" },
    { key = "SALVATION",  spellID = 1038,  greaterSpellID = 25895, fallback = "Blessing of Salvation",  greaterFallback = "Greater Blessing of Salvation" },
    { key = "LIGHT",      spellID = 19977, greaterSpellID = 25890, fallback = "Blessing of Light",      greaterFallback = "Greater Blessing of Light" },
}

local AURAS = {
    { key = "DEVOTION",      spellID = 465,   fallback = "Devotion Aura" },
    { key = "RETRIBUTION",   spellID = 7294,  fallback = "Retribution Aura" },
    { key = "CONCENTRATION", spellID = 19746, fallback = "Concentration Aura" },
    { key = "SHADOW",        spellID = 19876, fallback = "Shadow Resistance Aura" },
    { key = "FROST",         spellID = 19888, fallback = "Frost Resistance Aura" },
    { key = "FIRE",          spellID = 19891, fallback = "Fire Resistance Aura" },
}

local SEALS = {
    { key = "RIGHTEOUSNESS", spellID = 21084,   fallback = "Seal of Righteousness" },
    { key = "CRUSADER",      spellID = 21082,   fallback = "Seal of the Crusader" },
    { key = "FURY",          spellID = 1311649, fallback = "Seal of Fury" },
    { key = "COMMAND",       spellID = 20375,   fallback = "Seal of Command" },
    { key = "JUSTICE",       spellID = 20164,   fallback = "Seal of Justice" },
    { key = "LIGHT",         spellID = 20165,   fallback = "Seal of Light" },
    { key = "WISDOM",        spellID = 20166,   fallback = "Seal of Wisdom" },
}

local RIGHTEOUS_FURY = { spellID = 25780, fallback = "Righteous Fury" }

local blessingByKey = {}
local auraByKey = {}
local sealByKey = {}
for _, entry in ipairs(BLESSINGS) do blessingByKey[entry.key] = entry end
for _, entry in ipairs(AURAS) do auraByKey[entry.key] = entry end
for _, entry in ipairs(SEALS) do sealByKey[entry.key] = entry end

local defaults = {
    point = "CENTER",
    x = 0,
    y = 0,
    aura = "DEVOTION",
    seal = "RIGHTEOUSNESS",
    classBlessings = {},
}
for _, classToken in ipairs(CLASS_ORDER) do
    defaults.classBlessings[classToken] = "NONE"
end

local rows = {}
local mainFrame
local auraSelectButton
local auraCastButton
local sealSelectButton
local sealCastButton
local rfCastButton
local combatLabel
local refreshQueued = false

local function Print(msg)
    print(PREFIX .. tostring(msg))
end

local function IsSecret(value)
    if type(issecretvalue) == "function" then
        local ok, secret = pcall(issecretvalue, value)
        return ok and secret or false
    end
    return false
end

local function SafeSpellInfo(identifier)
    if not C_Spell or type(C_Spell.GetSpellInfo) ~= "function" then
        return nil
    end
    local ok, info = pcall(C_Spell.GetSpellInfo, identifier)
    if ok then
        return info
    end
    return nil
end

local function SpellName(spellID, fallback)
    local info = SafeSpellInfo(spellID)
    if info and info.name and not IsSecret(info.name) then
        return info.name
    end
    return fallback
end

local function ClassDisplayName(classToken)
    if LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classToken] then
        return LOCALIZED_CLASS_NAMES_MALE[classToken]
    end
    return classToken:sub(1, 1) .. classToken:sub(2):lower()
end

local function CopyDefaults()
    PhantomPowerDB = PhantomPowerDB or {}

    if type(PhantomPowerDB.classBlessings) ~= "table" then
        PhantomPowerDB.classBlessings = {}
    end

    if not PhantomPowerDB.point then PhantomPowerDB.point = defaults.point end
    if PhantomPowerDB.x == nil then PhantomPowerDB.x = defaults.x end
    if PhantomPowerDB.y == nil then PhantomPowerDB.y = defaults.y end
    if not PhantomPowerDB.aura or not auraByKey[PhantomPowerDB.aura] then
        PhantomPowerDB.aura = defaults.aura
    end
    if not PhantomPowerDB.seal or not sealByKey[PhantomPowerDB.seal] then
        PhantomPowerDB.seal = defaults.seal
    end

    for _, classToken in ipairs(CLASS_ORDER) do
        local key = PhantomPowerDB.classBlessings[classToken]
        if not key or not blessingByKey[key] then
            PhantomPowerDB.classBlessings[classToken] = defaults.classBlessings[classToken]
        end
    end
end

local function IsPaladin()
    local _, classToken = UnitClass("player")
    return classToken == "PALADIN"
end

local function GetGroupUnits()
    local units = {}

    if IsInRaid and IsInRaid() then
        local count = GetNumGroupMembers and GetNumGroupMembers() or 0
        for i = 1, count do
            local unit = "raid" .. i
            if UnitExists(unit) then
                units[#units + 1] = unit
            end
        end
    elseif IsInGroup and IsInGroup() then
        units[#units + 1] = "player"
        local count = GetNumSubgroupMembers and GetNumSubgroupMembers() or 0
        for i = 1, count do
            local unit = "party" .. i
            if UnitExists(unit) then
                units[#units + 1] = unit
            end
        end
    else
        units[1] = "player"
    end

    return units
end

local function UnitIsUsable(unit)
    if not UnitExists(unit) then return false end
    if UnitIsConnected and not UnitIsConnected(unit) then return false end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return false end
    return true
end

-- Returns: true = found, false = definitely not found, nil = scan contained
-- unreadable/secret aura slots so we cannot make a reliable determination.
local function UnitHasAssignedBlessing(unit, normalName, greaterName)
    if not C_UnitAuras or type(C_UnitAuras.GetAuraDataByIndex) ~= "function" then
        return nil
    end

    local unreadable = false

    for i = 1, 60 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
        if not ok then
            unreadable = true
        elseif aura == nil then
            break
        else
            local name = aura.name
            if IsSecret(name) then
                unreadable = true
            elseif name == normalName or name == greaterName then
                return true
            end
        end
    end

    if unreadable then
        return nil
    end
    return false
end

local function CycleEntry(list, currentKey, direction)
    local currentIndex = 1
    for i, entry in ipairs(list) do
        if entry.key == currentKey then
            currentIndex = i
            break
        end
    end

    currentIndex = currentIndex + direction
    if currentIndex < 1 then currentIndex = #list end
    if currentIndex > #list then currentIndex = 1 end
    return list[currentIndex].key
end

local function SetSelectorText(button, entry, kind)
    if not button then return end

    if kind == "blessing" then
        if entry.key == "NONE" then
            button:SetText("None")
        else
            button:SetText(SpellName(entry.spellID, entry.fallback))
        end
    else
        button:SetText(SpellName(entry.spellID, entry.fallback))
    end
end

local function SetCombatLabel()
    if not combatLabel then return end
    if InCombatLockdown and InCombatLockdown() then
        combatLabel:SetText("Combat: assignments and secure targets are locked")
        combatLabel:SetTextColor(1, 0.35, 0.2)
    else
        combatLabel:SetText("Left-click class cast = Greater Blessing; right-click = regular Blessing")
        combatLabel:SetTextColor(0.75, 0.75, 0.75)
    end
end

local function ApplyUtilityButtons()
    if not auraCastButton or not sealCastButton or not rfCastButton then return end
    if InCombatLockdown and InCombatLockdown() then return end

    local aura = auraByKey[PhantomPowerDB.aura]
    local seal = sealByKey[PhantomPowerDB.seal]

    if aura then
        local auraName = SpellName(aura.spellID, aura.fallback)
        auraCastButton:SetAttribute("type1", "spell")
        auraCastButton:SetAttribute("spell1", auraName)
        auraCastButton:SetAttribute("unit", "player")
        auraCastButton:SetText("Cast Aura")
        SetSelectorText(auraSelectButton, aura, "aura")
    end

    if seal then
        local sealName = SpellName(seal.spellID, seal.fallback)
        sealCastButton:SetAttribute("type1", "spell")
        sealCastButton:SetAttribute("spell1", sealName)
        sealCastButton:SetAttribute("unit", "player")
        sealCastButton:SetText("Cast Seal")
        SetSelectorText(sealSelectButton, seal, "seal")
    end

    rfCastButton:SetAttribute("type1", "spell")
    rfCastButton:SetAttribute("spell1", SpellName(RIGHTEOUS_FURY.spellID, RIGHTEOUS_FURY.fallback))
    rfCastButton:SetAttribute("unit", "player")
end

local function UpdateClassRows()
    if not mainFrame then return end

    SetCombatLabel()

    if InCombatLockdown and InCombatLockdown() then
        for _, row in pairs(rows) do
            row.status:SetText("LOCK")
            row.status:SetTextColor(1, 0.55, 0.15)
        end
        return
    end

    local units = GetGroupUnits()

    for _, classToken in ipairs(CLASS_ORDER) do
        local row = rows[classToken]
        local blessingKey = PhantomPowerDB.classBlessings[classToken]
        local blessing = blessingByKey[blessingKey] or blessingByKey.NONE

        SetSelectorText(row.selector, blessing, "blessing")

        if blessing.key == "NONE" then
            row.status:SetText("OFF")
            row.status:SetTextColor(0.6, 0.6, 0.6)
            row.cast:SetAttribute("type1", nil)
            row.cast:SetAttribute("spell1", nil)
            row.cast:SetAttribute("type2", nil)
            row.cast:SetAttribute("spell2", nil)
            row.cast:SetAttribute("unit", nil)
        else
            local normalName = SpellName(blessing.spellID, blessing.fallback)
            local greaterName = SpellName(blessing.greaterSpellID, blessing.greaterFallback)
            local total = 0
            local blessed = 0
            local unknown = false
            local firstMissing
            local firstAny

            for _, unit in ipairs(units) do
                local _, unitClass = UnitClass(unit)
                if unitClass == classToken then
                    total = total + 1
                    if not firstAny and UnitIsUsable(unit) then
                        firstAny = unit
                    end

                    local state = UnitHasAssignedBlessing(unit, normalName, greaterName)
                    if state == true then
                        blessed = blessed + 1
                    elseif state == nil then
                        unknown = true
                    elseif not firstMissing and UnitIsUsable(unit) then
                        firstMissing = unit
                    end
                end
            end

            local targetUnit = firstMissing or firstAny
            row.cast:SetAttribute("type1", "spell")
            row.cast:SetAttribute("spell1", greaterName)
            row.cast:SetAttribute("type2", "spell")
            row.cast:SetAttribute("spell2", normalName)
            row.cast:SetAttribute("unit", targetUnit)

            if total == 0 then
                row.status:SetText("-")
                row.status:SetTextColor(0.6, 0.6, 0.6)
            elseif unknown then
                row.status:SetText("? / " .. total)
                row.status:SetTextColor(1, 0.75, 0.2)
            elseif blessed >= total then
                row.status:SetText(blessed .. " / " .. total)
                row.status:SetTextColor(0.2, 1, 0.2)
            else
                row.status:SetText(blessed .. " / " .. total)
                row.status:SetTextColor(1, 0.35, 0.2)
            end
        end
    end

    ApplyUtilityButtons()
end

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true

    C_Timer.After(0.15, function()
        refreshQueued = false
        UpdateClassRows()
    end)
end

local function SaveFramePosition()
    if not mainFrame then return end
    local point, _, _, x, y = mainFrame:GetPoint(1)
    PhantomPowerDB.point = point or "CENTER"
    PhantomPowerDB.x = x or 0
    PhantomPowerDB.y = y or 0
end

local function CreateSecureButton(parent, width, height, text)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetText(text)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    return button
end

local function ShowCastTooltip(button, title, line1, line2)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 0.82, 0)
        if line1 then GameTooltip:AddLine(line1, 1, 1, 1, true) end
        if line2 then GameTooltip:AddLine(line2, 0.75, 0.75, 0.75, true) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function BuildUI()
    if mainFrame then return end

    mainFrame = CreateFrame("Frame", "PhantomPowerFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(570, 486)
    mainFrame:SetPoint(PhantomPowerDB.point or "CENTER", UIParent, PhantomPowerDB.point or "CENTER", PhantomPowerDB.x or 0, PhantomPowerDB.y or 0)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    mainFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.94)

    mainFrame:SetScript("OnDragStart", function(self)
        if InCombatLockdown and InCombatLockdown() then
            Print("The frame cannot be moved during combat.")
            return
        end
        self:StartMoving()
    end)
    mainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFramePosition()
    end)

    local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("PhantomPower  v" .. VERSION)

    local close = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    close:SetSize(28, 22)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetText("X")
    close:SetScript("OnClick", function()
        if InCombatLockdown and InCombatLockdown() then
            Print("The window cannot be hidden during combat because it contains secure cast buttons.")
            return
        end
        mainFrame:Hide()
    end)

    local utilityHeader = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    utilityHeader:SetPoint("TOPLEFT", 16, -46)
    utilityHeader:SetText("Paladin utility")

    auraSelectButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    auraSelectButton:SetSize(210, 24)
    auraSelectButton:SetPoint("TOPLEFT", 16, -68)
    auraSelectButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    auraSelectButton:SetScript("OnClick", function(_, mouseButton)
        if InCombatLockdown and InCombatLockdown() then
            Print("Aura selection is locked in combat.")
            return
        end
        local direction = mouseButton == "RightButton" and -1 or 1
        PhantomPowerDB.aura = CycleEntry(AURAS, PhantomPowerDB.aura, direction)
        ApplyUtilityButtons()
    end)

    auraCastButton = CreateSecureButton(mainFrame, 90, 24, "Cast Aura")
    auraCastButton:SetPoint("LEFT", auraSelectButton, "RIGHT", 8, 0)
    ShowCastTooltip(auraCastButton, "Aura", "Click to cast the selected Aura.", "Resistance Auras are raid-wide in WoW: Forever.")

    sealSelectButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    sealSelectButton:SetSize(210, 24)
    sealSelectButton:SetPoint("TOPLEFT", 16, -98)
    sealSelectButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    sealSelectButton:SetScript("OnClick", function(_, mouseButton)
        if InCombatLockdown and InCombatLockdown() then
            Print("Seal selection is locked in combat.")
            return
        end
        local direction = mouseButton == "RightButton" and -1 or 1
        PhantomPowerDB.seal = CycleEntry(SEALS, PhantomPowerDB.seal, direction)
        ApplyUtilityButtons()
    end)

    sealCastButton = CreateSecureButton(mainFrame, 90, 24, "Cast Seal")
    sealCastButton:SetPoint("LEFT", sealSelectButton, "RIGHT", 8, 0)
    ShowCastTooltip(sealCastButton, "Seal", "Click to cast the selected Seal.", "Includes WoW: Forever's new Seal of Fury. Seal status is not inferred in combat.")

    rfCastButton = CreateSecureButton(mainFrame, 140, 24, "Righteous Fury")
    rfCastButton:SetPoint("LEFT", sealCastButton, "RIGHT", 8, 0)
    ShowCastTooltip(rfCastButton, "Righteous Fury", "Click to cast Righteous Fury.", "Useful for Protection assignments; no automatic combat-state logic is used.")

    local gridHeader = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    gridHeader:SetPoint("TOPLEFT", 16, -138)
    gridHeader:SetText("Blessing assignments")

    local classHeader = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classHeader:SetPoint("TOPLEFT", 16, -160)
    classHeader:SetText("Class")

    local blessingHeader = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    blessingHeader:SetPoint("TOPLEFT", 126, -160)
    blessingHeader:SetText("Assigned blessing")

    local statusHeader = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusHeader:SetPoint("TOPLEFT", 370, -160)
    statusHeader:SetText("Buffed")

    local castHeader = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    castHeader:SetPoint("TOPLEFT", 448, -160)
    castHeader:SetText("Cast")

    local y = -180
    for _, classToken in ipairs(CLASS_ORDER) do
        local thisClass = classToken
        local row = {}
        rows[thisClass] = row

        row.classText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.classText:SetPoint("TOPLEFT", 16, y - 5)
        row.classText:SetWidth(104)
        row.classText:SetJustifyH("LEFT")
        row.classText:SetText(ClassDisplayName(thisClass))

        row.selector = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
        row.selector:SetSize(230, 24)
        row.selector:SetPoint("TOPLEFT", 122, y)
        row.selector:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.selector:SetScript("OnClick", function(_, mouseButton)
            if InCombatLockdown and InCombatLockdown() then
                Print("Blessing assignments are locked in combat.")
                return
            end
            local direction = mouseButton == "RightButton" and -1 or 1
            local oldKey = PhantomPowerDB.classBlessings[thisClass]
            PhantomPowerDB.classBlessings[thisClass] = CycleEntry(BLESSINGS, oldKey, direction)
            UpdateClassRows()
        end)

        row.status = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.status:SetPoint("TOPLEFT", 370, y - 5)
        row.status:SetWidth(62)
        row.status:SetJustifyH("CENTER")
        row.status:SetText("-")

        row.cast = CreateSecureButton(mainFrame, 92, 24, "Buff")
        row.cast:SetPoint("TOPLEFT", 448, y)
        ShowCastTooltip(
            row.cast,
            ClassDisplayName(thisClass) .. " blessing",
            "Left-click: Greater Blessing (when learned).",
            "Right-click: regular Blessing. Out of combat, regular casts retarget the first missing member of this class."
        )

        y = y - 30
    end

    combatLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    combatLabel:SetPoint("BOTTOMLEFT", 16, 14)
    combatLabel:SetWidth(530)
    combatLabel:SetJustifyH("LEFT")

    ApplyUtilityButtons()
    UpdateClassRows()
    mainFrame:Hide()
end

local function ToggleWindow()
    if not mainFrame then return end
    if InCombatLockdown and InCombatLockdown() then
        Print("The window cannot be shown or hidden during combat.")
        return
    end

    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        UpdateClassRows()
    end
end

local function ResetDB()
    if InCombatLockdown and InCombatLockdown() then
        Print("Reset is unavailable during combat.")
        return
    end

    PhantomPowerDB.point = defaults.point
    PhantomPowerDB.x = defaults.x
    PhantomPowerDB.y = defaults.y
    PhantomPowerDB.aura = defaults.aura
    PhantomPowerDB.seal = defaults.seal
    for _, classToken in ipairs(CLASS_ORDER) do
        PhantomPowerDB.classBlessings[classToken] = defaults.classBlessings[classToken]
    end

    if mainFrame then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    UpdateClassRows()
    Print("Assignments and frame position reset.")
end

local function Diagnostics()
    local version, build, date, toc = GetBuildInfo()
    Print("Addon v" .. VERSION)
    Print("Client: " .. tostring(version) .. " build " .. tostring(build) .. " TOC " .. tostring(toc) .. " (" .. tostring(date) .. ")")
    Print("C_Spell: " .. tostring(C_Spell ~= nil) .. ", C_UnitAuras: " .. tostring(C_UnitAuras ~= nil) .. ", issecretvalue: " .. tostring(type(issecretvalue) == "function"))
    Print("Seal of Fury resolves as: " .. SpellName(1311649, "Seal of Fury"))
end

SLASH_PHANTOMPOWER1 = "/pp"
SLASH_PHANTOMPOWER2 = "/phantompower"
SLASH_PHANTOMPOWER3 = "/phantom"
SlashCmdList.PHANTOMPOWER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "" or msg == "show" or msg == "toggle" then
        ToggleWindow()
    elseif msg == "reset" then
        ResetDB()
    elseif msg == "scan" or msg == "refresh" then
        UpdateClassRows()
        Print("Buff status refreshed.")
    elseif msg == "diag" then
        Diagnostics()
    else
        Print("Commands: /pp, /pp reset, /pp scan, /pp diag (also /phantompower or /phantom)")
    end
end

PP:RegisterEvent("ADDON_LOADED")
PP:RegisterEvent("PLAYER_LOGIN")
PP:RegisterEvent("PLAYER_ENTERING_WORLD")
PP:RegisterEvent("GROUP_ROSTER_UPDATE")
PP:RegisterEvent("UNIT_AURA")
PP:RegisterEvent("SPELLS_CHANGED")
PP:RegisterEvent("PLAYER_LEVEL_UP")
PP:RegisterEvent("PLAYER_REGEN_DISABLED")
PP:RegisterEvent("PLAYER_REGEN_ENABLED")

PP:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        CopyDefaults()
        return
    end

    if event == "PLAYER_LOGIN" then
        if not IsPaladin() then
            Print("Loaded, but this character is not a Paladin. The addon will remain inactive.")
            return
        end
        BuildUI()
        Print("Loaded. Type /pp to toggle the assignment window.")
        return
    end

    if not IsPaladin() or not mainFrame then return end

    if event == "UNIT_AURA" then
        local unit = arg1
        if unit == "player" or (unit and (unit:match("^party%d+$") or unit:match("^raid%d+$"))) then
            if not (InCombatLockdown and InCombatLockdown()) then
                QueueRefresh()
            end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        SetCombatLabel()
        UpdateClassRows()
    elseif event == "PLAYER_REGEN_ENABLED" then
        QueueRefresh()
    else
        if not (InCombatLockdown and InCombatLockdown()) then
            QueueRefresh()
        else
            SetCombatLabel()
        end
    end
end)
