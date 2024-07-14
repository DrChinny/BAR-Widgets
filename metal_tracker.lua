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
--V.0.1
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

local offsetX, offsetY          = 8,80 --Enough to avoid overlap of other right side menus, can be altered in settings
local nameStringWidth,metalStringWidth,unitStringWidth,otherStringWidth, maxStringWidth = 1,1,1,1,1 --string widths
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
        widgetScale = 1,
        offsetY = 80,
        offsetX = 20
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

    -- {
    --     configVariable = "offsetX",
    --     name = "Widget offsetX",
    --     description = "Screen Position on X axis",
    --     type = "slider",
    --     min = -vsx,
    --     max = 0,
    --     step = 16,
    -- },
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
                    resourceList[i][k]= {order = l.order, givername = k, metal =0, energy = 0, colour =l.colour}
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

--------------------------------------------------------------------------------
--Drawing Related Functions
--------------------------------------------------------------------------------

local function UpdateScales()
    fontSize = fontSizeDefault * uiScale
    xPadding = math.max(fontSizeDefault * uiScale / 2 ,6)
    yPadding = math.max(fontSizeDefault * uiScale / 4 ,2)
    widgetHeight = #printList * (fontSize + yPadding) + 2*(boarderWidth + yPadding)
    nameStringWidth = maxStringWidth  * fontSize
    metalStringWidth= font:GetTextWidth("8888 M  ")*fontSize/2
    unitStringWidth = font:GetTextWidth("energy ")*fontSize/2
    otherStringWidth = font:GetTextWidth(" donated  ")*fontSize/1.33
    widgetWidth = (nameStringWidth+metalStringWidth+ unitStringWidth +otherStringWidth)+2*(boarderWidth + xPadding)
    
end

local function MakePrintList()
    printList = {}
    fontSize = fontSizeDefault * uiScale
    nameStringWidth = 5
    maxStringWidth = 5
    local counter = 0
    for givername, list in pairs(resourceList[whoami]) do
        counter = counter +1
        local stringWidth = font:GetTextWidth(givername)
        if  stringWidth > maxStringWidth then
            maxStringWidth = stringWidth
        end
        printList[counter] = {}
        local metal, energy
        if list.metal <1000 then
                metal = string.format("%6s",tostring(string.format("%3d",list.metal)))
            elseif list.metal <1000000 then
                metal = string.format("%.5s",tostring(string.format("%.3f",(list.metal / 1000)))).." K"
            elseif list.metal <1000000000 then
                metal = string.format("%.5s",tostring(string.format("%.3f",(list.metal / 1000000)))).." M"
            else
                metal = "TOO MUCH"
        end

        if list.energy <1000 then
            energy = string.format("%6s",tostring(string.format("%3d",list.energy)))
        elseif list.energy<1000000 then
            energy = string.format("%.5s",tostring(string.format("%.3f",(list.energy / 1000)))).." K"
        elseif list.energy<1000000000 then
            energy = string.format("%.5s",tostring(string.format("%.3f",(list.energy / 1000000)))).." M"
        else
            energy = "TOO MUCH"
        end
        printList[counter].givername = string.sub(givername,1,24)
        printList[counter].metal = metal
        printList[counter].energy = energy
        printList[counter].colour = list.colour
        printList[counter].order = list.order
    end
    table.sort(printList, function (a,b) return a["order"] < b["order"] end) --orders in OS
    UpdateScales()
end

function UpdatePosition(forceUpdate)
	if forceUpdate == nil then forceUpdate = false end
	local newUiScale = config.widgetScale --spGetConfigFloat('ui_scale', 1) or 1
    local newoffsetY = config.offsetY
	local uiScaleChanged = newUiScale ~= uiScale
    --local offsetXChanged = newoffsetX ~= offsetX
    local offsetYChanged = newoffsetY ~= offsetY

	if (forceUpdate or uiScaleChanged or offsetYChanged) then --or offsetXChanged
        if uiScaleChanged then
	        uiScale = newUiScale
            updateImage = true
        end
        --offsetX = newoffsetX
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
    posXr = playerListRight - offsetX
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
    stuffToDraw = gl_CreateList(function()
        UiElement(posX,posY,posXr,posYt,1,1,1,1, 1,1,1,1, .5, {0,0,0,0.5},{1,1,1,0.05},boarderWidth)
        
        for i,list in ipairs(printList) do
            font:SetTextColor(list.colour.r,list.colour.g,list.colour.b,1)
            font:Print(list.givername,posXr - (metalStringWidth + unitStringWidth + otherStringWidth  + xPadding), posYt - boarderWidth - ((i)*(fontSize+yPadding)),fontSize,"rxos") --"rvos"
        end
        for i,list in ipairs(printList) do
            font:SetTextColor(list.colour.r,list.colour.g,list.colour.b,1)
            font:Print("donated ",posXr - (metalStringWidth + unitStringWidth + xPadding) ,posYt  - boarderWidth+ uiScale- ((i)*(fontSize+yPadding)),fontSize/1.33,"rxos") --uiscale offset centers nicely the text I HAVE NO FUCKING CLUE
        end
        
        for i,list in ipairs(printList) do
            font:SetTextColor(1,1,1,1) --White
            font:Print(list.metal,posXr- (metalStringWidth + unitStringWidth + xPadding), posYt  - boarderWidth+ (fontSize-yPadding)/5 - ((i)*(fontSize+yPadding))+yPadding,fontSize/2,"xos")
        end
        for i,list in ipairs(printList) do
            font:SetTextColor(1,1,1,1) --White
            font:Print("metal",posXr- (metalStringWidth + xPadding), posYt - boarderWidth + (fontSize-yPadding)/5 - ((i)*(fontSize+yPadding))+yPadding,fontSize/2,"xos")
        end

        for i,list in ipairs(printList) do
            font:SetTextColor(1,1,0,1) --yellow
            font:Print(list.energy,posXr- (metalStringWidth + unitStringWidth + xPadding),posYt  - boarderWidth - (fontSize-yPadding)/5- ((i)*(fontSize+ yPadding)),fontSize/2,"xos")
        end
        for i,list in ipairs(printList) do
            font:SetTextColor(1,1,0,1) --yellow
            font:Print("energy",posXr- (metalStringWidth + xPadding),posYt - boarderWidth - (fontSize-yPadding)/5- ((i)*(fontSize+ yPadding)),fontSize/2,"xos")
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
