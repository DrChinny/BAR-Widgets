function widget:GetInfo()
    return {
      name      = "SAG",
      desc      = "Displaying Stacked Area Graphs",
      author    = "Mr_Chinny",
      date      = "Feb 2026",
      handler   = true,
      enabled   = true,
      layer = 5 --must load be later than the advanced player list
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
---
---
local floor, ceil = math.floor, math.ceil
local insert = table.insert
local antiSpam = 0
local absoluteOrNormalisedToggle = false --false is abs on, true is normalised
local teamColourToggle = false
local drawer = false
local gl_CreateList             = gl.CreateList
local gl_DeleteList             = gl.DeleteList
local gl_CallList               = gl.CallList
local glVertex                  = gl.Vertex
local glBeginEnd                = gl.BeginEnd
local glColor                   = gl.Color
local glLineWidth               = gl.LineWidth
local spGetTeamColor            = Spring.GetTeamColor
local UiUnit
local UiElement
local windGraphEnabled = true

local comparisonToggle = false
local windCheckInterval = 60
local avgWind = nil
local minWind = Game.windMin
local maxWind = Game.windMax
local averagedWindSpeed = {}
local WindDescriptionText = {"None",0,"None",0}
local windDescriptionList = {"GALES!","Gusty","Average","Light","Becalmed"}
local windList = {} --list of last 10 windspeeds
local squishFactorSetPoint = 40 --max number of bars on the chart before we need to start averaging or ignoring results.
local fontSize = 18
local vsx, vsy                  = Spring.GetViewGeometry()
local buttonGraphsOnOffPositionList         = {} --{Xl,Yb,Xr,Yt}
local buttonColour      = {{{1,1,1,0.3},{0.5,0.5,0.5,0.3}},{{0,0,0,0.3},{0.5,0.5,0.5,0.3}}} --on/off and blend
local toggleButtonGraphs = false
local positionListButtonsForSelections ={}--used for checking mouse coords.
local positionListButtonsForPlayerSelections = {}
local spectator, fullview = Spring.GetSpectatingState()
local font
local teamColourCache = {}
local allyTeamColourCache = {}
local teamNamesCache = {}
local teamAllyTeamIDs = {}
local teamIDsorted = {} --sorted teamID in an array from [1] = 0 to max
local snapShotNumber = 1 -- increases by 1 every 450 frames (15s). a value of 1 is at frame 0, a value of 2 is at frame 450 etc.
local sagTeamTableStats = {}
local comparisonTeamIDs = {}

local trackedStatsNames = { --format = {statname, Human Readable Name, bool of avg per second (1) or discrete (0), bool spare}. xxx link to translation
    {"damageDealt", "Damage \n Dealt",1,0},
    {"damageReceived", "Damage \n Received",1,0},
    {"energyExcess", "Energy \n Excess" , 1,0},
    {"energyProduced", "Energy \n Produced" , 1,0},
    {"energyReceived", "Energy \n Received" , 0,0},
    {"energySent", "Energy \n Sent" , 0,0},
    {"energyUsed", "Energy \n Used" , 1, 0},
    {"metalExcess", "Metal \n Excess", 1, 0},
    {"metalProduced", "Metal \n Produced", 1, 0},
    {"metalReceived", "Metal \n Received", 1, 0},
    {"metalSent", "Metal \n Sent", 1, 0},
    {"metalUsed", "Metal \n Used", 1, 0},
    {"unitsCaptured", "Units \n captured" , 0 ,0},
    --{"unitsDied", "Units \n Died" , 0 ,1},
    --{"unitsKilled", "Units \n Killed" , 0 ,0},
    --{"unitsOutCaptured", "Units Out \n captured" , 0 ,0},
    {"unitsProduced", "Units \n Produced" , 0 ,0},
    {"unitsReceived", "Units \n Received" , 0 ,0},
    {"unitsSent", "Unit \n Sent" , 0 ,0},
    {"APM", "APM", 0 , 0 },
    {"FPS", "FPS" , 0 , 0},
    {"armyValue", "Standing \n Army Value",0,0},
    {"defenseValue", "Defensive \n Structures",0,0},
    {"utilityValue", "Utility \n Structures",0,0},
    {"economyValue", "Economy \n Structures",0,0},
    {"everything", "Everything \n Value ",0,0},
}
--{"armyValue","defenseValue", "utilityValue","economyValue","everything"}
local extraButtons = {"Absolute","Team Colours","WindSpeed Overlay"}
local trackedStats = {}
for _,data in ipairs(trackedStatsNames) do
    trackedStats[data[1]] = {data[2],data[3],data[4]}
end

local displayGraphCounter = 1
local displayGraph = "energyProduced"
local drawStackedAreaGraphTeam
local drawStackedAreaGraphAxis
local drawButtonGraphs
local drawButtonsForSelections
local gaiaID = Spring.GetGaiaTeamID


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

local function CacheTeams() -- get all the teamID / Ally Team ID captains and colours once, and cache.
    for _, allyTeamID in ipairs(Spring.GetAllyTeamList()) do
        local lowest_teamID = 9999
        for _, teamID in ipairs(Spring.GetTeamList(allyTeamID)) do
            if teamID < lowest_teamID then
                lowest_teamID = teamID
            end
            if Spring.GetGaiaTeamID() ~= teamID then
                table.insert(teamIDsorted,teamID)
                teamAllyTeamIDs[teamID] = allyTeamID
                
            end
        end
        allyTeamColourCache[allyTeamID] = {Spring.GetTeamColor(lowest_teamID)}
    end

    teamColourCache = {} --{r,g,b,a,name}
    for teamID,allyTeamID in pairs(teamAllyTeamIDs) do

        local playerName = nil
		local playerID = Spring.GetPlayerList(teamID, false)
        if playerID and playerID[1] then
            -- it's a player
            playerName = select(1, Spring.GetPlayerInfo(playerID[1], false))
        else
            local aiName = Spring.GetGameRulesParam("ainame_" .. teamID)
            if aiName then
                -- it's AI
                playerName = aiName
            else
                -- player is gone
                playerName = "(gone)"
            end
        end
        comparisonTeamIDs[teamID] = false
        teamColourCache[teamID] = {Spring.GetTeamColor(teamID)}
        teamNamesCache[teamID] = playerName
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
    local cumWind = 0
    local count = 0
    local recentWind = 0
    local windDescription = ""
    local recentWindDescription = ""
    local calulatedWindaverage = 0

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
        recentWind = recentWind / math.min(count-1,(windCheckInterval/30)*15)
        recentWindDescription = GetWindText(recentWind)
    end

    WindDescriptionText = {windDescription,calulatedWindaverage,recentWindDescription,recentWind}
end







local function PrimeSagTable(time)
    --local sagAllyTeamTable = {}
    --local sagTeamTable = {}

    for category,_ in pairs(trackedStats) do 
        if not sagTeamTableStats[category] then
            sagTeamTableStats[category] = { cumRanks= {}, sortedCumRanks = {}, largestCumTotal = 0}
            for teamID,allyTeamID in pairs(teamAllyTeamIDs) do
                sagTeamTableStats[category]["cumRanks"][teamID] = 0
            end
        end
        if not sagTeamTableStats[category][time] then
            sagTeamTableStats[category][time] = {cumTotal = 0, ranks = {},}
        else
            sagTeamTableStats[category][time] = {cumTotal = 0, ranks = {},} 
            for teamID, allyTeamID in pairs(teamAllyTeamIDs) do
                sagTeamTableStats[category][time][teamID] = 0
            end
        end
    end

end

local function AddInfoToSagTable(teamID, category, value, time)
    sagTeamTableStats[category][time][teamID] = value
    sagTeamTableStats[category][time].cumTotal = sagTeamTableStats[category][time].cumTotal + value
end

local function AddInfoToSagTableCumaltive(teamID, category, value, time)
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

end

local function DrawGraphToggleButton()
    gl_DeleteList(drawButtonGraphs)
    drawButtonGraphs = nil
    local playerListTop,playerListLeft, playerListBottom,playerListRight
    if WG.displayinfo ~= nil or
		WG.unittotals ~= nil or
		WG.music ~= nil or
		WG['advplayerlist_api'] ~= nil
	then
		local playerListPos
		if WG.displayinfo ~= nil then
			playerListPos = WG.displayinfo.GetPosition()
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

--{Xl,Yb,Xr,Yt}
    local yPadding = 1
    local sizeX, sizeY = 200,100
    local boarderWidth = 20
    local posXl = playerListLeft
    local posYt = playerListTop
    
    --buttonGraphsOnOffPositionList = {(posXr- boarderWidth - 5.5*  fontSize),(posYt-boarderWidth - (2*fontSize) + yPadding),(posXr- boarderWidth - 2.75*fontSize),(posYt-boarderWidth)}
    buttonGraphsOnOffPositionList = {(posXl),(posYt),(posXl + sizeX),(posYt + sizeY)}

    drawButtonGraphs = gl_CreateList(function()
        local colour = buttonColour[1]
        if toggleButtonGraphs then
            colour = buttonColour[1]
            font:SetTextColor(1, 1, 1, 1)
        else
            colour = buttonColour[2]
            font:SetTextColor(0.92, 0.92, 0.92, 1)
        end



        UiButton(buttonGraphsOnOffPositionList[1],buttonGraphsOnOffPositionList[2],buttonGraphsOnOffPositionList[3],buttonGraphsOnOffPositionList[4], 1,1,1,1, 1,1,1,1, nil,colour[1],colour[2],2)
        font:Begin()
        font:Print("Graphs", buttonGraphsOnOffPositionList[1]+((buttonGraphsOnOffPositionList[3]-buttonGraphsOnOffPositionList[1])/2),buttonGraphsOnOffPositionList[2]+((buttonGraphsOnOffPositionList[4]-buttonGraphsOnOffPositionList[2])/2)+fontSize/3, fontSize*0.67, "cvos")
        font:End()
    end)
end



local function DrawStackedAreaGraph()
    local offsetX, offsetY, sizeX, sizeY = 600,200,600,600 --xxx x and y offset need to be relative to either screen size or another widget
    local boarderWidth = 20
    local screenRatio = 1 --xxx this needs to be set according to the screen resolution
    local posXl = (offsetX - boarderWidth) * screenRatio
    local posXr = (offsetX + sizeX + boarderWidth) *screenRatio
    local posYb = (offsetY - boarderWidth) * screenRatio
    local posYt = (offsetY + sizeY + boarderWidth) * screenRatio
    
    local scaleX = sizeX / screenRatio
    local scaleY = sizeY / screenRatio
    local frameStreachFactor = 1
    local squishFactor = 1 --if curren sn
    --frameStreachFactor =  ceil(snapShotNumber / sizeX)
    local absScale = 1 --Value of 1 will allow the graph elements to stretch to the very top of y axis, <1 will squish.
    
    local largestCumTotal = 0
    

    if sagTeamTableStats[displayGraph].largestCumTotal then
        largestCumTotal = sagTeamTableStats[displayGraph].largestCumTotal
    end

    if snapShotNumber > 0 then
        scaleX = frameStreachFactor * sizeX / snapShotNumber
        squishFactor = math.ceil(snapShotNumber/squishFactorSetPoint) --xxx change 20 toa varible.


        --scaleX = floor(sizeX / (screenRatio * replayFrame * (frameStreachFactor) )) --replayframe needs to be the last frame, this is not dynamic.
    end
    if not drawStackedAreaGraphTeam then
        drawStackedAreaGraphTeam = gl_CreateList(function()
            UiElement(posXl ,posYb,posXr,posYt,1,1,1,1, 1,1,1,1, .5, {0,0,0,0.5},{1,1,1,0.05},boarderWidth) --widget outline / Create background


            local x1 ,x2, y1, y2
            local counter = 0
            for timePoint,data in pairs (sagTeamTableStats[displayGraph]) do
                if timePoint == "cumRanks" or timePoint == "sortedCumRanks" or timePoint == "largestCumTotal" then
                else
                    if timePoint % squishFactor == 0 then


                        absScale = 1
                        local cumY = 0
                        --for teamID, fraction in pairs(data) do
                        local teamID = 0 
                        local fraction = 0
                        if largestCumTotal > 0 and absoluteOrNormalisedToggle then
                            absScale = data["cumTotal"]/largestCumTotal
                        end
                        local denominator = 0
                        if comparisonToggle then
                            for teamID,bool in pairs(comparisonTeamIDs) do
                                if bool == true then
                                    fraction = data[teamID]
                                else
                                    fraction = 0
                                end
                                if fraction == nil then 
                                    fraction = 0 
                                end
                                denominator = denominator + fraction
                            end
                        else
                            for teamID,_ in pairs(teamAllyTeamIDs)do
                                comparisonTeamIDs[teamID] = true
                            end
                            denominator = 1 
                        end

                        if denominator == 0 then 
                            denominator = 1 
                        end
                        if antiSpam <2 then
                            Spring.Echo("denominator, comparisonToggle:",denominator,comparisonToggle)
                            antiSpam = antiSpam +1
                        end
                        fraction = 0
                        for i = 1, #teamIDsorted do
                            teamID = teamIDsorted[i]
                            if comparisonTeamIDs[teamID] == true then
                                
                                fraction = data[teamID]
                                if fraction == nil then
                                    fraction = 0
                                end

                                if counter % frameStreachFactor == 0 then
                                    x1 = offsetX + ((timePoint-squishFactor) * scaleX)
                                    x2 = offsetX + ((timePoint - 0) * scaleX)
                                    
                                    y1 = offsetY + (sizeY - ((cumY * scaleY))) * absScale
                                    cumY = cumY + (fraction / denominator)
                                    -- cumY =  cumY + fraction
                                    y2 = offsetY + (sizeY - ((cumY * scaleY))) * absScale
                                    if teamColourToggle then
                                        local colour = allyTeamColourCache[teamAllyTeamIDs[teamID]]
                                        glColor(colour[1],colour[2],colour[3],0.67)
                                    else
                                        glColor(teamColourCache[teamID][1],teamColourCache[teamID][2],teamColourCache[teamID][3],0.67)
                                    end
                                    glBeginEnd(GL.POLYGON,MakePolygonMap, x1,y1,x2-1,y2)
                                end
                            end
                        end
                    end
                    counter = counter + 1
                end
            end


            local maxX = #windList
            if windGraphEnabled and maxWind >0  and maxX > 0 then
                    glColor(1,1,1,1)
                for number, value in ipairs(windList) do
                    if number ~= 1 then
                        x1 = posXl + (boarderWidth* screenRatio) + ((number - 1) / maxX) * sizeX
                        x2 = posXl + (boarderWidth* screenRatio) + ((number) / maxX) * sizeX
                        y1 = posYb + (boarderWidth* screenRatio) + (windList[number - 1] / (maxWind+2)) * sizeY
                        y2 = posYb + (boarderWidth* screenRatio) + (value / (maxWind+2) * sizeY)
                    glLineWidth(1)
                    glBeginEnd(GL.LINE,MakeLine, x1,y1,x2,y2)
                    else
                    end
                    --glBeginEnd(GL.POLYGON,MakePolygonMap, x1,y1,x2,y2)
                end
            end
        end)
    end
    --xxx I need to scale Y axis when using two person comparisonToggle. currenltly shows total made that snapshot, rather than only for the two players involved. May be hard to do this well!
    if not drawStackedAreaGraphAxis then
        drawStackedAreaGraphAxis = gl_CreateList(function()
            local x1 ,x2, y1, y2
            --mid point line xxx just for two teams
            x1 = offsetX
            x2 = offsetX + sizeX
            y1 = (offsetY + (0.5 *sizeY)) - 1
            y2 = (offsetY + (0.5 *sizeY)) + 1
            if not absoluteOrNormalisedToggle then --remove also if not exactly two teams
                glColor(1,1,1,0.75)
                glBeginEnd(GL.POLYGON,MakePolygonMap, x1,y1,x2,y2)
            end

            --title
            local fontSizeL = 36
            font:Begin() --title text
            font:SetTextColor(1, 1, 1)
            font:Print(displayGraph, offsetX + (sizeX/2), posYt, fontSizeL, 'cvos')
            font:End()

            --X axis
            y1 = posYb + (boarderWidth*screenRatio) - 4
            y2 = posYb + (boarderWidth*screenRatio) + 4
            for i=0,4 do
                x1 = posXl + (boarderWidth*screenRatio) + (i/4*sizeX) - 1
                x2 = posXl + (boarderWidth*screenRatio) + (i/4*sizeX) + 1
                glColor(1,1,1,0.75)
                glBeginEnd(GL.POLYGON,MakePolygonMap, x1,y1,x2,y2)
                local text = string.format("%.1f", ((i/4)*(snapShotNumber-1)*15/60))
                -- if text >= 1 then
                --     text = math.floor(text * 10 + 0.5) / 10
                -- end
                font:Begin()
                font:SetTextColor(1, 1, 1,0.75)
                font:Print(text, x1, y1 -( boarderWidth*screenRatio / 4) , fontSize, 'cvos')
                font:End()
            end
            font:Begin()
            font:SetTextColor(1, 1, 1,0.75)
            font:Print("Time (min)", posXl + (posXr-posXl)/2, posYb - (boarderWidth* screenRatio /2)  , fontSize, 'cvos')
            font:End()

            --Y axis
            x1 = posXl + (boarderWidth*screenRatio) - 4
            x2 = posXl + (boarderWidth*screenRatio) + 4
            for i=1,3 do
                y1= posYb + (boarderWidth*screenRatio) + (i/3*sizeY) - 1
                y2= posYb + (boarderWidth*screenRatio) + (i/3*sizeY) + 1
                glColor(1,1,1,0.75)
                glBeginEnd(GL.POLYGON,MakePolygonMap, x1,y1,x2,y2)
                local text = nil
                local value = nil
                if absoluteOrNormalisedToggle == true then
                    value = (i*largestCumTotal/3)
                    if trackedStats[displayGraph][2] == 1 then
                        value = value /15 --changes the axis to per second
                    end
                    if value < 1000 then
                        text = string.format("%.0f",value)
                    elseif value <1000000 then
                        text = string.format("%.2f",(value)/1000).."K"
                    elseif value <1000000000 then
                        text = string.format("%.2f",(value)/1000000).."M"
                    else
                        text = string.format("%.2f",(value)/1000000000).."G" --xxx nothing will go above this??
                    end
                else
                    text = string.format("%.1f",(i*100/3))
                end
                font:Begin()
                font:SetTextColor(1, 1, 1,0.75)
                font:Print(text, x1-( boarderWidth*screenRatio / 4), y1 , fontSize, 'rvos')
                font:End()
                
            end
            
            
            --Rotated Y Axis Title

            local x, y = x1, posYb + (posYt-posYb)/2
            local extraText = ""
            if trackedStats[displayGraph][2] == 1 and absoluteOrNormalisedToggle then
                extraText = "\n(per Second)"
            end
            gl.PushMatrix()
            gl.Translate(x, y, 0)
            gl.Rotate(90, 0, 0, 1)   -- rotate around Z axis (screen)
            font:Begin()
            font:Print(displayGraph..extraText, 0, (boarderWidth*screenRatio), 16, "cvos")  -- print at origin after transform
            font:End()
            gl.PopMatrix()


            
            --Y2 Axis (wind) --XXX change polygones to lines for axis ticks
            if windGraphEnabled and maxWind > 0 then
                --wind max,min,predicted average lines.
                x1 = posXl + (boarderWidth*screenRatio)
                x2 = posXr - (boarderWidth*screenRatio)

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

                    local text = string.format("%.1f",(maxWind+2)) * i/4

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


            --Top 3 cumRank
            local winners = sagTeamTableStats[displayGraph].sortedCumRanks
            local name = "none"

            x1 = posXr + (boarderWidth *screenRatio) --left
            x2 = posXr + (boarderWidth *screenRatio) + (sizeX / 2) --right
            y1 = posYt - (sizeY / 2.5) --btm
            y2 = posYt --top

            UiElement(x1 ,y1,x2,y2,1,1,1,1, 1,1,1,1, .5, {0,0,0,0.5},{1,1,1,0.05},boarderWidth) --widget outline / Create background
            UiElement(x1 ,posYb,x2,(y1 - (boarderWidth*screenRatio/2)),1,1,1,1, 1,1,1,1, .5, {0,0,0,0.5},{1,1,1,0.05},boarderWidth) --widget outline / Create background
            font:Begin()
            font:SetTextColor(1,1,1,0.75)
            font:Print("LeaderBoard", x1 + ((x2-x1)/2), (y2) -(boarderWidth*screenRatio*2), fontSizeL, 'cvos')
            font:Print("Awards", x1 + ((x2-x1)/2), (y1) -(boarderWidth*screenRatio*2.5), fontSizeL, 'cvos')
            font:Print("Wind: ".. WindDescriptionText[1], x1 + ((x2-x1)/2), (y1) -(boarderWidth*screenRatio*2.5)- fontSizeL, fontSizeL, 'cvos')
            font:Print("Wind: ".. WindDescriptionText[3], x1 + ((x2-x1)/2), (y1) -(boarderWidth*screenRatio*2.5)- (2* fontSizeL), fontSizeL, 'cvos')


            local relativeSize = {1,0.6,0.5,0.3,0.3}
            local relativeIntensity= {1,0.7,0.6,0.5,0.5}
            local relativePosition = {2.5,3.4,4.2,5.1,5.5}
            for rank, teamID in ipairs(sagTeamTableStats[displayGraph].sortedCumRanks) do
                if rank < 6 then
                    font:SetTextColor(teamColourCache[teamID][1],teamColourCache[teamID][2],teamColourCache[teamID][3],relativeIntensity[rank])
                    local humanName = teamNamesCache[teamID]
                    if string.len(humanName) >= 10 and rank == 1 then
                        humanName = string.sub(humanName,1,8).."..."
                    end
                    font:Print((rank..": "..humanName), x1 + ((x2-x1)/2), (y2) -((relativePosition[rank])*fontSizeL)-(boarderWidth*screenRatio/4), (fontSizeL*relativeSize[rank]), 'cvos')
                end
            end
            font:End()

        end)
    end
    if not drawButtonsForSelections then
        drawButtonsForSelections = gl_CreateList(function()

            local x1 = posXl --left
            local x2 = posXr --right
            local y1 = posYb - (sizeY / 4) --btm
            local y2 = posYb - (boarderWidth * screenRatio)--top

            UiElement(x1 ,y1,x2,y2,1,1,1,1, 1,1,1,1, .5, {0,0,0,0.5},{1,1,1,0.05},boarderWidth/2)



            local colour = buttonColour[1]
            if toggleButtonGraphs then
                colour = buttonColour[1]
                font:SetTextColor(1, 1, 1, 1)
            else
                colour = buttonColour[2]
                font:SetTextColor(0.92, 0.92, 0.92, 1)
            end
  
            local sizeXButton,sizeYButton = 50,10
            --sizeYButton = sizeY / #trackedStatsNames / 2
            sizeYButton = (y2-y1) / 8
            sizeXButton = (x2-x1) / 8 --6 normal columns plus 2 reserved for major buttons

            for number,data in ipairs(trackedStatsNames) do
                local name = data[1]
                local humanName = data[2]
                if name == displayGraph then
                    colour = buttonColour[1]
                    font:SetTextColor(0, 5, .2, 1)
                else
                    colour = buttonColour[2]
                    font:SetTextColor(0.92, 0.92, 0.92, 1)
                end
                if number <= 6 then --top row
                    positionListButtonsForSelections[number] = {(x1 + (2*sizeXButton) + ((number-1)*sizeXButton)),(y2)-(sizeYButton*1),(x1 + (2*sizeXButton) + ((number)*sizeXButton) - (boarderWidth/2) ),(y2)-(sizeYButton*2)}
                elseif number <= 12 then
                    positionListButtonsForSelections[number] = {(x1 + (2*sizeXButton) + ((number-6-1)*sizeXButton)),(y2)-(sizeYButton*3),(x1 + (2*sizeXButton) + ((number-6)*sizeXButton)- (boarderWidth/2)),(y2)-(sizeYButton*4)}
                elseif number <= 18 then
                    positionListButtonsForSelections[number] = {(x1 + (2*sizeXButton) + ((number-12-1)*sizeXButton)),(y2)-(sizeYButton*5),(x1 + (2*sizeXButton) + ((number-12)*sizeXButton)- (boarderWidth/2)),(y2)-(sizeYButton*6)}
                else
                    positionListButtonsForSelections[number] = {(x1 + (2*sizeXButton) + ((number-18-1)*sizeXButton)),(y2)-(sizeYButton*7),(x1 + (2*sizeXButton) + ((number-18)*sizeXButton)- (boarderWidth/2)),(y2)-(sizeYButton*8)}
                end


                -- positionListButtonsForSelections[number] = {(posXl),((posYt)-(sizeYButton))-(sizeYButton*(number-1)*2),(posXl + sizeXButton),(posYt)-(sizeYButton*(number-1)*2)}
                UiButton(positionListButtonsForSelections[number][1],positionListButtonsForSelections[number][2],positionListButtonsForSelections[number][3],positionListButtonsForSelections[number][4], 1,1,1,1, 1,1,1,1, nil,colour[1],colour[2],2)
                font:Begin()
                font:Print(humanName, (positionListButtonsForSelections[number][1]+positionListButtonsForSelections[number][3])/2,(positionListButtonsForSelections[number][2]+positionListButtonsForSelections[number][4])/2, fontSize*.67, "cvos")
                font:End()
            end
            local number = #trackedStatsNames + 1 --abs button
            if not absoluteOrNormalisedToggle then
                colour = buttonColour[1]
                font:SetTextColor(0, 5, .2, 1)
            else
                colour = buttonColour[2]
                font:SetTextColor(0.92, 0.92, 0.92, 1)
            end
            positionListButtonsForSelections[number] = {(x1 + (boarderWidth*screenRatio)),(y2)-(sizeYButton*1)+ (boarderWidth*screenRatio),(x1 + (2*sizeXButton)) - (boarderWidth*screenRatio),(y2)-(sizeYButton*4) +(boarderWidth*screenRatio)}
            UiButton(positionListButtonsForSelections[number][1],positionListButtonsForSelections[number][2],positionListButtonsForSelections[number][3],positionListButtonsForSelections[number][4], 1,1,1,1, 0,0,0,0, nil,colour[1],colour[2],0,0)
            font:Begin()
            font:Print("Normalised", (positionListButtonsForSelections[number][1]+positionListButtonsForSelections[number][3])/2,(positionListButtonsForSelections[number][2]+positionListButtonsForSelections[number][4])/2, fontSize, "cvos")
            font:End()

            number = #trackedStatsNames + 2 --teamcolour button
            if teamColourToggle then
                colour = buttonColour[1]
                font:SetTextColor(0, 5, .2, 1)
            else
                colour = buttonColour[2]
                font:SetTextColor(0.92, 0.92, 0.92, 1)
            end
            positionListButtonsForSelections[number] = {(x1 + (boarderWidth*screenRatio)),(y2)-(sizeYButton*5) + (boarderWidth*screenRatio),(x1 + (2*sizeXButton))- (boarderWidth*screenRatio),(y2)-(sizeYButton*8) + (boarderWidth*screenRatio)}
            UiButton(positionListButtonsForSelections[number][1],positionListButtonsForSelections[number][2],positionListButtonsForSelections[number][3],positionListButtonsForSelections[number][4], 1,1,1,1, 1,1,1,1, nil,colour[1],colour[2],2)
            font:Begin()
            font:Print("  Team\n Colours", (positionListButtonsForSelections[number][1]+positionListButtonsForSelections[number][3])/2,(positionListButtonsForSelections[number][2]+positionListButtonsForSelections[number][4])/2, fontSize, "cvos")
            font:End()

            ---name selections xxx requires a toggle
            x1 = posXl - (boarderWidth * screenRatio) - 100  --left
            x2 = posXl - (boarderWidth * screenRatio) --right
            y1 = posYb --btm
            y2 = posYt --top

            sizeYButton = (y2-y1) / #teamIDsorted
            sizeXButton = (x2-x1) - (boarderWidth * screenRatio)
            UiElement(x1 ,y1, x2, y2,1,1,1,1, 1,1,1,1, .5, {0,0,0,0.5},{1,1,1,0.05},boarderWidth/2)

            positionListButtonsForPlayerSelections = {}
            local intensity = 1
            for number, teamID in ipairs(teamIDsorted) do
                if comparisonTeamIDs[teamID] then
                    colour = buttonColour[1]
                    intensity = 1
                else
                    colour = buttonColour[2]
                    intensity = 0.2
                end
                positionListButtonsForPlayerSelections[number] = { x1 + (boarderWidth*screenRatio), y2 - (boarderWidth*screenRatio*0) - (sizeYButton*(number-1)*1) - sizeYButton,x2-(boarderWidth*screenRatio*1),y2 - (boarderWidth*screenRatio*0) - (sizeYButton*(number-1)*1)}
                UiButton(positionListButtonsForPlayerSelections[number][1],positionListButtonsForPlayerSelections[number][2],positionListButtonsForPlayerSelections[number][3],positionListButtonsForPlayerSelections[number][4], 1,1,1,1, 1,1,1,1, nil,colour[1],colour[2],2)
                font:SetTextColor(teamColourCache[teamID][1],teamColourCache[teamID][2],teamColourCache[teamID][3],intensity)
                local humanName = teamNamesCache[teamID]
                font:Begin()
                font:Print(humanName, (positionListButtonsForPlayerSelections[number][1]+positionListButtonsForPlayerSelections[number][3])/2,(positionListButtonsForPlayerSelections[number][2]+positionListButtonsForPlayerSelections[number][4])/2, fontSize, "cvos")
                font:End()
            end
        end)
    end
end

local function FractioniliseData(time,category)
    local cumTotal
    cumTotal = sagTeamTableStats[category][time].cumTotal
    if cumTotal < 0 then --values should never be negitive, but sometimes widget detect unittaken twice which could cause problems
        cumTotal = 0
    end
    if cumTotal > 0 then
        if cumTotal > sagTeamTableStats[category].largestCumTotal then
            sagTeamTableStats[category].largestCumTotal = cumTotal
        end
        local fraction = 0
        local fractionTable = {}
        local value = 0

        for teamID,_ in pairs(teamAllyTeamIDs) do
            value = sagTeamTableStats[category][time][teamID]
            if value > 0 then
                fraction = value / cumTotal
                sagTeamTableStats[category][time][teamID] = fraction
                fractionTable[teamID] = fraction
            end
        end

        local rankedTeamIDTable = {}
        for k in pairs(fractionTable) do    
            rankedTeamIDTable[#rankedTeamIDTable + 1] = k
        end
        table.sort(rankedTeamIDTable, function(a, b)
            return fractionTable[a] > fractionTable[b]
        end)
        sagTeamTableStats[category][time].ranks = rankedTeamIDTable
        local cumRanks = sagTeamTableStats[category]["cumRanks"]

        if rankedTeamIDTable[1] then
            sagTeamTableStats[category]["cumRanks"][rankedTeamIDTable[1]] = sagTeamTableStats[category]["cumRanks"][rankedTeamIDTable[1]] + 3
        end
        if rankedTeamIDTable[2] then
            sagTeamTableStats[category]["cumRanks"][rankedTeamIDTable[2]] = sagTeamTableStats[category]["cumRanks"][rankedTeamIDTable[2]] + 2
        end
        if rankedTeamIDTable[3] then
            sagTeamTableStats[category]["cumRanks"][rankedTeamIDTable[3]] = sagTeamTableStats[category]["cumRanks"][rankedTeamIDTable[3]] + 1
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

    FractioniliseData(snapShotNumber,"APM")
    FractioniliseData(snapShotNumber,"FPS")
end

local function LatestStatsExtract()
    for teamID,_ in pairs(teamAllyTeamIDs) do
        local twoTableTimePoints = Spring.GetTeamStatsHistory(teamID,snapShotNumber-1,snapShotNumber)
        if not twoTableTimePoints then
        else
            for stat,data in pairs(twoTableTimePoints[1]) do
                if trackedStats[stat] then
                    local value = twoTableTimePoints[2][stat] - data
                    AddInfoToSagTable(teamID, stat,value,snapShotNumber)
                end
            end
        end
    end
    local counter = 0
    local max = 0
    for k,_ in pairs(WG['saghelper']) do
        counter = counter + 1
        if k > max then max = k end
    end
    Spring.Echo ("running 1 LatestStatsExtract for Saghelper: snapShotNumber,counter",snapShotNumber,counter, max)
    if WG['saghelper'][snapShotNumber-1] then
        Spring.Echo ("running 2 LatestStatsExtract for Saghelper",snapShotNumber)
        local sagHelperStats = WG['saghelper'][snapShotNumber-1] --this is a different format of list: list[snapshotnumber[teamID][caterogy] = value
            for teamID,data in pairs(sagHelperStats) do
                for stat,value in pairs (sagHelperStats[teamID]) do
                    if trackedStats[stat] then
                        AddInfoToSagTable(teamID, stat,value,snapShotNumber)
                    end
                end
            end
        end


    for stat,_ in pairs(trackedStats) do
        FractioniliseData(snapShotNumber,stat)
    end
end

local function CompleteStatsExtract()
    --Spring.Echo("Complete Extract Running",Spring.GetTeamStatsHistory(0),snapShotNumber)
    local sagHelperStats = {}
    local twoTableTimePoints = {}
    for i = 1, Spring.GetTeamStatsHistory(0)-1 do --all the snapshots in the game so far
        PrimeSagTable(i)
        for teamID,_ in pairs(teamAllyTeamIDs) do

            twoTableTimePoints = Spring.GetTeamStatsHistory(teamID,i,i+1)
            for stat,data in pairs(twoTableTimePoints[1]) do
                if trackedStats[stat] then
                    local value = twoTableTimePoints[2][stat] - data
                    AddInfoToSagTable(teamID, stat,value,i)
                end
            end
        end
        if WG['saghelper'][i] then
        sagHelperStats = WG['saghelper'][i] --this is a different format of list: list[snapshotnumber[teamID][caterogy] = value
            for teamID,data in pairs(sagHelperStats) do
                for stat,value in pairs (sagHelperStats[teamID]) do
                    -- if antiSpam < 5 then
                    --     antiSpam = antiSpam + 1
                    --     Spring.Echo("stat,value,teamID, data",stat,value,teamID, data)
                    -- end
                    if trackedStats[stat] then
                        AddInfoToSagTable(teamID, stat,value,i)
                    end
                end
            end
        end




        for stat,_ in pairs(trackedStats) do
            FractioniliseData(i,stat)
        end
    end


    if Spring.GetTeamStatsHistory(0) > snapShotNumber then
        snapShotNumber = Spring.GetTeamStatsHistory(0) 
    end
end



local function DeleteLists()
    if drawStackedAreaGraphTeam then
        gl_DeleteList(drawStackedAreaGraphTeam)
        drawStackedAreaGraphTeam = nil
    end
    if drawStackedAreaGraphAxis then
        gl_DeleteList(drawStackedAreaGraphAxis)
        drawStackedAreaGraphAxis = nil
    end
    if drawButtonGraphs then
        gl_DeleteList(drawButtonGraphs)
        drawButtonGraphs = nil
    end
    if drawButtonsForSelections then
        gl_DeleteList(drawButtonsForSelections)
        drawButtonsForSelections = nil
    end
end

function widget:Initialize()
    DeleteLists()
    UiElement = WG.FlowUI.Draw.Element
    font =  WG['fonts'].getFont()
    UiButton = WG.FlowUI.Draw.Button
    if WG['saghelper'] then

    end
    CacheTeams()
    spectator, fullview = Spring.GetSpectatingState()
    PrimeSagTable(1)
    local n = Spring.GetGameFrame()
    snapShotNumber = math.floor((n /450))+1
    Spring.Echo("gameframe on init:",n, snapShotNumber)
    
    PrimeSagTable(snapShotNumber)
    DrawGraphToggleButton()
end

function widget:TextCommand(command)
    if string.find(command, "bug",nil,true) then
        --Spring.Echo("largestCumTotal for:",displayGraph ,sagTeamTableStats[displayGraph].largestCumTotal)
        --Spring.Echo("maxWind,minWind, predicted avgwind, GetWind",maxWind,minWind, maxWind*0.75, select(4,Spring.GetWind()))
        --Spring.Echo("WindDescriptionText", WindDescriptionText)
        --Spring.Echo(Spring.GetTeamStatsHistory(0))
        -- if WG['saghelper'] then
        --     local temptable = WG['saghelper']
        --     Spring.Echo("temptable",temptable)
        -- end
        --Spring.Echo("trackedStats",trackedStats)
        Spring.Echo("positionListButtonsForPlayerSelections",positionListButtonsForPlayerSelections)
        
        -- if comparisonToggle == false then
        --     comparisonToggle = true
        --     Spring.Echo("comparisonToggle ON")
        -- else
        --     comparisonToggle = false
        --     Spring.Echo("comparisonToggle off")
        -- end
    end

    if string.find(command, "stat", nil, true) then
        if displayGraphCounter >12 then displayGraphCounter = 1 end
        displayGraphCounter = displayGraphCounter + 1
        local counter = 0
        for stat,_ in pairs (trackedStats) do
            counter = counter + 1
            if counter == displayGraphCounter then
                displayGraph = stat
            end
        end
        SortCumRanks(displayGraph)
        DrawStackedAreaGraph()
        Spring.Echo("displayGraph is now :",displayGraph)
    end
    if string.find(command, "big", nil, true) then
        CompleteStatsExtract()
    end

    if string.find(command, "wind", nil, true) then
        if windGraphEnabled == false then
            windGraphEnabled = true
            Spring.Echo("windGraphEnabled are displayed")
        else
            windGraphEnabled = false
            Spring.Echo("windGraphEnabled are off")
        end
            DeleteLists()
            DrawStackedAreaGraph()
    end

end


local gameOver =1
local drawGraphType = "team"

function widget:DrawScreen()
    
    if drawer and gameOver then
        if drawStackedAreaGraphTeam and drawGraphType == "team" then
            gl_CallList(drawStackedAreaGraphTeam)  
        end
        if drawButtonsForSelections then
            gl_CallList(drawButtonsForSelections)
        end

        -- if drawStackedAreaGraphTeam and drawGraphType == "allyTeam" then
        --     gl_CallList(drawStackedAreaGraphAllyTeam)  
        -- end
        -- if drawGraphCurrentFrameLine[drawFrame] then
        --     gl_CallList(drawGraphCurrentFrameLine[drawFrame])
        -- end   
        if drawStackedAreaGraphAxis then
            gl_CallList(drawStackedAreaGraphAxis)
        end
    end
    if drawButtonGraphs then
        gl_CallList(drawButtonGraphs)
    end

end

function widget:GameFrame(n)
    -- if n > 30 and n % 450 ==0 then
    if (n+30) % 450 == 0 then --one second after to allow for helper widget to do it's thing on n+1
        Spring.Echo("running first update", n, (n+30) %450 )
        snapShotNumber = ((n+30) /450)+1
        PrimeSagTable(snapShotNumber)
        if spectator and fullview then
            LatestStatsExtract()
        end
        APMStatsExtract()
        SortCumRanks(displayGraph)
        if #windList >0 and maxWind > 0 then
            CalculateGameWindAverage()
        end
    end
        

    if n >30 and (n+15) % 450 ==0 then --xxx do i need the first conditoinal??
    Spring.Echo("running second update", n, (n+15) %450 )
        DeleteLists()
        DrawStackedAreaGraph()
        DrawGraphToggleButton()
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
    DeleteLists()
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

function widget:MousePress(mx, my, button) --Sets the way point if hotkey is pressed and factory type selected.
    if displayGraphButton then
        if mx >= buttonGraphsOnOffPositionList[1] and mx <=buttonGraphsOnOffPositionList[3] and my >=buttonGraphsOnOffPositionList[2] and my <=buttonGraphsOnOffPositionList[4] then --xxx could nest all these in a list
            if toggleButtonGraphs == false then
                toggleButtonGraphs = true
                drawer = true
                DeleteLists()
                DrawGraphToggleButton()
                DrawStackedAreaGraph()
                graphsOnScreen = true
                Spring.Echo("Graphs are displayed")
            else
                toggleButtonGraphs = false
                drawer = false
                DeleteLists()
                DrawGraphToggleButton()
                graphsOnScreen = false
                Spring.Echo("Graphs are not displayed")
            end
        end
    end
    if graphsOnScreen then
        local lengthOfList = #positionListButtonsForSelections
        Spring.Echo("mx,my")
        for number,_ in ipairs(positionListButtonsForSelections) do
            if mx >= positionListButtonsForSelections[number][1] and mx <= positionListButtonsForSelections[number][3] then
                if my <= positionListButtonsForSelections[number][2] and my >= positionListButtonsForSelections[number][4] then
                    if number <= lengthOfList -2 then
                        displayGraph = trackedStatsNames[number][1]
                        SortCumRanks(displayGraph)
                        DeleteLists()
                        DrawGraphToggleButton()
                        DrawStackedAreaGraph()
                        Spring.Echo("I have clicked on", number ,trackedStatsNames[number][1])
                    elseif number == lengthOfList -1 then
                        if absoluteOrNormalisedToggle then
                            absoluteOrNormalisedToggle = false
                            Spring.Echo("I have clicked Absolute, now OFF")
                        else
                            absoluteOrNormalisedToggle = true
                            Spring.Echo("I have clicked Absolute, now ON")
                        end
                        DeleteLists()
                        DrawStackedAreaGraph()
                        
                    elseif number == lengthOfList then
                        if teamColourToggle then
                            teamColourToggle = false
                            Spring.Echo("I have clicked teamColourToggle, now OFF")
                        else
                            teamColourToggle = true
                            Spring.Echo("I have clicked teamColourToggle, now ON")
                        end
                        DeleteLists()
                        DrawStackedAreaGraph()
                    end
                end
            end
        end
        for number,_ in pairs(positionListButtonsForPlayerSelections) do
            if mx >= positionListButtonsForPlayerSelections[number][1] and mx <= positionListButtonsForPlayerSelections[number][3] then
                if my >= positionListButtonsForPlayerSelections[number][2] and my <= positionListButtonsForPlayerSelections[number][4] then
                    if comparisonTeamIDs[number] then
                        local teamID = teamIDsorted[number]
                        comparisonTeamIDs[teamID] = false
                        Spring.Echo("I have clicked on team ID, number", teamID, number ,comparisonTeamIDs[teamID])
                        comparisonToggle = true
                    else
                        local teamID = teamIDsorted[number]
                        comparisonTeamIDs[teamID] = true
                        Spring.Echo("I have clicked on team ID, number", teamID ,number ,comparisonTeamIDs[teamID])
                        local counterA = 0
                        local counterB =0
                        for key,bool in pairs(comparisonTeamIDs) do
                            counterB = counterB + 1
                            if bool == true then
                                counterA = counterA+1
                            end
                        end
                        if counterA == counterB then
                            comparisonToggle = false
                        end
                    end
                    DeleteLists()
                    DrawGraphToggleButton()
                    DrawStackedAreaGraph()                      
                end
            end
        end
        
    end
end