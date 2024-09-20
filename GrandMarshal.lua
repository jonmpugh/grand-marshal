GrandMarhshal_ConfigureSettings()

local counter = 0
-- Hide all textures on the HonorFrame except the first 4, these are the background
for _, child in ipairs({ HonorFrame:GetRegions() }) do
    if child:GetObjectType() == "Texture" then
        if counter >= 4 then
            child:Hide()
        end
        counter = counter + 1
    end
end

HonorFrameCurrentHK:Hide()
HonorFrameCurrentDK:Hide()
HonorFrameYesterdayHK:Hide()
HonorFrameYesterdayContribution:Hide()
HonorFrameThisWeekHK:Hide()
HonorFrameThisWeekContribution:Hide()
HonorFrameLastWeekHK:Hide()
HonorFrameLastWeekContribution:Hide()
HonorFrameLifeTimeHK:Hide()
HonorFrameLifeTimeDK:Hide()
HonorFrameLifeTimeRank:Hide()
HonorFrameRankButton:Hide()

HonorFrameCurrentPVPTitle:Hide()
HonorFrameCurrentPVPRank:Hide()
HonorFrameCurrentSessionTitle:Hide()
HonorFrameYesterdayTitle:Hide()
HonorFrameThisWeekTitle:Hide()
HonorFrameLastWeekTitle:Hide()
HonorFrameLifeTimeTitle:Hide()
HonorFramePvPIcon:Hide()
-- HonorFrame will Show() this so set size to make it invisible
HonorFramePvPIcon:SetSize(.01, .01)