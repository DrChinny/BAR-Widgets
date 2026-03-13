function widget:GetInfo()
    return {
      name      = "SAG",
      desc      = "Displaying Stacked Area Graphs",
      author    = "Mr_Chinny",
      date      = "Feb 2026",
      handler   = true,
      enabled   = true,
      layer = -5 --xxx must load be later than the advanced player list
    }
end
---sagTeamTableStats = [caterogy][snapShotNumber][teamID] = value. Also some cum totals

---Determine if the Data is cumiliative (eg resources earned entire game, from stats), or from an time instance (eg Army value at time = 45s, from gadget), and run appropiate function
---Table info needs to be for an instance, so if cumiliative, will need to subtract the previous time point.
---Functions needed to process totals from above tables into fractions for each allyteamID, and teamID as a specific time point.
---SAG tables for each tracked stat need to be created / ammended with the data from the latest time point.
---
---Types of Table: armyValue, DefenseValue, Economy Value, Damage, UnitsKilled, MetalIncome, EnergyIncome, Excess Metal, ExcessEnergy, Shared Resources, FPS, APM? 
---other inetersting stats. ping, pingspam, messages, most t1, most metal spent on unit type?
---display all (8?) grpahs at once small, click to expand one
---Ranking for standing army, porc, resource, sharer etc. score could be total area or 3,2,1 points per snamshot.
---Create the SAG.
---ability to unnormalise some of the charts (stretch based on the cumTotal), toggle option
---Need Team Colours / Captain colours (copy code)
---Can probably copy old function and adapt
---seperate into multipple bar charts for some of the caterogies
---Shader for efficency.
---Commander Deaths/rez
---Disable data gathering if not spec/fullview, enlable on game over
---Awards: first t2, first 500 energy, 1000 energy, 10000 energy, most wind built etc, first t3, other stats that can be interesting (prob req gadget)
---squish data together if more than (100?).
---Some stats need to be divided by frame (or over 15 seconds?) to make sense, some dont. I need a list to determine which and handle
---similar I need to be able to have human or translateable names for all titles, these can be in the same list as above.
---highest point a unit is, wind direction
---xxx bug - doesn't work right with AI players on init, perhaps need to do some things on frame 1 to ensure everything is loaded.
---copy gui_teamstats.lua viewresize to auto resize boarders etc
---xxx bug sort out the 1st bar to ensure it contains data, else it is blank. APM is fine, other data isn't
---xxx carefully choose if a stat is comitalitve, averaged per second or difference. may need to create some more categories or rename, eg metal produced -> metal income
---xxx add totals per team for the extra stats, need to only do this for 2 ally teams.
local floor, ceil = math.floor, math.ceil
local insert = table.insert
local antiSpam = 0
local sortVar = "T1Army"
--local teamColourToggle = false
local drawer = false
local gl_CreateList             = gl.CreateList
local gl_DeleteList             = gl.DeleteList
local gl_CallList               = gl.CallList
local glVertex                  = gl.Vertex
local glBeginEnd                = gl.BeginEnd
local glColor                   = gl.Color
local glLineWidth               = gl.LineWidth
local spGetTeamColor            = Spring.GetTeamColor
local UiElement
local RectRound
local bgpadding 
local elementCorner
local critterOfTheDay = {}
local enabledSAG = false --shows the bar chart. xxx add way to control this
local enableRanking = true --shows the extra three windows on right, rnaking, milestone, nature
local oddLineColour = {0.28,0.28,0.28,0.06}
local evenLineColour = {1,1,1,0.06}
local sortLineColour = {0.82,0.82,0.82,0.1}
--local sortLineColour = {0.82,0.82,0.82,0.4}
local suffix = {"st","nd","rd","th","th","th","th","th","th","th","th","th","th","th","th"}
local sagHighlight = nil
local screenPositions = {}
--local windGraphEnabled = true
--local comparisonToggle = false
--local extraStatsToggle = false
local seed = 0 -- dertermined seed to use for critterlist selection.
local windCheckInterval = 60
local minWind = Game.windMin
local maxWind = Game.windMax
local WindDescriptionText = {"None",0,"None",0}
local windDescriptionList = {"GALES!","Gusty","Average","Light","Becalmed"}
local windList = {} --list of last n windspeeds
local detailsToggle = false


local toggleTable = {teamColour = true, absolute = true, squishFactor = true, details = false, comparison = false, extraStats = false, graphButton = false, windGraph = true}


--local squishFactorToggle = true
local sortedTable = {}
local funStatsTypeToDisplayList = {{name="valueCurrent", typeName = "valueCurrentText", displayName="Value\nAlive"},{name="numberCurrent", typeName = "numberCurrent", displayName="Number\nAlive"},{name="valueMade", typeName = "valueMadeText", displayName="Value\nCreated"},{name="numberMade", typeName = "numberMade", displayName="number\nCreated"}}
local funStatsTypeToDisplayCounter = 1
local squishFactorSetPoint = 40 --max number of bars on the chart before we need to start averaging or ignoring results.
local squishFactor = 1 --Number of snapshots to squish and average into a single bar
local fontSize = 18
local fontSizeS = math.ceil(fontSize*.67)
local fontSizeL = math.ceil(fontSize * 2)
local vsx, vsy                  = Spring.GetViewGeometry()
local buttonGraphsOnOffPositionList         = {} --{Xl,Yb,Xr,Yt}
local buttonColour      = {{{1,1,1,0.3},{0.5,0.5,0.5,0.3}},{{0,0,0,0.3},{0.5,0.5,0.5,0.3}}} --on/off and blend
--local toggleButtonGraphs = false
local spectator, fullview = Spring.GetSpectatingState()
local font
local teamColourCache = {}
local allyTeamColourCache = {}
local teamNamesCache = {}
local teamAllyTeamIDs = {}
local teamIDsorted = {} --sorted teamID in an array from [1] = 0 to max
local snapShotNumber = 1 -- increases by 1 every 450 frames (15s). a value of 1 is at frame 0, a value of 2 is at frame 450 etc.
local sagTeamTableStats = {}
local sagCompareTableStats = {} --for current category only, with current camparison list
local comparisonTeamIDs = {}
local valuesOnYAxis = {"0","0","0"} --3 values to display on y Axis
local sizeX, sizeY, boarderWidth, screenRatio
local posXl, posXr, posYb, posYt
local milestonesResourcesNameSorted = {"50KDamage","100KDamage","500KDamage","500Energy", "1KEnergy","10KEnergy"}
local milestonesResourcesList ={}
for k, name in ipairs(milestonesResourcesNameSorted) do
    milestonesResourcesList[name] = {false,-1,"NONE"}
end
local numberOfAllyTeams = 0
local trackedStatsNames = { --format = {statname, Human Readable Name, bool of avg per second (1) or discrete (0), bool spare}. xxx link to translation
    {"damageDealt", "Damage \n Dealt",1,0,"Damage"},
    {"damageDealtCum", "Cum Damage \n Dealt",1,0,"Damage"},
    {"damageReceived", "Damage \n Received",1,0,"Damage"},
    {"energyExcess", "Energy \n Excess" , 1,0,"Energy"},
    {"energyProduced", "Energy \n Produced" , 1,0,"Energy"},
    {"energyProducedCum", "Cum Energy \n Produced" , 0,0,"Energy"},
    --{"energyReceived", "Energy \n Received" , 0,0,"Energy"},
    {"energySent", "Energy \n Sent" , 0,0,"Energy"},
    --{"energyUsed", "Energy \n Used" , 1, 0,"Energy"},
    {"metalExcess", "Metal \n Excess", 1, 0,"Metal"},
    {"metalProduced", "Metal \n Produced", 1, 0,"Metal"},
    {"metalProducedCum", "Cum Metal \n Produced", 0, 0,"Metal"},
    --{"metalReceived", "Metal \n Received", 1, 0,"Metal"},
    {"metalSent", "Metal \n Sent", 1, 0,"Metal"},
    --{"metalUsed", "Metal \n Used", 1, 0,"Metal"},
    {"unitsCaptured", "Units \n captured" , 0 ,0,"Units"},
    --{"unitsDied", "Units \n Died" , 0 ,1,"Units"},
    --{"unitsKilled", "Units \n Killed" , 0 ,0,"Units"},
    --{"unitsOutCaptured", "Units Out \n captured" , 0 ,0,"Units"},
    {"unitsProduced", "Units \n Produced" , 0 ,0,"Units"},
    --{"unitsReceived", "Units \n Received" , 0 ,0,"Units"},
    --{"unitsSent", "Unit \n Sent" , 0 ,0,"Units"},
    {"APM", "Actions \n per Min", 0 , 0, "APM"},
    {"FPS", "Frames \n per Sec" , 0 , 0,"FPS"},
    {"armyValue", "Standing \n Army Value",0,0,"Total Value"},
    {"defenseValue", "Defensive \n Structures",0,0,"Total Value"},
    {"utilityValue", "Utility \n Structures",0,0,"Total Value"},
    {"economyValue", "Economy \n Structures",0,0,"Total Value"},
    {"everything", "Everything \n Value ",0,0,"Total Value"},
}

local extraStatNames = {
    

    {name ="AllArmy", xxx = "armyUnitDefs", display = "1", displayName = "Army"},
    {name ="T1Army",xxx = "T1Army", display = "1", displayName = "T1 Army"},
    {name ="T2Army",xxx = "T2Army", display = "1", displayName = "T2 Army"},
    {name ="T3Army" ,xxx =  "T3Army", display = "1", displayName = "T3 Army"},
    {name ="AllDef", xxx = "defenseUnitDefs", display = "1", displayName = "Defense"},
    {name ="T1Defense", xxx = "T1Def", display = "1", displayName = "T1\nDefense"},
    {name ="T2Defense",xxx = "T2Def", display = "1", displayName = "T2\nDefense"},
    {name ="T2ArmyTime",xxx =  "T2Army", display = "time", displayName = "T2 Army\nTime"},
    {name ="T3ArmyTime",xxx =  "T3Army", display = "time", displayName = "T3 Army\nTime"},
    {name ="lltNumber" ,xxx = "llt", display = "1", displayName = "Custom\nLLT"},
    {name ="windNumber",xxx = "wind", display = "1", displayName = "Custom\nWind"},

}

local milestonesCategoryNames = { --xxx need to creat this list on the go
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
--local extraButtons = {"Absolute","Team Colours","WindSpeed Overlay","Compare"}
local extraButtons = {
    {name = "absolute", displayName = "Absolute"},
    {name = "teamColour", displayName = "Team Colours"},
    {name = "windGraph", displayName = "WindSpeed Overlay"},
    {name = "comparison", displayName = "Compare"}
}
local trackedStats = {}
for _,data in ipairs(trackedStatsNames) do
    trackedStats[data[1]] = {formattedName = data[2],perSecBool=data[3],spareBool = data[4], spareName = data[5]}
end

local drawExtraStats
local displayGraph = "energyProduced"
local drawStackedAreaGraphs
local drawStackedAreaGraphAxis
local drawButtonGraphs
local drawButtonsForSelections
local drawFixedElements
local gaiaID = Spring.GetGaiaTeamID()

local function Seed(playerID)
    local customtable = select(11, Spring.GetPlayerInfo(playerID))
    if customtable.accountid and customtable.skilluncertainty then
        seed = math.floor(customtable.accountid/customtable.skilluncertainty) or 1
        return seed
    else
        return 1
    end
end


local function MakePolygonMap(x1,y1,x2,y2) --note i need to start in topleft corner and go round.
    glVertex(x1,y1)
	glVertex(x2,y1)
    glVertex(x2,y2)
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
        text = string.format("%.2f",(value)/1000000000).."G" --xxx nothing will go above this??
    end
    return text
end

local function CacheTeams() -- get all the teamID / Ally Team ID captains and colours once, and cache.
    numberOfAllyTeams = -1 --need to remove gaia, which will always be present? xxx
    for _, allyTeamID in ipairs(Spring.GetAllyTeamList()) do
        local lowest_teamID = 1023
        for _, teamID in ipairs(Spring.GetTeamList(allyTeamID)) do
            if teamID < lowest_teamID then
                lowest_teamID = teamID
            end
            if gaiaID ~= teamID then
                table.insert(teamIDsorted,teamID)
                teamAllyTeamIDs[teamID] = allyTeamID    
            end
        end

        
        for _, teamID in ipairs(Spring.GetTeamList(allyTeamID)) do
            allyTeamColourCache[teamID] = {Spring.GetTeamColor(lowest_teamID)}
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
            local aiName = Spring.GetGameRulesParam("ainame_" .. teamID)
            if aiName then-- it's AI
                playerName = aiName
            else-- player is gone
                playerName = "(gone)"
            end
        end
        comparisonTeamIDs[teamID] = true
        teamColourCache[teamID] = {Spring.GetTeamColor(teamID)}
        teamNamesCache[teamID] = playerName
        extraStatsTable[teamID] = {}
        for _,data in ipairs(extraStatNames) do
            extraStatsTable[teamID][data.name] = {numberCurrent = 0,valueCurrent=0,numberMade=0 ,valueMade=0, timeText = "None",}
            if not extraStatsTableAlly[allyTeamID] then
                extraStatsTableAlly[allyTeamID] = {}
            end
            if not extraStatsTableAlly[allyTeamID][data.name] then
                extraStatsTableAlly[allyTeamID][data.name] = {numberCurrent = 0,valueCurrent=0,numberMade=0 ,valueMade=0, timeText = "None",valueCurrentText=0,valueMadeText=0}
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
    Spring.Echo("debug3")
    local critterList = {}
    if WG['saghelper'].critterList then
        for key,list in ipairs(WG['saghelper'].critterList) do
            critterList[key] = list
        end
    end
    Spring.Echo("debug4")
    if #critterList > 0 and not critterOfTheDay.unitID then
        if seed == 0 then
            seed = Seed(0) % #critterList + 1
            Spring.Echo("seed",seed,#critterList)
        end
        
        critterOfTheDay = critterList[seed]
        critterOfTheDay.name = string.gsub(critterOfTheDay.name,"critter_","")
        critterOfTheDay.alive = true
        critterOfTheDay.pos = {Spring.GetUnitPosition(critterOfTheDay.unitID)}
        if Spring.GetUnitHealth(critterOfTheDay.unitID) ==nil then
            critterOfTheDay.alive = false
            critterOfTheDay.name = critterOfTheDay.name.." ---RIP---"
            critterOfTheDay.pos = nil
        end
        if critterOfTheDay.flavour ==nil then
            critterOfTheDay.flavour = ""
            local flavour = {}
            local flavourCategories = {"Name","Age","Gender","Hobbies","Children"}
            local flavourCategoriesList = {}
            flavourCategoriesList.Name = {"Bobby","Alex","Sam","Gurt"}
            flavourCategoriesList.Age = {"Child","adolescent","Young Adult","Middle Aged","Elderly"}
            flavourCategoriesList.Gender = {"Male","Female","Other","Prefer not to say"}
            flavourCategoriesList.Hobbies = {"Frolicking","Questing","Gaming","Improvisational comedy","Reading"}
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
    Spring.Echo("sortCategory",sortVar)
    local tempTable = {}
    for teamID, teamAllyTeamID in pairs(teamAllyTeamIDs) do
        if not tempTable[teamAllyTeamID] then
            tempTable[teamAllyTeamID] = {}
        end
        tempTable[teamAllyTeamID][teamID] = extraStatsTable[teamID][sortVar][funStatsTypeToDisplayList[funStatsTypeToDisplayCounter].name] or extraStatsTable[teamID][sortVar].valueCurrent
    end
    sortedTable = {}
    for teamAllyTeamID, list1 in pairs(tempTable) do
        local list2 = {}
        for k,v in pairs(list1) do    
            list2[#list2+1] = k
        end
        table.sort(list2, function(a, b)
            if type(list1[a]) == "string" then
                Spring.Echo("string error",list1[a],list1[b])
            end
            return list1[a] > list1[b]
        end)
        sortedTable[teamAllyTeamID] = list2
    end
end



local function CreateExtraStatsText()
    for teamID,allyTeamID in pairs(teamAllyTeamIDs) do
        for _,data in ipairs(extraStatNames) do
            extraStatsTableAlly[allyTeamID][data.name] = {numberCurrent = 0,valueCurrent=0,numberMade=0 ,valueMade=0, timeText = "None",valueCurrentText=0,valueMadeText=0}
        end
    end
    if WG['saghelper'].trackedFunStats then
        local trackedFunStats
        for _, teamID in ipairs(teamIDsorted) do
            trackedFunStats = WG['saghelper'].trackedFunStats[teamID]
            local allyteamID = teamAllyTeamIDs[teamID]
            for key, extraStatNamesTable in ipairs(extraStatNames) do
                local category = extraStatNamesTable.name
                local data = trackedFunStats[extraStatNamesTable.xxx]
                if data and extraStatsTable[teamID][category] then
                    extraStatsTable[teamID][category] = {
                        numberCurrent = data.numberCurrent or 0,
                        numberMade=data.numberMade or 0,
                        valueCurrentText=NumberPrefix(data.valueCurrent or 0),
                        valueCurrent=(data.valueCurrent or 0),
                        valueMade=data.valueMade or 0,
                        valueMadeText=NumberPrefix(data.valueMade or 0),
                        timeText = data.timeText or "None", --xxx maybe move the time formatting to this widget
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
                        extraStatsTableAlly[allyteamID][category].valueCurrentText = NumberPrefix(extraStatsTableAlly[allyteamID][category].valueCurrent or 0)
                        extraStatsTableAlly[allyteamID][category].valueMadeText = NumberPrefix(extraStatsTableAlly[allyteamID][category].valueMade or 0)

                    end
                end
            end
        end
        SortExtraStats()
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

    local temp_cumRanksRecent = sagTeamTableStats[stat]["cumRanksRecent"]
    --Spring.Echo("temp_cumRanksRecent",temp_cumRanksRecent)

    if snapShotNumber > 4 and #sagTeamTableStats > 3 then
        for k,v in pairs(temp_cumRanksRecent) do    
            if v > 0 then
                sagTeamTableStats[stat].sortedCumRanksRecent[#sagTeamTableStats[stat].sortedCumRanksRecent + 1] = k
            end
        end
        table.sort(sagTeamTableStats[stat].sortedCumRanks, function(a, b)
            return temp_cumRanksRecent[a] > temp_cumRanksRecent[b]
        end)
    end
    
    -- if detailsToggle and sagCompareTableStats[sagHighlight] then
    --     sagCompareTableStats[sagHighlight].highlightSorted = 



end

local function UpdateDrawingPositions(updateName) ---need to run on viewchange etc XXX
    --main toggle button
    if updateName == "mainToggle" then
        local playerListTop,playerListLeft, playerListBottom,playerListRight,playerListPos
        if WG.displayinfo ~= nil or WG.unittotals ~= nil or WG.music ~= nil or WG['advplayerlist_api'] ~= nil then
            if WG.displayinfo ~= nil then
                playerListPos = WG.displayinfo.GetPosition()
                if playerListPos[1] < 100 then
                    playerListPos = {  504, 1508,476,1927,1.22938764,}
                end 
            elseif WG.unittotals ~= nil then
                playerListPos = WG.unittotals.GetPosition()
            elseif WG.music ~= nil then
                playerListPos = WG.music.GetPosition()
            elseif WG['advplayerlist_api'] ~= nil then
                playerListPos = WG['advplayerlist_api'].GetPosition()
            end
            if playerListPos then
                playerListTop,playerListLeft, playerListBottom,playerListRight = playerListPos[1],playerListPos[2],playerListPos[3],playerListPos[4]
            end
        else
            Spring.Echo("no advplayerlist_api detected")
            playerListTop,playerListLeft = vsy/2, (vsx-100)
        end

        local X, Y = 150,40
        buttonGraphsOnOffPositionList = {l = playerListLeft, b = playerListTop, r = playerListLeft + X, t = playerListTop + Y}
    end

    --All fixed parts of main display (Boarder for each area, X and Y axis blips) since these are all relative to main boarder.
    if updateName == "main" then
        sizeX, sizeY = vsx/3.5,vsy/2 --xxx x and y offset need to be relative to either screen size or another widget
        screenRatio = 1 --xxx this needs to be set according to the screen resolution. maybe can remove as now I as a ratio of vsx and vsy?
        boarderWidth = 20 * screenRatio

        posXl = ((vsx/3) - boarderWidth) * screenRatio
        posYb = ((vsy/5) - boarderWidth) * screenRatio
        posXr = ((vsx/3) + sizeX + boarderWidth) *screenRatio
        posYt = ((vsy/5) + sizeY + boarderWidth) * screenRatio
        
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



        --positionListLinesForRankingPositions = {}
        --local totalNumRows = 7
        screenPositions.ranking = {}
        screenPositions.ranking = {
            l = posXr + boarderWidth,               --left
            b = posYt - (sizeY / 3),              --btm
            r = posXr + boarderWidth + (sizeX / 2), --right
            t = posYt,
            columnWidth  = 1,    --top
            rowHeight = 1,   -- ((sizeY / 3)) * 1 / totalNumRows,
            totalNumRows = 7,
            totalNumCols = 1,
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
            l = posXr + boarderWidth,                   --left
            b = screenPositions.ranking.b - boarderWidth - (sizeY / 3),                                  --btm
            r = posXr + boarderWidth + (sizeX / 2),     --right
            t = screenPositions.ranking.b - boarderWidth,   --top
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


        --positionListLinesForNature = {}
        --totalNumRows = 8 
        screenPositions.nature = {
            l = posXr + boarderWidth,                   --left
            b = screenPositions.milestones.b - boarderWidth - (sizeY / 3),                                  --btm
            r = posXr + boarderWidth + (sizeX / 2),     --right
            t = screenPositions.milestones.b - boarderWidth,   --top
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

        screenPositions.extraButtons = {
            l = posXl,                              --left, x1
            b = posYb - (sizeY / 4),                --btm, y1
            r = posXl + (sizeX *1/4),                              --right, x2
            t = posYb - boarderWidth,               --top, y2
            columnWidth  = 1,
            rowHeight = 1,
            totalNumRows = 4,
            totalNumCols = 1,
            linePos = {}
        }
        screenPositions.extraButtons.columnWidth = (screenPositions.extraButtons.r - screenPositions.extraButtons.l) / screenPositions.extraButtons.totalNumCols
        screenPositions.extraButtons.rowHeight = (screenPositions.extraButtons.t -screenPositions.extraButtons.b) / screenPositions.extraButtons.totalNumRows
        for number,list in ipairs(extraButtons) do
            screenPositions.extraButtons.linePos[number] = {l=screenPositions.extraButtons.l, b=(screenPositions.extraButtons.t)-(screenPositions.extraButtons.rowHeight*(number)),r=screenPositions.extraButtons.l + screenPositions.extraButtons.columnWidth, t=(screenPositions.extraButtons.t)-(screenPositions.extraButtons.rowHeight*(number-1)),name=list.name, displayName = list.displayName}
        end

        screenPositions.categories = {
            l = screenPositions.extraButtons.r + boarderWidth/4,                            --left, x1
            b = posYb - (sizeY / 4),                --btm, y1
            r = posXr,                              --right, x2
            t = posYb - boarderWidth,               --top, y2
            columnWidth  = 1,
            rowHeight = 1,
            totalNumRows = 4,
            totalNumCols = 6,
            linePos = {}
        }
        screenPositions.categories.columnWidth = (screenPositions.categories.r - screenPositions.categories.l) / screenPositions.categories.totalNumCols
        screenPositions.categories.rowHeight = (screenPositions.categories.t -screenPositions.categories.b) / screenPositions.categories.totalNumRows




        --buttons for caterogies
        --local sizeXButton,sizeYButton = 50,10 --xxx need to be relative to something.

        --sizeYButton = (screenPositions.categories.t - screenPositions.categories.b) / screenPositions.categories.totalNumRows
        --sizeXButton = (screenPositions.categories.r - screenPositions.categories.l) / screenPositions.categories.totalNumCols
        local column,row = 0,0
        for number, data in ipairs(trackedStatsNames) do --makes a 6x4 array for 24 catergories.
        column = ((number-1) % screenPositions.categories.totalNumCols) + 1
            if (number-1) % screenPositions.categories.totalNumCols == 0 then
                row = row + 1
            end
            screenPositions.categories.linePos[number] = {l=(screenPositions.categories.l + ((column-1)*screenPositions.categories.columnWidth)),b=(screenPositions.categories.t)-(screenPositions.categories.rowHeight*(row)),r=(screenPositions.categories.l + ((column)*screenPositions.categories.columnWidth)),t=(screenPositions.categories.t)-(screenPositions.categories.rowHeight*(row-1)), displayName=trackedStats[data[1]].formattedName, name=data[1] }
        end
        


        --positionListButtonsForPlayerSelections = {}
        screenPositions.playerSelect = {
            l = posXl - boarderWidth - (sizeX / 6),
            b = posYb,
            r = posXl - boarderWidth,
            t = posYt,
            columnWidth  = 1,
            rowHeight = 1,
            totalNumRows = #teamIDsorted,
            totalNumCols = 1,
            linePos={}
        }
        screenPositions.playerSelect.columnWidth = (screenPositions.playerSelect.r - screenPositions.playerSelect.l) / screenPositions.playerSelect.totalNumCols
        screenPositions.playerSelect.rowHeight = (screenPositions.playerSelect.t -screenPositions.playerSelect.b) / screenPositions.playerSelect.totalNumRows

        local sizeYButton = (posYt-posYb) / #teamIDsorted
        local sizeXButton = (posXr-posXl) - boarderWidth
        for number, teamID in ipairs(teamIDsorted) do
            screenPositions.playerSelect.linePos[number] = { l=(screenPositions.playerSelect.l + boarderWidth), b=(screenPositions.playerSelect.t - (sizeYButton*(number-1)) - sizeYButton), r=(screenPositions.playerSelect.r-(boarderWidth)),t=(screenPositions.playerSelect.t - boarderWidth - (sizeYButton*(number-1)))}
        end

        screenPositions.details = { --this is in the same window as nature for now.
            l = screenPositions.nature.l,   --left
            b = screenPositions.nature.b,   --btm
            r = screenPositions.nature.r,   --right
            t = screenPositions.nature.t,   --top
            rowHeight = 1,
            columnWidth = 1,
            totalNumRows = #teamIDsorted + 2,--xxx need to relate this to a list length
            totalNumCols = 6,
            linePos = {}
        }
        screenPositions.details.rowHeight = (screenPositions.details.t - screenPositions.details.b) / screenPositions.details.totalNumRows
        screenPositions.details.columnWidth = (screenPositions.details.r - screenPositions.details.l) / screenPositions.details.totalNumCols

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
            l = posXl,
            b = posYb,
            r = posXr + boarderWidth + (sizeX / 2),
            t = posYt,
            -- rowHeight = (posYt - posYb) * 1 / totalNumRows,
            -- columnWidth = ((posXr + boarderWidth + (sizeX / 2))-posXl) / (#extraStatNames+2),
            totalNumRows = #teamIDsorted + 2 + (numberOfAllyTeams*2) + 1, --2 for headers, 1 for btm buttons
            totalNumCols = #extraStatNames+2, --xxx update this to the number of stats displayed + name column
            linePos = {}
        }

            screenPositions.funStatBox.rowHeight = (screenPositions.funStatBox.t - screenPositions.funStatBox.b) / screenPositions.funStatBox.totalNumRows
            screenPositions.funStatBox.columnWidth = (screenPositions.funStatBox.r - screenPositions.funStatBox.l) / screenPositions.funStatBox.totalNumCols

        --positionListLinesForFunStats = {}
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


--xxx add sound
local function DrawExtraStats()
    gl_DeleteList(drawExtraStats)
    drawExtraStats = nil
    if toggleTable["extraStats"] then
        drawExtraStats = gl_CreateList(function()
            local typeToDisplay = funStatsTypeToDisplayList[funStatsTypeToDisplayCounter]
            UiElement(screenPositions.funStatBox.l ,screenPositions.funStatBox.b,screenPositions.funStatBox.r,screenPositions.funStatBox.t,1,1,1,1, 1,1,1,1, .5, {0,0,0,0.5},{1,1,1,0.05},2) --xxx this 2 is boarder width
            font:Begin()

            for lineCount, pos in ipairs(screenPositions.funStatBox.linePos) do --lines, buttons
                RectRound(pos.l, pos.b, pos.r, pos.t, bgpadding, 0,0,0,0, {pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7},{pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*3*0.7} ) --xxx replace all these 0.7 with ui_opacity
                if lineCount == screenPositions.funStatBox.totalNumRows then
                    for i = 1, #funStatsTypeToDisplayList do
                        UiButton(pos.l + ((i-1)*screenPositions.funStatBox.columnWidth), pos.b, (pos.l + ((i)*screenPositions.funStatBox.columnWidth)), pos.t)
                        if funStatsTypeToDisplayList[i].name == typeToDisplay.name then
                            font:SetTextColor(0, 5, .2, 1)
                        else
                            font:SetTextColor(1, 1, 1, 1)
                        end
                        font:Print(funStatsTypeToDisplayList[i].displayName,pos.l + ((i-1)*screenPositions.funStatBox.columnWidth)+(screenPositions.funStatBox.columnWidth/2),pos.t-((pos.t-pos.b)/2) , fontSizeS, "cvos")
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
                font:Print(text, screenPositions.funStatBox.l+((k+2) * screenPositions.funStatBox.columnWidth) - (screenPositions.funStatBox.columnWidth/2),screenPositions.funStatBox.t - screenPositions.funStatBox.rowHeight , fontSizeS, "cvos")
            end

            local linenumber = 1
            local text = ""
            
            font:Print("Player", screenPositions.funStatBox.l + screenPositions.funStatBox.columnWidth,screenPositions.funStatBox.t - screenPositions.funStatBox.rowHeight , fontSizeS, "cvos")
            for allyTeamID, sortedTeamIDTable in pairs (sortedTable) do --need to get allteamid in order using i=1,i=#allyteamidsorted
                for key, teamID in ipairs(sortedTeamIDTable) do

                    font:SetTextColor(teamColourCache[teamID][1],teamColourCache[teamID][2],teamColourCache[teamID][3],1)
                    font:Print(teamNamesCache[teamID], screenPositions.funStatBox.l+ screenPositions.funStatBox.columnWidth,screenPositions.funStatBox.t - ((linenumber+1.5) * screenPositions.funStatBox.rowHeight), fontSizeS, "cvos")
                    font:SetTextColor(1,1,1,1)
                    for k, data in ipairs(extraStatNames) do
                    local category = data.name
                    text = (extraStatsTable[teamID][category])
                        if text.valueCurrentText and data.display == "1" then
                            if typeToDisplay then
                                font:Print(text[typeToDisplay.typeName], screenPositions.funStatBox.l+((k+2) * screenPositions.funStatBox.columnWidth) - (screenPositions.funStatBox.columnWidth/2), posYt - ((linenumber+1.5) * screenPositions.funStatBox.rowHeight), fontSizeS, "cvos")
                            end
                        elseif data.display == "time" then
                            font:Print(text.timeText, screenPositions.funStatBox.l+((k+2) * screenPositions.funStatBox.columnWidth) - (screenPositions.funStatBox.columnWidth/2), posYt - ((linenumber+1.5) * screenPositions.funStatBox.rowHeight), fontSizeS, "cvos")
                        else
                            font:Print("None", screenPositions.funStatBox.l+((k+2) * screenPositions.funStatBox.columnWidth) - (screenPositions.funStatBox.columnWidth/2), posYt - ((linenumber+1.5) * screenPositions.funStatBox.rowHeight), fontSizeS, "cvos")
                        end
                    end
                    linenumber= linenumber +1
                end
                font:SetTextColor(1,1,1,1)
                for k, data in ipairs(extraStatNames) do
                    local category = data.name
                    if typeToDisplay and data.display == "1" then
                        text = extraStatsTableAlly[allyTeamID][category][typeToDisplay.typeName]
                        font:Print('\255\255\220\130'..text, screenPositions.funStatBox.l +((k+2) * screenPositions.funStatBox.columnWidth) - (screenPositions.funStatBox.columnWidth/2), posYt - ((linenumber+1.5) * screenPositions.funStatBox.rowHeight), fontSizeS, "cvos")
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
        if toggleTable["graphButton"] then
            colour = buttonColour[1]
            font:SetTextColor(1, 1, 1, 1)
        else
            colour = buttonColour[2]
            font:SetTextColor(0.92, 0.92, 0.92, 1)
        end
        UiButton(buttonGraphsOnOffPositionList.l,buttonGraphsOnOffPositionList.b,buttonGraphsOnOffPositionList.r,buttonGraphsOnOffPositionList.t, 1,1,1,1, 1,1,1,1, nil,colour[1],colour[2],2)
        font:Begin()
        font:Print("Graphs", buttonGraphsOnOffPositionList.l+((buttonGraphsOnOffPositionList.r-buttonGraphsOnOffPositionList.l)/2),buttonGraphsOnOffPositionList.b+((buttonGraphsOnOffPositionList.t-buttonGraphsOnOffPositionList.b)/2)+fontSize/3, fontSize*0.67, "cvos")
        font:End()
    end)
end

local function DrawStackedAreaGraph()
    if not drawFixedElements then
        drawFixedElements = gl_CreateList(function()

            UiElement(posXl ,posYb,posXr,posYt,1,1,1,1, 1,1,1,1, .5, {0,0,0,0.5},{1,1,1,0.05},boarderWidth) --graph display element
            UiElement(screenPositions.categories.l ,screenPositions.categories.b,screenPositions.categories.r,screenPositions.categories.t,1,1,1,1, 1,1,1,1, .5, {0,0,0,0.5},{1,1,1,0.05}) --category display element
            UiElement(screenPositions.extraButtons.l,screenPositions.extraButtons.b,screenPositions.extraButtons.r,screenPositions.extraButtons.t,1,1,1,1, 1,1,1,1, .5, {0,0,0,0.5},{1,1,1,0.05})
            if enableRanking then
                UiElement(screenPositions.ranking.l ,screenPositions.ranking.b,screenPositions.ranking.r,screenPositions.ranking.t,1,1,1,1, 1,1,1,1, .5, {0,0,0,0.5},{1,1,1,0.05},2) --ranking display element
                for lineCount, pos in ipairs(screenPositions.ranking.linePos) do
                    if lineCount <=2 then
                        RectRound(pos.l, pos.b, pos.r, pos.t, bgpadding, 0,0,0,0, {pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7},{pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7} )
                    else
                        RectRound(pos.l, pos.b, pos.r, pos.t, bgpadding, 0,0,0,0, {pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7},{pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*3*0.7} ) --xxx replace all these 0.7 with ui_opacity
                    end
                end

                UiElement(screenPositions.milestones.l ,screenPositions.milestones.b, screenPositions.milestones.r,screenPositions.milestones.t,1,1,1,1, 1,1,1,1, .5, {0,0,0,0.5},{1,1,1,0.05},2) --Award display element
                for lineCount, pos in ipairs(screenPositions.milestones.linePos) do
                    if lineCount <=2 then
                        RectRound(pos.l, pos.b, pos.r, pos.t, bgpadding, 0,0,0,0, {pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7},{pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7} )
                    else
                        RectRound(pos.l, pos.b, pos.r, pos.t, bgpadding, 0,0,0,0, {pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7},{pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*3*0.7} ) --xxx replace all these 0.7 with ui_opacity
                    end
                end

                UiElement(screenPositions.nature.l ,screenPositions.nature.b, screenPositions.nature.r,screenPositions.nature.t,1,1,1,1, 1,1,1,1, .5, {0,0,0,0.5},{1,1,1,0.05},2) --Nature display element
                for lineCount, pos in ipairs(screenPositions.nature.linePos) do
                    if lineCount <=2 then
                        RectRound(pos.l, pos.b, pos.r, pos.t, bgpadding, 0,0,0,0, {pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7},{pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7} )
                    else
                        RectRound(pos.l, pos.b, pos.r, pos.t, bgpadding, 0,0,0,0, {pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*0.7},{pos.colour[1],pos.colour[2],pos.colour[3],pos.colour[4]*3*0.7} ) --xxx replace all these 0.7 with ui_opacity
                    end
                end
            end

            if toggleTable["comparison"] then
                UiElement(screenPositions.playerSelect.l ,screenPositions.playerSelect.b, screenPositions.playerSelect.r, screenPositions.playerSelect.t,1,1,1,1, 1,1,1,1, .5, {0,0,0,0.5},{1,1,1,0.05},boarderWidth/2) --player select element
            end

        end)
    end

    if not drawStackedAreaGraphs then ---SAG bars and Winds plot (if enabled)
        drawStackedAreaGraphs = gl_CreateList(function()

            ---SAG bars---
            local x1 ,x2, y1, y2
            if enabledSAG then
                local scaleX = sizeX / screenRatio
                local scaleY = sizeY / screenRatio
                local absScaleFactor = 1 --Value of 1 will allow the graph elements to stretch to the very top of y axis, <1 will squish.
                if snapShotNumber > 0 then
                scaleX = squishFactor * sizeX / snapShotNumber
                end
                local largestCumTotal = sagCompareTableStats.largestCumTotal
                local tooltipText = ""


                for timePoint,data in pairs (sagCompareTableStats) do
                    tooltipText = ""
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
                            if fraction > 0 then
                                tooltipText = tooltipText..teamNamesCache[teamID]..": "..NumberPrefix(data[teamID]*data.cumTotal).."\n"
                            end
                            --x1 = posXl + boarderWidth + ((timePoint - 1) * scaleX)
                            --x2 = posXl + boarderWidth + ((timePoint - 0) * scaleX)
                            x1 = screenPositions.graphs.l + ((timePoint - 1) * scaleX)
                            x2 = screenPositions.graphs.l + ((timePoint - 0) * scaleX)
                            y1 = screenPositions.graphs.b + (sizeY - (cumFraction * scaleY)) * absScaleFactor
                            --y1 = posYb + boarderWidth + (sizeY - (cumFraction * scaleY)) * absScaleFactor
                            cumFraction = cumFraction + fraction
                            y2 = screenPositions.graphs.b + (sizeY - (cumFraction * scaleY)) * absScaleFactor
                            --y2 = posYb + boarderWidth + (sizeY - (cumFraction * scaleY)) * absScaleFactor
                            local colour = {1,1,1,1}
                            if toggleTable["teamColour"] then
                                colour = allyTeamColourCache[teamID]
                                -- if timePoint == sagHighlight then
                                --     colour[4] = 1
                                -- end
                                    --glColor(colour[1],colour[2],colour[3],colour[4])
                            else
                                colour = teamColourCache[teamID]
                            end
                            colour[4] = 0.67
                            if timePoint == sagHighlight then
                                colour[4] = 1
                            end
                            glColor(colour[1],colour[2],colour[3],colour[4])
                            glBeginEnd(GL.POLYGON,MakePolygonMap, x1,y1,x2-1,y2)
                        end
                    end
                    --local area = {x1, posYb , x2, posYt}
                    --WG['tooltip'].AddTooltip("sag_stat"..timePoint,area,tooltipText,0.5,"Breakdown")
                end
            end

            local maxX = #windList
            if toggleTable["windGraph"] and maxWind >0  and maxX > 0 then
                    glColor(1,1,1,1)
                for number, value in ipairs(windList) do
                    if number ~= 1 then
                        x1 = posXl + (boarderWidth* screenRatio) + ((number - 1) / maxX) * sizeX
                        x2 = posXl + (boarderWidth* screenRatio) + ((number) / maxX) * sizeX
                        y1 = posYb + (boarderWidth* screenRatio) + (windList[number - 1] / (maxWind+2)) * sizeY
                        y2 = posYb + (boarderWidth* screenRatio) + (value / (maxWind+2) * sizeY)
                    glLineWidth(1)
                    glBeginEnd(GL.LINE,MakeLine, x1,y1,x2,y2)
                    end
                end
            end
        end)
    end
    
    if not drawStackedAreaGraphAxis then ---All Axis and Axis info and center lines
        drawStackedAreaGraphAxis = gl_CreateList(function()
            local x1 ,x2, y1, y2   
            local text
            --mid point line xxx just for two teams
            if enabledSAG then
                x1 = posXl + boarderWidth
                x2 = posXr - boarderWidth
                y1 = posYb + ((posYt - posYb) / 2)

                if not toggleTable["absolute"] then
                    glColor(1,1,1,1)
                    gl.LineWidth(2)
                    glBeginEnd(GL.LINE,MakeLine, x1,y1,x2,y1)
                end
            end

            --title
            if enabledSAG then
                local text = string.gsub(trackedStats[displayGraph].formattedName," \n","")
                font:Begin()
                font:SetTextColor(1, 1, 1)
                font:Print(text, posXl + ((posXr-posXl)/2), posYt, fontSizeL, 'cvos')
                font:End()
            end

            --X axis
            if enabledSAG or toggleTable["windGraph"] then
                y1 = posYb + (boarderWidth*screenRatio) - 4
                y2 = posYb + (boarderWidth*screenRatio) + 4
                text = ""
                for i=0,4 do
                    x1 = posXl + (boarderWidth*screenRatio) + (i/4*sizeX) -- - 1
                    x2 = posXl + (boarderWidth*screenRatio) + (i/4*sizeX) -- + 1
                    glColor(1,1,1,0.75)
                    gl.LineWidth(1)
                    glBeginEnd(GL.LINE,MakeLine, x1,y1,x1,y2)
                    --glBeginEnd(GL.POLYGON,MakePolygonMap, x1,y1,x2,y2) --xxx turn this to line
                    text = string.format("%.1f", ((i/4)*(snapShotNumber-1)*15/60))

                    font:Begin()
                    font:SetTextColor(1, 1, 1,0.75)
                    font:Print(text, x1, y1 -( boarderWidth*screenRatio / 4) , fontSize, 'cvos')
                    font:End()
                end
                text = ("Time (min) \n one bar ="..(squishFactor*15).." seconds") --xxx need to move this part somewhere
                font:Begin()
                font:SetTextColor(1, 1, 1,0.75)
                font:Print(text, posXl + (posXr-posXl)/2, posYb - (boarderWidth* screenRatio /2)  , fontSize, 'cvos')
                font:End()
            end

            --Y axis values
            if enabledSAG then
                x1 = posXl + (boarderWidth*screenRatio) - 4
                x2 = posXl + (boarderWidth*screenRatio) + 4
                for i=1,3 do
                    y1= posYb + (boarderWidth*screenRatio) + (i/3*sizeY) - 1
                    glColor(1,1,1,0.75)
                    gl.LineWidth(1)
                    glBeginEnd(GL.LINE,MakeLine, x1,y1,x2,y1)
                    local text = valuesOnYAxis[i]
                    font:Begin()
                    font:SetTextColor(1, 1, 1,0.75)
                    font:Print(text, x1-( boarderWidth*screenRatio / 4), y1 , fontSize, 'rvos')
                    font:End()
                end
            
            
            --Rotated Y Axis Title
                local x = x1
                local y = posYb + (posYt-posYb)/2
                local extraText = ""
                text = string.gsub(trackedStats[displayGraph].spareName," \n","")
                if trackedStats[displayGraph].perSecBool == 1 and toggleTable["absolute"] then
                    extraText = "\n(per Second)"
                end
                gl.PushMatrix()
                gl.Translate(x, y, 0)
                gl.Rotate(90, 0, 0, 1)   -- rotate around Z axis (screen)
                font:Begin()
                font:Print(text..extraText, 0, (boarderWidth*screenRatio), 16, "cvos")  -- print at origin after transform
                font:End()
                gl.PopMatrix()
            end

            --Y2 Axis (wind)
            if toggleTable["windGraph"] and maxWind > 0 then
                local x1 = posXl + (boarderWidth*screenRatio)
                local x2 = posXr - (boarderWidth*screenRatio)
                gl.LineStipple(1, 4369)

                y1 = posYb + (boarderWidth*screenRatio) + ((maxWind/(maxWind+2)*sizeY))
                glBeginEnd(GL.LINE,MakeLine, x1,y1,x2,y1)
                font:Begin()
                font:SetTextColor(1, 1, 1,0.75)
                font:Print("Max", x2-( boarderWidth*screenRatio / 4), y1 , fontSize*.67, 'lvos')
                font:End()

                y1 = posYb + (boarderWidth*screenRatio) + (((maxWind*0.75)/(maxWind+2)*sizeY))
                font:Begin()
                font:SetTextColor(1, 1, 1,0.75)
                font:Print("Avg", x2-( boarderWidth*screenRatio / 4), y1 , fontSize*.67, 'lvos')
                font:End()
                glBeginEnd(GL.LINE_STRIP,MakeLine, x1,y1,x2,y1)

                y1 = posYb + (boarderWidth*screenRatio) + ((minWind/(maxWind+2)*sizeY))
                font:Begin()
                font:SetTextColor(1, 1, 1,0.75)
                font:Print("Min", x2-( boarderWidth*screenRatio / 4), y1 , fontSize*.67, 'lvos')
                font:End()
                glBeginEnd(GL.LINE,MakeLine, x1,y1,x2,y1)
                gl.LineStipple(false)

                x1 = posXr - (boarderWidth*screenRatio) - 4
                x2 = posXr - (boarderWidth*screenRatio) + 4
                for i=1,4 do
                    y1= posYb + (boarderWidth*screenRatio) + (i/4*sizeY) - 1
                    y2= posYb + (boarderWidth*screenRatio) + (i/4*sizeY) + 1
                    glColor(1,1,1,0.75)
                    glBeginEnd(GL.POLYGON,MakePolygonMap, x1,y1,x2,y2)

                    text = string.format("%.1f",(maxWind+2)) * i/4

                    font:Begin()
                    font:SetTextColor(1, 1, 1,0.75)
                    font:Print(text, x1-( boarderWidth*screenRatio / 4), y1 , fontSize, 'lvos')
                    font:End()
                    local x, y = x2, posYb + (posYt-posYb)/2
                    gl.PushMatrix()
                    gl.Translate(x, y, 0)
                    gl.Rotate(-90, 0, 0, 1)   -- rotate around Z axis (screen)
                    font:Begin()
                    font:Print("wind Speed", 0, (boarderWidth*screenRatio), 16, "cvos")  -- print at origin after transform
                    font:End()
                    gl.PopMatrix()
                end
            end


            if enableRanking then
                font:Begin()
                font:SetTextColor(1,1,1,0.75)

                ---Nature---
                if toggleTable["details"] == false then
                    for lineCount, pos in ipairs(screenPositions.nature.linePos) do
                        if lineCount == 1 then
                            font:Print("Nature Facts", pos.l + ((pos.r-pos.l)/2), pos.t - screenPositions.nature.rowHeight, fontSize, 'cvos')
                        elseif lineCount == 3 then --xxx 
                            font:Print("Wind (All Game): ".. WindDescriptionText[1].." ("..WindDescriptionText[2]..")", pos.l + ((pos.r-pos.l)/2),pos.t-screenPositions.nature.rowHeight/2 , fontSizeS, 'cvos')
                        elseif lineCount == 4 then --and lineCount < 100
                            font:Print("Wind (Recent): ".. WindDescriptionText[3].." ("..WindDescriptionText[4]..")", pos.l + ((pos.r-pos.l)/2),pos.t-screenPositions.nature.rowHeight/2, fontSizeS, 'cvos')
                        elseif lineCount == 5 then
                            if WG['saghelper'].trees then
                                local destroyedTrees = WG['saghelper'].trees.destroyedTrees
                                local maxTrees = WG['saghelper'].trees.maxTrees
                                font:Print("DeForestation Progress: ".. string.format("%.1f",100* destroyedTrees / maxTrees).."%, ("..destroyedTrees.." / "..maxTrees..")", pos.l + ((pos.r-pos.l)/2),pos.t-screenPositions.nature.rowHeight/2, fontSize*.67, 'cvos')
                            else
                                font:Print("DeForestation Progress: Treeless World", pos.l + ((pos.r-pos.l)/2),pos.t-screenPositions.nature.rowHeight/2, fontSizeS, 'cvos')
                            end

                        elseif lineCount == 6 then
                            if WG['saghelper'].rocks then
                            local destroyedRocks = WG['saghelper'].rocks.destroyedRocks
                            local maxRocks = WG['saghelper'].rocks.maxRocks
                            font:Print("Demineralisation Progress: ".. string.format("%.1f",100* destroyedRocks / maxRocks).."%, ("..destroyedRocks.." / "..maxRocks..")", pos.l + ((pos.r-pos.l)/2),pos.t-screenPositions.nature.rowHeight/2, fontSize*.67, 'cvos')
                            else
                                font:Print("Demineralisation Progress: No usable Rocks", pos.l + ((pos.r-pos.l)/2),pos.t-screenPositions.nature.rowHeight/2, fontSizeS, 'cvos')
                            end
                        elseif lineCount == 7 then
                            if critterOfTheDay.name then
                                font:Print("Critter of the Day: "..critterOfTheDay.name, pos.l + ((pos.r-pos.l)/2),pos.t-screenPositions.nature.rowHeight/2, fontSizeS, 'cvos')
                                local area = {pos.l,pos.b,pos.r,pos.t}
                                local text = critterOfTheDay.flavour
                                WG['tooltip'].AddTooltip("Critter_Facts"..snapShotNumber,area,text,0.5,"Critter Details")
                            else
                                font:Print("No Living Critters Detected", pos.l + ((pos.r-pos.l)/2),pos.t-screenPositions.nature.rowHeight/2, fontSizeS, 'cvos')
                                WG['tooltip'].RemoveTooltip("Critter_Facts"..snapShotNumber)
                            end     
                        end
                    end
                end
                if toggleTable["details"] then
                    local cumTotal = sagCompareTableStats[sagHighlight].cumTotal
                    for lineCount, pos in ipairs(screenPositions.details.linePos) do
                        if lineCount == 1 then
                            font:Print("Details", pos.l + ((pos.r-pos.l)/2), pos.t - screenPositions.details.rowHeight, fontSize, 'cvos')
                        elseif lineCount >= 3 then --zzz this bit needs a sorted list with some team names omitted. also need to kink to comparetable for better cum total. also need to move window somewhere better, pehaps tooltip style? finally need allyteam totals.
                            local key = lineCount-2
                            local teamID = sagCompareTableStats[sagHighlight].sortedTeamIDs[key]
                            if teamID then
                            local fraction = sagCompareTableStats[sagHighlight][teamID]
                                if fraction > 0 then
                                    local value = NumberPrefix(fraction * cumTotal)
                                    fraction = string.format("%.1f",fraction*100)
                                    font:SetTextColor(teamColourCache[teamID])
                                    font:Print(teamNamesCache[teamID], pos.l + screenPositions.details.columnWidth * 3  ,pos.t , fontSizeS, 'rvos')
                                    font:SetTextColor(1,1,1,1)
                                    font:Print(" "..value, pos.l + screenPositions.details.columnWidth*3 ,pos.t, fontSizeS, 'lvos')
                                    font:Print(fraction.." %", pos.l + screenPositions.details.columnWidth*5 ,pos.t, fontSizeS, 'lvos')
                                end
                            end
                        end
                    end
                end

                ---MileStones
                for lineCount, pos in ipairs(screenPositions.milestones.linePos) do
                    if lineCount == 1 then
                        font:Print("Milestone Timings", pos.l + ((pos.r-pos.l)/2), pos.t - screenPositions.milestones.rowHeight, fontSize, 'cvos') --title
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
                                font:Print(text, pos.l + screenPositions.milestones.columnWidth*1.5,pos.t-screenPositions.milestones.rowHeight/2, fontSizeS, 'lvos')

                        elseif milestonesResourcesList[category] then
                            data = milestonesResourcesList[category]
                            if data[1] == true then
                                local teamID = data[2]
                                local humanName = teamNamesCache[teamID]
                                if string.len(humanName) >= 14 then
                                    humanName = string.sub(humanName,1,14).."..."
                                end 
                                font:SetTextColor(teamColourCache[teamID][1],teamColourCache[teamID][2],teamColourCache[teamID][3],1)
                                font:Print(humanName.." ("..data[3]..")", pos.l + screenPositions.milestones.columnWidth*1.5,pos.t-screenPositions.milestones.rowHeight/2, fontSizeS, 'lvos')
                            end 

                        end
                    end
                end

                ---Top 5 players --- xxx add overall best and current best
                local relativeSize = {1, 0.8, 0.8, 0.5, 0.5}
                local relativeIntensity= {1, 0.7, 0.6, 0.5, 0.5}
                local teamIDLatest
                local teamID
                for lineCount, pos in ipairs(screenPositions.ranking.linePos) do
                    if lineCount == 1 then
                        font:Print("Top Players", pos.l + ((pos.r-pos.l)/2), pos.t - screenPositions.ranking.rowHeight, fontSize, 'cvos')
                    elseif lineCount == 2 then
                        font:Print("Overall", pos.l + ((pos.r-pos.l)*1/3), pos.t - screenPositions.ranking.rowHeight, fontSizeS, 'cbos')
                        font:Print("(Recent)", pos.l + ((pos.r-pos.l)*2/3), pos.t - screenPositions.ranking.rowHeight, fontSizeS, 'cbos')
                    elseif lineCount >= 3 then
                        local rank = lineCount - 2
                        teamID = sagTeamTableStats[displayGraph].sortedCumRanks[rank]
                        if snapShotNumber >= 4 and sagTeamTableStats[displayGraph][snapShotNumber-1].ranks then
                            teamIDLatest = sagTeamTableStats[displayGraph].sortedCumRanksRecent[rank]--should return only the latest ranking xxx this isn't good enough as need to either use squish factor OR 60 secs 
                        end
                        if teamID then
                            local humanName = teamNamesCache[teamID]
                            if string.len(humanName) >= 10 and rank == 1 then
                                humanName = string.sub(humanName,1,8).."..."
                            end
                            font:SetTextColor(1,1,1,1)
                            font:Print((rank..suffix[rank]..":"), pos.l , pos.t-screenPositions.ranking.rowHeight/2 , (fontSizeL*relativeSize[rank]), 'lvos')
                            font:SetTextColor(teamColourCache[teamID][1],teamColourCache[teamID][2],teamColourCache[teamID][3],relativeIntensity[rank])
                            font:Print((humanName), pos.l + ((pos.r-pos.l)*(1/3)), pos.t-screenPositions.ranking.rowHeight/2 , (fontSize*relativeSize[rank]), 'cvos')
                        end
                        if teamIDLatest then
                            local humanName = teamNamesCache[teamIDLatest]
                            font:SetTextColor(teamColourCache[teamIDLatest][1],teamColourCache[teamIDLatest][2],teamColourCache[teamIDLatest][3],relativeIntensity[rank])
                            font:Print("("..(humanName..")"), pos.l + ((pos.r-pos.l)*(2/3)), pos.t-screenPositions.ranking.rowHeight/2 , (fontSize*relativeSize[rank]), 'cvos')
                        end
                    end   
                end
                font:End()
            end
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
                font:Print(data.displayName, (data.l+data.r)/2,(data.b+data.t)/2, fontSize*.67, "cvos")
                font:End()
            end
            for number,data in ipairs(screenPositions.extraButtons.linePos) do
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
                font:Print(data.displayName, (data.l+data.r)/2,(data.b+data.t)/2, fontSize*.67, "cvos")
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
                    UiButton(screenPositions.playerSelect.linePos[number].l,screenPositions.playerSelect.linePos[number].b,screenPositions.playerSelect.linePos[number].r,screenPositions.playerSelect.linePos[number].t, 1,1,1,1, 1,1,1,1, nil,colour[1],colour[2],2)
                    font:SetTextColor(teamColourCache[teamID][1],teamColourCache[teamID][2],teamColourCache[teamID][3],intensity)
                    local humanName = teamNamesCache[teamID]
                    font:Begin()
                    font:Print(humanName, (screenPositions.playerSelect.linePos[number].l+screenPositions.playerSelect.linePos[number].r)/2,(screenPositions.playerSelect.linePos[number].b+screenPositions.playerSelect.linePos[number].t)/2, fontSize, "cvos")
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
        --sagTeamTableStats[category][time].ranks = rankedTeamIDTable
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

        sagTeamTableStats[category]["cumRanksRecent"] = {}
        local temp_cumRanksRecent = {}
        if time > 4 then
            for i =0, 3 do
                local rankList = sagTeamTableStats[category][time-i].ranks
                for teamID, rankValue in pairs(rankList) do
                    if not temp_cumRanksRecent[teamID] then
                        temp_cumRanksRecent[teamID] = rankValue
                    else
                        temp_cumRanksRecent[teamID] = temp_cumRanksRecent[teamID] + rankValue --xxx still need to sort this.
                    end
                end
            end
            sagTeamTableStats[category]["cumRanksRecent"]  = temp_cumRanksRecent
        end
    end
end

local function APMStatsExtract()
    local teamAPM = WG.teamAPM
    for teamID,APM in pairs(teamAPM) do
        if teamID ~=gaiaID then
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

local function SnapTimeToText (timePoint)
    local time = math.floor(timePoint*15)
    local min =  math.floor(time / 60)
    local sec =  math.floor(time % 60)
    local timeText = string.format("%d:%02d",min,sec).."s"
    return timeText
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

    -- local counter = 0
    -- local max = 0
    -- for k,_ in pairs(WG['saghelper']["masterStatTable"]) do
    --     counter = counter + 1
    --     if k > max then max = k end
    -- end
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

local function RefreshLists()

end

local function DeleteLists(choice) --xxx need to decide how to show only some of these. related need to check blend settings to stop things changing on clicks/deletes etc.
    if drawStackedAreaGraphs then
        if choice == "all" or choice =="sag" then
        gl_DeleteList(drawStackedAreaGraphs)
        drawStackedAreaGraphs = nil
        end
    end
    if drawStackedAreaGraphAxis then
        if choice == "all" or choice =="all" then
        gl_DeleteList(drawStackedAreaGraphAxis)
        drawStackedAreaGraphAxis = nil
        end
    end
    if drawButtonGraphs then
        if choice == "all" or choice =="all" then
        gl_DeleteList(drawButtonGraphs)
        drawButtonGraphs = nil
        end
    end
    if drawButtonsForSelections then
        if choice == "all" or choice =="all" then
        gl_DeleteList(drawButtonsForSelections)
        drawButtonsForSelections = nil
        end
    end
    if drawFixedElements then
        if choice == "all" or choice =="all" then
        gl_DeleteList(drawFixedElements)
        drawFixedElements = nil
        end
    end
    if drawExtraStats then
        if choice == "all" or choice =="all" then
        gl_DeleteList(drawExtraStats)
        drawExtraStats = nil
        end
    end
    for i = 1, snapShotNumber do
        WG['tooltip'].RemoveTooltip("Critter_Facts"..i)
        WG['tooltip'].RemoveTooltip("sag_stat"..i)
    end
end

function widget:Initialize()
    CacheTeams()
    DeleteLists("all")
    UiElement = WG.FlowUI.Draw.Element
    RectRound = WG.FlowUI.Draw.RectRound
    bgpadding = WG.FlowUI.elementPadding
	elementCorner = WG.FlowUI.elementCorner
    font =  WG['fonts'].getFont()
    UiButton = WG.FlowUI.Draw.Button
    UISelector = WG.FlowUI.Draw.Selector
    if WG['saghelper'] then

    end
    UpdateDrawingPositions("mainToggle")
    UpdateDrawingPositions("main")
    UpdateDrawingPositions("funStats")
    spectator, fullview = Spring.GetSpectatingState()
    PrimeSagTable(1)
    local n = Spring.GetGameFrame()
    snapShotNumber = math.max(math.floor(((n-30) /450))+1,1)
    Spring.Echo("gameframe on init:",n, snapShotNumber)
    
    PrimeSagTable(snapShotNumber)
    DrawGraphToggleButton()
    if snapShotNumber > 1 then
        CompleteStatsExtract()
        CreateExtraStatsText()
    end
end

function widget:TextCommand(command)
    if string.find(command, "bug",nil,true) then
        Spring.Echo("debug")
        critterOfTheDay = nil
        critterOfTheDay = {}
        CritterCheck()
        Spring.Echo("debug2")
        if critterOfTheDay.pos then
            Spring.SetCameraTarget(critterOfTheDay.pos[1], critterOfTheDay.pos[2],critterOfTheDay.pos[3], 1)
        end
        Spring.Echo("debug3")
        if toggleTable["squishFactorToggle"] then
            toggleTable["squishFactorToggle"] = false
        else
            toggleTable["squishFactorToggle"] = true
        end
        --Spring.Echo("allyTeamColourCache",allyTeamColourCache) --xxx recursive ref, sort out!!
        --Spring.Echo("teamColourCache",teamColourCache)
        for i =1, 3 do
                --Spring.Echo(sagTeamTableStats[displayGraph][i].ranks)    
        end
        --Spring.Echo('sagTeamTableStats[displayGraph]["cumRanks"]',sagTeamTableStats[displayGraph]["cumRanks"])
        --Spring.Echo('sagTeamTableStats[displayGraph]["sortedCumRanks"]',sagTeamTableStats[displayGraph]["sortedCumRanks"])
    end

    if string.find(command, "extra", nil, true) then
        if toggleTable["extraStats"] == true then
            toggleTable["extraStats"] = false
            gl_DeleteList(drawExtraStats)
            drawExtraStats = nil
        else
            toggleTable["extraStats"] = true
            DrawExtraStats()
        end
    end

end


local gameOver =1

function widget:DrawScreen()
    
    if drawer and gameOver then
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
    end
    if drawButtonGraphs then
        gl_CallList(drawButtonGraphs)
    end
    if drawExtraStats then
        gl_CallList(drawExtraStats)
    end
end

function widget:GameFrame(n)
    if (n-30) % 450 == 0 then --one second after to allow for helper widget to do it's thing on n+1
        snapShotNumber = ((n-30) /450)+1
        if toggleTable["squishFactorToggle"] then
            squishFactor = math.ceil(snapShotNumber/squishFactorSetPoint)
        else
            squishFactor = 1
        end
        screenPositions.graphs.columnWidth = (screenPositions.graphs.r -screenPositions.graphs.l) * squishFactor / snapShotNumber
        PrimeSagTable(snapShotNumber)
        if spectator and fullview then
            LatestStatsExtract(snapShotNumber)
            APMStatsExtract()
            SortCumRanks(displayGraph)
            DetermineYAxisValues()
            CreateExtraStatsText()
        end
        
        if #windList >0 and maxWind > 0 then
            CalculateGameWindAverage()
        end
    end
        

    if n >30 and (n-45) % 450 ==0 then --xxx do i need the first conditoinal??
    --Spring.Echo("running second update", n, (n-45) %450 )
        DeleteLists("all")
        DrawStackedAreaGraph()
        DrawGraphToggleButton()
        DrawExtraStats()
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

local displayGraphButton = true
local graphsOnScreen = false

local function isAbove(mx,my,box,button) ---xxx if button is true, then it needs to cycle through a list to get line number. if not, then it can return a col, row value based on linewidth and column width.
    if mx >= box.l and mx <=box.r and my >=box.b and my <=box.t then
        local columnNumber, rowNumber = nil,nil
        if box.columnWidth then
            columnNumber = math.floor((mx - box.l) / box.columnWidth) + 1
        end
        if box.rowHeight then
            rowNumber = math.floor((my - box.t) / box.rowHeight)*-1 --counting top to bottom so inversed.
        end
        Spring.Echo("columnNumber, rowNumbner,",columnNumber,rowNumber)
        if button == true then
            for number,pos in ipairs(box.linePos) do
                if mx >= pos.l and mx <=pos.r and my >=pos.b and my <=pos.t then
                    return true, number ,columnNumber, rowNumber
                end
            end
        else
            return true,false,columnNumber, rowNumber
        end
    else
        return false,false,columnNumber, rowNumber
    end
end

function widget:MousePress(mx, my, button) 
    if displayGraphButton then
        local bool, _ = isAbove(mx,my,buttonGraphsOnOffPositionList,nil)
        if bool then
            if toggleTable["graphButton"] == false then
                toggleTable["graphButton"] = true
                drawer = true
                enabledSAG = true
                DeleteLists("all")
                DrawGraphToggleButton()
                DrawStackedAreaGraph()
                graphsOnScreen = true
                Spring.Echo("Graphs are displayed")
            else
                toggleTable["graphButton"] = false
                drawer = false
                enabledSAG = false
                DeleteLists("all")
                DrawGraphToggleButton()
                graphsOnScreen = false
                Spring.Echo("Graphs are not displayed")
            end
        end
    end
    if graphsOnScreen and enabledSAG then
        local bool, lineNumber = isAbove(mx,my,screenPositions.categories,true)
        if lineNumber then
            if trackedStatsNames[lineNumber] then
                displayGraph = trackedStatsNames[lineNumber][1]
                SortCumRanks(displayGraph)
                DeleteLists("all")
                DetermineYAxisValues()
                DrawGraphToggleButton()
                DrawStackedAreaGraph()
            end
        end
        local bool, lineNumber = isAbove(mx,my,screenPositions.extraButtons,true)
        if lineNumber then
            local name = screenPositions.extraButtons.linePos[lineNumber].name
            if toggleTable[name] ~=nil then
                if toggleTable[name] == false then
                    toggleTable[name] = true
                else
                    toggleTable[name] = false
                end
                DeleteLists("all")
                DetermineYAxisValues()
                DrawStackedAreaGraph()
            end
        --     if name == "absolute" then
        --         if toggleTable["absolute"] then
        --             toggleTable["absolute"] = false
        --         else
        --             toggleTable["absolute"] = true
        --         end
        --         DeleteLists("all")
        --         DetermineYAxisValues()
        --         DrawStackedAreaGraph()
                
        --     elseif name == "teamColour" then
        --         if toggleTable["teamColour"] then
        --             toggleTable["teamColour"] = false
        --         else
        --             toggleTable["teamColour"] = true
        --         end
        --         DeleteLists("all")
        --         DrawStackedAreaGraph()

        --     elseif name == "windGraph" then
        --         if toggleTable["windGraph"] == false then
        --             toggleTable["windGraph"] = true
        --         else
        --             toggleTable["windGraph"] = false
        --         end
        --         DeleteLists("all")
        --         DrawStackedAreaGraph()
                
        --     elseif name == "comparison" then
        --         if toggleTable["comparison"] == false then
        --             toggleTable["comparison"] = true
        --             DeleteLists("all")
        --             DrawStackedAreaGraph()
        --         else
        --             toggleTable["comparison"] = false
        --             for teamID, _ in pairs(teamAllyTeamIDs) do
        --                 comparisonTeamIDs[teamID] = true
        --             end
        --             DeleteLists("all")
        --             DrawGraphToggleButton()
        --             DetermineYAxisValues()
        --             DrawStackedAreaGraph()
        --         end
        --     end
        end
        if toggleTable["comparison"] then
            local bool, lineNumber = isAbove(mx,my,screenPositions.playerSelect,true)
            if lineNumber then
                local teamID = teamIDsorted[lineNumber]
                if comparisonTeamIDs[teamID] then
                    comparisonTeamIDs[teamID] = false
                else
                    comparisonTeamIDs[teamID] = true
                end
                DeleteLists("all")
                DrawGraphToggleButton()
                DetermineYAxisValues()
                DrawStackedAreaGraph()                      
            end
        end
        local bool, lineNumber,columnNumber, rowNumber = isAbove(mx,my,screenPositions.graphs,false)
        if bool and columnNumber then
            if sagHighlight and sagHighlight == columnNumber then
                toggleTable["details"] = false
                sagHighlight = nil
            else
                sagHighlight = columnNumber
                toggleTable["details"] = true
            end
            DeleteLists("sag")
            DrawGraphToggleButton()
            DetermineYAxisValues()
            DrawStackedAreaGraph()
        end
    end
    if toggleTable["extraStats"] then
        local bool, lineNumber,columnNumber, rowNumber = isAbove(mx,my,screenPositions.funStatBox,false)
        --need column 3 onwards, need row 1 or 2
        if bool and rowNumber <=2 then
            if extraStatNames[columnNumber-2] then
                sortVar = extraStatNames[columnNumber-2].name
                DeleteLists("all")
                CreateExtraStatsText()
                DrawExtraStats()
            end
            
        elseif bool and rowNumber == screenPositions.funStatBox.totalNumRows then
            if columnNumber <= #funStatsTypeToDisplayList then 
                funStatsTypeToDisplayCounter = columnNumber
            end
            DeleteLists("all")
            CreateExtraStatsText()
            DrawExtraStats()
        end
        Spring.Echo ("bool, lineNumber,columnNumber, rowNumber, sortVar, ",bool, lineNumber,columnNumber, rowNumber, sortVar,funStatsTypeToDisplayList[funStatsTypeToDisplayCounter].name)
    end
end

function widget:UnitFinished(unitID, unitDefID, teamID) --xxx need to check rez bots
    --Spring.Echo("unitfinsihed",unitID, unitDefID, teamID)
end



