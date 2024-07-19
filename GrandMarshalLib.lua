-- ╔═══════════╗
-- ║ Constants ║
-- ╚═══════════╝

local WASTED_HONOR = "This red section of the bar is wasted honor.\nConsider reaching the next milestone before the next reset"
local DEBUG_PRINTS = false

-- Update interval (sec) for next reset countdown frame updates
local UPDATE_INTERVAL = 1

local SOD_SERVERS = {
    "Chaos Bolt",
    "Crusader Strike",
    "Lava Lash",
    "Living Flame",
    "Lone Wolf",
    "Penance (AU)",
    "Shadowstrike (AU)",
    "Wild Growth"

}

local SOD_MAX_RANK = 10
local SERVER_NAME = GetRealmName()

-- ╔═══════════╗
-- ║ Variables ║
-- ╚═══════════╝

local play_rank_sound_when_setting = false
local rankUpTextColor = CreateColor(0, .45, .9)
local debugTextColor = CreateColor(0, .45, .9)
local function DebugPrint(str)
    if DEBUG_PRINTS then
        print(debugTextColor:WrapTextInColorCode("GrandMarshal: ") .. str)
    end
end

local sod_server = false

for _, value in ipairs(SOD_SERVERS) do
    if value == SERVER_NAME then
        sod_server = true
    end
end

local factionGroup, factionName = UnitFactionGroup("player");
if (factionGroup == "Alliance") then
    rankUpTextColor = CreateColor(.57, .64, .91)
else
    rankUpTextColor = CreateColor(.74, .17, .09)
end

-- ╔════════════════════════════╗
-- ║ Rank Calculation Functions ║
-- ╚════════════════════════════╝

local function GetEarnedCP(honor)
    if (honor > 500000) then
        honor = 500000
    end

    -- Honor between 1 and 45k uses rank 1-6 conversion rate 4/9
    if (honor < 45000) then
        return honor * (4 / 9)
    end

    local cpTotal = 45000 * (4 / 9)

    honor = honor - 45000

    -- Honor between 45k and 175k uses rank 7-10 conversion rate 2/13
    if (honor < 130000) then
        return cpTotal + (honor * (2 / 13))
    end

    -- Honor above 175k uses rank 11-14 conversion rate 4/65
    cpTotal = cpTotal + (130000 * (2 / 13))

    honor = honor - 130000

    return cpTotal + (honor * (4 / 65))
end

local function GetHonorChangeFactorForRank(rank)
    if rank == 1 or rank == 2 or rank == 3 then
        return 1
    elseif rank == 4 or rank == 5 or rank == 6 then
        return 0.8
    elseif rank == 7 or rank == 8 then
        return 0.7
    elseif rank == 9 then
        return 0.6
    elseif rank == 10 or rank == 11 then
        return 0.5
    elseif rank == 12 or rank == 13 then
        return 0.4
    elseif rank == 14 then
        return 0.34
    end

    print("Unknown rank: " .. rank)
end

local function GetCpForRank(rank)
    if rank < 2 then
        return 0
    elseif rank < 3 then
        return 2000
    end

    return (rank - 2) * 5000
end

local function GetExpectedRank(cp)
    if cp < 2000 then
        return 1
    end

    if cp < 5000 then
        return 2
    end

    local rank = (cp / 5000) + 2

    if rank > 14 then
        return 14
    end

    return rank
end

function MinHonorNeededForRank(rank)
    if (rank <= 6) then
        return GetCpForRank(rank) * (9 / 4)
    end

    if (rank <= 10) then
        return 45000 + ((GetCpForRank(rank) - 20000) * (13 / 2))
    end

    return 175000 + ((GetCpForRank(rank) - 40000) * (65 / 4))
end

local function GetCpCutoffForRank(rank)
    if rank == 9 then
        return 3000
    end

    if rank == 11 then
        return 2500
    end

    return (GetCpForRank(rank + 1) - GetCpForRank(rank)) * GetHonorChangeFactorForRank(rank + 1)
end

local function GetGoodBoyCpForRank(rank, bracket)
    if rank == 6 and bracket == 4 then
        return 500
    end

    if rank == 7 and bracket > 2 then
        return 500
    end

    if rank == 8 then
        if bracket == 4 then
            return 1000
        elseif bracket > 1 then
            return 500
        end
    end

    if rank == 9 and bracket > 2 then
        return 500
    end

    if rank == 10 and bracket > 1 then
        return 500
    end

    return 0
end

local function GetAwardedCp(honor, rank, progress)
    local earnedCp = GetEarnedCP(honor)
    local expectedRank = math.floor(GetExpectedRank(earnedCp))

    if expectedRank > rank + 4 then
        expectedRank = rank + 4
    end

    local in_decay = expectedRank < rank

    local awardedCp = 0

    for i = rank, expectedRank - 1, 1 do
        local award

        if i == rank then
            award = (GetCpForRank(i + 1) - GetCpForRank(i)) * (1 - progress)

            if award > GetCpCutoffForRank(i) then
                award = GetCpCutoffForRank(i)
            end

            award = award + GetGoodBoyCpForRank(rank, expectedRank - rank)
        else
            award = (GetCpForRank(i + 1) - GetCpForRank(i)) * GetHonorChangeFactorForRank(i + 1)
        end

        awardedCp = awardedCp + award
    end

    -- Getting out of decay awards the first CP milestone
    if awardedCp == 0 and not in_decay and rank < 14 then
        awardedCp = GetAwardedCp(MinHonorNeededForRank(rank + 1), rank, progress)
    end

    return awardedCp
end

local function GetNextRank(honor, rank, progress)
    if (rank < 1) then
        rank = 1
    end

    local currentCp = GetCpForRank(rank)
        -- CP for partial progress into the next rank
        + ((GetCpForRank(rank + 1) - GetCpForRank(rank))
            * progress)

    return GetExpectedRank(currentCp + GetAwardedCp(honor, rank, progress))
end

---@class Milestone
---@field honor integer?
---@field rank number?
---@field rankText string?
local Milestone = { honor = nil, rank = nil, rankText = nil }

function Milestone:new(currentRank, progress, expectedRank)
    local o = {}
    setmetatable(o, self)
    self.__index = self

    if (expectedRank > 14) then
        return o
    end

    o.honor = MinHonorNeededForRank(expectedRank)
    o.rank = GetNextRank(o.honor, currentRank, progress)
    o.rankText, _ = GetPVPRankInfo(o.rank + 4)

    return o
end

function Milestone:is_nil(o)
    return o.honor == nil or o.rank == nil or o.rankText == nil
end

function Milestone:DebugPrint(o)
    DebugPrint("Honor: " .. tostring(o.honor) .. ", Rank: " .. string.format("%.4f", o.rank) .. ", Rank Text: " .. tostring(o.rankText))
end

-- ╔═════════════════════╗
-- ║ UI Update Functions ║
-- ╚═════════════════════╝

local function updateChunk(statusBarChunk, milestoneFrame, minValue, maxValue, currentHonor, maxHonor, rankText, rankVal)
    local milestoneTick = _G[milestoneFrame:GetName() .. "Tick"]
    local milestoneTickNumber = _G[milestoneFrame:GetName() .. "TickNumber"]
    local milestoneTooltip = _G[milestoneFrame:GetName() .. "Tooltip"]
    local milestoneTooltipText1 = _G[milestoneFrame:GetName() .. "TooltipText1"]
    local milestoneTooltipText2 = _G[milestoneFrame:GetName() .. "TooltipText2"]

    if minValue == nil or maxValue == nil then
        statusBarChunk:Hide()
        milestoneFrame:Hide()
        return
    else
        statusBarChunk:Show()
        milestoneFrame:Show()
    end

    statusBarChunk:SetMinMaxValues(minValue, maxValue)
    statusBarChunk:SetWidth((maxValue - minValue) * (GrandMarshalProgressBar:GetWidth() - 10) / maxHonor)
    if currentHonor > maxValue then
        statusBarChunk:SetValue(maxValue)
        statusBarChunk:SetStatusBarColor(0, .45, .9)
        statusBarChunk:SetScript("OnEnter", nil)
        milestoneTickNumber:Hide()
    else
        statusBarChunk:SetValue(currentHonor)
        statusBarChunk:SetStatusBarColor(1, 0, 0)
        if currentHonor > minValue then
            -- Show remaining honor number to the left of tick
            milestoneTickNumber:Show()
            milestoneTickNumber:SetText(currentHonor - maxValue)

            statusBarChunk:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                GameTooltip:AddLine(WASTED_HONOR)
                GameTooltip:Show()
            end)
        else
            milestoneTickNumber:Hide()
            statusBarChunk:SetScript("OnEnter", nil)
        end
    end

    milestoneTick:SetPoint("CENTER", statusBarChunk, "RIGHT", 0, 0)

    milestoneTick:SetScript("OnEnter", function(self)
        milestoneTooltipText1:SetText(maxValue .. " Honor")
        milestoneTooltipText2:SetText("Reaching this milestone will grant:" .. "\n"
            .. "Rank " .. floor(tonumber(rankVal)) .. " and " .. string.format("%.2f", tonumber(rankVal) % 1 * 100) .. "%")
        milestoneTooltip:Show()
    end)
end

---- Update chunks
---@param currentHonor integer
---@param milestone1 Milestone
---@param milestone2 Milestone
---@param milestone3 Milestone
---@param milestone4 Milestone
local function updateChunks(currentHonor, milestone1, milestone2, milestone3, milestone4)
    local milestones = { milestone1, milestone2, milestone3, milestone4 }

    -- Remove all milestones after the SoD rank limit (if enabled)
    if sod_server and Settings.GRAND_MARSHAL_SOD_RANK_LIMIT:GetValue() then
        local limit_reached = false

        for _, milestone in ipairs(milestones) do
            if not Milestone:is_nil(milestone) and milestone.rank >= SOD_MAX_RANK then
                if limit_reached then
                    milestone.rank = nil
                else
                    milestone.rank = SOD_MAX_RANK
                    limit_reached = true
                end
            end
        end
    end

    local maxHonor = 1
    if not Milestone:is_nil(milestone4) then
        maxHonor = milestone4.honor
    elseif not Milestone:is_nil(milestone3) then
        maxHonor = milestone3.honor
    elseif not Milestone:is_nil(milestone2) then
        maxHonor = milestone2.honor
    else
        maxHonor = milestone1.honor
    end

    if not Milestone:is_nil(milestone1) and milestone1.honor ~= 0 then
        updateChunk(GrandMarshalProgressBarChunk1, Milestone1, 0, milestone1.honor, currentHonor, maxHonor, milestone1.rankText, milestone1.rank)
    else
        -- Setting the width to 0 causes later chunks to not render
        GrandMarshalProgressBarChunk1:SetWidth(.01)
        GrandMarshalProgressBarChunk1:Hide()
        Milestone1:Hide()
    end

    if not Milestone:is_nil(milestone1) and not Milestone:is_nil(milestone2) then
        updateChunk(GrandMarshalProgressBarChunk2, Milestone2, milestone1.honor, milestone2.honor, currentHonor, maxHonor, milestone2.rankText, milestone2.rank)
    else
        GrandMarshalProgressBarChunk2:SetWidth(0)
    end

    if not Milestone:is_nil(milestone2) and not Milestone:is_nil(milestone3) then
        updateChunk(GrandMarshalProgressBarChunk3, Milestone3, milestone2.honor, milestone3.honor, currentHonor, maxHonor, milestone3.rankText, milestone3.rank)
    else
        GrandMarshalProgressBarChunk3:SetWidth(0)
    end

    if not Milestone:is_nil(milestone3) and not Milestone:is_nil(milestone4) then
        updateChunk(GrandMarshalProgressBarChunk4, Milestone4, milestone3.honor, milestone4.honor, currentHonor, maxHonor, milestone4.rankText, milestone4.rank)
    else
        GrandMarshalProgressBarChunk4:SetWidth(0)
    end

    if currentHonor > maxHonor then
        GrandMarshalProgressBarChunk1:SetStatusBarColor(0, 1, 0)
        GrandMarshalProgressBarChunk2:SetStatusBarColor(0, 1, 0)
        GrandMarshalProgressBarChunk3:SetStatusBarColor(0, 1, 0)
        GrandMarshalProgressBarChunk4:SetStatusBarColor(0, 1, 0)
    end
end

function UpdateProgressBar()
    DebugPrint("UpdateProgressBar")
    local rank = UnitPVPRank("Player") - 4
    local _, honor = GetPVPThisWeekStats()
    local progress = GetPVPRankProgress()

    if GrandMarshalDebugFrame:IsShown() then
        rank = tonumber(GrandMarshalDebugFrameRankEditBox:GetText())
        honor = tonumber(GrandMarshalDebugFrameHonorEditBox:GetText())
        progress = tonumber(GrandMarshalDebugFramePercentEditBox:GetText()) * .01
    end

    if (rank < 1) then
        rank = 1
    end

    local expectedRank = rank + 4

    if expectedRank > 14 then
        expectedRank = 14
    end

    local milestone1 = Milestone:new(rank, progress, rank)
    --Milestone:DebugPrint(milestone1)

    local milestone2 = Milestone:new(rank, progress, rank + 2)
    --Milestone:DebugPrint(milestone2)

    local milestone3 = Milestone:new(rank, progress, rank + 3)
    --Milestone:DebugPrint(milestone3)

    local milestone4 = Milestone:new(rank, progress, rank + 4)
    --Milestone:DebugPrint(milestone4)

    updateChunks(honor, milestone1, milestone2, milestone3, milestone4)
end

function UpdateCurrentRank()
    DebugPrint("UpdateCurrentRank")
    local rank = UnitPVPRank("player") - 4
    local progress = GetPVPRankProgress()

    if GrandMarshalDebugFrame:IsShown() then
        rank = tonumber(GrandMarshalDebugFrameRankEditBox:GetText())
        progress = tonumber(GrandMarshalDebugFramePercentEditBox:GetText()) * .01
    end

    local rankName, rankNum = GetPVPRankInfo(rank + 4)

    if rankName == nil then
        rankName = "Unranked"
        CurrentRankPaneRankIcon:SetTexture("Interface\\PVPFrame\\PVP-Currency-Alliance")
    else
        CurrentRankPaneRankIcon:SetTexture(format("%s%02d", "Interface\\PvPRankBadges\\PvPRank", floor(rank)));
    end

    CurrentRankPaneRankText:SetText(rankName)
    CurrentRankPaneRankTitleText:SetText("Current Rank:")
    CurrentRankPaneRankSubText:SetText("Rank " ..
        rankNum .. " and " .. tonumber(string.format("%.2f", progress * 100)) .. "%")
end

local persistent_next_rank = nil

function UpdateNextRank()
    DebugPrint("UpdateNextRank")
    local rank = UnitPVPRank("player") - 4
    local progress = GetPVPRankProgress()
    local hks, honor = GetPVPThisWeekStats()

    if GrandMarshalDebugFrame:IsShown() then
        rank = tonumber(GrandMarshalDebugFrameRankEditBox:GetText())
        progress = tonumber(GrandMarshalDebugFramePercentEditBox:GetText()) * .01
        honor = tonumber(GrandMarshalDebugFrameHonorEditBox:GetText())
        hks = tonumber(GrandMarshalDebugFrameHKsEditBox:GetText())
    end

    local nextRank = GetNextRank(honor, rank, progress)

    -- Limit the rank to the SoD limit if playing SoD
    local use_sod_limit = sod_server and Settings.GRAND_MARSHAL_SOD_RANK_LIMIT:GetValue()
    if use_sod_limit and nextRank > SOD_MAX_RANK then
        nextRank = SOD_MAX_RANK
    end

    if rank == 14 or (use_sod_limit and rank >= SOD_MAX_RANK) then
        NextRankPaneRankTitleText:Hide()
        NextRankPaneRankText:SetText(nil)
        NextRankPaneRankSubText:SetText(nil)
        NextRankPaneRankIcon:SetTexture(nil)
        NextRankPaneHKWarningText:Hide()
        NextRankPaneMissionComplete:Show()
        GrandMarshalProgressBar:Hide()
        -- Show a warning if the player would rank up if they had 15 HKs
    elseif (rank + progress) ~= nextRank and hks < 15 then
        NextRankPaneRankText:SetText(nil)
        NextRankPaneRankSubText:SetText(nil)
        NextRankPaneRankIcon:SetTexture(nil)
        NextRankPaneHKWarningText:Show()
    else
        if NextRankPaneMissionComplete:IsShown() then
            NextRankPaneRankTitleText:Show()
            NextRankPaneMissionComplete:Hide()
        end

        if not GrandMarshalProgressBar:IsShown() then
            GrandMarshalProgressBar:Show()
        end

        local rankName, rankNum = GetPVPRankInfo(nextRank + 4)
        NextRankPaneRankText:SetText(rankName)
        NextRankPaneHKWarningText:Hide()
        NextRankPaneRankSubText:SetText("Rank " ..
            rankNum .. " and " .. tonumber(string.format("%.2f", (nextRank % 1) * 100)) .. "%")

        NextRankPaneRankIcon:SetTexture(format("%s%02d", "Interface\\PvPRankBadges\\PvPRank", floor(nextRank)));

        if persistent_next_rank ~= nextRank then
            if persistent_next_rank ~= nil then
                -- Print message on rank up if enabled
                if Settings.GRAND_MARSHAL_RANK_MSG_ENABLED:GetValue() then
                    print(rankUpTextColor:WrapTextInColorCode(
                        "Congratulations " .. rankName .. "! After the reset you will be rank " ..
                        rankNum .. " and " .. tonumber(string.format("%.2f", (nextRank % 1) * 100)) .. "%")
                    )
                end
                -- Play sound on rank up if enabled
                if Settings.GRAND_MARSHAL_RANK_SOUND_ENABLED:GetValue() then
                    PlaySound(Settings.GRAND_MARSHAL_RANK_SOUND_OPTION:GetValue(), "Master")
                end
            end

            persistent_next_rank = nextRank
        end
    end
end

local function GetNextReset()
    DebugPrint("GetNextReset")
    local currentTime = GetServerTime()
    -- Number of resets since epoch
    local d = floor((currentTime - 486000) / 604800)
    -- Next reset (UNIX time)
    local nextReset = (d + 1) * 604800 + 486000

    return {
        days = floor((nextReset - currentTime) / (24 * 60 * 60)),
        hours = floor((nextReset - currentTime) / (60 * 60)) % 24,
        mins = floor((nextReset - currentTime) / 60) % 60,
        secs = (nextReset - currentTime) % 60
    }
end

local function UpdateStats(updateAll)
    DebugPrint("UpdateStats")

    -- Today's stats
    local todayHKs, todayDKs = GetPVPSessionStats()
    --FullStatsPaneHonorTodayValue:SetText()
    FullStatsPaneHKTodayValue:SetText(todayHKs)
    FullStatsPaneDKTodayValue:SetText(todayDKs)

    -- Yesterday's stats
    if (updateAll) then
        local yesterdayHKs, yesterdayDKs, yesterdayHonor = GetPVPYesterdayStats()
        --FullStatsPaneHonorYesterdayValue:SetText(yesterdayHonor)
        FullStatsPaneHKYesterdayValue:SetText(yesterdayHKs)
        FullStatsPaneDKYesterdayValue:SetText(yesterdayDKs)
    end

    -- This week's stats
    local thisWeekHKs, thisWeekHonor = GetPVPThisWeekStats()
    FullStatsPaneHonorThisweekValue:SetText(thisWeekHonor)
    FullStatsPaneHKThisweekValue:SetText(thisWeekHKs)
    --FullStatsPaneDKThisweekValue:SetText()

    -- Last week's stats
    if (updateAll) then
        local lastWeekHKs, lastWeekDKs, lastWeekHonor = GetPVPLastWeekStats()
        FullStatsPaneHonorLastweekValue:SetText(lastWeekHonor)
        FullStatsPaneHKLastweekValue:SetText(lastWeekHKs)
        FullStatsPaneDKLastweekValue:SetText(lastWeekDKs)
    end

    -- Lifetime stats
    local lifetimeHKs, lifetimeDKs = GetPVPLifetimeStats()
    --FullStatsPaneHonorLifetimeValue:SetText()
    FullStatsPaneHKLifetimeValue:SetText(lifetimeHKs)
    FullStatsPaneDKLifetimeValue:SetText(lifetimeDKs)

    local yellow = { FullStatsPaneHonorYesterdayValue, FullStatsPaneHonorThisweekValue, FullStatsPaneHonorLastweekValue, FullStatsPaneHKTodayValue,
        FullStatsPaneHKYesterdayValue, FullStatsPaneHKThisweekValue, FullStatsPaneHKLastweekValue, FullStatsPaneHKLifetimeValue }

    local red = { FullStatsPaneDKTodayValue, FullStatsPaneDKYesterdayValue, FullStatsPaneDKLastweekValue, FullStatsPaneDKLifetimeValue }

    -- Set honor and HK values to yellow if 0, otherwise green
    for i, v in ipairs(yellow) do
        if v:GetText() == "0" then
            v:SetTextColor(1.0, 0.82, 0)
        else
            v:SetTextColor(0.1, 1.0, 0.1)
        end
    end

    -- Set DK values to green if 0, otherwise red
    for i, v in ipairs(red) do
        if v:GetText() == "0" then
            v:SetTextColor(0.1, 1.0, 0.1)
        else
            v:SetTextColor(1.0, 0.1, 0.1)
        end
    end
end

local function GrandMarshalFrame_SetLevel()
    DebugPrint("GrandMarshalFrame_SetLevel")
    GrandMarshalLevelText:SetFormattedText(PLAYER_LEVEL, UnitLevel("player"), UnitRace("player"), UnitClass("player"));
end

local function GrandMarshalFrame_SetGuild()
    DebugPrint("GrandMarshalFrame_SetGuild")
    local guildName;
    local rank;
    guildName, title, rank = GetGuildInfo("player");
    if (guildName) then
        GrandMarshalGuildText:Show();
        GrandMarshalGuildText:SetFormattedText(GUILD_TITLE_TEMPLATE, title, guildName);
    else
        GrandMarshalGuildText:Hide();
    end
end

-- ╔════════════════════════╗
-- ║ Frame Script Functions ║
-- ╚════════════════════════╝

function GrandMarshal_GrandMarshalFrameOnShow(self, event, arg1)
    --GrandMarshalFrame_SetLevel()
    --GrandMarshalFrame_SetGuild()
    UpdateProgressBar()
    UpdateStats()
    UpdateCurrentRank()
    UpdateNextRank()
end

function GrandMarshal_GrandMarshalFrameOnEvent(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "GrandMarshal" then
            if RankMsgEnabled == nil then
                RankMsgEnabled = Settings.GRAND_MARSHAL_RANK_MSG_ENABLED:GetDefaultValue()
            end
            if RankSoundEnabled == nil then
                RankSoundEnabled = Settings.GRAND_MARSHAL_RANK_SOUND_ENABLED:GetDefaultValue()
            end
            if RankSoundOption == nil then
                RankSoundOption = Settings.GRAND_MARSHAL_RANK_SOUND_OPTION:GetDefaultValue()
            end
            if SodRankLimit == nil then
                SodRankLimit = Settings.GRAND_MARSHAL_SOD_RANK_LIMIT:GetDefaultValue()
            end
            if DebugEnabled == nil then
                RankMsgEnabled = Settings.GRAND_MARSHAL_DEBUGGING:GetDefaultValue()
            end
            Settings.GRAND_MARSHAL_RANK_MSG_ENABLED:SetValue(RankMsgEnabled)
            Settings.GRAND_MARSHAL_RANK_SOUND_ENABLED:SetValue(RankSoundEnabled)
            Settings.GRAND_MARSHAL_RANK_SOUND_OPTION:SetValue(RankSoundOption)
            Settings.GRAND_MARSHAL_SOD_RANK_LIMIT:SetValue(SodRankLimit)
            Settings.GRAND_MARSHAL_DEBUGGING:SetValue(DebugEnabled)
            play_rank_sound_when_setting = true
        end
    elseif event == "PLAYER_LOGOUT" then
        -- Save the value on logout
        RankMsgEnabled = Settings.GRAND_MARSHAL_RANK_MSG_ENABLED:GetValue()
        RankSoundEnabled = Settings.GRAND_MARSHAL_RANK_SOUND_ENABLED:GetValue()
        RankSoundOption = Settings.GRAND_MARSHAL_RANK_SOUND_OPTION:GetValue()
        SodRankLimit = Settings.GRAND_MARSHAL_SOD_RANK_LIMIT:GetValue()
        DebugEnabled = Settings.GRAND_MARSHAL_DEBUGGING:GetValue()
    elseif event == "UNIT_LEVEL" then
        GrandMarshalFrame_SetLevel()
    elseif event == "PLAYER_GUILD_UPDATE" then
        GrandMarshalFrame_SetGuild()
    elseif event == "PLAYER_ENTERING_WORLD" then
        GrandMarshalFrame_SetGuild()
        GrandMarshalFrame_SetLevel()
        UpdateStats(true)
    elseif event == "PLAYER_PVP_KILLS_CHANGED" then
        UpdateProgressBar()
        UpdateStats()
        UpdateNextRank()
    elseif event == "PLAYER_PVP_RANK_CHANGED" then
        self:GetScript("OnShow")()
    else
        DebugPrint(event)
        --self:GetScript("OnShow")()
        -- Update the progress bar on PLAYER_ENTERING_WORLD, rank info can be wrong if read too early
    end
end

function GrandMarshal_NextResetPaneOnUpdate(self, elapsed)
    self.TimeSinceLastUpdate = self.TimeSinceLastUpdate + elapsed
    if self.TimeSinceLastUpdate > UPDATE_INTERVAL then
        local d = GetNextReset()
        local dayStr = d["days"] .. " day" .. (d["days"] == 1 and "" or "s")
        local hourStr = d["hours"] .. " hour" .. (d["hours"] == 1 and "" or "s")
        local minStr = d["mins"] .. " min" .. (d["mins"] == 1 and "" or "s")
        local secStr = d["secs"] .. " sec" .. (d["secs"] == 1 and "" or "s")

        NextResetCountdownText:SetText(dayStr .. ", " .. hourStr .. ", " .. minStr .. ", " .. secStr)
        self.TimeSinceLastUpdate = 0
    end
end

StaticPopupDialogs["GrandMarshalExportDialog"] = {
    text = "Copy the link below to share your progress:",
    button1 = "Close",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3, -- avoid some UI taint, see http://www.wowace.com/announcements/how-to-avoid-some-ui-taint/
    OnLoad = function(self)
        self.editBox:SetAutoFocus(true);
    end,
    hasEditBox = true
}

function ShowGrandMarshalExportDialog()
    local dialog   = StaticPopup_Show("GrandMarshalExportDialog")
    local rank     = UnitPVPRank("Player") - 4
    local progress = GetPVPRankProgress()
    local _, honor = GetPVPThisWeekStats()
    local level    = UnitLevel("Player")

    dialog.editBox:SetText("https://soffe.github.io/ClassicEraHonorCalculator/calculator/" ..
        tostring(rank) .. "/" .. tostring(progress) .. "/" .. tostring(honor) .. "/" .. tostring(level) .. "")
    dialog.editBox:HighlightText()
end

-- ╔════════════════════════╗
-- ║ Settings Configuration ║
-- ╚════════════════════════╝

function GrandMarhshall_ConfigureSettings()
    -- Configure the settings categories
    local category, layout = Settings.RegisterVerticalLayoutCategory("Grand Marshal")
    Settings.GRAND_MARSHAL_CATEGORY = category
    local settingsCategory, settingsLayout = Settings.RegisterVerticalLayoutSubcategory(category, "Settings")
    Settings.GRAND_MARSHAL_SETTINGS_CATEGORY = settingsCategory

    -- Add the help frames
    do
        local data = { settings = nil };
        local initializer = Settings.CreatePanelInitializer("GrandMarshalHelpOverviewTemplate", data);
        layout:AddInitializer(initializer);
        initializer = Settings.CreatePanelInitializer("GrandMarshalHelpProgressBarTemplate", data);
        layout:AddInitializer(initializer);
        initializer = Settings.CreatePanelInitializer("GrandMarshalHelpFaqTemplate", data);
        layout:AddInitializer(initializer);
    end

    -- Add the rank message setting
    do
        local variable = "rankmessage"
        local defaultValue = true
        Settings.GRAND_MARSHAL_RANK_MSG_ENABLED = Settings.RegisterAddOnSetting(settingsCategory, "Print message on rank up", variable, type(defaultValue),
            defaultValue)
        Settings.CreateCheckBox(settingsCategory, Settings.GRAND_MARSHAL_RANK_MSG_ENABLED,
            "Prints a message to the chat window when you reach a new rank milestone")
    end

    -- Add the rank up sound setting
    do
        local variable = "playsound"
        local variable2 = "soundtoplay"
        Settings.GRAND_MARSHAL_RANK_SOUND_ENABLED = Settings.RegisterAddOnSetting(settingsCategory, "Play Sound", variable, Settings.VarType.Boolean, false);
        Settings.GRAND_MARSHAL_RANK_SOUND_OPTION = Settings.RegisterAddOnSetting(settingsCategory, "Sound to play", variable2, Settings.VarType.Number,
            SOUNDKIT.HARDCORE_DUEL);

        local function GetOptionData(options)
            local container = Settings.CreateControlTextContainer();
            container:Add(SOUNDKIT.HARDCORE_DUEL, "Mak'gora", "The sound that plays when a hardcore duel is initiated");
            container:Add(SOUNDKIT.READY_CHECK, "Ready Check", "The sound that plays when a ready check is started");
            container:Add(SOUNDKIT.PVP_THROUGH_QUEUE, "PvP Queue Ready", "The sound that plays when a battleground queue pops");
            container:Add(SOUNDKIT.MURLOC_AGGRO, "Murloc", "RWLRWLRWLRWL");
            return container:GetData();
        end

        local function SoundFileSettingChanged(_, _, value)
            if play_rank_sound_when_setting then
                PlaySound(value, "Master")
            end
        end

        local function SoundEnabledSettingChanged(_, _, value)
            if play_rank_sound_when_setting and value then
                PlaySound(Settings.GRAND_MARSHAL_RANK_SOUND_OPTION:GetValue(), "Master")
            end
        end

        Settings.SetOnValueChangedCallback(variable, SoundEnabledSettingChanged)
        Settings.SetOnValueChangedCallback(variable2, SoundFileSettingChanged)

        local initializer = CreateSettingsCheckBoxDropDownInitializer(
            Settings.GRAND_MARSHAL_RANK_SOUND_ENABLED, "Play sound on rank up", "Plays a sound when you reach a new rank milestone",
            Settings.GRAND_MARSHAL_RANK_SOUND_OPTION, GetOptionData, "Sound to play on rank up", nil);
        settingsLayout:AddInitializer(initializer);
    end

    -- Add the SoD rank limit setting
    do
        local variable = "sodranklimit"
        local defaultValue = true
        Settings.GRAND_MARSHAL_SOD_RANK_LIMIT = Settings.RegisterAddOnSetting(settingsCategory, "Enable SoD Rank Limit", variable, type(defaultValue),
            defaultValue)
        Settings.CreateCheckBox(settingsCategory, Settings.GRAND_MARSHAL_SOD_RANK_LIMIT,
            "Limits the maximum possible rank for Season of Discovery servers to rank " .. tostring(SOD_MAX_RANK))
    end

    -- Add the debug setting
    do
        local function DebugSettingChanged(_, _, value)
            if value then
                GrandMarshalDebugFrame:Show()
            else
                GrandMarshalDebugFrame:Hide()
            end
        end

        local variable = "debug"
        local defaultValue = false
        Settings.GRAND_MARSHAL_DEBUGGING = Settings.RegisterAddOnSetting(settingsCategory, "Enable Debugging", variable, type(defaultValue), defaultValue)
        Settings.CreateCheckBox(settingsCategory, Settings.GRAND_MARSHAL_DEBUGGING, "Enables debugging, intended for developers only")
        Settings.SetOnValueChangedCallback(variable, DebugSettingChanged)
    end

    Settings.RegisterAddOnCategory(category)
end
