local ADDON_NAME, ns = ...

local PP = CreateFrame("Frame")
ns.PP = PP

local VERSION = "0.3.0"
local PROTOCOL_VERSION = "1"
local COMM_PREFIX = "PhantomPower"
local PREFIX = "|cffffd200PhantomPower|r: "
local MAX_PALADIN_ROWS = 12

local ICON_SIZES = {
    SMALL = 14,
    MEDIUM = 18,
    LARGE = 22,
}

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

local CLASS_SHORT = {
    WARRIOR = "War",
    PALADIN = "Pal",
    HUNTER = "Hun",
    ROGUE = "Rog",
    PRIEST = "Pri",
    SHAMAN = "Sha",
    MAGE = "Mag",
    WARLOCK = "Wlk",
    DRUID = "Dru",
}

local BLESSINGS = {
    { key = "NONE",       label = "None",       short = "-" },
    { key = "MIGHT",      label = "Might",      short = "Mgt", spellID = 19740, greaterSpellID = 25782, fallback = "Blessing of Might",      greaterFallback = "Greater Blessing of Might" },
    { key = "WISDOM",     label = "Wisdom",     short = "Wis", spellID = 19742, greaterSpellID = 25894, fallback = "Blessing of Wisdom",     greaterFallback = "Greater Blessing of Wisdom" },
    { key = "KINGS",      label = "Kings",      short = "Kng", spellID = 20217, greaterSpellID = 25898, fallback = "Blessing of Kings",      greaterFallback = "Greater Blessing of Kings" },
    { key = "SALVATION",  label = "Salvation",  short = "Sal", spellID = 1038,  greaterSpellID = 25895, fallback = "Blessing of Salvation",  greaterFallback = "Greater Blessing of Salvation" },
    { key = "LIGHT",      label = "Light",      short = "Lgt", spellID = 19977, greaterSpellID = 25890, fallback = "Blessing of Light",      greaterFallback = "Greater Blessing of Light" },
}

local BLESSING_ENCODE = {
    NONE = "0",
    MIGHT = "M",
    WISDOM = "W",
    KINGS = "K",
    SALVATION = "S",
    LIGHT = "L",
}
local BLESSING_DECODE = {}
for key, code in pairs(BLESSING_ENCODE) do
    BLESSING_DECODE[code] = key
end

local AURAS = {
    { key = "DEVOTION",      short = "Dev", spellID = 465,   fallback = "Devotion Aura" },
    { key = "RETRIBUTION",   short = "Ret", spellID = 7294,  fallback = "Retribution Aura" },
    { key = "CONCENTRATION", short = "Con", spellID = 19746, fallback = "Concentration Aura" },
    { key = "SHADOW",        short = "Sha", spellID = 19876, fallback = "Shadow Resistance Aura" },
    { key = "FROST",         short = "Fro", spellID = 19888, fallback = "Frost Resistance Aura" },
    { key = "FIRE",          short = "Fir", spellID = 19891, fallback = "Fire Resistance Aura" },
}

local SEALS = {
    { key = "RIGHTEOUSNESS", short = "Rig", spellID = 21084,   fallback = "Seal of Righteousness" },
    { key = "CRUSADER",      short = "Cru", spellID = 21082,   fallback = "Seal of the Crusader" },
    { key = "FURY",          short = "Fur", spellID = 1311649, fallback = "Seal of Fury" },
    { key = "COMMAND",       short = "Com", spellID = 20375,   fallback = "Seal of Command" },
    { key = "JUSTICE",       short = "Jus", spellID = 20164,   fallback = "Seal of Justice" },
    { key = "LIGHT",         short = "Lgt", spellID = 20165,   fallback = "Seal of Light" },
    { key = "WISDOM",        short = "Wis", spellID = 20166,   fallback = "Seal of Wisdom" },
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
    iconSize = "MEDIUM",
    classBlessings = {},
}
for _, classToken in ipairs(CLASS_ORDER) do
    defaults.classBlessings[classToken] = "NONE"
end

local mainFrame
local matrixRows = {}
local buffButtons = {}
local auraSelectButton
local auraCastButton
local sealSelectButton
local sealCastButton
local rfCastButton
local syncLabel
local combatLabel
local assignmentHeader
local buffHeader
local remotePaladins = {}
local addonUsers = {}
local refreshQueued = false
local syncQueued = false

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
    if ok then return info end
    return nil
end

local function SpellName(spellID, fallback)
    local info = SafeSpellInfo(spellID)
    if info and info.name and not IsSecret(info.name) then
        return info.name
    end
    return fallback
end

local function SpellTexture(spellID)
    if C_Spell and type(C_Spell.GetSpellTexture) == "function" then
        local ok, texture = pcall(C_Spell.GetSpellTexture, spellID)
        if ok and texture and not IsSecret(texture) then
            return texture
        end
    end

    local info = SafeSpellInfo(spellID)
    if info and info.iconID and not IsSecret(info.iconID) then
        return info.iconID
    end

    if type(GetSpellTexture) == "function" then
        local ok, texture = pcall(GetSpellTexture, spellID)
        if ok and texture and not IsSecret(texture) then
            return texture
        end
    end

    return nil
end

local function CurrentIconSize()
    local key = PhantomPowerDB and PhantomPowerDB.iconSize or defaults.iconSize
    return ICON_SIZES[key] or ICON_SIZES.MEDIUM
end

local function EnsureAssignmentIcon(button)
    if button.assignmentIcon then return button.assignmentIcon end
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.assignmentIcon = icon
    return icon
end

local function SetAssignmentIcon(button, entry, hasData)
    local icon = EnsureAssignmentIcon(button)
    local iconSize = CurrentIconSize()
    icon:SetSize(iconSize, iconSize)

    if not hasData then
        icon:Hide()
        button:SetText("?")
        button:SetAlpha(0.8)
        return
    end

    button:SetText("")
    if not entry or entry.key == "NONE" then
        icon:Hide()
        button:SetAlpha(0.48)
        return
    end

    local texture = SpellTexture(entry.spellID)
    if texture then
        icon:SetTexture(texture)
        icon:Show()
        button:SetAlpha(1.0)
    else
        icon:Hide()
        button:SetText(entry.short or "?")
        button:SetAlpha(1.0)
    end
end

local function EntryFullName(entry)
    if not entry then return "No synchronized data" end
    if entry.key == "NONE" then return "None" end
    return SpellName(entry.spellID, entry.fallback or entry.label or entry.key)
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
    PhantomPowerDB.iconSize = string.upper(tostring(PhantomPowerDB.iconSize or defaults.iconSize))
    if not ICON_SIZES[PhantomPowerDB.iconSize] then
        PhantomPowerDB.iconSize = defaults.iconSize
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

local function ShortPlayerName(name)
    if not name then return "Unknown" end
    if type(Ambiguate) == "function" then
        local ok, short = pcall(Ambiguate, name, "short")
        if ok and short and short ~= "" then return short end
    end
    return name:match("^([^%-]+)") or name
end

local function PlayerKey(name)
    return string.lower(ShortPlayerName(name or ""))
end

local function GetSelfName()
    local name = UnitName("player")
    return name or "Player"
end

local function GetGroupChannel()
    if type(IsInRaid) == "function" and IsInRaid() then
        return "RAID"
    end
    if type(IsInGroup) == "function" and IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function GetGroupUnits()
    local units = {}

    if type(IsInRaid) == "function" and IsInRaid() then
        local count = type(GetNumGroupMembers) == "function" and GetNumGroupMembers() or 0
        for i = 1, count do
            local unit = "raid" .. i
            if UnitExists(unit) then units[#units + 1] = unit end
        end
    elseif type(IsInGroup) == "function" and IsInGroup() then
        units[#units + 1] = "player"
        local count = type(GetNumSubgroupMembers) == "function" and GetNumSubgroupMembers() or 0
        for i = 1, count do
            local unit = "party" .. i
            if UnitExists(unit) then units[#units + 1] = unit end
        end
    else
        units[1] = "player"
    end

    return units
end

local function GetPaladinRoster()
    local found = {}
    local list = {}

    for _, unit in ipairs(GetGroupUnits()) do
        local name = UnitName(unit)
        local _, classToken = UnitClass(unit)
        if name and classToken == "PALADIN" then
            local key = PlayerKey(name)
            if not found[key] then
                found[key] = true
                list[#list + 1] = {
                    key = key,
                    name = ShortPlayerName(name),
                    isSelf = UnitIsUnit and UnitIsUnit(unit, "player") or key == PlayerKey(GetSelfName()),
                }
            end
        end
    end

    table.sort(list, function(a, b)
        if a.isSelf ~= b.isSelf then return a.isSelf end
        return string.lower(a.name) < string.lower(b.name)
    end)

    return list
end

local function UnitIsUsable(unit)
    if not UnitExists(unit) then return false end
    if UnitIsConnected and not UnitIsConnected(unit) then return false end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return false end
    return true
end

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

    if unreadable then return nil end
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

local function CreateSecureButton(parent, width, height, text)
    local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetText(text)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    return button
end

local function ShowTooltip(frame, titleFunc, bodyFunc)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local title = type(titleFunc) == "function" and titleFunc() or titleFunc
        local body = type(bodyFunc) == "function" and bodyFunc() or bodyFunc
        GameTooltip:SetText(title or "PhantomPower", 1, 0.82, 0)
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function SendAddon(payload)
    local channel = GetGroupChannel()
    if not channel then return false end
    if not C_ChatInfo or type(C_ChatInfo.SendAddonMessage) ~= "function" then return false end
    local ok = pcall(C_ChatInfo.SendAddonMessage, COMM_PREFIX, payload, channel)
    return ok
end

local function EncodeAssignments(assignments)
    local chars = {}
    for i, classToken in ipairs(CLASS_ORDER) do
        local key = assignments[classToken] or "NONE"
        chars[i] = BLESSING_ENCODE[key] or "0"
    end
    return table.concat(chars, "")
end

local function DecodeAssignments(encoded)
    if type(encoded) ~= "string" or #encoded < #CLASS_ORDER then return nil end
    local result = {}
    for i, classToken in ipairs(CLASS_ORDER) do
        local code = encoded:sub(i, i)
        result[classToken] = BLESSING_DECODE[code] or "NONE"
    end
    return result
end

local function SendState()
    if not IsPaladin() or not PhantomPowerDB then return end
    local payload = table.concat({
        "S",
        PROTOCOL_VERSION,
        VERSION,
        PhantomPowerDB.aura or "DEVOTION",
        PhantomPowerDB.seal or "RIGHTEOUSNESS",
        EncodeAssignments(PhantomPowerDB.classBlessings),
    }, "|")
    SendAddon(payload)
end

local function SendHello()
    local role = IsPaladin() and "P" or "V"
    SendAddon(table.concat({ "H", PROTOCOL_VERSION, VERSION, role }, "|"))
end

local function RequestStates()
    SendAddon("R|" .. PROTOCOL_VERSION)
end

local function AnnounceAndRequest()
    if not GetGroupChannel() then return end
    SendHello()
    if IsPaladin() then SendState() end
    RequestStates()
end

local function SplitMessage(message)
    local fields = {}
    local start = 1
    while true do
        local pos = string.find(message, "|", start, true)
        if not pos then
            fields[#fields + 1] = string.sub(message, start)
            break
        end
        fields[#fields + 1] = string.sub(message, start, pos - 1)
        start = pos + 1
    end
    return fields
end

local function SetUtilitySelectorText()
    if auraSelectButton then
        local aura = auraByKey[PhantomPowerDB.aura]
        auraSelectButton:SetText(aura and SpellName(aura.spellID, aura.fallback) or "Aura")
    end
    if sealSelectButton then
        local seal = sealByKey[PhantomPowerDB.seal]
        sealSelectButton:SetText(seal and SpellName(seal.spellID, seal.fallback) or "Seal")
    end
end

local function ApplyUtilityButtons()
    if not IsPaladin() then return end
    if not auraCastButton or not sealCastButton or not rfCastButton then return end
    SetUtilitySelectorText()
    if InCombatLockdown and InCombatLockdown() then return end

    local aura = auraByKey[PhantomPowerDB.aura]
    local seal = sealByKey[PhantomPowerDB.seal]

    if aura then
        auraCastButton:SetAttribute("type1", "spell")
        auraCastButton:SetAttribute("spell1", SpellName(aura.spellID, aura.fallback))
        auraCastButton:SetAttribute("unit", "player")
    end
    if seal then
        sealCastButton:SetAttribute("type1", "spell")
        sealCastButton:SetAttribute("spell1", SpellName(seal.spellID, seal.fallback))
        sealCastButton:SetAttribute("unit", "player")
    end
    rfCastButton:SetAttribute("type1", "spell")
    rfCastButton:SetAttribute("spell1", SpellName(RIGHTEOUS_FURY.spellID, RIGHTEOUS_FURY.fallback))
    rfCastButton:SetAttribute("unit", "player")
end

local function UpdateBuffBar()
    if not IsPaladin() or not next(buffButtons) then return end

    local locked = InCombatLockdown and InCombatLockdown()
    local units = GetGroupUnits()

    if combatLabel then
        if locked then
            combatLabel:SetText("Combat: assignments and secure buff targets are locked")
            combatLabel:SetTextColor(1, 0.35, 0.2)
        else
            combatLabel:SetText("Buff bar: left-click Greater Blessing • right-click regular Blessing")
            combatLabel:SetTextColor(0.75, 0.75, 0.75)
        end
    end

    for _, classToken in ipairs(CLASS_ORDER) do
        local button = buffButtons[classToken]
        local blessingKey = PhantomPowerDB.classBlessings[classToken] or "NONE"
        local blessing = blessingByKey[blessingKey] or blessingByKey.NONE
        local className = ClassDisplayName(classToken)

        if locked then
            button:SetText(className .. " • LOCK")
        elseif blessing.key == "NONE" then
            button:SetText(className .. " • Off")
            button:SetAttribute("type1", nil)
            button:SetAttribute("spell1", nil)
            button:SetAttribute("type2", nil)
            button:SetAttribute("spell2", nil)
            button:SetAttribute("unit", nil)
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
                    if not firstAny and UnitIsUsable(unit) then firstAny = unit end
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
            button:SetAttribute("type1", "spell")
            button:SetAttribute("spell1", greaterName)
            button:SetAttribute("type2", "spell")
            button:SetAttribute("spell2", normalName)
            button:SetAttribute("unit", targetUnit)

            local status
            if total == 0 then
                status = "-"
            elseif unknown then
                status = "? / " .. total
            else
                status = blessed .. " / " .. total
            end
            button:SetText(className .. " • " .. blessing.label .. "  " .. status)
        end
    end

    ApplyUtilityButtons()
end

local function LocalState()
    return {
        version = VERSION,
        aura = PhantomPowerDB.aura,
        seal = PhantomPowerDB.seal,
        assignments = PhantomPowerDB.classBlessings,
        synced = true,
    }
end

local function GetRosterState(entry)
    if entry.isSelf and IsPaladin() then
        return LocalState()
    end
    return remotePaladins[entry.key]
end

local function UpdateMatrix()
    if not mainFrame then return end

    local roster = GetPaladinRoster()
    local syncedCount = 0
    for _, entry in ipairs(roster) do
        if GetRosterState(entry) then syncedCount = syncedCount + 1 end
    end

    for rowIndex = 1, MAX_PALADIN_ROWS do
        local row = matrixRows[rowIndex]
        local entry = roster[rowIndex]
        if entry then
            row.entry = entry
            row.frame:Show()
            row.name:SetText(entry.name)
            local state = GetRosterState(entry)

            if entry.isSelf then
                row.name:SetTextColor(1, 0.82, 0)
            elseif state then
                row.name:SetTextColor(0.75, 1, 0.75)
            else
                row.name:SetTextColor(1, 0.4, 0.4)
            end

            if state then
                row.sync:SetText(state.version and ("v" .. state.version) or "sync")
                row.sync:SetTextColor(0.55, 0.9, 0.55)
            else
                row.sync:SetText("No data")
                row.sync:SetTextColor(1, 0.45, 0.35)
            end

            for _, classToken in ipairs(CLASS_ORDER) do
                local cell = row.cells[classToken]
                cell.playerKey = entry.key
                cell.isSelf = entry.isSelf and IsPaladin()
                local blessingKey = state and state.assignments and state.assignments[classToken] or nil
                local blessing = blessingKey and blessingByKey[blessingKey] or nil
                cell.currentEntry = blessing
                cell.hasData = state ~= nil
                SetAssignmentIcon(cell, blessing, state ~= nil)
                cell:SetEnabled(cell.isSelf and not (InCombatLockdown and InCombatLockdown()))
            end

            local aura = state and auraByKey[state.aura] or nil
            local seal = state and sealByKey[state.seal] or nil
            row.aura.currentEntry = aura
            row.seal.currentEntry = seal
            row.aura.hasData = state ~= nil
            row.seal.hasData = state ~= nil
            SetAssignmentIcon(row.aura, aura, state ~= nil)
            SetAssignmentIcon(row.seal, seal, state ~= nil)
            row.aura.isSelf = entry.isSelf and IsPaladin()
            row.seal.isSelf = entry.isSelf and IsPaladin()
            row.aura:SetEnabled(row.aura.isSelf and not (InCombatLockdown and InCombatLockdown()))
            row.seal:SetEnabled(row.seal.isSelf and not (InCombatLockdown and InCombatLockdown()))
        else
            row.entry = nil
            row.frame:Hide()
        end
    end

    if syncLabel then
        local channel = GetGroupChannel()
        if not channel then
            if IsPaladin() then
                syncLabel:SetText("Solo • your assignments are local until you join a party or raid")
            else
                syncLabel:SetText("Join a party or raid to view PhantomPower Paladin assignments")
            end
        else
            syncLabel:SetText(string.format("%s sync • %d Paladin%s • %d reporting PhantomPower", channel, #roster, #roster == 1 and "" or "s", syncedCount))
        end
    end

    local visibleRows = math.min(math.max(#roster, 1), MAX_PALADIN_ROWS)
    if IsPaladin() then
        mainFrame:SetHeight(392 + visibleRows * 28)
    else
        mainFrame:SetHeight(154 + visibleRows * 28)
    end
end

local function UpdateAll()
    UpdateMatrix()
    UpdateBuffBar()
end

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.15, function()
        refreshQueued = false
        UpdateAll()
    end)
end

local function QueueSync()
    if syncQueued then return end
    syncQueued = true
    C_Timer.After(0.5, function()
        syncQueued = false
        AnnounceAndRequest()
    end)
end

local function SaveFramePosition()
    if not mainFrame then return end
    local point, _, _, x, y = mainFrame:GetPoint(1)
    PhantomPowerDB.point = point or "CENTER"
    PhantomPowerDB.x = x or 0
    PhantomPowerDB.y = y or 0
end

local function OnLocalAssignmentChanged()
    UpdateAll()
    SendState()
end

local function CreateMatrixRow(parent, index, topY)
    local row = {}
    row.frame = CreateFrame("Frame", nil, parent)
    row.frame:SetSize(746, 26)
    row.frame:SetPoint("TOPLEFT", 12, topY - ((index - 1) * 28))

    row.name = row.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", 0, 0)
    row.name:SetWidth(104)
    row.name:SetJustifyH("LEFT")

    row.sync = row.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.sync:SetPoint("LEFT", 106, 0)
    row.sync:SetWidth(56)
    row.sync:SetJustifyH("LEFT")

    row.cells = {}
    local x = 164
    for _, classToken in ipairs(CLASS_ORDER) do
        local thisClass = classToken
        local cell = CreateFrame("Button", nil, row.frame, "UIPanelButtonTemplate")
        cell:SetSize(48, 24)
        cell:SetPoint("LEFT", x, 0)
        cell:SetText("?")
        EnsureAssignmentIcon(cell)
        cell:RegisterForClicks("LeftButtonUp")
        cell:SetScript("OnClick", function(self)
            if not self.isSelf then return end
            if InCombatLockdown and InCombatLockdown() then
                Print("Blessing assignments are locked in combat.")
                return
            end
            local oldKey = PhantomPowerDB.classBlessings[thisClass] or "NONE"
            PhantomPowerDB.classBlessings[thisClass] = CycleEntry(BLESSINGS, oldKey, 1)
            OnLocalAssignmentChanged()
        end)
        ShowTooltip(cell,
            function()
                if not cell.hasData then
                    return ClassDisplayName(thisClass) .. ": No synchronized data"
                end
                return EntryFullName(cell.currentEntry)
            end,
            function()
                local className = ClassDisplayName(thisClass)
                if not cell.hasData then
                    return "No PhantomPower assignment has been received for this Paladin."
                elseif cell.isSelf then
                    return className .. " assignment. Left-click to cycle to the next blessing."
                elseif cell.currentEntry and cell.currentEntry.key ~= "NONE" then
                    return "Assigned to this Paladin for " .. className .. "."
                end
                return "No blessing assigned to this Paladin for " .. className .. "."
            end
        )
        row.cells[thisClass] = cell
        x = x + 50
    end

    row.aura = CreateFrame("Button", nil, row.frame, "UIPanelButtonTemplate")
    row.aura:SetSize(48, 24)
    row.aura:SetPoint("LEFT", x + 2, 0)
    row.aura:SetText("?")
    EnsureAssignmentIcon(row.aura)
    row.aura:RegisterForClicks("LeftButtonUp")
    row.aura:SetScript("OnClick", function(self)
        if not self.isSelf then return end
        if InCombatLockdown and InCombatLockdown() then
            Print("Aura assignment is locked in combat.")
            return
        end
        PhantomPowerDB.aura = CycleEntry(AURAS, PhantomPowerDB.aura, 1)
        ApplyUtilityButtons()
        OnLocalAssignmentChanged()
    end)
    ShowTooltip(row.aura,
        function()
            if not row.aura.hasData then return "Aura: No synchronized data" end
            return EntryFullName(row.aura.currentEntry)
        end,
        function()
            if not row.aura.hasData then
                return "No PhantomPower aura assignment has been received for this Paladin."
            elseif row.aura.isSelf then
                return "Aura assignment. Left-click to cycle to the next aura."
            end
            return "This Paladin's assigned aura."
        end
    )

    row.seal = CreateFrame("Button", nil, row.frame, "UIPanelButtonTemplate")
    row.seal:SetSize(48, 24)
    row.seal:SetPoint("LEFT", x + 52, 0)
    row.seal:SetText("?")
    EnsureAssignmentIcon(row.seal)
    row.seal:RegisterForClicks("LeftButtonUp")
    row.seal:SetScript("OnClick", function(self)
        if not self.isSelf then return end
        if InCombatLockdown and InCombatLockdown() then
            Print("Seal assignment is locked in combat.")
            return
        end
        PhantomPowerDB.seal = CycleEntry(SEALS, PhantomPowerDB.seal, 1)
        ApplyUtilityButtons()
        OnLocalAssignmentChanged()
    end)
    ShowTooltip(row.seal,
        function()
            if not row.seal.hasData then return "Seal: No synchronized data" end
            return EntryFullName(row.seal.currentEntry)
        end,
        function()
            if not row.seal.hasData then
                return "No PhantomPower seal assignment has been received for this Paladin."
            elseif row.seal.isSelf then
                return "Seal assignment. Left-click to cycle to the next seal."
            end
            return "This Paladin's assigned seal."
        end
    )

    row.frame:Hide()
    return row
end

local function BuildUI()
    if mainFrame then return end

    mainFrame = CreateFrame("Frame", "PhantomPowerFrame", UIParent, "BackdropTemplate")
    mainFrame:SetSize(770, 430)
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
        if IsPaladin() and InCombatLockdown and InCombatLockdown() then
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
    title:SetPoint("TOPLEFT", 14, -13)
    title:SetText("PhantomPower  v" .. VERSION)

    local close = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    close:SetSize(28, 22)
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetText("X")
    close:SetScript("OnClick", function()
        if IsPaladin() and InCombatLockdown and InCombatLockdown() then
            Print("The window cannot be hidden during combat because it contains secure cast buttons.")
            return
        end
        mainFrame:Hide()
    end)

    local refresh = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    refresh:SetSize(72, 22)
    refresh:SetPoint("RIGHT", close, "LEFT", -6, 0)
    refresh:SetText("Sync")
    refresh:SetScript("OnClick", function()
        AnnounceAndRequest()
        QueueRefresh()
    end)
    ShowTooltip(refresh, "Synchronize", "Broadcast PhantomPower presence and request current Paladin assignments from your party or raid.")

    syncLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    syncLabel:SetPoint("TOPLEFT", 14, -40)
    syncLabel:SetWidth(735)
    syncLabel:SetJustifyH("LEFT")

    assignmentHeader = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    assignmentHeader:SetPoint("TOPLEFT", 14, -62)
    assignmentHeader:SetText("Shared Paladin assignments")

    local nameHeader = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameHeader:SetPoint("TOPLEFT", 14, -83)
    nameHeader:SetWidth(104)
    nameHeader:SetJustifyH("LEFT")
    nameHeader:SetText("Paladin")

    local syncHeader = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    syncHeader:SetPoint("TOPLEFT", 120, -83)
    syncHeader:SetWidth(56)
    syncHeader:SetJustifyH("LEFT")
    syncHeader:SetText("Sync")

    local x = 178
    for _, classToken in ipairs(CLASS_ORDER) do
        local h = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", x, -83)
        h:SetWidth(48)
        h:SetJustifyH("CENTER")
        h:SetText(CLASS_SHORT[classToken])
        x = x + 50
    end

    local auraHeader = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    auraHeader:SetPoint("TOPLEFT", x + 2, -83)
    auraHeader:SetWidth(48)
    auraHeader:SetJustifyH("CENTER")
    auraHeader:SetText("Aura")

    local sealHeader = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sealHeader:SetPoint("TOPLEFT", x + 52, -83)
    sealHeader:SetWidth(48)
    sealHeader:SetJustifyH("CENTER")
    sealHeader:SetText("Seal")

    for i = 1, MAX_PALADIN_ROWS do
        matrixRows[i] = CreateMatrixRow(mainFrame, i, -104)
    end

    if IsPaladin() then
        local utilityY = -104 - (MAX_PALADIN_ROWS * 0)
        buffHeader = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        buffHeader:SetText("Your Paladin controls")

        auraSelectButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
        auraSelectButton:SetSize(200, 24)
        auraSelectButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        auraSelectButton:SetScript("OnClick", function(_, mouseButton)
            if InCombatLockdown and InCombatLockdown() then
                Print("Aura selection is locked in combat.")
                return
            end
            local direction = mouseButton == "RightButton" and -1 or 1
            PhantomPowerDB.aura = CycleEntry(AURAS, PhantomPowerDB.aura, direction)
            ApplyUtilityButtons()
            OnLocalAssignmentChanged()
        end)

        auraCastButton = CreateSecureButton(mainFrame, 82, 24, "Cast Aura")
        sealSelectButton = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
        sealSelectButton:SetSize(200, 24)
        sealSelectButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        sealSelectButton:SetScript("OnClick", function(_, mouseButton)
            if InCombatLockdown and InCombatLockdown() then
                Print("Seal selection is locked in combat.")
                return
            end
            local direction = mouseButton == "RightButton" and -1 or 1
            PhantomPowerDB.seal = CycleEntry(SEALS, PhantomPowerDB.seal, direction)
            ApplyUtilityButtons()
            OnLocalAssignmentChanged()
        end)
        sealCastButton = CreateSecureButton(mainFrame, 82, 24, "Cast Seal")
        rfCastButton = CreateSecureButton(mainFrame, 120, 24, "Righteous Fury")

        local buffStartY = 0
        for i, classToken in ipairs(CLASS_ORDER) do
            local col = (i - 1) % 3
            local row = math.floor((i - 1) / 3)
            local button = CreateSecureButton(mainFrame, 236, 28, ClassDisplayName(classToken))
            button:SetPoint("TOPLEFT", 14 + (col * 248), buffStartY - (row * 32))
            ShowTooltip(button,
                ClassDisplayName(classToken) .. " blessing",
                "Left-click: Greater Blessing. Right-click: regular Blessing. Targets update out of combat from your assignment row."
            )
            buffButtons[classToken] = button
        end

        combatLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        combatLabel:SetWidth(735)
        combatLabel:SetJustifyH("LEFT")
    end

    mainFrame:Hide()
    UpdateAll()
end

local function LayoutPaladinControls()
    if not IsPaladin() or not mainFrame or not buffHeader then return end
    local roster = GetPaladinRoster()
    local visibleRows = math.min(math.max(#roster, 1), MAX_PALADIN_ROWS)
    local gridBottomY = -104 - ((visibleRows - 1) * 28) - 28
    local controlsY = gridBottomY - 14

    buffHeader:ClearAllPoints()
    buffHeader:SetPoint("TOPLEFT", 14, controlsY)

    auraSelectButton:ClearAllPoints()
    auraSelectButton:SetPoint("TOPLEFT", 14, controlsY - 24)
    auraCastButton:ClearAllPoints()
    auraCastButton:SetPoint("LEFT", auraSelectButton, "RIGHT", 6, 0)
    sealSelectButton:ClearAllPoints()
    sealSelectButton:SetPoint("LEFT", auraCastButton, "RIGHT", 14, 0)
    sealCastButton:ClearAllPoints()
    sealCastButton:SetPoint("LEFT", sealSelectButton, "RIGHT", 6, 0)
    rfCastButton:ClearAllPoints()
    rfCastButton:SetPoint("TOPLEFT", 14, controlsY - 54)

    local buffStartY = controlsY - 88
    for i, classToken in ipairs(CLASS_ORDER) do
        local col = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        local button = buffButtons[classToken]
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", 14 + (col * 248), buffStartY - (row * 32))
    end

    combatLabel:ClearAllPoints()
    combatLabel:SetPoint("TOPLEFT", 14, buffStartY - 102)
end

local function RefreshLayout()
    UpdateMatrix()
    LayoutPaladinControls()
    UpdateBuffBar()
end

-- Replace UpdateAll with the layout-aware version after UI helpers are defined.
UpdateAll = RefreshLayout

local function ToggleWindow()
    if not mainFrame then return end
    if IsPaladin() and InCombatLockdown and InCombatLockdown() then
        Print("The window cannot be shown or hidden during combat.")
        return
    end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        RefreshLayout()
        AnnounceAndRequest()
    end
end

local function ResetDB()
    if IsPaladin() and InCombatLockdown and InCombatLockdown() then
        Print("Reset is unavailable during combat.")
        return
    end

    PhantomPowerDB.point = defaults.point
    PhantomPowerDB.x = defaults.x
    PhantomPowerDB.y = defaults.y
    PhantomPowerDB.aura = defaults.aura
    PhantomPowerDB.seal = defaults.seal
    PhantomPowerDB.iconSize = defaults.iconSize
    for _, classToken in ipairs(CLASS_ORDER) do
        PhantomPowerDB.classBlessings[classToken] = defaults.classBlessings[classToken]
    end

    if mainFrame then
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    RefreshLayout()
    SendState()
    Print("Assignments and frame position reset.")
end

local function Diagnostics()
    local version, build, date, toc = GetBuildInfo()
    Print("Addon v" .. VERSION .. " protocol " .. PROTOCOL_VERSION)
    Print("Client: " .. tostring(version) .. " build " .. tostring(build) .. " TOC " .. tostring(toc) .. " (" .. tostring(date) .. ")")
    Print("C_ChatInfo: " .. tostring(C_ChatInfo ~= nil) .. ", prefix registered: " .. tostring(C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered and C_ChatInfo.IsAddonMessagePrefixRegistered(COMM_PREFIX)))
    Print("Group channel: " .. tostring(GetGroupChannel()) .. ", Paladin: " .. tostring(IsPaladin()))
    Print("Assignment icon size: " .. tostring(PhantomPowerDB and PhantomPowerDB.iconSize))
    Print("Known remote Paladin states: " .. tostring((function() local n = 0 for _ in pairs(remotePaladins) do n = n + 1 end return n end)()))
end

local function RegisterCommPrefix()
    if C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, COMM_PREFIX)
    end
end

local function HandleAddonMessage(prefix, message, channel, sender)
    if prefix ~= COMM_PREFIX then return end
    if channel ~= "PARTY" and channel ~= "RAID" then return end
    if not sender or not message then return end

    local senderKey = PlayerKey(sender)
    if senderKey == PlayerKey(GetSelfName()) then return end

    local fields = SplitMessage(message)
    local command = fields[1]
    local protocol = fields[2]
    if protocol ~= PROTOCOL_VERSION then return end

    if command == "H" then
        addonUsers[senderKey] = {
            version = fields[3],
            role = fields[4],
            lastSeen = GetTime and GetTime() or 0,
        }
        if IsPaladin() then SendState() end
        QueueRefresh()
    elseif command == "R" then
        if IsPaladin() then SendState() end
    elseif command == "S" then
        local assignments = DecodeAssignments(fields[6] or "")
        if not assignments then return end
        if not auraByKey[fields[4]] or not sealByKey[fields[5]] then return end
        remotePaladins[senderKey] = {
            name = ShortPlayerName(sender),
            version = fields[3],
            aura = fields[4],
            seal = fields[5],
            assignments = assignments,
            lastSeen = GetTime and GetTime() or 0,
        }
        addonUsers[senderKey] = {
            version = fields[3],
            role = "P",
            lastSeen = GetTime and GetTime() or 0,
        }
        QueueRefresh()
    end
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
    elseif msg == "scan" or msg == "refresh" or msg == "sync" then
        RefreshLayout()
        AnnounceAndRequest()
        Print("Assignment sync requested.")
    elseif msg == "diag" then
        Diagnostics()
    elseif msg == "icons" then
        Print("Assignment icon size is " .. string.lower(PhantomPowerDB.iconSize or defaults.iconSize) .. ". Use /pp icons small, /pp icons medium, or /pp icons large.")
    elseif msg == "icons small" or msg == "icons medium" or msg == "icons large" then
        local size = string.upper(msg:match("icons%s+(%a+)") or "MEDIUM")
        PhantomPowerDB.iconSize = ICON_SIZES[size] and size or defaults.iconSize
        RefreshLayout()
        Print("Assignment icon size set to " .. string.lower(PhantomPowerDB.iconSize) .. ".")
    else
        Print("Commands: /pp, /pp sync, /pp reset, /pp scan, /pp icons small|medium|large, /pp diag")
    end
end

PP:RegisterEvent("ADDON_LOADED")
PP:RegisterEvent("PLAYER_LOGIN")
PP:RegisterEvent("PLAYER_ENTERING_WORLD")
PP:RegisterEvent("GROUP_ROSTER_UPDATE")
PP:RegisterEvent("CHAT_MSG_ADDON")
PP:RegisterEvent("UNIT_AURA")
PP:RegisterEvent("SPELLS_CHANGED")
PP:RegisterEvent("PLAYER_LEVEL_UP")
PP:RegisterEvent("PLAYER_REGEN_DISABLED")
PP:RegisterEvent("PLAYER_REGEN_ENABLED")

PP:SetScript("OnEvent", function(_, event, ...)
    local arg1, arg2, arg3, arg4 = ...

    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        CopyDefaults()
        RegisterCommPrefix()
        return
    end

    if event == "CHAT_MSG_ADDON" then
        HandleAddonMessage(arg1, arg2, arg3, arg4)
        return
    end

    if event == "PLAYER_LOGIN" then
        CopyDefaults()
        RegisterCommPrefix()
        BuildUI()
        if IsPaladin() then
            Print("Loaded. Shared Paladin assignments are enabled. Type /pp to open PhantomPower.")
        else
            Print("Loaded in assignment-viewer mode. Type /pp to see synced Paladin assignments.")
        end
        C_Timer.After(1.0, function()
            AnnounceAndRequest()
            QueueRefresh()
        end)
        return
    end

    if not mainFrame then return end

    if event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        QueueSync()
        QueueRefresh()
    elseif event == "UNIT_AURA" then
        if not IsPaladin() then return end
        local unit = arg1
        if unit == "player" or (unit and (unit:match("^party%d+$") or unit:match("^raid%d+$"))) then
            if not (InCombatLockdown and InCombatLockdown()) then QueueRefresh() end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        QueueRefresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        QueueRefresh()
        SendState()
    else
        QueueRefresh()
    end
end)
