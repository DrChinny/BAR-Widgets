function widget:GetInfo()
    return {
      name      = "SAG",
      desc      = "Displaying Stacked Area Graphs",
      author    = "Mr_Chinny",
      date      = "March 2026",
      handler   = true,
      enabled   = true,
      layer = 1 --must load be later than the topbar, sag helper
    }
end


---Things to do---
---xxx if free for all, or too many players, adjust accordingly
---xxx anonymousMode mode
---other inetersting stats. ping, pingspam, messages, most t1, most metal spent on unit type? highest point a unit is, wind direction?
---Shader for efficency.
---Commander Deaths/rez
---Disable data gathering if not spec/fullview, enlable on game over
---similar I need to be able to have human or translateable names for all titles, these can be in the same list as above.
---xxx bug - doesn't work right with AI players on init, perhaps need to do some things on frame 1 to ensure everything is loaded.
---copy gui_teamstats.lua viewresize to auto resize boarders etc
---xxx add totals per team for the extra stats, need to only do this for 2 ally teams.

---known big bugs --- 
---deforestion / rocks not counting correctly, and seems to only remove 1/2. some rocks not in correct category.
---graph timer count in details is off.
---APM and FPS stops working after squish factor

---Speedups---
local floor, ceil = math.floor, math.ceil
local insert = table.insert
local gl_CreateList             = gl.CreateList
local gl_DeleteList             = gl.DeleteList
local gl_CallList               = gl.CallList
local glVertex                  = gl.Vertex
local glBeginEnd                = gl.BeginEnd
local glColor                   = gl.Color
local glLineWidth               = gl.LineWidth
local GL_QUADS                  = GL.QUADS
local spGetTeamColor            = Spring.GetTeamColor
local playSounds = true
local sounds = {buttonclick = 'LuaUI/Sounds/buildbar_waypoint.wav', duck = 'Sounds/critters/duckcall1.wav'}


---FlowUI---
local UiElement
local RectRound
local bgpadding 

local elementColours = {{0,0,0.0,0.6},{1,1,1,0.05}}
local oddLineColour = {0.28,0.28,0.28,0.08}
local evenLineColour = {1,1,1,0.08}
local sortLineColour = {0.82,0.82,0.82,0.1}
local buttonColour      = {{{1,1,1,0.2},{0.5,0.5,0.5,0.2}},{{0,0,0,0.3},{0.5,0.5,0.5,0.3}}}
local drawExtraStats
local drawStackedAreaGraphs
local drawStackedAreaGraphAxis
local drawButtonGraphs
local drawButtonsForSelections
local drawFixedElements
local maxRowHeight
local fontSize = 18
local fontSizeS = ceil(fontSize*.67)
local fontSizeL = ceil(fontSize * 2)
local font
local boarderWidth, screenRatio

---GameVariables
local minWind = Game.windMin
local maxWind = Game.windMax
local gaiaID = Spring.GetGaiaTeamID()
local vsx, vsy = Spring.GetViewGeometry()
local spectator, fullview = Spring.GetSpectatingState()



local sagHighlight = false
local displayGraph = "energyProduced"


local WindDescriptionText = {"None",0,"None",0}
local windDescriptionList = {"GALES!","Gusty","Average","Light","Becalmed"}
local suffix = {"st","nd","rd","th","th","th","th","th","th","th","th","th","th","th","th"}



---UserPreference
local squishFactorSetPoint = 40 --max number of bars on the chart before we need to start averaging or ignoring results.
local windCheckInterval = 60 --How often wind speed is checked and recorded (in frames)

---Local Caches---
local allyTeamColourCache = {}
local teamNamesCache = {}
local teamAllyTeamIDs = {}
local teamIDsorted = {} --sorted teamID in an array from [1] = 0 to max


---WidgetVariables---
local windList = {}
local antiSpam = 0
local gameOver = false
local playerRestricMode = false
local drawer = false
local screenPositions = {}
local critterOfTheDay = {}
local toggleTable = {teamColour = true, absolute = true, squishFactor = true, details = false, comparison = false, extraStats = false, graphSAG = false, windGraph = true,}
local extraStatsSortedTable = {}
local extraStatsTypeToDisplayList = {{name="valueCurrent", typeName = "valueCurrentText", displayName="Value\nAlive"},{name="numberCurrent", typeName = "numberCurrent", displayName="Number\nAlive"},{name="valueMade", typeName = "valueMadeText", displayName="Value\nCreated"},{name="numberMade", typeName = "numberMade", displayName="number\nCreated"}}
local extraStatsTypeToDisplayCounter = 1
local squishFactor = 1 
local snapShotNumber = 1 -- increases by 1 every 450 frames (15s). a value of 1 is at frame 0, a value of 2 is at frame 450 etc.
local sagTeamTableStats = {}
local sagCompareTableStats = {} --for current category only, with current camparison list
local comparisonTeamIDs = {}


local valuesOnYAxis = {"0","0","0"} --3 values to display on y Axis

local milestonesResourcesNameSorted = {"50KDamage","100KDamage","500KDamage","500Energy", "1KEnergy","10KEnergy"}
local milestonesResourcesList ={}
for k, name in ipairs(milestonesResourcesNameSorted) do
    milestonesResourcesList[name] = {false,-1,"NONE"}
end

local numberOfAllyTeams = 0
local trackedStatsNames = {
    {name = "armyValue", displayName = "Standing\n    Army", perSec = 0, spare = 0, type = "Total Value"},
    {name = "defenseValue", displayName = " Defensive\nStructures", perSec = 0, spare = 0, type = "Total Value"},
    {name = "utilityValue", displayName = "     Utility\nStructures", perSec = 0, spare = 0, type = "Total Value"},
    {name = "economyValue", displayName = " Economy\nStructures", perSec = 0, spare = 0, type = "Total Value"},
    {name = "everything", displayName = "Everything\n    Value ", perSec = 0, spare = 0, type = "Total Value"},
    {name = "APM", displayName = "APM", perSec = 0, spare = 0, type = "APM"},

    {name = "damageDealtCum", displayName = "   Total\nDamage", perSec = 0, spare = 0, type = "Damage"},
    {name = "damageDealt", displayName = "Damage\n   Dealt", perSec = 1, spare =0, type = "Damage"},
    {name = "damageReceived", displayName = "Damage\nReceived", perSec = 1, spare = 0, type = "Damage"},
    {name = "unitsSent", displayName = "Unit\nSent" , perSec = 0, spare = 0, type = "Units"},
    {name = "unitsKilled", displayName = "Units\nKilled" , perSec = 0, spare = 0, type = "Units"},
    {name = "unitsProduced", displayName = "    Units\nProduced" , perSec = 0, spare = 0, type = "Units"},
    
    {name = "energyProducedCum", displayName = " Total\nEnergy" , perSec = 0, spare = 0, type = "Energy"},
    {name = "energyProduced", displayName = "   Energy\nProduced" , perSec = 1, spare = 0, type = "Energy"},
    {name = "energyExcess", displayName = "Energy\nExcess" , perSec = 1, spare = 0, type = "Energy"},
    {name = "energySent", displayName = "Energy\n  Sent" , perSec = 0, spare = 0, type = "Energy"},
    {name = "energyReceived", displayName = "  Energy\nReceived" , perSec = 0, spare = 0, type = "Energy"},
    {name = "FPS", displayName = "FPS" , perSec = 0, spare = 0, type ="FPS"},

    {name = "metalProducedCum", displayName = "Total\nMetal", perSec = 0, spare = 0, type = "Metal"},
    {name = "metalProduced", displayName = "    Metal\nProduced", perSec = 1, spare = 0, type = "Metal"},
    {name = "metalExcess", displayName = " Metal\nExcess", perSec = 1, spare = 0, type = "Metal"},
    {name = "metalSent", displayName = "Metal\n Sent", perSec = 0, spare = 0, type = "Metal"},
    {name = "metalReceived", displayName = "   Metal\nReceived", perSec = 0, spare = 0, type = "Metal"},

    --{name = "metalReceived", displayName = "Metal \n Received", perSec = 1, spare = 0, type = "Metal"},
    --{name = "metalUsed", displayName = "Metal \n Used", perSec = 1, spare =0, type = "Metal"},
    --{name = "unitsDied", displayName = "Units \n Died" , perSec = 0, spare = 1, type = "Units"}, 
    --{name = "unitsOutCaptured", displayName = "Units Out \n captured" ,perSec = 0, spare = 0, type = "Units"},   
    --{name = "unitsReceived", displayName = "Units \n Received" , perSec = 0, spare = 0, type = "Units"},
    --
    --{name = "unitsCaptured", displayName = "    Units\nCaptured" , perSec = 0, spare = 0, type = "Units"},
    --{name = "energyReceived", displayName = "Energy \n Received" , perSec = 0, spare = 0, type = "Energy"},
    --{name = "energyUsed", displayName = "Energy \n Used" , perSec = 1, spare = 0, type = "Energy"},
}
local sortVar = "AllArmy"
local extraStatNames = {
    {name ="AllArmy", type = "armyUnitDefs", display = "1", displayName = "Army"},
    {name ="T1Army",type = "T1Army", display = "1", displayName = "T1 Army"},
    {name ="T2Army",type = "T2Army", display = "1", displayName = "T2 Army"},
    {name ="T3Army" ,type =  "T3Army", display = "1", displayName = "T3 Army"},
    {name ="AllDef", type = "defenseUnitDefs", display = "1", displayName = "Defense"},
    {name ="T1Defense", type = "T1Def", display = "1", displayName = "T1\nDefense"},
    {name ="T2Defense",type = "T2Def", display = "1", displayName = "T2\nDefense"},
    {name ="T2ArmyTime",type =  "T2Army", display = "time", displayName = "T2 Army\nTime"},
    {name ="T3ArmyTime",type =  "T3Army", display = "time", displayName = "T3 Army\nTime"},
    {name ="lltNumber" ,type = "llt", display = "1", displayName = "Custom\nLLT"},
    {name ="windNumber",type = "wind", display = "1", displayName = "Custom\nWind"},

}

local milestonesCategoryNames = {
    "T2Factory",
    "T2Constructor",
    "T2Army",
    "T3Army",
    "50KDamage",
    "100KDamage",
    "500KDamage",
    "500Energy",
    "1KEnergy",
    "10kEnergy",
}
local extraStatsTable = {}
local extraStatsTableAlly = {}
--local graphControlButtons = {"Absolute","Team Colours","WindSpeed Overlay","Compare"}
local graphControlButtons = {
    {name = "absolute", displayName = "Absolute"},
    {name = "teamColour", displayName = "Team Colours"},
    {name = "windGraph", displayName = "WindSpeed Overlay"},
    {name = "comparison", displayName = "Compare"}
}
local trackedStats = {}
for _,data in ipairs(trackedStatsNames) do
    trackedStats[data.name] = {formattedName = data.displayName ,perSecBool=data.perSec, spareBool = data.spare, type = data.type}
end




local function Seed(playerID)
    local customtable = select(11, Spring.GetPlayerInfo(playerID))
    if customtable.accountid and customtable.skilluncertainty then
        seed = floor(customtable.accountid/customtable.skilluncertainty) or 1
        return seed
    else
        return 1
    end
end

local function MakePolygonMap(x1,y1,x2,y2,c1,c2) --note i need to start in topleft corner and go round.
    glColor(c1[1],c1[2],c1[3],c1[4])
    glVertex(x1,y1)
    glColor(c2[1],c2[2],c2[3],c2[4])
	glVertex(x2,y1)
    glVertex(x2,y2)
    glColor(c1[1],c1[2],c1[3],c1[4])
	glVertex(x1,y2)
end

local function MakeLine(x1, y1, x2, y2)
	glVertex(x1, y1)
	glVertex(x2, y2)
end

local function NumberPrefix(value) ---takes a number and returns string of shorterned version. eg 43420 -> 43.2k
    local text
    if value < 1000 then
        text = string.format("%.0f",value)
    elseif value <1000000 then
        text = string.format("%.2f",(value)/1000).."K"
    elseif value <1000000000 then
        text = string.format("%.2f",(value)/1000000).."M"
    else
        text = string.format("%.2f",(value)/1000000000).."G"
    end
    return text
end

local function SnapTimeToText (timePoint)
    local time = floor(timePoint*15)
    local min =  floor(time / 60)
    local sec =  floor(time % 60)
    local timeText = string.format("%d:%02d",min,sec)--.."s"
    return timeText
end

local function CacheTeams() -- get all the teamID / Ally Team ID captains and colours once, and cache.
    myTeamID = Spring.GetMyTeamID()
	myAllyTeamID = Spring.GetMyAllyTeamID()
    myTeamList = Spring.GetTeamList(myAllyTeamID)
     --zzz change to false
    teamIDsorted = {}
    numberOfAllyTeams = -1 --need to remove gaia, which will always be present? xxx
    for _, allyTeamID in ipairs(Spring.GetAllyTeamList()) do
        local lowest_teamID = 1023
        for _, teamID in ipairs(Spring.GetTeamList(allyTeamID)) do
            if teamID < lowest_teamID then
                lowest_teamID = teamID
            end
            if gaiaID ~= teamID then
                insert(teamIDsorted,teamID)
                teamAllyTeamIDs[teamID] = allyTeamID
                if myTeamID == teamID and spectator == false and fullview == false then
                    playerRestricMode = true
                end
            end
        end

        for _, teamID in ipairs(Spring.GetTeamList(allyTeamID)) do
            allyTeamColourCache[teamID] = {spGetTeamColor(lowest_teamID)}
        end
        numberOfAllyTeams = numberOfAllyTeams + 1
    end
    teamColourCache = {} --{r,g,b,a,}
    for teamID,allyTeamID in pairs(teamAllyTeamIDs) do
        local playerName = nil
		local playerID = Spring.GetPlayerList(teamID, false)
        if playerID and playerID[1] then-- it's a player
            playerName = select(1, Spring.GetPlayerInfo(playerID[1], false))
        else
            forceAINameCheck = true
            local aiName = Spring.GetGameRulesParam("ainame_" .. teamID)
            if aiName then-- it's AI
                playerName = aiName.."(AI)"
            else-- player is gone
                playerName = "(gone)"  
            end
        end
        comparisonTeamIDs[teamID] = true
        teamColourCache[teamID] = {spGetTeamColor(teamID)}
        teamNamesCache[teamID] = playerName
        extraStatsTable[teamID] = {}
        for _,data in ipairs(extraStatNames) do
            extraStatsTable[teamID][data.name] = {numberCurrent = 0,valueCurrent=0,numberMade=0 ,valueMade=0, timeText = "-",}
            if not extraStatsTableAlly[allyTeamID] then
                extraStatsTableAlly[allyTeamID] = {}
            end
            if not extraStatsTableAlly[allyTeamID][data.name] then
                extraStatsTableAlly[allyTeamID][data.name] = {numberCurrent = 0,valueCurrent=0,numberMade=0 ,valueMade=0, timeText = "-",valueCurrentText=0,valueMadeText=0}
            end
        end
    end
end

local function GetWindText(calulatedWindaverage)
    local windDescription = ""
    local predictedWindAverage =  (maxWind * 0.75) --xxx copytopbar wind simulation results?
    if calulatedWindaverage >= (predictedWindAverage * 1.2) then
        windDescription = windDescriptionList[1]
    elseif calulatedWindaverage >= (predictedWindAverage * 1.11) then
        windDescription = windDescriptionList[2]
    elseif calulatedWindaverage >= (predictedWindAverage * 0.90) then
        windDescription = windDescriptionList[3]
    elseif calulatedWindaverage >= (predictedWindAverage * 0.83) then
        windDescription = windDescriptionList[4]
    else
        windDescription = windDescriptionList[5]
    end
    return windDescription
end

local function CalculateGameWindAverage()
    local cumWind, recentWind, calulatedWindaverage, count = 0, 0, 0, 0
    local windDescription, recentWindDescription = "", ""

    for _,value in ipairs(windList) do
        cumWind = cumWind + value
        count = count + 1
    end

    if count > 0 then
        calulatedWindaverage = (cumWind / count)
        windDescription = GetWindText(calulatedWindaverage)
    end

    if count > 1 then --30 sec
    local length = #windList
        for i = 1, math.min(count-1,(windCheckInterval/30)*15) do
            recentWind = recentWind + windList[length-i]
        end
        recentWind = (recentWind / math.min(count-1,(windCheckInterval/30)*15)) --1dp
        recentWindDescription = GetWindText(recentWind)
    end
    WindDescriptionText = {windDescription,string.format("%.1f",calulatedWindaverage),recentWindDescription,string.format("%.1f",recentWind)}
end

local function CalculateYAxisDataForCompare()
    sagCompareTableStats = {}
    sagCompareTableStats["largestCumTotal"] = 1
    local maxComparableCumTotal = 0
    local cumTotal = 0
    local cumTotalForTeamID = {}
    for time = 1, #sagTeamTableStats[displayGraph] do
        if time % squishFactor ~=0 then --gathering data
            for teamID, bool in pairs(comparisonTeamIDs) do
                if bool == true then
                    if not cumTotalForTeamID[teamID] then
                        cumTotalForTeamID[teamID] = 0
                    end
                    cumTotalForTeamID[teamID] = cumTotalForTeamID[teamID] + sagTeamTableStats[displayGraph][time][teamID]
                end
            end
        else
            local i = time / squishFactor
            sagCompareTableStats[i] = {["cumTotal"] = 0,}
            for teamID, bool in pairs(comparisonTeamIDs) do
                if bool == true then
                    if not cumTotalForTeamID[teamID] then
                        cumTotalForTeamID[teamID] = 0
                    end
                    cumTotalForTeamID[teamID] = cumTotalForTeamID[teamID] + sagTeamTableStats[displayGraph][time][teamID]
                    cumTotal = cumTotal + cumTotalForTeamID[teamID] 
                end
            end
            for teamID, bool in pairs(comparisonTeamIDs) do --as a fraction
                if bool == true and cumTotal > 0 then
                    sagCompareTableStats[i][teamID] = cumTotalForTeamID[teamID] / cumTotal
                else
                    sagCompareTableStats[i][teamID] = 0
                end
            end
            if trackedStats[displayGraph].perSecBool == 1 then
                cumTotal = cumTotal /15 /squishFactor --changes the axis to per second
            end
            if cumTotal > maxComparableCumTotal then
                    maxComparableCumTotal = cumTotal
            end
            sagCompareTableStats[i].cumTotal = cumTotal
            sagCompareTableStats[i].sortedTeamIDs = {}
            local sortingTable =  {}
            sagCompareTableStats[i].sortedValues = {}
            if sagHighlight and sagHighlight == i then
                local ranks = sagCompareTableStats[i]

                for k,v in pairs(ranks) do    
                    if type(k) ~="string" and v > 0 then
                        sortingTable[#sortingTable + 1] = k
                    end
                end

                table.sort(sortingTable, function(a, b)
                    return ranks[a] > ranks[b]
                end)
                sagCompareTableStats[i].sortedTeamIDs = sortingTable
            end
            cumTotal = 0
            cumTotalForTeamID = {}
        end
        sagCompareTableStats.largestCumTotal = maxComparableCumTotal
    end
    return maxComparableCumTotal
end

local function DetermineYAxisValues()
    local largestCumTotal = 0
    largestCumTotal= CalculateYAxisDataForCompare()
    for i=1,3 do
        local text = ""
        local value = 0
        if toggleTable["absolute"] == true then
            value = (i*largestCumTotal/3)
            -- if trackedStats[displayGraph].perSecBool == 1 then --moved this to above function.
            --     value = value /15 /squishFactor --changes the axis to per second
            -- end
            text = NumberPrefix(value)
        else
            text = string.format("%.1f",(i*100/3))
        end
        valuesOnYAxis[i] = text
    end
end

local function CritterCheck()
    toggleTable["critter"] = false
    local critterList = nil
    critterList = {}
    local seed = 0
    if WG['saghelper'].critterList then
        for key,list in ipairs(WG['saghelper'].critterList) do
            critterList[key] = {name = list.name, unitID = list.unitID}
        end
    end

    if #critterList > 0 and not critterOfTheDay.unitID then
        toggleTable["critter"] = true
        seed = Seed(0) % #critterList + 1
        critterOfTheDay = critterList[seed]
        critterOfTheDay.name = string.gsub(critterOfTheDay.name,"critter_","")
        critterOfTheDay.alive = true
        critterOfTheDay.pos = {Spring.GetUnitPosition(critterOfTheDay.unitID)}
        if Spring.GetUnitHealth(critterOfTheDay.unitID) ==nil then
            critterOfTheDay.alive = false
            critterOfTheDay.name = critterOfTheDay.name.." ---RIP---"
            critterOfTheDay.pos = nil
        end
        if not critterOfTheDay.flavour then
            critterOfTheDay.flavour = ""
            local flavour = {}
            local flavourCategories = {"Name","Age","Gender","Hobbies","Children"}
            local flavourCategoriesList = {}
            flavourCategoriesList.Name = {"Bobby","Alex","Sam","Gurte", "Charlie", "Robin", }
            flavourCategoriesList.Age = {"Child", "Juvenile", "Adolescent","Young Adult", "In its Prime", "Middle Aged","Elderly"}
            flavourCategoriesList.Gender = {"Male","Female","Other","Prefer not to say"}
            flavourCategoriesList.Hobbies = {"Frolicking","Questing","Gaming","Improvisational comedy","Reading", "Hunting", "Nerd"}
            flavourCategoriesList.Children = {"None","Maybe one Day","On the Way","1","2","3","So Many",}
            for key, category in ipairs(flavourCategories) do
                flavour[key] = category..": "..flavourCategoriesList[category][Seed(0) % #flavourCategoriesList[category] + 1].."\n"
            end
            for i = 1, #flavour do
                critterOfTheDay.flavour = critterOfTheDay.flavour..flavour[i]
            end
        end
    end
end

local function SortExtraStats()
    sortVar = sortVar or "AllArmy"
    local tempTable = {}
    for teamID, teamAllyTeamID in pairs(teamAllyTeamIDs) do
        -- if not tempTable[teamAllyTeamID] then
        --     tempTable[teamAllyTeamID] = {}
        -- end
        if playerRestricMode then
            if teamAllyTeamID == myAllyTeamID then
                if not tempTable[teamAllyTeamID] then
                    tempTable[teamAllyTeamID] = {}
                end
                tempTable[teamAllyTeamID][teamID] = extraStatsTable[teamID][sortVar][extraStatsTypeToDisplayList[extraStatsTypeToDisplayCounter].name] or extraStatsTable[teamID][sortVar].valueCurrent
            end
        else
            if not tempTable[teamAllyTeamID] then
                tempTable[teamAllyTeamID] = {}
            end
            tempTable[teamAllyTeamID][teamID] = extraStatsTable[teamID][sortVar][extraStatsTypeToDisplayList[extraStatsTypeToDisplayCounter].name] or extraStatsTable[teamID][sortVar].valueCurrent
        end

        --tempTable[teamAllyTeamID][teamID] = extraStatsTable[teamID][sortVar][extraStatsTypeToDisplayList[extraStatsTypeToDisplayCounter].name] or extraStatsTable[teamID][sortVar].valueCurrent
    end
    extraStatsSortedTable = {}
    for teamAllyTeamID, list1 in pairs(tempTable) do
        local list2 = {}
        for k,v in pairs(list1) do    
            list2[#list2+1] = k
        end
        table.sort(list2, function(a, b)
            return list1[a] > list1[b]
        end)
        extraStatsSortedTable[teamAllyTeamID] = list2
    end
end



local function CreateExtraStatsText()
    for teamID,allyTeamID in pairs(teamAllyTeamIDs) do
        if playerRestricMode == false or allyTeamID == myAllyTeamID then
            for _,data in ipairs(extraStatNames) do
                extraStatsTableAlly[allyTeamID][data.name] = {numberCurrent = 0,valueCurrent=0,numberMade=0 ,valueMade=0, timeText = "-",valueCurrentText=0,valueMadeText=0}
            end
        end
    end
    if WG['saghelper'].trackedFunStats then --xxx can replace the way i go through the teamid/allyteam id here.
        local trackedFunStats
        for _, teamID in ipairs(teamIDsorted) do
            trackedFunStats = WG['saghelper'].trackedFunStats[teamID]
            local allyteamID = teamAllyTeamIDs[teamID]
            for key, extraStatNamesTable in ipairs(extraStatNames) do
                local category = extraStatNamesTable.name
                local data = trackedFunStats[extraStatNamesTable.type]
                if data and extraStatsTable[teamID][category] then
                    extraStatsTable[teamID][category] = {
                        numberCurrent = data.numberCurrent or 0,
                        numberMade=data.numberMade or 0,
                        valueCurrentText=NumberPrefix(data.valueCurrent or 0),
                        valueCurrent=(data.valueCurrent or 0),
                        valueMade=data.valueMade or 0,
                        valueMadeText=NumberPrefix(data.valueMade or 0),
                        timeText = data.timeText or "-", --xxx maybe move the time formatting to this widget
                        time = data.time or 0,
                        shared = data.shared,
                        oldTeamID = data.oldTeamID,
                    }
                    if category == "T2ArmyTime" or category == "T3ArmyTime" then
                        extraStatsTable[teamID][category].timeText = data.timeText
                        if data.shared then
                            extraStatsTable[teamID][category].timeText = "   "..extraStatsTable[teamID][category].timeText.."\n(shared)"
                        end
                    end
                    if extraStatsTableAlly[allyteamID][category].valueMade then
                        extraStatsTableAlly[allyteamID][category].valueCurrent = extraStatsTableAlly[allyteamID][category].valueCurrent + (data.valueCurrent or 0)
                        extraStatsTableAlly[allyteamID][category].valueMade = extraStatsTableAlly[allyteamID][category].valueMade + (data.valueMade or 0)
                        extraStatsTableAlly[allyteamID][category].numberCurrent = extraStatsTableAlly[allyteamID][category].numberCurrent + (data.numberCurrent or 0)
                        extraStatsTableAlly[allyteamID][category].numberMade = extraStatsTableAlly[allyteamID][category].numberMade + (data.numberMade or 0)
                        extraStatsTableAlly[allyteamID][category].valueCurrentText = NumberPrefix(extraStatsTableAlly[allyteamID][category].valueCurrent or 0) --xxx this is wasteful, need a way to add at end of allyteam.
                        extraStatsTableAlly[allyteamID][category].valueMadeText = NumberPrefix(extraStatsTableAlly[allyteamID][category].valueMade or 0)
                    end
                end
            end
        end
        SortExtraStats()
    end
end

local function PlaySound(sound)
    if playSounds then
        if sounds[sound] then
            Spring.PlaySoundFile(sounds[sound], 0.6, 'ui')
        end
    end    
end
					

local function PrimeSagTable(time)
    for category,_ in pairs(trackedStats) do 
        if not sagTeamTableStats[category] then
            sagTeamTableStats[category] = { cumRanks= {}, sortedCumRanks = {}, largestCumTotal = 0, cumRanksRecent = {}, sortedCumRanksRecent={}}
            for teamID,_ in pairs(teamAllyTeamIDs) do
                sagTeamTableStats[category]["cumRanks"][teamID] = 0
            end
        end
        if not sagTeamTableStats[category][time] then
            sagTeamTableStats[category][time] = {cumTotal = 0, ranks = {},}
            for teamID, _ in pairs(teamAllyTeamIDs) do
                sagTeamTableStats[category][time][teamID] = 0
            end
        else
            sagTeamTableStats[category][time] = {cumTotal = 0, ranks = {},} 
            for teamID, _ in pairs(teamAllyTeamIDs) do
                sagTeamTableStats[category][time][teamID] = 0
            end
        end
    end
end

local function AddInfoToSagTable(teamID, category, value, time)
    sagTeamTableStats[category][time][teamID] = value
    sagTeamTableStats[category][time].cumTotal = sagTeamTableStats[category][time].cumTotal + value
end


local function SortCumRanks(stat)
    sagTeamTableStats[stat].sortedCumRanks = {}
    local ranks = sagTeamTableStats[stat].cumRanks
    for k,v in pairs(ranks) do    
        if v > 0 then
            sagTeamTableStats[stat].sortedCumRanks[#sagTeamTableStats[stat].sortedCumRanks + 1] = k
        end
    end
    table.sort(sagTeamTableStats[stat].sortedCumRanks, function(a, b)
        return ranks[a] > ranks[b]
    end)

    -- local temp_cumRanksRecent = sagTeamTableStats[stat]["cumRanksRecent"]

    -- if snapShotNumber > 4 and #sagTeamTableStats[stat] > 3 then
    --     for k,v in pairs(temp_cumRanksRecent) do    
    --         if v > 0 then
    --             sagTeamTableStats[stat].sortedCumRanksRecent[#sagTeamTableStats[stat].sortedCumRanksRecent + 1] = k
    --         end
    --     end
    --     table.sort(sagTeamTableStats[stat].sortedCumRanks, function(a, b)
    --         return temp_cumRanksRecent[a] > temp_cumRanksRecent[b]
    --     end)
    -- end
end

local function UpdateDrawingPositions(updateName) ---need to run on viewchange etc XXX
    --main toggle button
    if updateName == "mainToggle" then
        local buttonSizeX, buttonSizeY = 80,60
        local topBarPosition
        local paddingX, paddingY = 10,0
        if WG['topbar'] then
            topBarPosition = WG['topbar'].GetFreeArea()
        else
            topBarPosition{vsx,vsy,vsx,vsy} --xxx better defaults
        end
        if gameOver == true then
            paddingY = topBarPosition[4]-topBarPosition[2]
            Spring.Echo(paddingY)
        end

        screenPositions.GraphOnOffButton = {l = topBarPosition[3] - buttonSizeX - paddingX , b = topBarPosition[2] - paddingY, r = topBarPosition[3] - paddingX, t = topBarPosition[2] + buttonSizeY - paddingY}
        screenPositions.StatsOnOffButton = {l = screenPositions.GraphOnOffButton.l- buttonSizeX, b = screenPositions.GraphOnOffButton.b, r = screenPositions.GraphOnOffButton.l, t = screenPositions.GraphOnOffButton.t}
    end

    --All fixed parts of main display (Boarder for each area, X and Y axis blips) since these are all relative to main boarder.
    if updateName == "main" then
        local sizeX, sizeY = vsx/3.5,vsy/2 --xxx x and y offset need to be relative to either screen size or another widget
        screenRatio = 1 --xxx this needs to be set according to the screen resolution. maybe can remove as now I as a ratio of vsx and vsy?
        boarderWidth = 20 * screenRatio
        maxRowHeight = vsy/40 --xxx check value

        local posXl = ((vsx/3) - boarderWidth) * screenRatio
        local posYb = ((vsy/5) - boarderWidth) * screenRatio
        --local posXr = ((vsx/3) + sizeX + boarderWidth) *screenRatio
        --local posYt = ((vsy/5) + sizeY + boarderWidth) * screenRatio
        
        screenPositions.graphs = {}
        screenPositions.graphs = {
            l = posXl + boarderWidth,             --left
            b = posYb + boarderWidth,              --btm
            r = posXl + boarderWidth + sizeX,           --right
            t = posYb + boarderWidth + sizeY,
            columnWidth = 1,
            rowHeight = 1,
            totalNumRows = 1,
            totalNumCols = 1,
            sizeX = sizeX,
            sizeY = sizeY,
        }
        screenPositions.graphs.columnWidth = (screenPositions.graphs.r -screenPositions.graphs.l) * squishFactor / snapShotNumber
        screenPositions.graphs.rowHeight = (screenPositions.graphs.t -screenPositions.graphs.b) / screenPositions.graphs.totalNumRows
        screenPositions.graphs.totalNumCols = floor(snapShotNumber / squishFactor)

        --positionListLinesForRankingPositions = {}
        --local totalNumRows = 7
        screenPositions.ranking = {}
        screenPositions.ranking = {
            l = screenPositions.graphs.r + (2* boarderWidth),               --left
            b = screenPositions.graphs.t - (screenPositions.graphs.sizeY / 4),              --btm
            r = screenPositions.graphs.r + (2* boarderWidth) + (screenPositions.graphs.sizeX / 2), --right
            t = screenPositions.graphs.t,
            columnWidth  = 1,    --top
            rowHeight = 1,   -- ((sizeY / 3)) * 1 / totalNumRows,
            totalNumRows = 7,
            totalNumCols = 6,
            linePos = {}
        }
        screenPositions.ranking.columnWidth = (screenPositions.ranking.r - screenPositions.ranking.l) / screenPositions.ranking.totalNumCols
        screenPositions.ranking.rowHeight = (screenPositions.ranking.t -screenPositions.ranking.b) / screenPositions.ranking.totalNumRows


        for lineCount=1,screenPositions.ranking.totalNumRows do
            local colour = evenLineColour
            if lineCount <= 2 then
                colour = sortLineColour
            end
            if lineCount > 2 and (lineCount+1)%2 == 0 then
                colour = oddLineColour
            end
            screenPositions.ranking.linePos[lineCount] = {l=(screenPositions.ranking.l) , b=(screenPositions.ranking.t-(screenPositions.ranking.rowHeight*lineCount)), r=(screenPositions.ranking.r), t=(screenPositions.ranking.t-(screenPositions.ranking.rowHeight*(lineCount-1))),colour = colour}
        end

        --positionListLinesForMilestonesPositions = {}

        screenPositions.milestones = {
            l = screenPositions.graphs.r + (2* boarderWidth),                   --left
            b = screenPositions.ranking.b - boarderWidth - (screenPositions.graphs.sizeY * 2 / 5),                                  --btm
            r = screenPositions.graphs.r + (2* boarderWidth) + (screenPositions.graphs.sizeX / 2),     --right
            t = screenPositions.ranking.b - (boarderWidth/6),   --top
            rowHeight =1,
            columnWidth = 1,
            totalNumRows = #milestonesCategoryNames+2,
            totalNumCols = 4,
            linePos = {}
        }
        screenPositions.milestones.rowHeight = (screenPositions.milestones.t - screenPositions.milestones.b) / screenPositions.milestones.totalNumRows
        screenPositions.milestones.columnWidth = (screenPositions.milestones.r-screenPositions.milestones.l) / screenPositions.milestones.totalNumCols

        for lineCount=1,screenPositions.milestones.totalNumRows do
            local colour = evenLineColour
            if lineCount <= 2 then
                colour = sortLineColour
            end
            if lineCount > 2 and (lineCount+1)%2 == 0 then
                colour = oddLineColour
            end
            screenPositions.milestones.linePos[lineCount] = {l=(screenPositions.milestones.l) , b=(screenPositions.milestones.t-(screenPositions.milestones.rowHeight*lineCount)), r=(screenPositions.milestones.r), t=(screenPositions.milestones.t-(screenPositions.milestones.rowHeight*(lineCount-1))),colour= colour}
        end

        screenPositions.nature = {
            l = screenPositions.graphs.r + (2* boarderWidth),               
            b = screenPositions.graphs.b, 
            r = screenPositions.graphs.r + (2* boarderWidth) + (screenPositions.graphs.sizeX / 2),    
            t = screenPositions.milestones.b - (boarderWidth/6),
            rowHeight = 1,
            columnWidth = 1,
            totalNumRows = 8,--xxx need to relate this to a list length
            totalNumCols = 1,
            linePos = {}
        }
        screenPositions.nature.rowHeight = (screenPositions.nature.t - screenPositions.nature.b) / screenPositions.nature.totalNumRows
        screenPositions.nature.columnWidth = (screenPositions.nature.r - screenPositions.nature.l) / screenPositions.nature.totalNumCols

        for lineCount=1,screenPositions.nature.totalNumRows do
            local colour = evenLineColour
            if lineCount <= 2 then
                colour = sortLineColour
            end
            if lineCount > 2 and (lineCount+1)%2 == 0 then
                colour = oddLineColour
            end
            screenPositions.nature.linePos[lineCount] = {l=(screenPositions.nature.l) , b=(screenPositions.nature.t-(screenPositions.nature.rowHeight*lineCount)), r=(screenPositions.nature.r), t=(screenPositions.nature.t-(screenPositions.nature.rowHeight*(lineCount-1))),colour = colour}
        end

        screenPositions.graphControlButtons = {
            l = screenPositions.graphs.l,                              --left, x1
            b = screenPositions.graphs.b - (2* boarderWidth) - (screenPositions.graphs.sizeY / 4),                --btm, y1
            r = screenPositions.graphs.l + (screenPositions.graphs.sizeX *1/4),                              --right, x2
            t = screenPositions.graphs.b - (2* boarderWidth),               --top, y2
            columnWidth  = 1,
            rowHeight = 1,
            totalNumRows = 4,
            totalNumCols = 1,
            linePos = {}
        }
        screenPositions.graphControlButtons.columnWidth = (screenPositions.graphControlButtons.r - screenPositions.graphControlButtons.l) / screenPositions.graphControlButtons.totalNumCols
        screenPositions.graphControlButtons.rowHeight = (screenPositions.graphControlButtons.t -screenPositions.graphControlButtons.b) / screenPositions.graphControlButtons.totalNumRows
        for number,list in ipairs(graphControlButtons) do
            screenPositions.graphControlButtons.linePos[number] = {l=screenPositions.graphControlButtons.l, b=(screenPositions.graphControlButtons.t)-(screenPositions.graphControlButtons.rowHeight*(number)),r=screenPositions.graphControlButtons.l + screenPositions.graphControlButtons.columnWidth, t=(screenPositions.graphControlButtons.t)-(screenPositions.graphControlButtons.rowHeight*(number-1)),name=list.name, displayName = list.displayName}
        end

        screenPositions.categories = {
            l = screenPositions.graphControlButtons.r + boarderWidth/4,                            --left, x1
            b = screenPositions.graphs.b - (2* boarderWidth) - (screenPositions.graphs.sizeY / 4),                --btm, y1
            r = screenPositions.graphs.r,                              --right, x2
            t = screenPositions.graphs.b - (2* boarderWidth),               --top, y2
            columnWidth  = 1,
            rowHeight = 1,
            totalNumRows = 4,
            totalNumCols = 6,
            linePos = {}
        }
        screenPositions.categories.columnWidth = (screenPositions.categories.r - screenPositions.categories.l) / screenPositions.categories.totalNumCols
        screenPositions.categories.rowHeight = (screenPositions.categories.t -screenPositions.categories.b) / screenPositions.categories.totalNumRows




        --buttons for caterogies
        local column,row = 0,0
        for number, data in ipairs(trackedStatsNames) do --makes a (6x4) array for 24 catergories.
            column = ((number-1) % screenPositions.categories.totalNumCols) + 1
            if (number-1) % screenPositions.categories.totalNumCols == 0 then
                row = row + 1
            end
            screenPositions.categories.linePos[number] = {l=(screenPositions.categories.l + ((column-1)*screenPositions.categories.columnWidth)),b=(screenPositions.categories.t)-(screenPositions.categories.rowHeight*(row)),r=(screenPositions.categories.l + ((column)*screenPositions.categories.columnWidth)),t=(screenPositions.categories.t)-(screenPositions.categories.rowHeight*(row-1)), displayName=trackedStats[data.name].formattedName, name=data.name }
        end
        


        --positionListButtonsForPlayerSelections = {}
        screenPositions.playerSelect = {
            l = screenPositions.graphs.l - (2* boarderWidth) - (screenPositions.graphs.sizeX / 6),
            b = screenPositions.graphs.b,
            r = screenPositions.graphs.l - (2* boarderWidth),
            t = screenPositions.graphs.t,
            columnWidth  = 1,
            rowHeight = 1,
            totalNumRows = #teamIDsorted,
            totalNumCols = 1,
            linePos={}
        }
        screenPositions.playerSelect.columnWidth = (screenPositions.playerSelect.r - screenPositions.playerSelect.l) / screenPositions.playerSelect.totalNumCols
        screenPositions.playerSelect.rowHeight = math.min((screenPositions.playerSelect.t -screenPositions.playerSelect.b) / screenPositions.playerSelect.totalNumRows,maxRowHeight*2)
        screenPositions.playerSelect.b = screenPositions.playerSelect.t - (screenPositions.playerSelect.rowHeight * screenPositions.playerSelect.totalNumRows)

        local sizeYButton = screenPositions.playerSelect.rowHeight
        for number, teamID in ipairs(teamIDsorted) do
            screenPositions.playerSelect.linePos[number] = { l=(screenPositions.playerSelect.l), b=(screenPositions.playerSelect.t - (sizeYButton*(number-1)) - sizeYButton), r=(screenPositions.playerSelect.r),t=(screenPositions.playerSelect.t - (sizeYButton*(number-1)))}
        end

        screenPositions.details = {
            l = screenPositions.nature.l,   --left
            b = screenPositions.categories.b,   --btm
            r = screenPositions.nature.r,   --right
            t = screenPositions.nature.t,   --top
            rowHeight = 1,
            columnWidth = 1,
            totalNumRows = #teamIDsorted + 2 + 1, --Title x2 + total
            totalNumCols = 6,
            linePos = {}
        }
        screenPositions.details.rowHeight = math.min((screenPositions.details.t - screenPositions.details.b) / screenPositions.details.totalNumRows,maxRowHeight)
        screenPositions.details.columnWidth = (screenPositions.details.r - screenPositions.details.l) / screenPositions.details.totalNumCols
        screenPositions.details.b = screenPositions.nature.t - (screenPositions.details.rowHeight * screenPositions.details.totalNumRows)
        for lineCount=1,screenPositions.details.totalNumRows do
            local colour = evenLineColour
            if lineCount <= 2 then
                colour = sortLineColour
            end
            if lineCount > 2 and (lineCount+1)%2 == 0 then
                colour = oddLineColour
            end
            screenPositions.details.linePos[lineCount] = {l=(screenPositions.details.l) , b=(screenPositions.details.t-(screenPositions.details.rowHeight*lineCount)), r=(screenPositions.details.r), t=(screenPositions.details.t-(screenPositions.details.rowHeight*(lineCount-1))),colour = colour}
        end
    end


    if updateName == "funStats" then
        screenPositions.funStatBox = {
            l = screenPositions.playerSelect.l,
            b = screenPositions.graphs.b,
            r = screenPositions.graphs.r + boarderWidth + (screenPositions.graphs.sizeX / 2),
            t = screenPositions.graphs.t,
            rowHeight = 1,
            columnWidth = 1,
            totalNumRows = #teamIDsorted + 2 + (numberOfAllyTeams*2) + 1, --2 for headers, 1 for btm buttons
            totalNumCols = #extraStatNames+2,
            linePos = {}
        }
            if playerRestricMode then
                screenPositions.funStatBox.totalNumRows = #myTeamList + 2 + 1 + 1
            end
            screenPositions.funStatBox.rowHeight = math.min((screenPositions.funStatBox.t - screenPositions.funStatBox.b) / screenPositions.funStatBox.totalNumRows, maxRowHeight)
            screenPositions.funStatBox.columnWidth = (screenPositions.funStatBox.r - screenPositions.funStatBox.l) / screenPositions.funStatBox.totalNumCols
            screenPositions.funStatBox.b = screenPositions.funStatBox.t - (screenPositions.funStatBox.rowHeight * screenPositions.funStatBox.totalNumRows)

        for lineCount=1,screenPositions.funStatBox.totalNumRows do
            local colour = evenLineColour
            if lineCount <= 2 then
                colour = sortLineColour
            end
            if lineCount > 2 and (lineCount+1)%2 == 0 then
                colour = oddLineColour
            end
            screenPositions.funStatBox.linePos[lineCount] = {l=(screenPositions.funStatBox.l) , b=(screenPositions.funStatBox.t-(screenPositions.funStatBox.rowHeight*lineCount)), r=(screenPositions.funStatBox.r), t=(screenPositions.funStatBox.t-(screenPositions.funStatBox.rowHeight*(lineCount-1))),colour = colour}
        end
    end
end

local function DrawExtraStats()
    gl_DeleteList(drawExtraStats)
    drawExtraStats = nil
    if toggleTable["extraStats"] then
        drawExtraStats = gl_CreateList(function()
            local typeToDisplay = extraStatsTypeToDisplayList[extraStatsTypeToDisplayCounter]
            UiElement(screenPositions.funStatBox.l ,screenPositions.funStatBox.b,screenPositions.funStatBox.r,screenPositions.funStatBox.t,1,1,1,1, 1,1,1,1, .5, elementColours[1],elementColours[2],2)
            font:Begin()

            for lineCount, pos in ipairs(screenPositions.funStatBox.linePos) do
                RectRound(pos.l, pos.b, pos.r, pos.t, bgpadding, 0,0,0,0, {pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7},{pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*3*0.7} ) --xxx replace all these 0.7 with ui_opacity
                if lineCount == screenPositions.funStatBox.totalNumRows then --buttons on btm
                    for i = 1, #extraStatsTypeToDisplayList do
                        UiButton(pos.l + ((i-1)*screenPositions.funStatBox.columnWidth), pos.b, (pos.l + ((i)*screenPositions.funStatBox.columnWidth)), pos.t)
                        if extraStatsTypeToDisplayList[i].name == typeToDisplay.name then
                            font:SetTextColor(0, 5, .2, 1)
                        else
                            font:SetTextColor(1, 1, 1, 1)
                        end
                        font:Print(extraStatsTypeToDisplayList[i].displayName,pos.l + ((i-1)*screenPositions.funStatBox.columnWidth)+(screenPositions.funStatBox.columnWidth/2),pos.t-((pos.t-pos.b)/2) , fontSizeS, "cvo")
                    end
                    font:SetTextColor(1, 1, 1, 1)
                end
            end

            for k, data in ipairs(extraStatNames) do --headers
                local text = data.displayName
                if sortVar == data.name then
                    font:SetTextColor(0, 5, .2, 1)
                else
                    font:SetTextColor(1, 1, 1, 1)
                end
                font:Print(text, screenPositions.funStatBox.l+((k+2) * screenPositions.funStatBox.columnWidth) - (screenPositions.funStatBox.columnWidth/2),screenPositions.funStatBox.t - screenPositions.funStatBox.rowHeight , fontSizeS, "cvo")
            end
            font:Print("Player", screenPositions.funStatBox.l + screenPositions.funStatBox.columnWidth,screenPositions.funStatBox.t - screenPositions.funStatBox.rowHeight , fontSizeS, "cvo")
            
            
            local linenumber = 1
            local text = ""
            for allyTeamID, sortedTeamIDTable in pairs (extraStatsSortedTable) do --need to get allteamid in order using i=1,i=#allyteamidsorted
                for key, teamID in ipairs(sortedTeamIDTable) do
                    font:SetTextColor(teamColourCache[teamID][1],teamColourCache[teamID][2],teamColourCache[teamID][3],1)
                    font:Print(teamNamesCache[teamID], screenPositions.funStatBox.l+ screenPositions.funStatBox.columnWidth,screenPositions.funStatBox.t - ((linenumber+1.5) * screenPositions.funStatBox.rowHeight), fontSizeS, "cvo")
                    font:SetTextColor(1,1,1,1)
                    for k, data in ipairs(extraStatNames) do
                    local category = data.name
                    text = (extraStatsTable[teamID][category])
                        if text.valueCurrentText and data.display == "1" then
                            if typeToDisplay then
                                font:Print(text[typeToDisplay.typeName], screenPositions.funStatBox.l+((k+2) * screenPositions.funStatBox.columnWidth) - (screenPositions.funStatBox.columnWidth/2), screenPositions.funStatBox.t - ((linenumber+1.5) * screenPositions.funStatBox.rowHeight), fontSizeS, "cvo")
                            end
                        elseif data.display == "time" then
                            font:Print(text.timeText, screenPositions.funStatBox.l+((k+2) * screenPositions.funStatBox.columnWidth) - (screenPositions.funStatBox.columnWidth/2), screenPositions.funStatBox.t - ((linenumber+1.5) * screenPositions.funStatBox.rowHeight), fontSizeS, "cvo")
                        else
                            font:Print(0, screenPositions.funStatBox.l+((k+2) * screenPositions.funStatBox.columnWidth) - (screenPositions.funStatBox.columnWidth/2), screenPositions.funStatBox.t - ((linenumber+1.5) * screenPositions.funStatBox.rowHeight), fontSizeS, "cvo")
                        end
                    end
                    linenumber= linenumber +1
                end
                font:SetTextColor(1,1,1,1)
                for k, data in ipairs(extraStatNames) do
                    local category = data.name
                    if typeToDisplay and data.display == "1" then
                        text = extraStatsTableAlly[allyTeamID][category][typeToDisplay.typeName]
                        font:Print('\255\255\220\130'..text, screenPositions.funStatBox.l +((k+2) * screenPositions.funStatBox.columnWidth) - (screenPositions.funStatBox.columnWidth/2), screenPositions.funStatBox.t - ((linenumber+1.5) * screenPositions.funStatBox.rowHeight), fontSizeS, "cvo")
                    end
                end
                font:SetTextColor(1,1,1,1)
                linenumber = linenumber +2          
            end
            font:End() --extra stat background element
        end)
    end
end


local function DrawGraphToggleButton()
    gl_DeleteList(drawButtonGraphs)
    drawButtonGraphs = nil
    drawButtonGraphs = gl_CreateList(function()
        local colour = buttonColour[1]
        if toggleTable["graphSAG"] then
            colour = buttonColour[1]
            font:SetTextColor(1, 1, 1, 1)
        else
            colour = buttonColour[2]
            font:SetTextColor(0.92, 0.92, 0.92, 1)
        end
        UiButton(screenPositions.GraphOnOffButton.l,screenPositions.GraphOnOffButton.b,screenPositions.GraphOnOffButton.r,screenPositions.GraphOnOffButton.t, 1,1,1,1, 1,1,1,1, nil,colour[1],colour[2],2)
        font:Begin()
        font:Print("Graphs", screenPositions.GraphOnOffButton.l+((screenPositions.GraphOnOffButton.r-screenPositions.GraphOnOffButton.l)/2),screenPositions.GraphOnOffButton.b+((screenPositions.GraphOnOffButton.t-screenPositions.GraphOnOffButton.b)/2), fontSize, "cvos")
        font:End()
        if toggleTable["extraStats"] then
            colour = buttonColour[1]
            font:SetTextColor(1, 1, 1, 1)
        else
            colour = buttonColour[2]
            font:SetTextColor(0.92, 0.92, 0.92, 1)
        end
        UiButton(screenPositions.StatsOnOffButton.l,screenPositions.StatsOnOffButton.b,screenPositions.StatsOnOffButton.r,screenPositions.StatsOnOffButton.t, 1,1,1,1, 1,1,1,1, nil,colour[1],colour[2],2)
        font:Begin()
        font:Print("Stats", screenPositions.StatsOnOffButton.l+((screenPositions.StatsOnOffButton.r-screenPositions.StatsOnOffButton.l)/2),screenPositions.StatsOnOffButton.b+((screenPositions.StatsOnOffButton.t-screenPositions.StatsOnOffButton.b)/2), fontSize, "cvos")
        font:End()
    end)
end

local function DrawStackedAreaGraph()
    if not drawFixedElements then
        drawFixedElements = gl_CreateList(function()
            UiElement(screenPositions.graphs.l - boarderWidth ,screenPositions.graphs.b - boarderWidth,screenPositions.graphs.r + boarderWidth ,screenPositions.graphs.t + boarderWidth,1,1,1,1, 1,1,1,1, .5, elementColours[1],elementColours[2],boarderWidth) --graph display element
            UiElement(screenPositions.categories.l ,screenPositions.categories.b,screenPositions.categories.r,screenPositions.categories.t,1,1,1,1, 1,1,1,1, .5, {0,0,0,0.5},{1,1,1,0.05}) --category display element
            UiElement(screenPositions.graphControlButtons.l,screenPositions.graphControlButtons.b,screenPositions.graphControlButtons.r,screenPositions.graphControlButtons.t,1,1,1,1, 1,1,1,1, .5, elementColours[1],elementColours[2])

            UiElement(screenPositions.ranking.l ,screenPositions.ranking.b,screenPositions.ranking.r,screenPositions.ranking.t,1,1,1,1, 1,1,1,1, .5, elementColours[1],elementColours[2],2) --ranking display element
            for lineCount, pos in ipairs(screenPositions.ranking.linePos) do
                if lineCount <=2 then
                    RectRound(pos.l, pos.b, pos.r, pos.t, bgpadding, 0,0,0,0, {pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7},{pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7} )
                else
                    RectRound(pos.l, pos.b, pos.r, pos.t, bgpadding, 0,0,0,0, {pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7},{pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*3*0.7} ) --xxx replace all these 0.7 with ui_opacity
                end
            end

            UiElement(screenPositions.milestones.l ,screenPositions.milestones.b, screenPositions.milestones.r,screenPositions.milestones.t,1,1,1,1, 1,1,1,1, .5, elementColours[1],elementColours[2],2) --Award display element
            for lineCount, pos in ipairs(screenPositions.milestones.linePos) do
                if lineCount <=2 then
                    RectRound(pos.l, pos.b, pos.r, pos.t, bgpadding, 0,0,0,0, {pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7},{pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7} )
                else
                    RectRound(pos.l, pos.b, pos.r, pos.t, bgpadding, 0,0,0,0, {pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7},{pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*3*0.7} ) --xxx replace all these 0.7 with ui_opacity
                end
            end

            if toggleTable["details"] == false then
                UiElement(screenPositions.nature.l ,screenPositions.nature.b, screenPositions.nature.r,screenPositions.nature.t,1,1,1,1, 1,1,1,1, .5, elementColours[1],elementColours[2],2) --Nature display element
                for lineCount, pos in ipairs(screenPositions.nature.linePos) do
                    if lineCount <=2 then
                        RectRound(pos.l, pos.b, pos.r, pos.t, bgpadding, 0,0,0,0, {pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7},{pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7} )
                    else
                        RectRound(pos.l, pos.b, pos.r, pos.t, bgpadding, 0,0,0,0, {pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7},{pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*3*0.7} ) --xxx replace all these 0.7 with ui_opacity
                    end
                end
            else
                UiElement(screenPositions.details.l ,screenPositions.details.b, screenPositions.details.r,screenPositions.details.t,1,1,1,1, 1,1,1,1, .5, elementColours[1],elementColours[2],2) --Details display element
                for lineCount, pos in ipairs(screenPositions.details.linePos) do
                    if lineCount <=2 then
                        RectRound(pos.l, pos.b, pos.r, pos.t, bgpadding, 0,0,0,0, {pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7},{pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7} )
                    else
                        RectRound(pos.l, pos.b, pos.r, pos.t, bgpadding, 0,0,0,0, {pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7},{pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*3*0.7} ) --xxx replace all these 0.7 with ui_opacity
                    end
                end
            end


            if toggleTable["comparison"] then
                UiElement(screenPositions.playerSelect.l ,screenPositions.playerSelect.b, screenPositions.playerSelect.r, screenPositions.playerSelect.t,1,1,1,1, 1,1,1,1, .5, elementColours[1],elementColours[2],boarderWidth/8) --player select element
            end

        end)
    end

    if not drawStackedAreaGraphs then ---SAG bars and Winds plot (if enabled)
        drawStackedAreaGraphs = gl_CreateList(function()
            ---SAG bars---
            local x1 ,x2, y1, y2
            if toggleTable["graphSAG"] then
                local scaleY = screenPositions.graphs.sizeY / screenRatio
                local absScaleFactor = 1 --Value of 1 will allow the graph elements to stretch to the very top of y axis, <1 will squish.
                local largestCumTotal = sagCompareTableStats.largestCumTotal
                for timePoint,data in pairs (sagCompareTableStats) do
                    if type(timePoint) ~= "string" then
                        absScaleFactor = 1
                        if largestCumTotal> 0 and toggleTable["absolute"] then
                            absScaleFactor = data.cumTotal / largestCumTotal
                        end
                        local fraction,cumFraction,teamID = 0,0,0
                        for i = 1, #teamIDsorted do
                            teamID = teamIDsorted[i]
                            fraction = data[teamID]
                            if fraction == nil then
                                fraction = 0
                            end
                            --allyTeamFraction[teamAllyTeamIDs[teamID]] = allyTeamFraction[teamAllyTeamIDs[teamID]] + fraction XXX look at cumalting allyteam fraction to draw only one quad, allowing better tint/totals.
                            x1 = screenPositions.graphs.l + ((timePoint - 1) * screenPositions.graphs.columnWidth)
                            x2 = screenPositions.graphs.l + ((timePoint - 0) * screenPositions.graphs.columnWidth)
                            y1 = screenPositions.graphs.b + (screenPositions.graphs.sizeY - (cumFraction * scaleY)) * absScaleFactor
                            cumFraction = cumFraction + fraction
                            y2 = screenPositions.graphs.b + (screenPositions.graphs.sizeY - (cumFraction * scaleY)) * absScaleFactor

                            local colour = {1,1,1,1}
                            local colour2 = {1,1,1,1}
                            if toggleTable["teamColour"] then
                                colour = allyTeamColourCache[teamID]
                                for i = 1,3 do
                                    colour2[i] = math.min(colour[i] + 0.2,1)
                                end
                            else
                                colour = teamColourCache[teamID]
                                for i = 1,3 do
                                    colour2[i] = math.min(colour[i] + 0.2,1)
                                end
                            end
                            if timePoint == sagHighlight then
                                colour[4] = 1
                                colour2[4] = 1
                            else
                                colour[4] =0.67
                                colour2[4] = 0.67
                            end


                            glBeginEnd(GL_QUADS,MakePolygonMap, x1,y1,x2-1,y2,colour,colour2)
                        end
                    end
                end
            end

            local maxX = #windList
            if toggleTable["windGraph"] and maxWind >0  and maxX > 0 then
                glColor(1,1,1,1)
                for number, value in ipairs(windList) do
                    if number ~= 1 then
                        x1 = screenPositions.graphs.l + ((number - 1) / maxX) * screenPositions.graphs.sizeX
                        x2 = screenPositions.graphs.l + ((number) / maxX) * screenPositions.graphs.sizeX
                        y1 = screenPositions.graphs.b + (windList[number - 1] / (maxWind)) * screenPositions.graphs.sizeY*.8
                        y2 = screenPositions.graphs.b + (value / (maxWind) * screenPositions.graphs.sizeY*.8)
                    glLineWidth(1)
                    glBeginEnd(GL.LINE,MakeLine, x1,y1,x2,y2)
                    end
                end
            end
        end)
    end
    
    if not drawStackedAreaGraphAxis then
        drawStackedAreaGraphAxis = gl_CreateList(function()
            local x1 ,x2, y1, y2   
            local text
            if toggleTable["graphSAG"] then
                x1 = screenPositions.graphs.l
                x2 = screenPositions.graphs.r
                y1 = screenPositions.graphs.b + screenPositions.graphs.sizeY/2

                if not toggleTable["absolute"] and numberOfAllyTeams == 2 then
                    glColor(1,1,1,1)
                    gl.LineWidth(2)
                    glBeginEnd(GL.LINE,MakeLine, x1,y1,x2,y1)
                end
            end

            --title
            if toggleTable["graphSAG"] then
                local text = string.gsub(trackedStats[displayGraph].formattedName," \n","")
                font:Begin()
                font:SetTextColor(1, 1, 1)
                font:Print(text, screenPositions.graphs.l + screenPositions.graphs.sizeX/2, screenPositions.graphs.t + boarderWidth, fontSizeL, 'cvos')
                font:End()
            end

            --X axis
            if toggleTable["graphSAG"] or toggleTable["windGraph"] then
                y1 = screenPositions.graphs.b - 4
                y2 = screenPositions.graphs.b + 4
                text = ""
                for i=0,4 do
                    if i == 2 then
                    else
                        x1 = screenPositions.graphs.l + (i/4*screenPositions.graphs.sizeX)
                        glColor(1,1,1,0.75)
                        gl.LineWidth(1)
                        glBeginEnd(GL.LINE,MakeLine, x1,y1,x1,y2)
                        text = SnapTimeToText((i/4)*(snapShotNumber-1))

                        font:Begin()
                        font:SetTextColor(1, 1, 1,0.75)
                        font:Print(text, x1, y1 -( boarderWidth*screenRatio / 4) , fontSizeS, 'cvo')
                        font:End()
                    end
                end
                font:Begin()
                font:SetTextColor(1, 1, 1,0.75)
                font:Print("Time", screenPositions.graphs.l + (screenPositions.graphs.r - screenPositions.graphs.l)/2, screenPositions.graphs.b - (boarderWidth/2) , fontSize, 'cvos')
                font:Print("|One Bar| = "..(squishFactor*15).." s", screenPositions.graphs.l + (screenPositions.graphs.r - screenPositions.graphs.l)/2, screenPositions.graphs.b - (boarderWidth/2) - fontSize  , fontSize, 'cvo')
                font:End()
            end

            --Y axis values
            if toggleTable["graphSAG"] then
                x1 = screenPositions.graphs.l - 4
                x2 = screenPositions.graphs.l + 4
                for i=1,3 do
                    y1= screenPositions.graphs.b + (i/3*screenPositions.graphs.sizeY)
                    glColor(1,1,1,0.75)
                    gl.LineWidth(1)
                    glBeginEnd(GL.LINE,MakeLine, x1,y1,x2,y1)
                    local text = valuesOnYAxis[i]
                    font:Begin()
                    font:SetTextColor(1, 1, 1,0.75)
                    font:Print(text, x1-( boarderWidth*screenRatio / 4), y1 , fontSizeS, 'rvo')
                    font:End()
                end
            
            
            --Rotated Y Axis Title
                local x = screenPositions.graphs.l - (boarderWidth*1.5)
                local y = screenPositions.graphs.b + (screenPositions.graphs.t-screenPositions.graphs.b)/2
                local extraText = ""
                text = string.gsub(trackedStats[displayGraph].type," \n","")
                if trackedStats[displayGraph].perSecBool == 1 and toggleTable["absolute"] then
                    extraText = "\n(per Second)"
                end
                gl.PushMatrix()
                gl.Translate(x, y, 0)
                gl.Rotate(90, 0, 0, 1)   -- rotate around Z axis (screen)
                font:Begin()
                font:Print(text, 0, 0, fontSize, "cvos")  -- print at origin after transform
                font:Print(extraText, 0, -fontSize, fontSizeS, "cvo")  -- print at origin after transform
                font:End()
                gl.PopMatrix()
            end

            --Y2 Axis (wind)
            if toggleTable["windGraph"] and maxWind >0 and maxWind-minWind > 0 then
                local x1 = screenPositions.graphs.l
                local x2 = screenPositions.graphs.r
                gl.LineStipple(1, 4369)

                y1 = screenPositions.graphs.b + (screenPositions.graphs.sizeY * 0.8)
                glBeginEnd(GL.LINE,MakeLine, x1,y1,x2,y1)
                glBeginEnd(GL.LINE,MakeLine, x1,y1,x2,y1)
                font:Begin()
                font:SetTextColor(1, 1, 1,0.75)
                font:Print("Max", x2, y1 , fontSizeS, 'lvo')
                font:End()

                y1 = screenPositions.graphs.b + ((screenPositions.graphs.sizeY * 0.8) * (maxWind*0.75/maxWind))
                font:Begin()
                font:SetTextColor(1, 1, 1,0.75)
                font:Print("Avg", x2, y1 , fontSizeS, 'lvo')
                font:End()
                glBeginEnd(GL.LINE_STRIP,MakeLine, x1,y1,x2,y1)

                y1 = screenPositions.graphs.b + ((minWind/(maxWind)*(screenPositions.graphs.sizeY * 0.8)))
                font:Begin()
                font:SetTextColor(1, 1, 1,0.75)
                font:Print("Min", x2, y1 , fontSizeS, 'lvo')
                font:End()
                glBeginEnd(GL.LINE,MakeLine, x1,y1,x2,y1)
                gl.LineStipple(false)

                x1 = screenPositions.graphs.r
                x2 = screenPositions.graphs.r + 4
                -- for i=1,4 do
                --     y1= screenPositions.graphs.b + (boarderWidth*screenRatio) + (i/4*screenPositions.graphs.t-(screenPositions.graphs.t-screenPositions.graphs.b)/2)
                --     glColor(1,1,1,0.75)
                --     glBeginEnd(GL.LINE,MakeLine, x1,y1,x2,y1)

                --     text = string.format("%.1f",(maxWind+2)) * i/4

                --     font:Begin()
                --     font:SetTextColor(1, 1, 1,0.75)
                --     font:Print(text, x1+ ( boarderWidth / 4), y1 , fontSizeS, 'lvo')
                --     font:End()
                -- end
                    --local x, y = x1, posYb + (posYt-posYb)/2
                    local x, y = x1 + (boarderWidth/2), screenPositions.graphs.b + (screenPositions.graphs.t-screenPositions.graphs.b)/2
                    gl.PushMatrix()
                    gl.Translate(x, y, 0)
                    gl.Rotate(-90, 0, 0, 1)
                    font:Begin()
                    font:Print("Wind Speed", 0, (boarderWidth*screenRatio), fontSize, "cvo")
                    font:End()
                    gl.PopMatrix()
            end



            font:Begin()
            font:SetTextColor(1,1,1,0.75)

            ---Nature---
            if toggleTable["details"] == false then --xxx could probably neat and future proof this with a list...
                for lineCount, pos in ipairs(screenPositions.nature.linePos) do
                    if lineCount == 1 then
                        font:Print("Nature Facts", pos.l + ((pos.r-pos.l)/2), pos.t - screenPositions.nature.rowHeight, fontSize, 'cvo')
                    elseif lineCount == 3 then
                        font:Print("Wind (All Game): ".. WindDescriptionText[1].." ("..WindDescriptionText[2]..")", pos.l + ((pos.r-pos.l)/2),pos.t-screenPositions.nature.rowHeight/2 , fontSizeS, 'cvo')
                    elseif lineCount == 4 then
                        font:Print("Wind (Recent): ".. WindDescriptionText[3].." ("..WindDescriptionText[4]..")", pos.l + ((pos.r-pos.l)/2),pos.t-screenPositions.nature.rowHeight/2, fontSizeS, 'cvo')
                    
                    elseif lineCount == 5 then
                        if WG['saghelper'].trees then
                            local area = {pos.l,pos.b,pos.r,pos.t}
                            local text1 = "Energy Liberated\n("..WG['saghelper'].trees.energyDestroyed.." / "..WG['saghelper'].trees.maxEnergy..")\n\n" --could change colour to grey/yellow here
                            local text2 = "Metal Liberated\n("..WG['saghelper'].trees.metalDestroyed.." / "..WG['saghelper'].trees.maxMetal..")"
                            font:Print("Deforestation Progress: ".. string.format("%.1f",100* WG['saghelper'].trees.numberDestroyed / WG['saghelper'].trees.maxNumber).."%, ("..WG['saghelper'].trees.numberDestroyed.." / "..WG['saghelper'].trees.maxNumber..")", pos.l + ((pos.r-pos.l)/2),pos.t-screenPositions.nature.rowHeight/2, fontSize*.67, 'cvo')
                            WG['tooltip'].AddTooltip("deforestation"..snapShotNumber,area,text1..text2,0.5,"Resources Extracted")
                        else
                            font:Print("Deforestation Progress: Treeless World", pos.l + ((pos.r-pos.l)/2),pos.t-screenPositions.nature.rowHeight/2, fontSizeS, 'cvo')
                            WG['tooltip'].RemoveTooltip("deforestation"..snapShotNumber)
                        end

                    elseif lineCount == 6 then
                        if WG['saghelper'].rocks then
                            local area = {pos.l,pos.b,pos.r,pos.t}
                            local text1 = "Energy Liberated\n("..WG['saghelper'].rocks.energyDestroyed.." / "..WG['saghelper'].rocks.maxEnergy..")\n\n"
                            local text2 = "Metal Liberated\n("..WG['saghelper'].rocks.metalDestroyed.." / "..WG['saghelper'].rocks.maxMetal..")"
                            font:Print("Demineralisation Progress: ".. string.format("%.1f",100* WG['saghelper'].rocks.numberDestroyed / WG['saghelper'].rocks.maxNumber).."%, ("..WG['saghelper'].rocks.numberDestroyed.." / "..WG['saghelper'].rocks.maxNumber..")", pos.l + ((pos.r-pos.l)/2),pos.t-screenPositions.nature.rowHeight/2, fontSize*.67, 'cvo')
                            WG['tooltip'].AddTooltip("demineralisation"..snapShotNumber,area,text1..text2,0.5,"Resources Extracted")
                        else
                            font:Print("Demineralisation Progress: No usable Rocks", pos.l + ((pos.r-pos.l)/2),pos.t-screenPositions.nature.rowHeight/2, fontSizeS, 'cvo')
                            WG['tooltip'].RemoveTooltip("demineralisation"..snapShotNumber)
                        end

                    elseif lineCount == 7 then
                        if critterOfTheDay.name then
                            font:Print("Critter of the Day: "..critterOfTheDay.name, pos.l + ((pos.r-pos.l)/2),pos.t-screenPositions.nature.rowHeight/2, fontSizeS, 'cvo')
                            local area = {pos.l,pos.b,pos.r,pos.t}
                            local text = critterOfTheDay.flavour
                            WG['tooltip'].AddTooltip("Critter_Facts"..snapShotNumber,area,text,0.5,"Critter Details")
                        else
                            font:Print("No Living Critters Detected", pos.l + ((pos.r-pos.l)/2),pos.t-screenPositions.nature.rowHeight/2, fontSizeS, 'cvo')
                            WG['tooltip'].RemoveTooltip("Critter_Facts"..snapShotNumber)
                        end     
                    end
                end
            end
            if toggleTable["details"] and sagHighlight then
                local cumTotal = sagCompareTableStats[sagHighlight].cumTotal
                for lineCount, pos in ipairs(screenPositions.details.linePos) do
                    if lineCount == 1 then
                        font:Print("  Details", pos.l + ((pos.r-pos.l)/2), pos.t - screenPositions.details.rowHeight, fontSize, 'cvo')
                        font:Print("  Game Time", pos.l, pos.t - (screenPositions.details.rowHeight)/2, fontSizeS, 'lvo')
                    elseif lineCount == 2 then  --XXX i hav a miscount on the times on the bar, the first bar should be 0-15s, last should be up to the prveious 15 sec mark.
                        font:Print("  ("..SnapTimeToText((sagHighlight-1)*squishFactor).."-"..SnapTimeToText(sagHighlight*squishFactor)..")", pos.l, (pos.t - screenPositions.details.rowHeight/2), fontSizeS, 'lvo')
                    elseif lineCount >= 3 and lineCount < screenPositions.details.totalNumRows then
                        local key = lineCount-2
                        local teamID = sagCompareTableStats[sagHighlight].sortedTeamIDs[key]
                        if teamID then
                        local fraction = sagCompareTableStats[sagHighlight][teamID]
                            if fraction > 0 then
                                local value = NumberPrefix(fraction * cumTotal)
                                fraction = string.format("%.1f",fraction*100)
                                font:SetTextColor(teamColourCache[teamID])
                                font:Print(teamNamesCache[teamID], pos.l + screenPositions.details.columnWidth * 3  ,pos.t - (screenPositions.details.rowHeight/2)  , fontSizeS, 'rvos')
                                font:SetTextColor(1,1,1,1)
                                font:Print(" "..value, pos.l + screenPositions.details.columnWidth*3 ,pos.t - (screenPositions.details.rowHeight/2), fontSizeS, 'lvo')
                                font:Print(fraction.." %", pos.l + screenPositions.details.columnWidth*5 ,pos.t - (screenPositions.details.rowHeight/2), fontSizeS, 'cvo')
                            end
                        end
                    elseif lineCount == screenPositions.details.totalNumRows then
                        local numberText = NumberPrefix(cumTotal)
                        font:Print('\255\255\220\130'..numberText,pos.l + screenPositions.details.columnWidth*3 ,pos.t - (screenPositions.details.rowHeight/2), fontSizeS, 'lvo')
                        font:Print('\255\255\220\130'.."100 %",pos.l + screenPositions.details.columnWidth*5 ,pos.t - (screenPositions.details.rowHeight/2), fontSizeS, 'cvo')
                    end
                end
            end

                ---MileStones
            for lineCount, pos in ipairs(screenPositions.milestones.linePos) do
                if lineCount == 1 then
                    font:Print("Milestone Timings", pos.l + ((pos.r-pos.l)/2), pos.t - screenPositions.milestones.rowHeight, fontSize, 'cvo') --title
                elseif lineCount >=3 and WG['saghelper'].firstsWinnersList then

                    local category = milestonesCategoryNames[lineCount-2]
                    font:SetTextColor(1,1,1,1)
                    font:Print(category..": ", pos.l+ screenPositions.milestones.columnWidth*1.5,pos.t-screenPositions.milestones.rowHeight/2, fontSizeS, 'rvos') -- row headers


                    local data = WG['saghelper'].firstsWinnersList[category]
                    if data then
                        local teamID = data.teamID
                        local humanName = teamNamesCache[teamID]
                        if string.len(humanName) >= 14 then
                            humanName = string.sub(humanName,1,14).."..."
                        end
                        local sharedFromText = ""
                        if data.shared == true then
                            sharedFromText = "Shared by "..teamNamesCache[data.oldTeamID]
                        end
                        local text = ""
                        if category =="T2Factory" or category== "T2Constructor" then
                            text = humanName.." ("..data.timeText..")"
                        else
                            text = humanName.." ("..data.timeText..") -"..data.unitName.."\n"..sharedFromText
                        end
                            font:SetTextColor(teamColourCache[teamID][1],teamColourCache[teamID][2],teamColourCache[teamID][3],1)
                            font:Print(text, pos.l + screenPositions.milestones.columnWidth*1.5,pos.t-screenPositions.milestones.rowHeight/2, fontSizeS, 'lvo')

                    elseif milestonesResourcesList[category] then
                        data = milestonesResourcesList[category]
                        if data[1] == true then
                            local teamID = data[2]
                            local humanName = teamNamesCache[teamID]
                            if string.len(humanName) >= 14 then
                                humanName = string.sub(humanName,1,14).."..."
                            end 
                            font:SetTextColor(teamColourCache[teamID][1],teamColourCache[teamID][2],teamColourCache[teamID][3],1)
                            font:Print(humanName.." ("..data[3]..")", pos.l + screenPositions.milestones.columnWidth*1.5,pos.t-screenPositions.milestones.rowHeight/2, fontSizeS, 'lvo')
                        end 

                    end
                end
            end

            local relativeSize = {1, 0.95, 1, 1, 1}
            local relativeIntensity= {1, 1, 1, 0.5, 0.5}
            local medalColour = {{0.83, 0.69, 0.20},{0.75, 0.75, 0.8, 1},{0.8, 0.5, 0.2, 1},{0.5, 0.5, 0.5, },{0.5, 0.5, 0.5, 1}}
            --local teamIDLatest
            local teamID
            for lineCount, pos in ipairs(screenPositions.ranking.linePos) do
                if lineCount == 1 then
                    font:Print("Top Players", pos.l + ((pos.r-pos.l)/2), pos.t - screenPositions.ranking.rowHeight, fontSize, 'cvo')
                elseif lineCount == 2 then
                    --font:Print("Overall", pos.l + ((pos.r-pos.l)*1/3), pos.t - screenPositions.ranking.rowHeight, fontSizeS, 'cvo')
                    --font:Print("(Recent)", pos.l + ((pos.r-pos.l)*2/3), pos.t - screenPositions.ranking.rowHeight, fontSizeS, 'cvo')
                elseif lineCount >= 3 then
                    local rank = lineCount - 2
                    teamID = sagTeamTableStats[displayGraph].sortedCumRanks[rank]
                    -- if snapShotNumber >= 4 and sagTeamTableStats[displayGraph][snapShotNumber-1].ranks then
                    --     teamIDLatest = sagTeamTableStats[displayGraph].sortedCumRanksRecent[rank]--should return only the latest ranking xxx this isn't good enough as need to either use squish factor OR 60 secs 
                    -- end
                    if teamID then
                        local humanName = teamNamesCache[teamID]
                        if string.len(humanName) >= 10 and rank == 1 then
                            humanName = string.sub(humanName,1,18).."..."
                        end
                        font:SetTextColor(medalColour[rank])
                        font:Print((rank..suffix[rank]..":"), pos.l + (screenPositions.ranking.columnWidth * 2), pos.t-screenPositions.ranking.rowHeight/2 , (fontSize*relativeSize[rank]), 'rvos')
                        font:SetTextColor(teamColourCache[teamID][1],teamColourCache[teamID][2],teamColourCache[teamID][3],relativeIntensity[rank])
                        font:Print("  "..humanName, pos.l + (screenPositions.ranking.columnWidth * 2), pos.t-screenPositions.ranking.rowHeight/2 , (fontSizeS*relativeSize[rank]), 'lvo')
                    end
                    -- if teamIDLatest then
                    --     local humanName = teamNamesCache[teamIDLatest]
                    --     font:SetTextColor(teamColourCache[teamIDLatest][1],teamColourCache[teamIDLatest][2],teamColourCache[teamIDLatest][3],relativeIntensity[rank])
                    --     font:Print("("..(humanName..")"), pos.l + ((pos.r-pos.l)*(2/3)), pos.t-screenPositions.ranking.rowHeight/2 , (fontSize*relativeSize[rank]), 'cvo')
                    -- end
                end   
            end
            font:End()
        end)
    end

    if not drawButtonsForSelections then
        drawButtonsForSelections = gl_CreateList(function()
            --catergories (always on while graph is up) XXX need to add a bunch of IFs to select extrabutton colours.
            local colour = buttonColour[1]
            for number,data in ipairs(screenPositions.categories.linePos) do

                if data.name == displayGraph then
                    colour = buttonColour[1]
                    font:SetTextColor(0, 5, .2, 1)
                else
                    colour = buttonColour[2]
                    font:SetTextColor(0.92, 0.92, 0.92, 1)
                end
                UiButton(data.l,data.b,data.r,data.t, 1,1,1,1, 1,1,1,1, nil,colour[1],colour[2],2)
                font:Begin()
                font:Print(data.displayName, (data.l+data.r)/2,(data.b+data.t)/2, fontSize*.67, "cvo")
                font:End()
            end
            for number,data in ipairs(screenPositions.graphControlButtons.linePos) do
                local name = data.name

                if toggleTable[data.name] == true then --xxx need to update this for the extra buttons.
                    colour = buttonColour[1]
                    font:SetTextColor(0, 5, .2, 1)
                else
                    colour = buttonColour[2]
                    font:SetTextColor(0.92, 0.92, 0.92, 1)
                end
                UiButton(data.l,data.b,data.r,data.t, 1,1,1,1, 1,1,1,1, nil,colour[1],colour[2],2)
                font:Begin()
                font:Print(data.displayName, (data.l+data.r)/2,(data.b+data.t)/2, fontSize*.67, "cvo")
                font:End()
            end

            ---name selections (only on if compare selected?)
            if toggleTable["comparison"] then
                local colour = buttonColour[1]
                local intensity = 1
                for number, teamID in ipairs(teamIDsorted) do
                    if comparisonTeamIDs[teamID] then
                        colour = buttonColour[1]
                        intensity = 1
                    else
                        colour = buttonColour[2]
                        intensity = 0.2
                    end
                    UiButton(screenPositions.playerSelect.linePos[number].l,screenPositions.playerSelect.linePos[number].b + (boarderWidth/10),screenPositions.playerSelect.linePos[number].r,screenPositions.playerSelect.linePos[number].t - (boarderWidth/10), 1,1,1,1, 1,1,1,1, nil,colour[1],colour[2],2)
                    font:SetTextColor(teamColourCache[teamID][1],teamColourCache[teamID][2],teamColourCache[teamID][3],intensity)
                    local humanName = teamNamesCache[teamID]
                    font:Begin()
                    font:Print(humanName, (screenPositions.playerSelect.linePos[number].l+screenPositions.playerSelect.linePos[number].r)/2,(screenPositions.playerSelect.linePos[number].b+screenPositions.playerSelect.linePos[number].t)/2, fontSizeS, "cvos")
                    font:End()
                end
            end
        end)
    end
end

local function RankData(time,category)
    local cumTotal
    cumTotal = sagTeamTableStats[category][time].cumTotal
    if cumTotal < 0 then --values should never be negitive, but sometimes widget detect unittaken twice which could cause problems
        cumTotal = 0
    end
    if cumTotal > 0 then
        if cumTotal > sagTeamTableStats[category].largestCumTotal then
            sagTeamTableStats[category].largestCumTotal = cumTotal
        end

        local value = 0
        local rankingTable = {}
        for teamID,_ in pairs(teamAllyTeamIDs) do
            value = sagTeamTableStats[category][time][teamID]
            if value > 0 then
                rankingTable[teamID] = value
            end
        end

        local rankedTeamIDTable = {}
        for k in pairs(rankingTable) do    
            rankedTeamIDTable[#rankedTeamIDTable + 1] = k
        end
        table.sort(rankedTeamIDTable, function(a, b)
            return rankingTable[a] > rankingTable[b]
        end)
        for i=1,#rankedTeamIDTable do
            if rankedTeamIDTable[i] then
                if i <= 5 then
                    sagTeamTableStats[category]["cumRanks"][rankedTeamIDTable[i]] = sagTeamTableStats[category]["cumRanks"][rankedTeamIDTable[i]] + 6-i
                    sagTeamTableStats[category][time].ranks[rankedTeamIDTable[i]] = 6-i
                else
                    sagTeamTableStats[category][time].ranks[rankedTeamIDTable[i]] = 1
                end
            end
        end

        -- sagTeamTableStats[category]["cumRanksRecent"] = {}
        -- local temp_cumRanksRecent = {}
        -- if time > 4 then
        --     for i =0, 3 do
        --         local rankList = sagTeamTableStats[category][time-i].ranks
        --         for teamID, rankValue in pairs(rankList) do
        --             if not temp_cumRanksRecent[teamID] then
        --                 temp_cumRanksRecent[teamID] = rankValue
        --             else
        --                 temp_cumRanksRecent[teamID] = temp_cumRanksRecent[teamID] + rankValue --xxx still need to sort this.
        --             end
        --         end
        --     end
        --     sagTeamTableStats[category]["cumRanksRecent"]  = temp_cumRanksRecent
        -- end
    end
end

local function APMStatsExtract()
    local teamAPM = WG.teamAPM
    for teamID,APM in pairs(teamAPM) do
        if teamID ~=gaiaID and APM < 1800 then --APM on time 0 seems to be 1800, look into this.
            AddInfoToSagTable(teamID,"APM",APM,snapShotNumber)
        end
    end

    local teamfps = WG.playerFPS
    local fps = 0
    for teamID, _ in pairs (teamAllyTeamIDs) do
        if teamID ~=gaiaID then
            if teamfps[teamID] then 
                fps = teamfps[teamID]
            end
            AddInfoToSagTable(teamID,"FPS",fps,snapShotNumber)   
        end
    end

    RankData(snapShotNumber,"APM")
    RankData(snapShotNumber,"FPS")
end



local function CheckMilestones(stat, value, teamID,timePoint)
    if stat == "energyProduced" then
        local valuePerSec = value / 15 
        if milestonesResourcesList["500Energy"][1] == false and valuePerSec >= 500 then
            milestonesResourcesList["500Energy"] = {true,teamID,SnapTimeToText(timePoint)}
        end
        if milestonesResourcesList["1KEnergy"][1] == false and valuePerSec >= 1000 then
                milestonesResourcesList["1KEnergy"] = {true, teamID,SnapTimeToText(timePoint)}
        end
        if milestonesResourcesList["10KEnergy"][1] == false and valuePerSec >= 10000 then
                milestonesResourcesList["1KEnergy"] = {true,teamID,SnapTimeToText(timePoint)}
        end
    elseif stat == "damageDealt" then
        if milestonesResourcesList["50KDamage"][1] == false and value >= 50000 then
            milestonesResourcesList["50KDamage"] = {true,teamID,SnapTimeToText(timePoint)}
        end
        if milestonesResourcesList["100KDamage"][1] == false and value >= 100000 then
                milestonesResourcesList["100KDamage"] = {true,teamID,SnapTimeToText(timePoint)}
        end
        if milestonesResourcesList["500KDamage"][1] == false and value >= 500000 then
                milestonesResourcesList["500KDamage"] = {true,teamID,SnapTimeToText(timePoint)}
        end
    end
end

local function LatestStatsExtract(timePoint)
    for teamID,_ in pairs(teamAllyTeamIDs) do
        local twoTableTimePoints = Spring.GetTeamStatsHistory(teamID,timePoint-1,timePoint)
        if not twoTableTimePoints or #twoTableTimePoints ~=2 then
        else
            for stat,data in pairs(twoTableTimePoints[1]) do
                if trackedStats[stat] then
                    if stat == "damageDealt" then
                        CheckMilestones(stat,twoTableTimePoints[2][stat],teamID,timePoint)
                    end
                    local value = twoTableTimePoints[2][stat] - data
                    local lastValue = twoTableTimePoints[2][stat] --used for cumalitive total
                    AddInfoToSagTable(teamID, stat,value,timePoint)
                    if stat == "energyProduced" then
                        CheckMilestones(stat,value,teamID,timePoint)
                        AddInfoToSagTable(teamID, "energyProducedCum", lastValue,timePoint)
                    end
                    if stat == "damageDealt" then
                        CheckMilestones(stat,lastValue,teamID,timePoint)
                        AddInfoToSagTable(teamID, "damageDealtCum", lastValue,timePoint)
                    end
                    if stat == "metalProduced" then
                        AddInfoToSagTable(teamID, "metalProducedCum",lastValue,timePoint)
                    end
                end
            end
        end
    end

    if WG['saghelper'].masterStatTable and WG['saghelper'].masterStatTable[timePoint-1] then
        local sagHelperStats = WG['saghelper'].masterStatTable[timePoint-1] --this is a different format of list: list[snapshotnumber[teamID][caterogy] = value
            for teamID,data in pairs(sagHelperStats) do
                for stat,value in pairs (sagHelperStats[teamID]) do
                    if trackedStats[stat] then
                        AddInfoToSagTable(teamID, stat,value,timePoint)
                    end
                end
            end
        end

    for stat,_ in pairs(trackedStats) do
        RankData(timePoint,stat)
    end
end

local function CompleteStatsExtract()
    for i = 1, Spring.GetTeamStatsHistory(0)-1 do --all the snapshots in the game so far
        PrimeSagTable(i)
        LatestStatsExtract(i)
    end
    if Spring.GetTeamStatsHistory(0) > snapShotNumber then
        snapShotNumber = Spring.GetTeamStatsHistory(0) 
    end
end



local function DeleteLists(choice) --xxx need to decide how to show only some of these. related need to check blend settings to stop things changing on clicks/deletes etc.
    if drawStackedAreaGraphs then
        if choice == "all" or choice =="sag" or choice == "most" then
        gl_DeleteList(drawStackedAreaGraphs)
        drawStackedAreaGraphs = nil
        end
    end
    if drawStackedAreaGraphAxis then
        if choice == "all" or choice =="sag" or choice == "most" then
        gl_DeleteList(drawStackedAreaGraphAxis)
        drawStackedAreaGraphAxis = nil
        end
    end
    if drawButtonGraphs then
        if choice == "all" or choice =="button"  then
        gl_DeleteList(drawButtonGraphs)
        drawButtonGraphs = nil
        end
    end
    if drawButtonsForSelections then
        if choice == "all" or choice =="sag" or choice == "most" then
        gl_DeleteList(drawButtonsForSelections)
        drawButtonsForSelections = nil
        end
    end
    if drawFixedElements then
        if choice == "all" or choice =="sag" or choice == "most" then
        gl_DeleteList(drawFixedElements)
        drawFixedElements = nil
        end
    end
    if drawExtraStats then
        if choice == "all" or choice =="extra" or choice == "most" then
        gl_DeleteList(drawExtraStats)
        drawExtraStats = nil
        end
    end
    for i = 1, snapShotNumber do
        WG['tooltip'].RemoveTooltip("Critter_Facts"..i)
        WG['tooltip'].RemoveTooltip("sag_stat"..i)
        WG['tooltip'].RemoveTooltip("deforestation"..i)
        WG['tooltip'].RemoveTooltip("demineralisation"..i)
    end
end

local function RefreshLists(mode)
    mode = mode or "all"
    if mode == "all" then
        DeleteLists(mode)
        SortCumRanks(displayGraph)
        DetermineYAxisValues()
        DrawGraphToggleButton()
        DrawStackedAreaGraph()
        CreateExtraStatsText()
        DrawExtraStats()

    elseif mode == "sag" then
        DeleteLists(mode)
        SortCumRanks(displayGraph)
        DetermineYAxisValues()
        DrawGraphToggleButton()
        DrawStackedAreaGraph()

    elseif mode =="extra" then
        DeleteLists(mode)
        DrawGraphToggleButton()
        CreateExtraStatsText()
        DrawExtraStats()
    end
end

function widget:Initialize()
    CacheTeams()
    DeleteLists("all")
    UiElement = WG.FlowUI.Draw.Element
    RectRound = WG.FlowUI.Draw.RectRound
    bgpadding = WG.FlowUI.elementPadding
    font =  WG['fonts'].getFont()
    UiButton = WG.FlowUI.Draw.Button
    UISelector = WG.FlowUI.Draw.Selector

    spectator, fullview = Spring.GetSpectatingState()
    PrimeSagTable(1)
    local n = Spring.GetGameFrame()
    snapShotNumber = math.max(floor(((n-30) /450))+1,1)
    if toggleTable["squishFactor"] then
        squishFactor = ceil(snapShotNumber/squishFactorSetPoint)
    else
        squishFactor = 1
    end
    
    UpdateDrawingPositions("main")
    UpdateDrawingPositions("mainToggle")
    UpdateDrawingPositions("funStats")
    PrimeSagTable(snapShotNumber)
    DrawGraphToggleButton()
    if snapShotNumber > 1 then
        CompleteStatsExtract()
        CreateExtraStatsText()
    end
    if Spring.IsGameOver() then
        widget:GameOver()
    end
end

function widget:TextCommand(command)
    if string.find(command, "bug",nil,true) then
        if WG['topbar'] then
            local topBarPosition = WG['topbar'].GetPosition()
            Spring.Echo(topBarPosition)
        end
    end

    if string.find(command, "extra", nil, true) then
        if toggleTable["extraStats"] == false then
            toggleTable["extraStats"] = true
            toggleTable["graphSAG"] = false
            DeleteLists("all")
            drawer = true
            RefreshLists("extra")
            PlaySound("buttonclick")
        else
            toggleTable["extraStats"] = false
            drawer = false
            DeleteLists("all")
            DrawGraphToggleButton()
            PlaySound("buttonclick")
        end
    end
    if string.find(command, "graph", nil, true) then
        if toggleTable["graphSAG"] == false then
            toggleTable["graphSAG"] = true
            toggleTable["extraStats"] = false
            DeleteLists("all")
            drawer = true
            RefreshLists("all")
            PlaySound("buttonclick")
        else
            toggleTable["graphSAG"] = false
            drawer = false
            DeleteLists("all")
            DrawGraphToggleButton()
            PlaySound("buttonclick")
        end

    end

end




function widget:DrawScreen()
    if drawer and (gameOver == true or spectator == true) then
        if drawFixedElements then
            gl_CallList(drawFixedElements)
        end

        if drawStackedAreaGraphs  then
            gl_CallList(drawStackedAreaGraphs)  
        end

        if drawButtonsForSelections then
            gl_CallList(drawButtonsForSelections)
        end

        if drawStackedAreaGraphAxis then
            gl_CallList(drawStackedAreaGraphAxis)
        end
        if drawExtraStats then
            gl_CallList(drawExtraStats)
        end
    end

    if drawExtraStats then
        gl_CallList(drawExtraStats)
    end

    if drawButtonGraphs then
        gl_CallList(drawButtonGraphs)
    end
    -- if drawExtraStats then
    --     gl_CallList(drawExtraStats)
    -- end
end

function widget:GameFrame(n)

    if n == 1 and forceAINameCheck then --stupid bodge as AI names don't show up before first gameframe??
        for teamID,allyTeamID in pairs(teamAllyTeamIDs) do
            local aiName = Spring.GetGameRulesParam("ainame_" .. teamID)
            if aiName then
                teamNamesCache[teamID] = aiName.."(AI)"
            end
        end
    end

    if (n-30) % 450 == 0 then --one second after to allow for helper widget to do it's thing on n+1
        snapShotNumber = ((n-30) /450)+1
        if toggleTable["squishFactor"] then
            squishFactor = ceil(snapShotNumber/squishFactorSetPoint)
        else
            squishFactor = 1
        end
        screenPositions.graphs.columnWidth = (screenPositions.graphs.r -screenPositions.graphs.l) * squishFactor / snapShotNumber
        
        PrimeSagTable(snapShotNumber)

        if spectator or fullview or playerRestricMode == true then --xxx temp to debug, if i don't wish to show graphs during game then this part needs to be off for players.
            LatestStatsExtract(snapShotNumber)
            APMStatsExtract()
            SortCumRanks(displayGraph)
            DetermineYAxisValues()
            if #windList >0 and maxWind > 0 then
                CalculateGameWindAverage()
            end
        end
        CreateExtraStatsText() --xxx i will always calculate this as stats can be avalible during a game to a player?
    end
        

    if n >30 and (n-45) % 450 ==0 then --xxx do i need the first conditoinal??
    
        if toggleTable["critter"] == nil then
            CritterCheck()
        end

        DeleteLists("all")
        DrawGraphToggleButton()
        if toggleTable["extraStats"] then
            DrawExtraStats()
        end
        if toggleTable["graphSAG"] then
            DrawStackedAreaGraph()
        end
    end

    if n % windCheckInterval == 0 and maxWind > 0 then
        if n == 0 then
            windList[#windList + 1] = maxWind/2 --starting wind
        else
            windList[#windList + 1] = select(4,Spring.GetWind())
        end
    end

end

function widget:Shutdown()
    DeleteLists("all")
end

function widget:PlayerChanged()
    spectator, fullview = Spring.GetSpectatingState()
    if spectator and fullview then
        CompleteStatsExtract()
    end
end

function widget:ViewResize()
    vsx, vsy = Spring.GetViewGeometry()
end


local function isAbove(mx,my,box,button) ---xxx if button is true, then it needs to cycle through a list to get line number. if not, then it can return a col, row value based on linewidth and column width.
    if mx >= box.l and mx <=box.r and my >=box.b and my <=box.t then
        local columnNumber, rowNumber, lineNumber = nil,nil,nil
        if box.columnWidth then
            columnNumber = floor((mx - box.l) / box.columnWidth) + 1
        end
        if box.rowHeight then
            rowNumber = floor((my - box.t) / box.rowHeight)*-1 --counting top to bottom so inversed.
        end
        if columnNumber and rowNumber then
            lineNumber = (rowNumber - 1) * box.totalNumCols + columnNumber
        end

        return true, lineNumber, columnNumber, rowNumber
    else
        return false,lineNumber,columnNumber, rowNumber
    end
end

function widget:MousePress(mx, my, button) --xxx need to add a bool to each function, if all of them are false then hide everything (for when clicking off the screen)
    local clickedEmptySpace = false
    local bool, lineNumber, columnNumber, rowNumber = nil,nil,nil,nil

    if toggleTable["graphSAG"] then
        clickedEmptySpace = true

        bool, lineNumber, columnNumber, rowNumber = isAbove(mx,my,screenPositions.categories,true)
        if bool and lineNumber then
            if trackedStatsNames[lineNumber] then
                displayGraph = trackedStatsNames[lineNumber].name
                SortCumRanks(displayGraph)
                RefreshLists("sag")
                clickedEmptySpace = false
                PlaySound("buttonclick")
            end
        end

        bool, lineNumber, columnNumber, rowNumber = isAbove(mx,my,screenPositions.graphControlButtons,true)
        if bool and lineNumber then
            local name = screenPositions.graphControlButtons.linePos[lineNumber].name
            if toggleTable[name] ~=nil then
                if toggleTable[name] == false then
                    toggleTable[name] = true
                else
                    toggleTable[name] = false
                end
                RefreshLists("sag")
                clickedEmptySpace = false
                PlaySound("buttonclick")
            end
        end

        if toggleTable["comparison"] then
            bool, lineNumber, columnNumber, rowNumber = isAbove(mx,my,screenPositions.playerSelect,true)
            if bool and lineNumber then
                local teamID = teamIDsorted[lineNumber]
                if comparisonTeamIDs[teamID] then
                    comparisonTeamIDs[teamID] = false
                else
                    comparisonTeamIDs[teamID] = true
                end
                RefreshLists("sag")
                clickedEmptySpace = false
                PlaySound("buttonclick")
            end
        end

        bool, lineNumber,columnNumber, rowNumber = isAbove(mx,my,screenPositions.graphs,false)
        if bool and columnNumber then
            if (sagHighlight and sagHighlight == columnNumber) then
                toggleTable["details"] = false
                sagHighlight = false
            elseif columnNumber > snapShotNumber/squishFactor then
                toggleTable["details"] = false
                sagHighlight = false
            else
                sagHighlight = columnNumber
                toggleTable["details"] = true
                PlaySound("buttonclick")
            end
            RefreshLists("all")
            clickedEmptySpace = false
            
        end

        bool, lineNumber, columnNumber, rowNumber = isAbove(mx,my,screenPositions.ranking,true)
        if bool then
            clickedEmptySpace = false
        end

        bool, lineNumber, columnNumber, rowNumber = isAbove(mx,my,screenPositions.milestones,true)
        if bool then
            clickedEmptySpace = false
        end

        if toggleTable["details"] == false then
            bool, lineNumber, columnNumber, rowNumber = isAbove(mx,my,screenPositions.nature,true)
            if bool and rowNumber == 7 and critterOfTheDay.unitID then
                critterOfTheDay.pos = {Spring.GetUnitPosition(critterOfTheDay.unitID)}
                if critterOfTheDay.pos then
                    Spring.SetCameraTarget(critterOfTheDay.pos[1], critterOfTheDay.pos[2],critterOfTheDay.pos[3], 5)
                else
                    critterOfTheDay.name = critterOfTheDay.name.." ---RIP---"
                end
                clickedEmptySpace = false
                PlaySound("duck")
            elseif bool then
                clickedEmptySpace = false
            end
        else
            bool, lineNumber, columnNumber, rowNumber = isAbove(mx,my,screenPositions.details,true)
             if bool then
                clickedEmptySpace = false
            end
        end
    end

    if toggleTable["extraStats"] then
        clickedEmptySpace = true
        bool, lineNumber,columnNumber, rowNumber = isAbove(mx,my,screenPositions.funStatBox,false)
        if bool and rowNumber <=2 then
            if extraStatNames[columnNumber-2] then
                sortVar = extraStatNames[columnNumber-2].name
                RefreshLists("extra")
                PlaySound("buttonclick")
            end
            clickedEmptySpace = false      
        elseif bool and rowNumber == screenPositions.funStatBox.totalNumRows then
            if columnNumber <= #extraStatsTypeToDisplayList then 
                extraStatsTypeToDisplayCounter = columnNumber
            end
            RefreshLists("extra")
            clickedEmptySpace = false
            PlaySound("buttonclick")
        elseif bool == true then
            clickedEmptySpace = false
        end
    end


    bool, _,_,_ = isAbove(mx,my,screenPositions.GraphOnOffButton,nil)
    if bool then
        if toggleTable["graphSAG"] == false then
            toggleTable["graphSAG"] = true
            toggleTable["extraStats"] = false
            DeleteLists("all")
            drawer = true
            RefreshLists("all")
            PlaySound("buttonclick")
        else
            toggleTable["graphSAG"] = false
            drawer = false
            DeleteLists("all")
            DrawGraphToggleButton()
            PlaySound("buttonclick")
        end
        
    end

    bool, _,_,_ = isAbove(mx,my,screenPositions.StatsOnOffButton,nil)
    if bool then
        if toggleTable["extraStats"] == false then
            toggleTable["extraStats"] = true
            toggleTable["graphSAG"] = false
            DeleteLists("all")
            drawer = true
            RefreshLists("extra")
            PlaySound("buttonclick")
        else
            toggleTable["extraStats"] = false
            drawer = false
            DeleteLists("all")
            DrawGraphToggleButton()
            PlaySound("buttonclick")
        end
    end
    if clickedEmptySpace == true and toggleTable["graphSAG"] and sagHighlight then
        toggleTable["details"] = false
        sagHighlight = false
        RefreshLists("all")
    elseif clickedEmptySpace == true then
        DeleteLists("most")
        toggleTable["graphSAG"] = false
        toggleTable["extraStats"] = false
        drawer = false
    end
end

function widget:GameOver()
	gameOver = true
    playerRestricMode = false
    toggleTable["graphSAG"] = true
    CompleteStatsExtract()
    UpdateDrawingPositions("mainToggle")
    UpdateDrawingPositions("funStats")
    RefreshLists("all")
end

function widget:UnitFinished(unitID, unitDefID, teamID) --xxx need to check rez bots
    --Spring.Echo("unitfinsihed",unitID, unitDefID, teamID)
end



