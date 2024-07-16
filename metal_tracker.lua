function widget:GetInfo()
    return {
      name      = "Metal Tracker",
      desc      = "Tracks and displays resources sent to you",
      author    = "Mr_Chinny",
      date      = "July 2024",
      handler   = true,
      enabled   = true
    }
end
--V0.1 Initial release
--V0.2 Added buttons/graphics to hide names and/or when 0 metal has been sent, reset resources and include shared units values. Included Xoffset,
---------------------------------------------------------------------------------
--Use
---------------------------------------------------------------------------------
--This widget keeps track of the metal and energy sent to you during the game from each team mate.
--It can be toggled on/off by Alt+J, or whichever hotkey is bound to uikeys.txt (add to uikeys the following: 'bind           Alt+sc_j  metal_tracker')
--If in spec, it will keep track of each player of all teams. However it cannot know the what has happened in the enemy team should you be playing then resign.
--It should work for AI team mates / games.
--There are scaling options in the settings screen for custom widgets.


--TODO
-- Max length of list for V.large team, or add pages
-- Reset button for a player/tick off button once given T2
-- Improve formatting of metal energy
-- Combined total?

--BUGS/FUTURE work:
--Record sent resources (not really useful info tho)
--Check scavs, raptors etc,
--Play test what happens when unusaul team changes occur (eg archon mode)
--Some of the code is wasteful and repeating, go through and clean up.

---------------------------------------------------------------------------------
--Change these values to set 
---------------------------------------------------------------------------------

local custom_keybind_mode       = false -- Set to true for custom keybind, false for hotkeys defined in this code.
local hotkeys                   = {106} -- Alt-j bound. Only needed if custom_keybind_mode is set false. For Reference: 106 = j .Shift/Alt requirements must be changed on keypress function 
local defaultOn                 = true  -- show widgetgraphics on game start?
local clickedButtonCombined     = false -- show transfered units resources in the stats
local clickedButtonHideZero     = false
local clickedButtonShowAll      = false
---------------------------------------------------------------------------------
--Drawing and Scaling
---------------------------------------------------------------------------------
local vsx, vsy                  = Spring.GetViewGeometry() --might need to do some fancy stuff with this for larger/smaller resolutions, for now needed only to find right side of screen
local font
local uiScale                   = 1  --Can change in settings. xxx how to save the value?
local fontSizeDefault           = vsx/96 -- Want to be 20 for 1920 screen. (1920 / 96 = 20)
local fontSize                  = fontSizeDefault * uiScale
local yPadding                  = math.floor(fontSize/5) --Space between rows
local xPadding                  = math.floor(fontSize/2) --Space away from edge of screen
local buttonCombinedCoords      = {} --- {Xl,Yb,Xr,Yt}
local buttonColour      = {{{1,1,1,0.3},{0.5,0.5,0.5,0.3}},{{0,0,0,0.3},{0.5,0.5,0.5,0.3}}} --on/off and blend

local buttonNameCoords          = {} --- {Xl,Yb,Xr,Yt}
local buttonHideZeroCoords      = {} --- {Xl,Yb,Xr,Yt}
local buttonShowAllCoords       = {} --- {Xl,Yb,Xr,Yt}
local buttonResetZeroCoords     = {} --- {Xl,Yb,Xr,Yt}

local offsetX, offsetY          = -8,80 --Enough to avoid overlap of other right side menus, can be altered in settings
local nameStringWidth,metalStringWidth,unitStringWidth,otherStringWidth, maxStringWidth = 1,1,1,1, 6.5 --string widths
local playerListTop,playerListLeft,playerListRight,posX, posY, posXr, posYt --positions of playerlist and this widget, which will sit on top of it
local boarderWidth              = 6
local widgetHeight,widgetWidth  = 1,1 --Height/width of the widget, calculated on the go

local fontfile2                 = "fonts/" .. Spring.GetConfigString("bar_font2", "Exo2-SemiBold.otf")

local updateCounter             = 0
local updateImage               = false
local changedWidgetPos          = false
local stuffToDrawReady          = false
local drawer                    = false
local stuffToDraw 

--------------------------------------------------------------------------------
--Running Functions
--------------------------------------------------------------------------------

local printList                 = {} --Formatted list of things to print to screen
local whoami                         --Playername i am/or am speccing
local myTeamID                       --Will be the ID of me, or the person I am speccing
local allyTeamList              = {} --Contains list of of all players on each (ally)team. indexed by allyteamID+1 so as to avoid 0
local resourceList              = {} --Main table with all name /givers, created an populated once on game start.

--------------------------------------------------------------------------------
--  speedups?
--------------------------------------------------------------------------------

local gl_CreateList             = gl.CreateList
local gl_DeleteList             = gl.DeleteList
local gl_CallList               = gl.CallList
local UiElement

--------------------------------------------------------------------------------
--Config Stuff
--------------------------------------------------------------------------------

local config                    = {
        widgetScale = 1, --xxx rest to defaults before commits
        offsetY = 80,
        offsetX = -10
}
local OPTION_SPECS              = {
    -- TODO: add i18n to the names and descriptions
    {
        configVariable = "widgetScale",
        name = "Widget Size",
        description = "Widget Size",
        type = "slider",
        min = 0.2,
        max = 2,
        step = 0.05,
    },
    {
        configVariable = "offsetY",
        name = "Widget offsetY",
        description = "How far above adv player list the widget is",
        type = "slider",
        min = -512,
        max = vsy,
        step = 16,
    },

    {
        configVariable = "offsetX",
        name = "Widget offsetX",
        description = "Screen Position on X axis",
        type = "slider",
        min = -vsx,
        max = 0,
        step = 16,
    },
}


local function getOptionId(optionSpec)
    return "metal_tracker__" .. optionSpec.configVariable
  end
  
  local function getWidgetName()
    return "Metal Tracker"
  end
  
  local function getOptionValue(optionSpec)
    if optionSpec.type == "slider" then
      return config[optionSpec.configVariable]
    elseif optionSpec.type == "bool" then
      return config[optionSpec.configVariable]
    elseif optionSpec.type == "select" then
      -- we have text, we need index
      for i, v in ipairs(optionSpec.options) do
        if config[optionSpec.configVariable] == v then
          return i
        end
      end
    end
  end

  local function setOptionValue(optionSpec, value)
    if optionSpec.type == "slider" then
      config[optionSpec.configVariable] = value
    elseif optionSpec.type == "bool" then
      config[optionSpec.configVariable] = value
    elseif optionSpec.type == "select" then
      -- we have index, we need text
      config[optionSpec.configVariable] = optionSpec.options[value]
    end
        --InitGraphicUpdate()
  end
  
  local function createOnChange(optionSpec)
    return function(i, value, force)
      setOptionValue(optionSpec, value)
    end
  end
  
  local function createOptionFromSpec(optionSpec)
    local option = table.copy(optionSpec)
    option.configVariable = nil
    option.enabled = nil
    option.id = getOptionId(optionSpec)
    option.widgetname = getWidgetName()
    option.value = getOptionValue(optionSpec)
    option.onchange = createOnChange(optionSpec)
    WG['options'].addOption(option)
  end
--------------------------------------------------------------------------------
--Player Data Functions
--------------------------------------------------------------------------------

local function PopulateResourceList()
    for _,listof8names in pairs(allyTeamList) do
        for i,j in pairs(listof8names) do
            if not resourceList[i] then
                resourceList[i] ={}
            end
        end
        for i,j in pairs(listof8names) do
            for k,l in pairs(listof8names) do
                if i~=k then
                    resourceList[i][k]= {order = l.order, givername = k, metal =0, energy = 0, colour =l.colour ,unitmetal = 0, unitenergy = 0, showplayer =true}
                end
            end
        end
    end
end

local function FindAllPlayersOnAllyTeam() --creates a list with all allys per team, inc players and AI, stores colours too.
    allyTeamList ={}
    local numberOfTeams = Spring.Utilities.GetAllyTeamCount()
    for i= 0, numberOfTeams-1 do --all"real" teams (no gaia (or raptors?))
        local counter = 1
        for _,teamID in pairs(Spring.GetTeamList(i)) do
            if not allyTeamList[i+1] then
                allyTeamList[i+1] ={}
            end
            local miniPlayerList = Spring.GetPlayerList(teamID)
            local pid = miniPlayerList[1]
            if pid then --is a player on the teamID
                local name,active,isspec,playerID,allyTeamID,_,_,_ = Spring.GetPlayerInfo(miniPlayerList[1])
                if name and isspec ~= true then 
                    local r,g,b = Spring.GetTeamColor(pid)
                    allyTeamList[i+1][name] = {order = counter , colour = {r =r ,g=g, b=b}}
                end
            else --Ai or something else
                local a,b,allyTeamID,isAI,e,f,g,h,w,r,t,y  =  Spring.GetAIInfo(teamID)
                if isAI then
                    local name = Spring.GetGameRulesParam('ainame_' .. teamID)
                    local r,g,b = Spring.GetTeamColor(teamID)
                    allyTeamList[i+1][name] = {order = counter , colour = {r =r ,g=g, b=b}}
                end        
            end
            counter = counter + 1
        end
    end
end

local function gdParser(message) --parsers the message into names and numbers
    local giver = string.match(message,"<(.-)>")
    local receiver= string.match(message,"name=.+")
    receiver = string.sub(receiver,6, #receiver)

    local metalamount = string.match(message,"Metal:amount=%d+")
    if metalamount then
        metalamount = string.sub(metalamount,14, #metalamount)
    else metalamount = 0
    end

    local energyamount = string.match(message,"Energy:amount=%d+")
    if energyamount then
        energyamount = string.sub(energyamount,15, #energyamount)
    else energyamount = 0
    end
    return giver, metalamount, energyamount ,receiver
end

local function GetUnitCost (unitDefID)
    for a = 1, #UnitDefs do
        if a == unitDefID then
            return UnitDefs[a].metalCost,UnitDefs[a].energyCost
        end
    end
    return nil
end
--------------------------------------------------------------------------------
--Drawing Related Functions
--------------------------------------------------------------------------------

local function UpdateScales()
    fontSize = fontSizeDefault * uiScale
    xPadding = math.max(fontSizeDefault * uiScale / 2 ,6)
    yPadding = math.max(fontSizeDefault * uiScale / 4 ,2)
    widgetHeight = (#printList +1) * (fontSize + yPadding) + 2*(boarderWidth + yPadding)
    nameStringWidth = (maxStringWidth  * fontSize)
    metalStringWidth= font:GetTextWidth("8888 M    ")*fontSize/2
    unitStringWidth = font:GetTextWidth("energy ")*fontSize/2
    otherStringWidth = font:GetTextWidth("8")*fontSize
    widgetWidth = (nameStringWidth+metalStringWidth+ unitStringWidth +otherStringWidth)+2*(boarderWidth + xPadding)
    
end

local function MakePrintList()
    printList = {}
    fontSize = fontSizeDefault * uiScale
    maxStringWidth = 6.5
    local counter = 0
    for givername, list in pairs(resourceList[whoami]) do
        if list.showplayer == true then
            if clickedButtonHideZero == true and list.metal == 0 then
            else
                counter = counter +1
                local stringWidth = font:GetTextWidth(givername)
                if  stringWidth > maxStringWidth then
                    maxStringWidth = stringWidth
                end
                printList[counter] = {}
                local metal, energy, combinedMetal, combinedEnergy

                if clickedButtonCombined ==true then
                    combinedMetal = list.metal + list.unitmetal
                    combinedEnergy = list.energy + list.unitenergy
                else
                    combinedMetal = list.metal
                    combinedEnergy = list.energy
                end

                if combinedMetal <1000 then
                        metal = string.format("%6s",tostring(string.format("%3d",combinedMetal)))
                    elseif combinedMetal <1000000 then
                        metal = string.format("%.5s",tostring(string.format("%.3f",(combinedMetal / 1000)))).."K"
                    elseif combinedMetal <1000000000 then
                        metal = string.format("%.5s",tostring(string.format("%.3f",(combinedMetal / 1000000)))).."M"
                    else
                        metal = ">1M"
                end

                if combinedEnergy <1000 then
                    energy = string.format("%6s",tostring(string.format("%3d",combinedEnergy)))
                elseif combinedEnergy<1000000 then
                    energy = string.format("%.5s",tostring(string.format("%.3f",(combinedEnergy / 1000)))).."K"
                elseif combinedEnergy<1000000000 then
                    energy = string.format("%.5s",tostring(string.format("%.3f",(combinedEnergy / 1000000)))).."M"
                else
                    energy = ">1M"
                end
                printList[counter].givername = string.sub(givername,1,24)
                printList[counter].metal = metal
                printList[counter].energy = energy
                printList[counter].colour = list.colour
                printList[counter].order = list.order
                printList[counter].receivername = whoami
            end
        end
    end
    if #printList >0 then --XXX THIS MAY BREAK THE GRAPHIC UPDATE CHAIN, NEED TO EXIT SAFELY
        table.sort(printList, function (a,b) return a["order"] < b["order"] end) --orders in OS
    end
    UpdateScales()
end

function UpdatePosition(forceUpdate)
	if forceUpdate == nil then forceUpdate = false end
	local newUiScale = config.widgetScale --spGetConfigFloat('ui_scale', 1) or 1
    local newoffsetY = config.offsetY
    local newoffsetX = config.offsetX
	local uiScaleChanged = newUiScale ~= uiScale
    local offsetXChanged = newoffsetX ~= offsetX
    local offsetYChanged = newoffsetY ~= offsetY

	if (forceUpdate or uiScaleChanged or offsetYChanged or offsetXChanged) then
        if uiScaleChanged then
	        uiScale = newUiScale
            updateImage = true
        end
        offsetX = newoffsetX
        offsetY = newoffsetY
        changedWidgetPos = true
	end

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
		playerListTop,playerListLeft,playerListRight = playerListPos[1],playerListPos[2],playerListPos[4]
	else
		playerListTop,playerListLeft,playerListRight = 256,256, vsx
	end
    local oldposY = posY
    local oldposX = posX
    posY = playerListTop + offsetY
    posXr = playerListRight + offsetX
    posX = posXr - widgetWidth
    posYt = posY + widgetHeight
    if oldposX ~=posX or oldposY ~= posY then
        changedWidgetPos = true
    end
end

local function CreateTexture()
    if stuffToDraw then
		gl_DeleteList(stuffToDraw)
	end
    local colour
    buttonCombinedCoords = {(posXr- boarderWidth - 2.75*fontSize),(posYt-boarderWidth - (2*fontSize) + yPadding),(posXr- boarderWidth - 0  *fontSize),(posYt-boarderWidth)} --button to inc unit costs
    buttonHideZeroCoords = {(posXr- boarderWidth - 5.5*  fontSize),(posYt-boarderWidth - (2*fontSize) + yPadding),(posXr- boarderWidth - 2.75*fontSize),(posYt-boarderWidth)}--button to hide names with zero metal sent
    buttonShowAllCoords  = {(posXr- boarderWidth - 8.25*fontSize),(posYt-boarderWidth - (2*fontSize) + yPadding),(posXr- boarderWidth - 5.5  *fontSize),(posYt-boarderWidth)}--button to show all hidden names
    buttonNameCoords = {} --button /highlight to hide a player
    buttonResetZeroCoords = {}
    stuffToDraw = gl_CreateList(function()


        UiElement(posX,posY,posXr,posYt,1,1,1,1, 1,1,1,1, .5, {0,0,0,0.5},{1,1,1,0.05},boarderWidth) --widget outline

        if clickedButtonCombined then --show units button
            colour = buttonColour[1]
            font:SetTextColor(0, 0.6, 0, 1)
            font:SetOutlineColor(0, 0, 0, 1)
        else
            colour = buttonColour[2]
            font:SetTextColor(0.92, 0.92, 0.92, 1)
            font:SetOutlineColor(0, 0, 0, 1)
        end
        UiButton(buttonCombinedCoords[1],buttonCombinedCoords[2],buttonCombinedCoords[3],buttonCombinedCoords[4], 1,1,1,1, 1,1,1,1, nil,colour[1],colour[2],2)
        font:Print("Inc.Unit", buttonCombinedCoords[1]+((buttonCombinedCoords[3]-buttonCombinedCoords[1])/2),buttonCombinedCoords[2]+((buttonCombinedCoords[4]-buttonCombinedCoords[2])/2)+fontSize/3, fontSize*0.67, "cvos")
        font:Print("Values",buttonCombinedCoords[1]+((buttonCombinedCoords[3]-buttonCombinedCoords[1])/2),buttonCombinedCoords[2]+((buttonCombinedCoords[4]-buttonCombinedCoords[2])/2)-fontSize/3, fontSize*0.67, "cvos")

        if clickedButtonHideZero then --Hide all Zeross button
            colour = buttonColour[1]
            font:SetTextColor(0, 0.6, 0, 1)
            font:SetOutlineColor(0, 0, 0, 1)
        else
            colour = buttonColour[2]
            font:SetTextColor(0.92, 0.92, 0.92, 1)
            font:SetOutlineColor(0, 0, 0, 1)
        end
        UiButton(buttonHideZeroCoords[1],buttonHideZeroCoords[2],buttonHideZeroCoords[3],buttonHideZeroCoords[4], 1,1,1,1, 1,1,1,1, nil,colour[1],colour[2],2)
        font:Print("Hide", buttonHideZeroCoords[1]+((buttonHideZeroCoords[3]-buttonHideZeroCoords[1])/2),buttonHideZeroCoords[2]+((buttonHideZeroCoords[4]-buttonHideZeroCoords[2])/2)+fontSize/3, fontSize*0.67, "cvos")
        font:Print("Zeros",buttonHideZeroCoords[1]+((buttonHideZeroCoords[3]-buttonHideZeroCoords[1])/2),buttonHideZeroCoords[2]+((buttonHideZeroCoords[4]-buttonHideZeroCoords[2])/2)-fontSize/3, fontSize*0.67, "cvos")

        if clickedButtonShowAll then --Show All button
            colour = buttonColour[1]
            font:SetTextColor(0, 0.6, 0, 1)
            font:SetOutlineColor(0, 0, 0, 1)
        else
            colour = buttonColour[2]
            font:SetTextColor(0.92, 0.92, 0.92, 1)
            font:SetOutlineColor(0, 0, 0, 1)
        end
        UiButton(buttonShowAllCoords[1] ,buttonShowAllCoords[2] ,buttonShowAllCoords[3] ,buttonShowAllCoords[4] , 1,1,1,1, 1,1,1,1,nil,colour[1],colour[2],2)
        font:Print("Reveal",  buttonShowAllCoords[1]+((buttonShowAllCoords[3]-buttonShowAllCoords[1])/2),buttonShowAllCoords[2]+((buttonShowAllCoords[4]-buttonShowAllCoords[2])/2)+fontSize/3, fontSize*0.67, "cvos")
        font:Print("Hidden",buttonShowAllCoords[1]+((buttonShowAllCoords[3]-buttonShowAllCoords[1])/2),buttonShowAllCoords[2]+((buttonShowAllCoords[4]-buttonShowAllCoords[2])/2)-fontSize/3, fontSize*0.67, "cvos")
        
        for i,list in ipairs(printList) do
            buttonNameCoords[i] = {posX + boarderWidth, posYt - boarderWidth - (0.5* fontSize) - ((i+1)*(fontSize+yPadding)),posXr - (metalStringWidth + unitStringWidth + otherStringWidth  + xPadding), posYt -(0.5* fontSize)- boarderWidth - ((i)*(fontSize+yPadding)),list.receivername, list.givername }
            font:SetTextColor(list.colour.r,list.colour.g,list.colour.b,1)
            font:Print(list.givername,posXr - (metalStringWidth + unitStringWidth + otherStringWidth  + xPadding), posYt - boarderWidth - ((i+1)*(fontSize+yPadding) +yPadding),fontSize,"rxos") --"rvos"
        end

        for i,list in ipairs(printList) do
            font:SetTextColor(0.92, 0.92, 0.92, 1) -- Metal White
            font:Print(list.metal,posXr- (metalStringWidth + unitStringWidth + xPadding), posYt  - boarderWidth+ (fontSize-yPadding)/5 - ((i+1)*(fontSize+yPadding))+ 0*yPadding,fontSize/2,"xos")
        end

        for i,list in ipairs(printList) do
            font:SetTextColor(1,1,0,1) --yellow
            font:Print(list.energy, posXr - (metalStringWidth + unitStringWidth + xPadding), posYt  - boarderWidth - (fontSize-yPadding)/5- ((i+1)*(fontSize+ yPadding))-1*yPadding,fontSize/2,"xos")
        end

        for i,list in ipairs(printList) do
            buttonResetZeroCoords[i] = {posXr - boarderWidth -(metalStringWidth + unitStringWidth + xPadding), posYt - boarderWidth- (0.5* fontSize) - ((i+1)*(fontSize+yPadding)),posXr - boarderWidth- xPadding, posYt - boarderWidth - (0.5* fontSize)- ((i)*(fontSize+yPadding)),list.receivername, list.givername }
            font:SetTextColor(0.92, 0.92, 0.92, 1) --Metal White
            font:Print("metal",posXr- (metalStringWidth + xPadding), posYt - boarderWidth + (fontSize-yPadding)/5 - ((i+1)*(fontSize+yPadding))+0*yPadding,fontSize/2,"xos")
        end

        for i,list in ipairs(printList) do
            font:SetTextColor(1,1,0,1) --yellow
            font:Print("energy",posXr- (metalStringWidth + xPadding),posYt - boarderWidth - (fontSize-yPadding)/5- ((i+1)*(fontSize+ yPadding))-1*yPadding,fontSize/2,"xos")
        end
    end)
    stuffToDrawReady = true
end

local function InitGraphicUpdate()
    UpdateScales()
    MakePrintList()
    UpdatePosition(true)
    CreateTexture()
end



--------------------------------------------------------------------------------
--Hotkeys / Controls
--------------------------------------------------------------------------------
local function ShowWidget(show)
    if show then
        UpdatePosition()
        CreateTexture()
        drawer= true
    else
        drawer = false
        stuffToDrawReady = false
    end
end

local function MetalAction(_, b, _, args)
    if custom_keybind_mode then
        if args[1] then --pressed
            if drawer then --already on?
                ShowWidget(false)
            else
                ShowWidget(true)
            end
        end
    end
end

--------------------------------------------------------------------------------
--BAR Callins
--------------------------------------------------------------------------------
function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam)
    updateImage = true
    local giverStr
    local pidlist= Spring.GetPlayerList(newTeam)
    local receiverStr = Spring.GetPlayerInfo(pidlist[1])
    pidlist= Spring.GetPlayerList(oldTeam)
    if pidlist[1] then --if player specced /resigned they don't have a team. this can therefore be ignored as taken units shouldn't count.
            giverStr = Spring.GetPlayerInfo(pidlist[1])
    else
        return
    end
    local metalamount, energyamount = GetUnitCost(unitDefID)
    if metalamount then
        if resourceList[receiverStr] then
            if resourceList[receiverStr][giverStr] then
                resourceList[receiverStr][giverStr].unitmetal = resourceList[receiverStr][giverStr].unitmetal+metalamount
                resourceList[receiverStr][giverStr].unitenergy = resourceList[receiverStr][giverStr].unitenergy+energyamount
            end
        end
    end
end

function widget:MousePress(mx, my, button) --sets the way point if hotkey is pressed and factory type selected.
    if button == 1 and drawer then
        if mx >= buttonCombinedCoords[1] and mx <=buttonCombinedCoords[3] and my >=buttonCombinedCoords[2] and my <=buttonCombinedCoords[4] then --xxx could nest all these in a list
            if not clickedButtonCombined then
                clickedButtonCombined = true
                updateImage = true
            else
                clickedButtonCombined = false
                updateImage =true
            end
        elseif mx >= buttonHideZeroCoords[1] and mx <=buttonHideZeroCoords[3] and my >=buttonHideZeroCoords[2] and my <=buttonHideZeroCoords[4] then
            if not clickedButtonHideZero then
                clickedButtonHideZero = true
                updateImage = true
            else
                clickedButtonHideZero = false
                updateImage =true
            end
        elseif mx >= buttonShowAllCoords[1] and mx <=buttonShowAllCoords[3] and my >=buttonShowAllCoords[2] and my <=buttonShowAllCoords[4] then
            if not clickedButtonShowAll then
                clickedButtonShowAll = true
                for i, j in pairs(resourceList) do
                    for i2,j2 in pairs(j) do
                        j2.showplayer =true
                    end
                end
                updateImage = true
            end
        end
        for i, j in ipairs(buttonNameCoords) do
            if mx >= buttonNameCoords[i][1] and mx <=buttonNameCoords[i][3] and my >=buttonNameCoords[i][2] and my <=buttonNameCoords[i][4] then
                resourceList[buttonNameCoords[i][5]][buttonNameCoords[i][6]].showplayer = false
                updateImage =true
            end
        end
        for i, j in ipairs(buttonResetZeroCoords) do
            if mx >= buttonResetZeroCoords[i][1] and mx <=buttonResetZeroCoords[i][3] and my >=buttonResetZeroCoords[i][2] and my <=buttonResetZeroCoords[i][4] then
                resourceList[buttonResetZeroCoords[i][5]][buttonResetZeroCoords[i][6]].metal = 0
                resourceList[buttonResetZeroCoords[i][5]][buttonResetZeroCoords[i][6]].energy = 0
                resourceList[buttonResetZeroCoords[i][5]][buttonResetZeroCoords[i][6]].unitmetal = 0
                resourceList[buttonResetZeroCoords[i][5]][buttonResetZeroCoords[i][6]].unitenergy = 0
                updateImage =true
            end
        end
        
    end
end
function widget:KeyPress(key, mods, isRepeat)
    if not custom_keybind_mode and mods.alt  == true and not isRepeat then
        if hotkeys[1] == key then
            if drawer then --already on?
                ShowWidget(false)
            else
                ShowWidget(true)
            end
        end
     end
end

function widget:AddConsoleLine(msg, priority)
    if string.find(msg, ":ui.playersList.chat.giveMetal:amount=") or string.find(msg, ":ui.playersList.chat.giveEnergy:amount=") then
        local giverStr, metalamount,energyamount, receiverStr = gdParser(msg)
        updateImage = true
        if resourceList[receiverStr] then
            if resourceList[receiverStr][giverStr] then
                resourceList[receiverStr][giverStr].metal = resourceList[receiverStr][giverStr].metal+metalamount
                resourceList[receiverStr][giverStr].energy = resourceList[receiverStr][giverStr].energy+energyamount
            end
       end
    end
end

function widget:DrawScreen()
    if drawer == true and stuffToDrawReady == true then
        gl_CallList(stuffToDraw)
        local mx, my, b = Spring.GetMouseState()
        for i, j in ipairs(buttonNameCoords) do
            if mx >= buttonNameCoords[i][1] and mx <=buttonNameCoords[i][3] and my >=buttonNameCoords[i][2] and my <=buttonNameCoords[i][4] then
                UiSelectHighlight(buttonNameCoords[i][1],buttonNameCoords[i][2],buttonNameCoords[i][3],buttonNameCoords[i][4],nil,0.2,nil)
            end
        end
        for i, j in ipairs(buttonResetZeroCoords) do
            if mx >= buttonResetZeroCoords[i][1] and mx <=buttonResetZeroCoords[i][3] and my >=buttonResetZeroCoords[i][2] and my <=buttonResetZeroCoords[i][4] then
                UiSelectHighlight(buttonResetZeroCoords[i][1],buttonResetZeroCoords[i][2],buttonResetZeroCoords[i][3],buttonResetZeroCoords[i][4],nil,0.2,nil)
            end
        end
        if mx >= buttonShowAllCoords[1] and mx <=buttonShowAllCoords[3] and my >=buttonShowAllCoords[2] and my <=buttonShowAllCoords[4] then
            UiSelectHighlight(buttonShowAllCoords[1],buttonShowAllCoords[2],buttonShowAllCoords[3],buttonShowAllCoords[4],nil,0.2,nil)

        elseif mx >= buttonHideZeroCoords[1] and mx <=buttonHideZeroCoords[3] and my >=buttonHideZeroCoords[2] and my <=buttonHideZeroCoords[4] then
            UiSelectHighlight(buttonHideZeroCoords[1],buttonHideZeroCoords[2],buttonHideZeroCoords[3],buttonHideZeroCoords[4],nil,0.2,nil)

        elseif mx >= buttonCombinedCoords[1] and mx <=buttonCombinedCoords[3] and my >=buttonCombinedCoords[2] and my <=buttonCombinedCoords[4] then
            UiSelectHighlight(buttonCombinedCoords[1],buttonCombinedCoords[2],buttonCombinedCoords[3],buttonCombinedCoords[4],nil,0.2,nil)
        end
    end
end

function widget:Update(dt)
    updateCounter = updateCounter+1
	local prevMyTeamID = myTeamID
	if Spring.GetMyTeamID() ~= prevMyTeamID then --check if the team that we are spectating/on changed
        myTeamID = Spring.GetMyTeamID()
        whoami,_,_,_,_,_,_,_,_ = Spring.GetPlayerInfo(myTeamID,false)
        updateImage = true
	end
    if updateCounter % 100 == 0 then
        if clickedButtonShowAll == true then 
            clickedButtonShowAll = false
        end
        UpdatePosition(false)
        if changedWidgetPos == true then
            changedWidgetPos = false
            CreateTexture()
        end
    end
    if updateImage then
        InitGraphicUpdate()
        updateImage = false
    end
end


function widget:Initialize()
    widgetHandler.actionHandler:AddAction(self, "metal_tracker", MetalAction, { true }, "pR")
    widgetHandler.actionHandler:AddAction(self, "metal_tracker", MetalAction, { false }, "r")

    font =  WG['fonts'].getFont(fontfile2, 1.0, math.max(0.16, 0.25 / uiScale), math.max(4.5, 6 / uiScale))
    UiElement = WG.FlowUI.Draw.Element
    UiButton = WG.FlowUI.Draw.Button
    UiSelectHighlight = WG.FlowUI.Draw.SelectHighlight
    myTeamID = Spring.GetMyTeamID()
    whoami = Spring.GetPlayerInfo(myTeamID,false)
    if WG['options'] ~= nil then
        WG['options'].addOptions(table.map(OPTION_SPECS, createOptionFromSpec))
    end
    FindAllPlayersOnAllyTeam()
    PopulateResourceList()
    InitGraphicUpdate()
    if defaultOn == true then
        drawer= true
    end
end

function widget:Shutdown()
    if WG['options'] ~= nil then
        WG['options'].removeOptions(table.map(OPTION_SPECS, getOptionId))
    end
    if stuffToDraw then
		gl_DeleteList(stuffToDraw)
	end
end

function widget:ViewResize()
    vsx, vsy = Spring.GetViewGeometry()
end
