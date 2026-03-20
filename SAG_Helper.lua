function widget:GetInfo()
    return {
      name      = "SAG_Helper",
      desc      = "Supporting Stats for SAG",
      author    = "Mr_Chinny",
      date      = "Feb 2026",
      handler   = true,
      enabled   = true,
      layer = 0 
    }
end



---on only team id, it should return highest snapShotNumber, if all three arguments it should return the stats.
---Fun things to track: First T2 + time, first T3 + time, most common unit, most resource spent on unit (not buildings), llt spammer, com sniper, no. winds or t1 solar.
---
---

local sp_GetFeatureID = Spring.GetFeatureDefID
local uncategorisedUnits = {} --xxx remove, for debug only
local unclassifiedFeatureList= {} --xxx debug only
local knowntrees = VFS.Include("modelmaterials_gl4/known_feature_trees.lua")
local gaiaID
local teamAllyTeamIDs = {}
local teamIDSorted = {}
local MasterStatTable = {}
local categories = {"armyValue","defenseValue", "utilityValue","economyValue","everything"}
local temporaryStatTable = {}
local unitDefsToTrack = {}
local snapShotNumber = 1

local spectator, fullview = Spring.GetSpectatingState()
local myTeamID = Spring.GetMyTeamID()
local myAllyTeamID = Spring.GetMyAllyTeamID()
local playerRestricMode = false --zzz starts false

local firstsWinnersList = {}
local firstsCategoryNames = {
    "T2Factory",
    "T2Constructor",
    "T2Army",
    "T3Army",
}
local firstsCategoryList = {}
for _, name in ipairs(firstsCategoryNames) do
    firstsCategoryList[name] = false
end 
local rockTracker = {maxMetal = 0, maxEnergy = 0, metalDestroyed = 0, energyDestroyed = 0, maxNumber = 0, numberDestroyed =0}
local treeTracker = {maxMetal = 0, maxEnergy = 0, metalDestroyed = 0, energyDestroyed = 0, maxNumber = 0, numberDestroyed =0}
local funStatsNames = {["armyUnitDefs"]=true, ["defenseUnitDefs"]=true, ["T1Army"] = true, ["T1Def"] = true, ["T2Army"] = true, ["T2Def"] = true,["T3Army"] = true, ["T2Factory"]=true, ["T2Constructor"] = true, ["llt"] = true, ["wind"] = true}
local trackedFunStats = {}
local unfinishedSharedUnits = {}


local treeListID = {}
local rockList = {}
local rockListID = {}
local critterList = {}

local function CacheTeams() -- get all the teamID / Ally Team ID captains and colours once, and cache.
    myTeamID = Spring.GetMyTeamID()
	myAllyTeamID = Spring.GetMyAllyTeamID()
    playerRestricMode = false --zzz starts false
    for _, allyTeamID in ipairs(Spring.GetAllyTeamList()) do
        for _, teamID in ipairs(Spring.GetTeamList(allyTeamID)) do
            if Spring.GetGaiaTeamID() ~= teamID then
                table.insert(teamIDSorted,teamID)
                teamAllyTeamIDs[teamID] = allyTeamID
                trackedFunStats[teamID] = {}
                if myTeamID == teamID and spectator == false and fullview == false then
                    playerRestricMode = true
                end
            else
                gaiaID = teamID
            end
        end
    end
end

local function TreeCache()
    local treeList = {}

    for featureDefID , featureDef in pairs(FeatureDefs) do
        local featureName = featureDef.name
        if knowntrees[featureDef.name] then
            if featureDef.metal == 0 then
                treeList[featureDefID] = {metal = featureDef.metal, energy = featureDef.energy}
            elseif featureDef.metal > 0 and  featureDef.customParams.category ~="corpse" then
                Spring.Echo("metal = featureDef.metal, energy = featureDef.energy",featureDef.metal, featureDef.energy)
                rockList[featureDefID] = {metal = featureDef.metal, energy = featureDef.energy}
            end
        end
    end
    local featureDefID

    for _, featureID in pairs(Spring.GetFeaturesInRectangle(1,1,Game.mapSizeX,Game.mapSizeZ)) do
        featureDefID = sp_GetFeatureID(featureID)
        if rockList[featureDefID] then
            rockListID[featureID] = rockList[featureDefID]
            rockTracker.maxNumber = rockTracker.maxNumber + 1
            rockTracker.maxMetal = rockTracker.maxMetal + rockList[featureDefID].metal
            rockTracker.maxEnergy = rockTracker.maxEnergy + rockList[featureDefID].energy
        elseif treeList[featureDefID] then
            treeListID[featureID] = treeList[featureDefID]
            treeTracker.maxNumber = treeTracker.maxNumber + 1
            treeTracker.maxMetal = treeTracker.maxMetal + treeList[featureDefID].metal
            treeTracker.maxEnergy = treeTracker.maxEnergy + treeList[featureDefID].energy
        else
            unclassifiedFeatureList[featureDefID] = FeatureDefs[featureDefID].name
        end
    end
end

local function AddValuesToMasterStatsTable (time)
    if not MasterStatTable[time] then
        MasterStatTable[time] = {}
        for _, category in ipairs(categories) do
            for k,teamID in ipairs (teamIDSorted) do
                if not MasterStatTable[time][teamID] then
                    MasterStatTable[time][teamID] = {}
                    if MasterStatTable[time-1] then
                        MasterStatTable[time][teamID][category] = MasterStatTable[time-1][teamID][category] + temporaryStatTable[teamID][category]
                    else
                        MasterStatTable[time][teamID][category] = temporaryStatTable[teamID][category]
                    end
                else
                    if MasterStatTable[time-1] then
                        MasterStatTable[time][teamID][category] = MasterStatTable[time-1][teamID][category] + temporaryStatTable[teamID][category]
                    else
                        MasterStatTable[time][teamID][category] = temporaryStatTable[teamID][category]
                    end
                end
                if MasterStatTable[time][teamID][category] < 0 then
                    MasterStatTable[time][teamID][category] = 0
                end
            end
        end
    end
end

local function StatTracking(teamID, unitDefID, value, unitID, killed)
    if teamID == gaiaID then
        return
    end
    local tempCategory = {}
    for category, _ in pairs (funStatsNames) do
        if unitDefsToTrack[category][unitDefID] then
            if not trackedFunStats[teamID][category] then
                trackedFunStats[teamID][category] = {["numberMade"] = 1, ["valueMade"] = value, ["numberCurrent"] = 1, ["valueCurrent"] = value}
                local time = math.floor(Spring.GetGameFrame()/30)
                local min =  math.floor(time / 60)
                local sec =  math.floor(time % 60)
                local timeText = string.format("%d:%02d",min,sec).."s"
                local shared, newTeam, oldTeamID = false, nil,nil
                if unfinishedSharedUnits[unitID] then
                    oldTeamID = unfinishedSharedUnits[unitID][2]
                    shared = true
                end
                trackedFunStats[teamID][category]["timeText"] = timeText
                trackedFunStats[teamID][category]["time"] =time
                trackedFunStats[teamID][category]["shared"] = shared
                trackedFunStats[teamID][category]["oldTeamID"] = oldTeamID

                if firstsCategoryList[category] == false then --xxx check this, may return nil not false?
                    local time = math.floor(Spring.GetGameFrame()/30)
                    local min =  math.floor(time / 60)
                    local sec =  math.floor(time % 60)
                    local timeText = string.format("%d:%02d",min,sec).."s"
                    firstsWinnersList[category] = {["teamID"] = teamID, ["timeText"] = timeText, ["unitName"] = unitDefsToTrack[category][unitDefID][2],["timeSeconds"] = time,["shared"] = shared,["oldTeamID"] = oldTeamID }
                    Spring.Echo("winner", category,bool, firstsWinnersList[category])
                    tempCategory[category] = true
                end
            else
                if killed then
                    trackedFunStats[teamID][category].numberCurrent = math.max(trackedFunStats[teamID][category].numberCurrent - 1 , 0)
                    trackedFunStats[teamID][category].valueCurrent = math.max(trackedFunStats[teamID][category].valueCurrent - value, 0 )
                else
                    trackedFunStats[teamID][category].numberCurrent = trackedFunStats[teamID][category].numberCurrent + 1
                    trackedFunStats[teamID][category].valueCurrent = trackedFunStats[teamID][category].valueCurrent + value
                    trackedFunStats[teamID][category].numberMade = trackedFunStats[teamID][category].numberMade + 1
                    trackedFunStats[teamID][category].valueMade = trackedFunStats[teamID][category].valueMade + value
                end
            end
        end
    end

    for category, _ in pairs (tempCategory) do
        firstsCategoryList[category] = true
    end
    --this part tracks everything built by unitID, but don't want to waste resources ranking here so need to do in other widget.
    if not trackedFunStats[teamID][unitDefID] then
        trackedFunStats[teamID][unitDefID] = {["numberMade"] = 1, ["valueMade"] = value, ["numberCurrent"] = 1, ["valueCurrent"] = value}
    else
        if killed then
            trackedFunStats[teamID][unitDefID].numberCurrent = math.max(trackedFunStats[teamID][unitDefID].numberCurrent - 1, 0 )
            trackedFunStats[teamID][unitDefID].valueCurrent = math.max(trackedFunStats[teamID][unitDefID].valueCurrent - value, 0 )
        else
            trackedFunStats[teamID][unitDefID].numberCurrent = trackedFunStats[teamID][unitDefID].numberCurrent + 1
            trackedFunStats[teamID][unitDefID].valueCurrent = trackedFunStats[teamID][unitDefID].valueCurrent + value
            trackedFunStats[teamID][unitDefID].numberMade = trackedFunStats[teamID][unitDefID].numberMade + 1
            trackedFunStats[teamID][unitDefID].valueMade = trackedFunStats[teamID][unitDefID].valueMade + value
        end
    end

end

local function buildUnitDefs()
    local function isCommander(unitDefID, unitDef)
        return unitDef.customParams.iscommander
    end

    local function isReclaimerUnit(unitDefID, unitDef)
        return unitDef.isBuilder and not unitDef.isFactory
    end

    local function isEnergyConverter(unitDefID, unitDef)
        return unitDef.customParams.energyconv_capacity and unitDef.customParams.energyconv_efficiency
    end

    local function isBuildPower(unitDefID, unitDef)
        return unitDef.buildSpeed and (unitDef.buildSpeed > 0) and unitDef.canAssist
    end

    local function isArmyUnit(unitDefID, unitDef)
        -- anything with a least one weapon and speed above zero is considered an army unit, not commanders
        return unitDef.weapons and (#unitDef.weapons > 0) and unitDef.speed and (unitDef.speed > 0) and not unitDef.customParams.iscommander
    end

    local function isDefenseUnit(unitDefID, unitDef)
        return unitDef.weapons and (#unitDef.weapons > 0) and (not unitDef.speed or (unitDef.speed == 0))
    end

    local function isUtilityUnit(unitDefID, unitDef)
        return unitDef.customParams.unitgroup == 'util' or unitDef.transportSize 
    end

    local function isEconomyBuilding(unitDefID, unitDef)
        return (unitDef.customParams.unitgroup == 'metal') or (unitDef.customParams.unitgroup == 'energy') or unitDef.isFactory
    end

    local function isT1Def(unitDefID,unitDef)
        return unitDef.customParams.techlevel ~= "2" and unitDef.customParams.techlevel ~= "3" and unitDef.weapons and (#unitDef.weapons > 0) and (not unitDef.speed or (unitDef.speed == 0))
    end

    local function isT2Def(unitDefID,unitDef)
        return unitDef.customParams.techlevel == "2" and unitDef.weapons and (#unitDef.weapons > 0) and (not unitDef.speed or (unitDef.speed == 0))
    end

    local function isT1Army(unitDefID,unitDef)
        return unitDef.customParams.techlevel ~= "2" and unitDef.customParams.techlevel ~= "3" and unitDef.weapons and (#unitDef.weapons > 0) and unitDef.speed and (unitDef.speed > 0) and not unitDef.customParams.iscommander
    end

    local function isT2Army(unitDefID,unitDef)
        return unitDef.customParams.techlevel == "2" and unitDef.weapons and (#unitDef.weapons > 0) and unitDef.speed and (unitDef.speed > 0)
    end

    local function isT3Army(unitDefID,unitDef)
        return unitDef.customParams.techlevel == "3" and unitDef.weapons and (#unitDef.weapons > 0) and unitDef.speed and (unitDef.speed > 0)
    end

    local function isT2Factory(unitDefID, unitDef)
        return unitDef.isFactory and unitDef.customParams.techlevel == "2"
    end

    local function isT2Constructor(unitDefID, unitDef)
        return unitDef.isBuilder and not unitDef.isFactory and unitDef.customParams.techlevel == "2"
    end

    local function isWind(unitDefID, unitDef)
        return unitDef.windGenerator > 0
    end

    local function isLLT(unitDefID, unitDef)
        return  unitDef.name == "armllt" or unitDef.name == "corllt" or unitDef.name == "leglht"
    end

    
    --main categories
    unitDefsToTrack = {}
    unitDefsToTrack.commanderUnitDefs = {}
    unitDefsToTrack.reclaimerUnitDefs = {}
    unitDefsToTrack.energyConverterDefs = {}
    unitDefsToTrack.buildPowerDefs = {}
    unitDefsToTrack.armyUnitDefs = {}
    unitDefsToTrack.defenseUnitDefs = {}
    unitDefsToTrack.utilityUnitDefs = {}
    unitDefsToTrack.economyBuildingDefs = {}
    --fun track categories
    --unitDefsToTrack.T1Spam = {}
    unitDefsToTrack.T1Def = {}
    unitDefsToTrack.T2Def = {}
    unitDefsToTrack.T1Army = {}
    unitDefsToTrack.T2Army = {}
    unitDefsToTrack.T3Army = {}
    unitDefsToTrack.T2Factory = {}
    unitDefsToTrack.T2Constructor = {}
    unitDefsToTrack.wind = {}
    unitDefsToTrack.llt = {}

    for unitDefID, unitDef in ipairs(UnitDefs) do
        if isCommander(unitDefID, unitDef) then
            unitDefsToTrack.commanderUnitDefs[unitDefID] = {true,unitDef.name, unitDef.translatedHumanName }
        end
        if isReclaimerUnit(unitDefID, unitDef) then
            unitDefsToTrack.utilityUnitDefs[unitDefID] = {math.floor(unitDef.metalCost + (unitDef.energyCost / 70)),unitDef.metalMake, unitDef.energyMake,unitDef.name, unitDef.translatedHumanName }
        end
        
        if isEnergyConverter(unitDefID, unitDef) then
            unitDefsToTrack.energyConverterDefs[unitDefID] = {tonumber(unitDef.customParams.energyconv_capacity),unitDef.name, unitDef.translatedHumanName }
        end
        if isBuildPower(unitDefID, unitDef) then
            unitDefsToTrack.economyBuildingDefs[unitDefID] = {math.floor(unitDef.metalCost + (unitDef.energyCost / 70)), unitDef.metalCost, unitDef.energyCost, unitDef.name, unitDef.translatedHumanName }
        end
        if isArmyUnit(unitDefID, unitDef) then
            unitDefsToTrack.armyUnitDefs[unitDefID] = { math.floor(unitDef.metalCost + (unitDef.energyCost / 70)), unitDef.metalCost, unitDef.energyCost,unitDef.name, unitDef.translatedHumanName  }
        end
        if isDefenseUnit(unitDefID, unitDef) then
            unitDefsToTrack.defenseUnitDefs[unitDefID] = { math.floor(unitDef.metalCost + (unitDef.energyCost / 70)), unitDef.metalCost, unitDef.energyCost,unitDef.name, unitDef.translatedHumanName  }
        end
        if isUtilityUnit(unitDefID, unitDef) then
            unitDefsToTrack.utilityUnitDefs[unitDefID] = { math.floor(unitDef.metalCost + (unitDef.energyCost / 70)), unitDef.metalCost, unitDef.energyCost,unitDef.name, unitDef.translatedHumanName }
        end
        if isEconomyBuilding(unitDefID, unitDef) then
            unitDefsToTrack.economyBuildingDefs[unitDefID] = { math.floor(unitDef.metalCost + (unitDef.energyCost / 70)), unitDef.metalCost, unitDef.energyCost, unitDef.name, unitDef.translatedHumanName }
        end

        if isT1Def (unitDefID, unitDef) then
            unitDefsToTrack.T1Def[unitDefID] = {true, unitDef.translatedHumanName }
        end

        if isT2Def (unitDefID, unitDef) then
            unitDefsToTrack.T2Def[unitDefID] = {true, unitDef.translatedHumanName }
        end

        if isT1Army(unitDefID, unitDef) then
            unitDefsToTrack.T1Army[unitDefID] = {true, unitDef.translatedHumanName }
        end

        if isT2Army(unitDefID, unitDef) then
            unitDefsToTrack.T2Army[unitDefID] = {true, unitDef.translatedHumanName }
        end

        if isT3Army(unitDefID, unitDef) then
            unitDefsToTrack.T3Army[unitDefID] = {true, unitDef.translatedHumanName }
        end
        if isT2Factory(unitDefID, unitDef) then
            unitDefsToTrack.T2Factory[unitDefID] = {true, unitDef.translatedHumanName }
        end
        if isT2Constructor(unitDefID, unitDef) then
            unitDefsToTrack.T2Constructor[unitDefID] = {true, unitDef.translatedHumanName }
        end
        if isWind(unitDefID, unitDef) then
            unitDefsToTrack.wind[unitDefID] = {true, unitDef.translatedHumanName }
        end
        if isLLT(unitDefID, unitDef) then
            unitDefsToTrack.llt[unitDefID] = {true, unitDef.translatedHumanName }
        end


    end
end

local function DetermineCategoryAndValue(unitDefID) --note a unit cannot by in multiple categories, need to confirm each is in the most appropiate.
	if unitDefsToTrack.armyUnitDefs[unitDefID] then
        return "armyValue", unitDefsToTrack.armyUnitDefs[unitDefID][1] --{name, value}
	end
	if unitDefsToTrack.defenseUnitDefs[unitDefID] then
        return "defenseValue", unitDefsToTrack.defenseUnitDefs[unitDefID][1] --{name, value}
	end
	if unitDefsToTrack.economyBuildingDefs[unitDefID] then
        return "economyValue", unitDefsToTrack.economyBuildingDefs[unitDefID][1] --{name, value}
	end
    if unitDefsToTrack.utilityUnitDefs[unitDefID] then
        return "utilityValue", unitDefsToTrack.utilityUnitDefs[unitDefID][1] --{name, value}
	end
    return nil,nil
end

local function GetStatsFromHelper(teamID,firstSnapShot,lastSnapShot)
    return MasterStatTable[firstSnapShot][teamID],MasterStatTable[lastSnapShot][teamID]
end




local function ClearTemporyStatTable ()
    for _, category in ipairs(categories) do
        for key,teamID in ipairs(teamIDSorted) do
            if not temporaryStatTable[teamID] then
                temporaryStatTable[teamID] = {}
            end
            temporaryStatTable[teamID][category] =  0
        end
    end
end

local function AddStatToTemporaryStatTable(teamID,category,value)
    temporaryStatTable[teamID][category] = temporaryStatTable[teamID][category] + value
    temporaryStatTable[teamID]["everything"] = temporaryStatTable[teamID]["everything"] + value
end

local function RunSnapshotUpdate()
    WG['saghelper'].masterStatTable = MasterStatTable
    WG['saghelper'].trackedFunStats = trackedFunStats
    WG['saghelper'].firstsWinnersList = firstsWinnersList
    if treeTracker.maxNumber > 0 then
        WG['saghelper'].trees = {maxMetal = treeTracker.maxMetal, maxEnergy = treeTracker.maxEnergy, metalDestroyed = treeTracker.metalDestroyed, energyDestroyed = treeTracker.energyDestroyed, maxNumber = treeTracker.maxNumber, numberDestroyed =treeTracker.numberDestroyed}
    end
    if rockTracker.maxNumber > 0 then
        WG['saghelper'].rocks = {maxMetal = rockTracker.maxMetal, maxEnergy = rockTracker.maxEnergy, metalDestroyed = rockTracker.metalDestroyed, energyDestroyed = rockTracker.energyDestroyed, maxNumber = rockTracker.maxNumber, numberDestroyed =rockTracker.numberDestroyed}
    end
    if #critterList >0 then
        WG['saghelper'].critterList = critterList
    end
end

function widget:UnitFinished(unitID, unitDefID, teamID) --xxx need to check rez bots
    if playerRestricMode == false or (playerRestricMode == true and teamAllyTeamIDs[teamID] == myAllyTeamID) then
        if teamID ~= gaiaID then
            local category, value = DetermineCategoryAndValue(unitDefID)
            --Spring.Echo("unit finished", teamID,category,value)
            if category then
                AddStatToTemporaryStatTable(teamID,category,value)
                StatTracking(teamID,unitDefID,value,unitID,false)
                unfinishedSharedUnits[unitID] = nil
            else
                Spring.Echo("Debug - this unit isn't in any categories:", unitID, unitDefID, teamID, UnitDefs[unitDefID].translatedHumanName)
                uncategorisedUnits[unitDefID] = UnitDefs[unitDefID].translatedHumanName
            end
        else
            if string.find(UnitDefs[unitDefID].name,"critter_") then
                Spring.Echo("Critter found:",UnitDefs[unitDefID].name)
                critterList[#critterList+1] = {unitID=unitID,unitdDefID=unitDefID, name=UnitDefs[unitDefID].name}
            else
                Spring.Echo("Debug - this unit isn't in any categories gaia:", unitID, unitDefID, teamID, UnitDefs[unitDefID].translatedHumanName)
                uncategorisedUnits[unitDefID] = UnitDefs[unitDefID].translatedHumanName
            end
        end
    end
end

function widget:UnitDestroyed(unitID, unitDefID, teamID)
    if playerRestricMode == false or (playerRestricMode == true and teamAllyTeamIDs[teamID] == myAllyTeamID) then
        if Spring.GetUnitIsBeingBuilt(unitID) or teamID == gaiaID then
            return
        end
        local category, value = DetermineCategoryAndValue(unitDefID)
        --Spring.Echo("unit finished", teamID,category,value)
        if category then
            AddStatToTemporaryStatTable(teamID,category,-value)
            StatTracking(teamID,unitDefID,value, unitID, true)
        end
    end
end

function widget:UnitGiven(unitID, unitDefID, newTeamID, oldTeamID)
    if playerRestricMode == false or (playerRestricMode == true and teamAllyTeamIDs[oldTeamID] == myAllyTeamID) then
        if Spring.GetUnitIsBeingBuilt(unitID) then
            unfinishedSharedUnits[unitID] = {newTeamID,oldTeamID}
            return
        end
        if newTeamID >=0 and oldTeamID >= 0 then
            local category, value = DetermineCategoryAndValue(unitDefID)
            if category and newTeamID ~=gaiaID then
                AddStatToTemporaryStatTable(newTeamID,category,value)
            end
            if category and oldTeamID ~=gaiaID then
                AddStatToTemporaryStatTable(oldTeamID,category,-value)
            end
        end
    end
end


local function Catchup()
    for _, unitID in ipairs(Spring.GetAllUnits()) do
        if Spring.GetUnitIsBeingBuilt(unitID) then
        else
            local unitDefID = Spring.GetUnitDefID(unitID)
            local teamID = Spring.GetUnitTeam(unitID)
            local category, value = DetermineCategoryAndValue(unitDefID)
            if teamID ~= gaiaID and category then
                if playerRestricMode == false or (playerRestricMode == true and teamAllyTeamIDs[teamID] == myAllyTeamID) then
                    AddStatToTemporaryStatTable(teamID,category,value)
                    StatTracking(teamID,unitDefID,value,unitID,false)
                end
            else
                Spring.Echo("gaia or nil",teamID,unitID, UnitDefs[unitDefID].translatedHumanName, UnitDefs[unitDefID].name)
                if teamID == gaiaID and string.find(UnitDefs[unitDefID].name,"critter_") then
                    Spring.Echo("Citter found:",UnitDefs[unitDefID].name)
                    critterList[#critterList+1] = {unitID=unitID,unitdDefID=unitDefID, name=UnitDefs[unitDefID].name}
                end
            end
        end
    end
end

local function Init()
    CacheTeams()
    TreeCache()
    ClearTemporyStatTable()
    spectator, fullview = Spring.GetSpectatingState()
    local n = Spring.GetGameFrame()
    snapShotNumber = math.floor((n /450))+1
    buildUnitDefs()
    if n > 1 then --only needed if widget crashes/turned off
        Catchup()
    end
end

function widget:Initialize()
    WG['saghelper'] = {}
    Init()
end

function widget:TextCommand(command)
    if string.find(command, "bag",nil,true) then
        Spring.Echo("bag ran")
       -- Spring.Echo("unfinishedSharedUnits",unfinishedSharedUnits)
        Spring.Echo("uncategorisedUnits",uncategorisedUnits)
        for _, teamID in ipairs(teamIDSorted) do
            Spring.Echo(teamID,"MasterStatTable[time]",MasterStatTable[snapShotNumber-1][teamID]["economyValue"])
            Spring.Echo(teamID,"MasterStatTable[time]",MasterStatTable[snapShotNumber-1][teamID]["armyValue"])  
        end
        
        --Spring.Echo("unclassifiedFeatureList",unclassifiedFeatureList)
        --Spring.Echo("WG['saghelper'].trees",WG['saghelper'].trees)
    end
end

function widget:GameFrame(n)
    if n == 0 then
        Init()
    end
    if (n - 1) % 450 ==0 then --xxx this will skip the first frame to allow 
        snapShotNumber = ((n-1) /450)+1
        AddValuesToMasterStatsTable(snapShotNumber)
        ClearTemporyStatTable()
        RunSnapshotUpdate()
    end
end

function widget:FeatureDestroyed(featureID, allyTeamID)
    if treeListID[featureID] then
        treeTracker.numberDestroyed = treeTracker.numberDestroyed + 1
        treeTracker.metalDestroyed = treeTracker.metalDestroyed + treeListID[featureID].metal
        treeTracker.energyDestroyed = treeTracker.energyDestroyed + treeListID[featureID].energy
    elseif rockListID[featureID] then
        rockTracker.numberDestroyed = rockTracker.numberDestroyed + 1
        rockTracker.metalDestroyed = rockTracker.metalDestroyed + rockListID[featureID].metal
        rockTracker.energyDestroyed = rockTracker.energyDestroyed + rockListID[featureID].energy
    end
end