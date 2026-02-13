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

---On unit finished, unit destroyed or unit gifted, track resource cost over the past 450 gameframes.
---Decide if the unit is Army, Defense or Eco (use spect hub definitions).
---For each player, track: cumalitive of each of the above (other widget can handle differences).
---format the same as the stats from engine: [snapShotNumber][teamID][Stat]
---need a function that accepts TeamID and 2 or more required snapshots numbers.
---on only team id, it should return highest snapShotNumber, if all three arguments it should return the stats.
---Fun things to track: First T2 + time, first T3 + time, most common unit, most resource spent on unit (not buildings), llt spammer, com sniper, no. winds or t1 solar.
---
---Table to track certain counts of units. name[teamID][unitdefID] = {count, resourceValue}

local gaiaID
local teamAllyTeamIDs = {}
local teamIDSorted = {}
local MasterStatTable = {}
local caterogies = {"armyValue","defenseValue", "utilityValue","economyValue","everything"}
local temporaryStatTable = {}
local unitDefsToTrack = {}
local snapShotNumber = 1
local spectator, fullview

local firstsWinnersList = {}
local firstsCategoryList = {["T2Army"] = false, ["T3Army"] = false, ["T2Factory"]=false, ["T2Constructor"] = false}
local trackedFunStats = {}


local function CacheTeams() -- get all the teamID / Ally Team ID captains and colours once, and cache.
    for _, allyTeamID in ipairs(Spring.GetAllyTeamList()) do
        for _, teamID in ipairs(Spring.GetTeamList(allyTeamID)) do
            if Spring.GetGaiaTeamID() ~= teamID then
                table.insert(teamIDSorted,teamID)
                teamAllyTeamIDs[teamID] = allyTeamID
                trackedFunStats[teamID] = {}
            else
                gaiaID = teamID
            end

        end
    end
    
end

local function AddValuesToMasterStatsTable (key)
    if not MasterStatTable[key] then
        MasterStatTable[key] = {}
        for _, category in ipairs(caterogies) do
            for k,teamID in ipairs (teamIDSorted) do
                if not MasterStatTable[key][teamID] then
                    MasterStatTable[key][teamID] = {}
                    if MasterStatTable[key-1] then
                        MasterStatTable[key][teamID][category] = MasterStatTable[key-1][teamID][category] + temporaryStatTable[teamID][category]--xxx reaplce with the number
                    else
                        MasterStatTable[key][teamID][category] = temporaryStatTable[teamID][category]
                    end
                else
                    if MasterStatTable[key-1] then
                        MasterStatTable[key][teamID][category] = MasterStatTable[key-1][teamID][category] + temporaryStatTable[teamID][category]
                    else
                        MasterStatTable[key][teamID][category] = temporaryStatTable[teamID][category]
                    end
                end
            end
        end
    end
end

local function StatTracking(teamID, unitDefID, value)
    if teamID == gaiaTeamId then
        return
    end
    local tempCategory = {}
    for caterogy, bool in pairs (firstsCategoryList) do
        if not bool then
           if unitDefsToTrack[caterogy][unitDefID] == true then
                firstsWinnersList[caterogy] = {teamID, Spring.GetGameFrame()}
                tempCategory[caterogy] = true
           end
        end
    end

    for caterogy, bool in pairs (tempCategory) do
        firstsCategoryList[caterogy] = true
    end

    if not trackedFunStats[teamID][unitDefID] then
        trackedFunStats[teamID][unitDefID] = {1,value}
    else
        trackedFunStats[teamID][unitDefID][1] = trackedFunStats[teamID][unitDefID][1] + 1
        trackedFunStats[teamID][unitDefID][2] = trackedFunStats[teamID][unitDefID][2] + value 
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
        -- anything with a least one weapon and speed above zero is considered an army unit
        return unitDef.weapons and (#unitDef.weapons > 0) and unitDef.speed and (unitDef.speed > 0)
    end

    local function isDefenseUnit(unitDefID, unitDef)
        return unitDef.weapons and (#unitDef.weapons > 0) and (not unitDef.speed or (unitDef.speed == 0))
    end

    local function isUtilityUnit(unitDefID, unitDef)
        return unitDef.customParams.unitgroup == 'util'
    end

    local function isEconomyBuilding(unitDefID, unitDef)
        return (unitDef.customParams.unitgroup == 'metal') or (unitDef.customParams.unitgroup == 'energy') or unitDef.isFactory
    end
    
    local function isT2Army(unitDefIF,unitDef)
        return unitDef.customParams.techlevel == "2" and unitDef.weapons and (#unitDef.weapons > 0) and unitDef.speed and (unitDef.speed > 0)
    end

    local function isT3Army(unitDefIF,unitDef)
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

    
    --main caterogies
    unitDefsToTrack = {}
    unitDefsToTrack.commanderUnitDefs = {}
    unitDefsToTrack.reclaimerUnitDefs = {}
    unitDefsToTrack.energyConverterDefs = {}
    unitDefsToTrack.buildPowerDefs = {}
    unitDefsToTrack.armyUnitDefs = {}
    unitDefsToTrack.defenseUnitDefs = {}
    unitDefsToTrack.utilityUnitDefs = {}
    unitDefsToTrack.economyBuildingDefs = {}
    --fun track caterogies
    --unitDefsToTrack.T1Spam = {}
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
        if isT2Army(unitDefID, unitDef) then
            unitDefsToTrack.T2Army[unitDefID] = unitDef.translatedHumanName
        end

        if isT3Army(unitDefID, unitDef) then
            unitDefsToTrack.T3Army[unitDefID] = unitDef.translatedHumanName
        end
        if isT2Factory(unitDefID, unitDef) then
            unitDefsToTrack.T2Factory[unitDefID] = unitDef.translatedHumanName
        end
        if isT2Constructor(unitDefID, unitDef) then
            unitDefsToTrack.T2Constructor[unitDefID] = unitDef.translatedHumanName
        end
        if isWind(unitDefID, unitDef) then
            unitDefsToTrack.wind[unitDefID] = unitDef.translatedHumanName
        end
        if isLLT(unitDefID, unitDef) then
            unitDefsToTrack.llt[unitDefID] = unitDef.translatedHumanName
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
	if unitDefsToTrack.utilityUnitDefs[unitDefID] then
        return "utilityValue", unitDefsToTrack.utilityUnitDefs[unitDefID][1] --{name, value}
	end
	if unitDefsToTrack.economyBuildingDefs[unitDefID] then
        return "economyValue", unitDefsToTrack.economyBuildingDefs[unitDefID][1] --{name, value}
	end
    return nil,nil
end

local function GetStatsFromHelper(teamID,firstSnapShot,lastSnapShot)
    return MasterStatTable[firstSnapShot][teamID],MasterStatTable[lastSnapShot][teamID]
end




local function ClearTemporyStatTable ()
    for _, category in ipairs(caterogies) do
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
    WG['saghelper'] = MasterStatTable
end

function widget:UnitFinished(unitID, unitDefID, teamID)
    local category, value = DetermineCategoryAndValue(unitDefID)
    --Spring.Echo("unit finished", teamID,category,value)
    if category then
        AddStatToTemporaryStatTable(teamID,category,value)
        StatTracking()
    else
        Spring.Echo("Debug - this unit isn't in any caterogies:", unitID, unitDefID, teamID )
    end

end

function widget:UnitDestroyed(unitID, unitDefID, teamID)
    if Spring.GetUnitIsBeingBuilt(unitID) then
        return
    end
    local category, value = DetermineCategoryAndValue(unitDefID)
    --Spring.Echo("unit finished", teamID,category,value)
    if category then
        AddStatToTemporaryStatTable(teamID,category,-value)
    end
end

function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
    if Spring.GetUnitIsBeingBuilt(unitID) then
        return
    end
    local category, value = DetermineCategoryAndValue(unitDefID)
        if category then
        AddStatToTemporaryStatTable(newTeam,category,value)
        AddStatToTemporaryStatTable(oldTeam,category,-value)
    end

end


local function Catchup()
    for _, unitID in ipairs(Spring.GetAllUnits()) do
        if Spring.GetUnitIsBeingBuilt(unitID) then
        else
            local unitDefID = Spring.GetUnitDefID(unitID)
            local teamID = Spring.GetUnitTeam(unitID)
            local category, value = DetermineCategoryAndValue(unitDefID)
            if teamID ~= Spring.GetGaiaTeamID and category then
                AddStatToTemporaryStatTable(teamID,category,value)
                StatTracking()
            else
                Spring.Echo("gaia or nil",teamID,unitID, UnitDefs[unitDefID].translatedHumanName, UnitDefs[unitDefID].name)
            end
        end
    end
end

function widget:Initialize()
    WG['saghelper'] = {}
    CacheTeams()
    ClearTemporyStatTable()
    spectator, fullview = Spring.GetSpectatingState()

    local n = Spring.GetGameFrame()
    snapShotNumber = math.floor((n /450))+1
    buildUnitDefs()
    Catchup()
    
end

function widget:TextCommand(command)
    if string.find(command, "bag",nil,true) then
        Spring.Echo("bag ran")
        Spring.Echo("trackedFunStats",trackedFunStats)

    end
end

function widget:GameFrame(n)
    if (n + 1) % 450 ==0 then --xxx this will skip the first frame to allow 
        snapShotNumber = ((n+1) /450)+1
        AddValuesToMasterStatsTable(snapShotNumber)
        ClearTemporyStatTable()
        RunSnapshotUpdate()
    end
end