function widget:GetInfo()
    return {
      name      = "Factory Extra Rally Points",
      desc      = "Allows multiple rally queues for units built out of factories",
      author    = "Mr_Chinny",
      date      = "July 2024",
      handler   = true,
      enabled   = true
    }
end
---------------
--Instructions
---------------
--Tired of rezbots and constructors following your tick spam into enemy artillery? Want your AA to rally to a different spot from your front liners? Then this is the Widget for you!
--This widget allows the creation of a second and third (and any amount!) of extra rally points for units leaving factories.

--Making Extra Rally Points
    --Extra rally points are made by holding a hotkey ("j" or "u" by default) and Middleclicking while a factory(s) is selected. Holding Shift and hotkey while clicking allows a queue of waypoints.
    --The default is move command, but [Fight and Patrol] queues can be achieved by pressing command button on the factory before making a rally poiny node. Node will change colour.
    --Set a guard command to a unit by setting the rally point to a friendly unit - Note the queue of rally points will be removed if this unit dies.

--Assigning Units To Rally Points
    --Units can be assigned to a rally point by pressing the hotkey whilst hovering over the unit picture in the factory build menu. To remove unit from the rally point press the hotkey again.
    --In V0.1 there is no icon change / visual cue other than an ingame echo message.
    --If a rally point out of a factory doesn't exist, units will default to the engine rally.
    --See 'Configuable' below to add units to a rally point by default, 

--Hotkeys 
    --Compatible with uikey.txt. Change 'custom_keybind_mode' to true to use this setup (recommended for easy hotkey manageament).
    --Go to uikeys.txt and add (eg):  
        --bind           any+sc_j  extra_factory_rally 1
        --bind           any+sc_u  extra_factory_rally 2
        --Following the same numbering format for any extra rally points above 2
    --Hotkeys are "j" and "u" by default.
    --Changing max rally points will require a hotkey for each, to be added in "hotkey" or uikey.txt.

----------
--Info
----------
--V.0.1
--Status 
--Code works and tested for skirmish, not been able to crash. Behaviour of units and way points achieves aim. Generally feels intuitive and close to engines rally point behaviour.
--Still using placeholder graphics, no decent notifcation of units added to rally groups, other than Echo/sound.
--Need to address behvaiour of team changes, speccing etc that may crash widget if not addressed.
--No configuation outside of code

--TODO
--Sounds - improve
--Major Work - Graphical Represenation of rally groups when assigning eg Pawn --need to tie into buildmenu.
--Possible to tie into drag menu for line dragging multiple rally points? change mouse button from middle to right click (Would need to stop engine's rally point from setting at same time)
--Config options in menu.
--Bug check, edge cases etc.

--Known/possible Bugs
--Bug where rally pointed units need to go back to factory position after being made if not going in direction of factory facing. Fixed?

------------
--Variables
------------
--Configable
local maxRallyPoints            = 2 --Two is more than enough, but can increase to any number. Each will need a hotkey assigned.
local custom_keybind_mode       = false -- Set to true for custom keybind, false for hotkeys defined in this code.
local hotkeys                   = {106,117} -- For Reference: 106 = j, 117 = u, 107 = k. Only needed if custom_keybind_mode is set false
local defaultRallyedUnits       = {} -- Place units here to be included by default. Uses unitdefid and a list per rally group: format: {{num1,num2,num3},{num4,num5}}. eg {{163,101},{95}} 
local colourList                = {{1.0, 1.0, 0.0, 0.6},{1.0, 0.6, 0.0, 0.6},{1.0, 0.3, 0.2, 0.6}}  --{R,G,B,A} of different rally points

--Graphical / Audio
local GL_LINE_STRIP             = GL.LINE_STRIP
local glLineStipple             = gl.LineStipple
local glVertex                  = gl.Vertex
local glBeginEnd                = gl.BeginEnd
local glDrawGroundCircle		= gl.DrawGroundCircle
local glColor                   = gl.Color
local gdMarkers                 = true
local soundMove                 = "sounds/commands/cmd-move.wav"
local soundGuard                = "sounds/commands/cmd-guard.wav"
local soundOn                   = "sounds/commands/cmd-on.wav"
local soundOff                  = "sounds/commands/cmd-off.wav"

local cmdColours = {
                    stop       ={ 0.0 , 0.0 , 0.0 , 0.7},
                    wait       ={ 0.5 , 0.5 , 0.5 , 0.7},
                    build      ={ 0.0 , 1.0 , 0.0 , 0.3},
                    move       ={ 0.5 , 1.0 , 0.5 , 0.6},
                    attack     ={ 1.0 , 0.2 , 0.2 , 0.5},
                    fight      ={ 1.0 , 0.2 , 1.0 , 0.6},
                    guard      ={ 0.6 , 1.0 , 1.0 , 0.3},
                    patrol     ={ 0.2 , 0.5 , 1.0 , 0.6},
                    capture    ={ 1.0 , 1.0 , 0.3 , 0.6},
                    repair     ={ 1.0 , 0.9 , 0.2 , 0.6},
                    reclaim    ={ 0.5 , 1.0 , 0.4 , 0.3},
                    restore    ={ 0.0 , 1.0 , 0.0 , 0.3},
                    resurrect  ={ 0.9 , 0.5 , 1.0 , 0.5},
                    load       ={ 0.4 , 0.9 , 0.9 , 0.7},
                    unload     ={ 1.0 , 0.8 , 0.0 , 0.7},
                    deathWatch ={ 0.5 , 0.5 , 0.5 , 0.7},
}

--local iconTypes = VFS.Include("gamedata/icontypes.lua") --Future work

--Others loaded locally to speed up
local spTraceScreenRay          = Spring.TraceScreenRay
local spGetMyTeamID             = Spring.GetMyTeamID
local allyID                    = Spring.GetMyAllyTeamID()

--hotkey related
local keyType                   = nil
local keyDown                   = false
local shiftKey                  = false

--Main vars --Descriptions of main tables/vars used
local gdMasterIsFactoryTable    = {} --Master list that all types of factory types from UnitDefs. [UnitDefsID, true]
local gdRallyPointList          = {} --Holds All rally point information.
local gdGuardedUnits            = {} --A list of all units currently with a guard/follow command from rally point queue
local gdFactorySelectedTable    = {} --Shows any currently selected factories {X,Y,Z,UnitID}
local gdIsFactorybyID           = {} --Updated of all factories for player [indexed by facID)
local gdRedirectedUnitList      = {} --Dynamic list containing which rally point a unit type follows.
local gdDrawCoords              = {} -- Easily accessable list of sets of 3 coords for drawing functions

--Run checks -- Ensures functions don't run twice in a row/ needlessly
local gdDrawTime                = false --true if need to call draw function
local gdJustUpdated             = false
local gdSelectionChangedVar     = false --true to run update on frist frame after selection change
local gdpassedTime              = 0

--Initialise some of the default tables
for a = 1, #UnitDefs do
	if UnitDefs[a].isFactory then
        gdMasterIsFactoryTable[a] = true
	end
end

if #colourList < maxRallyPoints then
    for i = #colourList, maxRallyPoints do
        colourList[i+1] = {1.0, 1.0, 1.0, 0.5}
    end
end

for unitDefID, name in pairs(UnitDefs) do
    for indexwp, listwp in pairs (defaultRallyedUnits) do
        for _,uid in pairs(listwp) do
            if unitDefID == uid then
                gdRedirectedUnitList[uid] = indexwp
                
            end
        end
    end
end

--local functions

local function IndexlessTableCheck(t) --Safely checks if a table contains values
    for i,k in pairs(t) do
        if t[i] ~= nil then return true end
    end
    return false
end

local function AddUnitTypeToRallyPointGroup(unitDefID,wpGroup) --Changes the Rallygroup that a unitdefid belongs to.
    if gdRedirectedUnitList[unitDefID] ==wpGroup then
        Spring.Echo(UnitDefs[unitDefID].translatedHumanName,"REMOVED from Extra Rally Points")
        gdRedirectedUnitList[unitDefID] = nil
        Spring.PlaySoundFile(soundOff, 0.5, 'ui')
    else
        gdRedirectedUnitList[unitDefID] = wpGroup
        Spring.Echo(UnitDefs[unitDefID].translatedHumanName,"ADDED to Extra Rally GROUP: " , wpGroup)
        Spring.PlaySoundFile(soundOn, 0.5, 'ui')
    end
    keyDown,gdJustUpdated,keyType = false,false,nil
end

local function CheckToDraw() --Checks if something needs to be drawn and updates gdDrawCoords, Should only run when something changes.
    gdDrawTime = false
    if #gdFactorySelectedTable >0 and IndexlessTableCheck(gdRallyPointList) then
        gdDrawCoords = {}
        local tempCoords = {}
        for _ , fstvalue in pairs(gdFactorySelectedTable) do
            if gdRallyPointList[fstvalue.factoryID] ~= nil then
                for wpiindex,wpivalue in pairs(gdRallyPointList[fstvalue.factoryID]) do
                    if wpivalue.use == true then
                        if gdDrawCoords[wpiindex] == nil then
                            gdDrawCoords[wpiindex] = {}
                        end
                        tempCoords = { x= wpivalue.x, y= wpivalue.y, z= wpivalue.z, factoryID = fstvalue.factoryID, colour = wpivalue.cursor}
                        table.insert(gdDrawCoords[wpiindex],tempCoords)
                        gdDrawTime = true
                    end
                end
            end
        end
        gdDrawCoords= table.copy(gdDrawCoords)
    end
end

local function InitialiseNewFactory(factoryID) --as soon as a new factory is made initialise all default values.
    if gdRallyPointList[factoryID] == nil then
        gdRallyPointList[factoryID] = {}
        for i=1, maxRallyPoints do
            gdRallyPointList[factoryID][i] = {x={gdIsFactorybyID[factoryID].x,x},y={gdIsFactorybyID[factoryID].y,y},z={gdIsFactorybyID[factoryID].z,z}, guard={false},use=false, cursor={"none"}}
        end
    end
end

local function AddToFactoryList(unitID) --Adds factory to table of players factories
    local x,y,z = Spring.GetUnitPosition(unitID)
    gdIsFactorybyID[unitID] = {x=x, y=y, z=z}
    InitialiseNewFactory(unitID)
end

local function FindFactories(teamID) --Searches all Factories on team. Adds to gdIsFactoryByID if on players team. Ran on initialise only.
    local factoryIDList = {}
    for index,value in pairs(gdMasterIsFactoryTable) do
        factoryIDList = Spring.GetTeamUnitsByDefs(teamID,index)
        for _,value2 in ipairs(factoryIDList) do
            AddToFactoryList(value2)
        end
    end  
end

local function RemoveFromFactoryList(unitID, unitDefID)  --Removes a factory from table of player factories
    gdIsFactorybyID[unitID] = nil
end

local function CheckIfUnitToBeRallyedExists(unitDefID)
    if gdRedirectedUnitList[unitDefID] then
        return gdRedirectedUnitList[unitDefID]
    end
    return nil
end

local function CheckAndRemoveFromGuardedList(unitID,removeWPList)
    local check = false
    local affectedIDs,affectedWPinFactory ={},{}--for wap with same factoryID and WPI as a destroyed unit
    if unitID then
        for i,j in pairs(gdGuardedUnits) do
            if j.UID == unitID then --remove units from guardedunitslist if unit being rally pointed to is destroyed
                table.insert(affectedWPinFactory,{FID= j.FID,WPI = j.WPI})
                gdRallyPointList[j.FID][j.WPI] = {x={gdIsFactorybyID[j.FID].x,x},y={gdIsFactorybyID[j.FID].y,y},z={gdIsFactorybyID[j.FID].z,z},use=true, guard={false},cursor= {"none"}}
                check = true
            elseif j.FID == unitID then --remove units from guardedunitslist if factory rally pointing to that unit is destoryed. need a check when rally point is reset as well!
                gdGuardedUnits[i] =nil
                check = true
            end
        end
    end
    if removeWPList then
        for i,j in pairs(gdGuardedUnits) do
            if j.FID ==removeWPList.FID and j.WPI == removeWPList.WPI then
                table.insert(affectedWPinFactory,{FID= j.FID,WPI = j.WPI})
                check = true
            end
        end

    end

    if check then
        for i,j in pairs(gdGuardedUnits) do
            for i2,j2 in pairs(affectedWPinFactory) do
                if j.FID == j2.FID and j.WPI == j2.WPI then
                    affectedIDs[i] = true
                end
            end
        end
        for i,j in pairs(affectedIDs) do
            gdGuardedUnits[i] =nil      
        end
        CheckToDraw()
    end
end

local function OrderListForUnit(unitID, factoryID, wayPointInt)
    for index,_ in pairs(gdRallyPointList) do
        if index == factoryID and gdRallyPointList[factoryID][wayPointInt].use then
            for i = 2, #gdRallyPointList[factoryID][wayPointInt].x do
                local wayPointCoord = {gdRallyPointList[factoryID][wayPointInt].x[i],gdRallyPointList[factoryID][wayPointInt].y[i],gdRallyPointList[factoryID][wayPointInt].z[i]}
                if gdRallyPointList[factoryID][wayPointInt].guard[i] then
                    Spring.GiveOrderToUnit(unitID, CMD.GUARD,gdRallyPointList[factoryID][wayPointInt].guard[i], {"shift"})
                else
                    if gdRallyPointList[factoryID][wayPointInt].cursor[i] == "Fight" then
                        Spring.GiveOrderToUnit(unitID, CMD.FIGHT,wayPointCoord, {"shift"})
                    elseif gdRallyPointList[factoryID][wayPointInt].cursor[i] == "Patrol" then
                        Spring.GiveOrderToUnit(unitID, CMD.PATROL,wayPointCoord, {"shift"})
                    else
                        Spring.GiveOrderToUnit(unitID, CMD.MOVE,wayPointCoord, {"shift"})
                    end
                end
            end
        end
    end
end

local function AddNewRallyPoint(x,y,z,factoryID, wayPointInt,targetType,cursorType)
    --reset rally points # and place exactly one new one (plus default)
    if shiftKey == false then --reset only the selected rally point to current mouse coords
        gdRallyPointList[factoryID][wayPointInt] = {x={gdIsFactorybyID[factoryID].x,x},y={gdIsFactorybyID[factoryID].y,y},z={gdIsFactorybyID[factoryID].z,z},use=true, guard={false},cursor={"none"}}
        CheckAndRemoveFromGuardedList(nil,{FID = factoryID, WPI = wayPointInt})

        if targetType.type == "unit" then
            table.insert(gdRallyPointList[factoryID][wayPointInt].guard,targetType.ID)
            table.insert(gdRallyPointList[factoryID][wayPointInt].cursor,cursorType)    
            table.insert(gdGuardedUnits,{UID=targetType.ID ,FID = factoryID, WPI = wayPointInt, WPQ = #gdRallyPointList[factoryID][wayPointInt].guard })
            Spring.PlaySoundFile(soundGuard, 0.5, 'ui')

        else
            table.insert(gdRallyPointList[factoryID][wayPointInt].guard,false)
            table.insert(gdRallyPointList[factoryID][wayPointInt].cursor,cursorType)
            Spring.PlaySoundFile(soundMove, 0.5, 'ui')
        end
--add rally point if shift held on
    elseif shiftKey ==true then --only add second rally point if shift is pressed
        for index,value in pairs (gdRallyPointList) do
            if index == factoryID then -- to add another way point on top of existing ones
                local tempx, tempy, tempz ={},{},{}
                tempx, tempy,tempz = gdRallyPointList[factoryID][wayPointInt].x, gdRallyPointList[factoryID][wayPointInt].y , gdRallyPointList[factoryID][wayPointInt].z
                table.insert(tempx,x) ; table.insert(tempy,y); table.insert(tempz,z)
                gdRallyPointList[factoryID][wayPointInt].x= tempx ;gdRallyPointList[factoryID][wayPointInt].y= tempy;gdRallyPointList[factoryID][wayPointInt].z= tempz;gdRallyPointList[factoryID][wayPointInt].use = true
                if targetType.type == "unit" then
                    table.insert(gdRallyPointList[factoryID][wayPointInt].guard,targetType.ID)
                    table.insert(gdRallyPointList[factoryID][wayPointInt].cursor,cursorType)
                    table.insert(gdGuardedUnits,{UID=targetType.ID ,FID = factoryID, WPI = wayPointInt, WPQ = #gdRallyPointList[factoryID][wayPointInt].guard })
                    Spring.PlaySoundFile(soundGuard, 0.5, 'ui')
                else
                    table.insert(gdRallyPointList[factoryID][wayPointInt].guard,false)
                    table.insert(gdRallyPointList[factoryID][wayPointInt].cursor,cursorType)
                    Spring.PlaySoundFile(soundMove, 0.5, 'ui')
                end
            break
            end
        end
    end
end

local function RemoveOldRallyPoint(factoryID,WP,wayPointInt) --only called when a J is pressed whilst factory selected (resets the rally points)
    local x,y,z
    gdSelectionChangedVar =true
--removes all different rally points from the factory
    if WP == "all" then
        for index, value in pairs (gdGuardedUnits) do
            if value.FID == factoryID then
                gdGuardedUnits[index] = nil
            end
        end
        gdRallyPointList[factoryID] = nil
--removes only one # of rally point from the factory
    elseif WP == "single" then --need to remove only the rally point 
        x,y,z = gdIsFactorybyID[factoryID].x,gdIsFactorybyID[factoryID].y,gdIsFactorybyID[factoryID].z
        for _, value in pairs (gdGuardedUnits) do
            if value.FID == factoryID and value.WPI == wayPointInt then
                CheckAndRemoveFromGuardedList(value.UID)
            end
        end
        gdRallyPointList[factoryID][wayPointInt] = {x={x},y={y},z={z},use = false , guard={false}, cursor={"none"}}
    end      
end

local function UpdateGuardedUnitPos() --Updates unit position if moved; for graphical checks
    local x,y,z
    for i,j in pairs (gdGuardedUnits) do
        x,y,z = Spring.GetUnitPosition(j.UID)
        if math.abs(gdRallyPointList[j.FID][j.WPI].x[j.WPQ] - x) > 2 or math.abs(gdRallyPointList[j.FID][j.WPI].y[j.WPQ] - y) > 2 or math.abs(gdRallyPointList[j.FID][j.WPI].z[j.WPQ] - z) > 2 then
        gdRallyPointList[j.FID][j.WPI].x[j.WPQ] = x
        gdRallyPointList[j.FID][j.WPI].y[j.WPQ] = y
        gdRallyPointList[j.FID][j.WPI].z[j.WPQ] = z
        gdSelectionChangedVar = true
        end
    end
end

function widget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
    if gdMasterIsFactoryTable[unitDefID] ==true then --checks if new unit is factory type, and if so adds to list
        AddToFactoryList(unitID)
    end
    local rallyPointNumber = CheckIfUnitToBeRallyedExists(unitDefID)
    if rallyPointNumber then
        OrderListForUnit(unitID,builderID,rallyPointNumber)
    end
end

function widget:UnitGiven(unitID, unitDefID, unitTeam, oldTeam) --unit given to me
    if gdMasterIsFactoryTable[unitDefID] ==true then --checks if new unit is factory type, and if so adds to list
        AddToFactoryList(unitID)
    end
end

function widget:UnitTaken(unitID, unitDefID, unitTeam, newTeam) --unit taken away
    if gdMasterIsFactoryTable[unitDefID] == true then
        RemoveOldRallyPoint(unitID,"all",nil)
        RemoveFromFactoryList(unitID, unitDefID)
    end
end

function widget:UnitDestroyed(unitID, unitDefID, unitTeam)
    if gdMasterIsFactoryTable[unitDefID] == true then
        RemoveOldRallyPoint(unitID,"all",nil)
        RemoveFromFactoryList(unitID, unitDefID)
        
    end
    CheckAndRemoveFromGuardedList(unitID)
end

function widget:Update(dt)
    gdpassedTime = gdpassedTime + dt
    if gdpassedTime > 0.05 then
        gdpassedTime =0
        if #gdFactorySelectedTable >0 then
            UpdateGuardedUnitPos()
        end
    end
    if gdSelectionChangedVar == true then --required to run first draw frame after selection change
        gdSelectionChangedVar = false
        CheckToDraw()
    end
end

function widget:SelectionChanged(selectedUnits, subselection)
    gdDrawTime = false
    gdFactorySelectedTable = {}
    for i=1, #selectedUnits do
        if gdIsFactorybyID[selectedUnits[i]] then
            local x,y,z = Spring.GetUnitPosition(selectedUnits[i])
            table.insert(gdFactorySelectedTable,{x = x,y = y,z = z,factoryID = selectedUnits[i]})
        end
    end
    CheckToDraw()
    gdSelectionChangedVar = true
end

--Hotkey functions
function ExtraRallyAction1(_, b, _, args)
    if custom_keybind_mode then
        if args[1] then --pressed
            keyDown = true
            keyType = tonumber(b)
        else --false
            keyDown = false
            keyType = tonumber(b)
            if WG.buildmenu.hoverID and keyType then
                AddUnitTypeToRallyPointGroup(WG.buildmenu.hoverID,keyType)
            else
                CheckKeyStatus()
            end
        end
    end
end

function widget:KeyPress(key, mods, isRepeat)
    if mods.shift == true then
        shiftKey = true
    end
    if not custom_keybind_mode then
        for i,k in ipairs(hotkeys) do
            if key == k then
                keyDown = true
                keyType = i
            end
        end
    end
end

function CheckKeyStatus()
    if gdJustUpdated ==false then
        local selectedUnits =  Spring.GetSelectedUnits()
        for index=1, #selectedUnits do
            if gdIsFactorybyID[selectedUnits[index]] then
                RemoveOldRallyPoint(selectedUnits[index],"single",keyType)
            end
        end
    end
    keyDown,gdJustUpdated,keyType  = false, false, nil
end

function widget:KeyRelease(key, mods)
    if key == 304 then shiftKey = false; return end
    if mods.shift == true then shiftKey = true; else shiftKey = false end
    if not custom_keybind_mode and gdJustUpdated ==false and keyDown == true then
        for i,k in ipairs(hotkeys) do
            if key == k then
                keyDown, keyType = true , i
                if WG.buildmenu.hoverID and keyType then
                    AddUnitTypeToRallyPointGroup(WG.buildmenu.hoverID,keyType)
                else
                    CheckKeyStatus()
                end
            end
        end
    end
    gdJustUpdated = false
end

function widget:MousePress(mx, my, button) --sets the way point if hotkey is pressed and factory type selected.
    if keyDown and button == 2 then
        local type ,pos = spTraceScreenRay(mx, my, false)
        local targetType = {}
        local cursorType = nil
        cursorType = Spring.GetMouseCursor()
        if type == "unit" or "feature" then
            targetType = {type = type, ID = pos , pos = {}}
            if type =="unit" then
                if not Spring.IsUnitAllied(pos) then
                    type = "enemy"
                    targetType.type = type
                end
                pos = {Spring.GetUnitPosition(pos)}     
            elseif type == "feature" then
                pos = {Spring.GetFeaturePosition(pos)}
            end
            targetType.pos = pos
        else
            targetType = {type = type, ID = nil , pos = pos} 
        end
        local posX,posY,posZ = pos[1],pos[2], pos[3] --this pos can either be the ground, or unit position at time of running
        local selectedUnits =  Spring.GetSelectedUnits()
        for index=1, #selectedUnits do
            if gdIsFactorybyID[selectedUnits[index]] then
                AddNewRallyPoint(posX, posY, posZ, selectedUnits[index],keyType,targetType,cursorType) --SelectedUnits[index] here will be factory ID
                gdSelectionChangedVar = true
                gdJustUpdated = true
            end
        end

    end
end

--Drawing Functions
local function MakeLine(x1, y1, z1, x2, y2, z2)
	glVertex(x1, y1, z1)
	glVertex(x2, y2, z2)
end

function widget:DrawWorld()
    if gdDrawTime == true then
        for wpiindex,wpivalue2 in pairs(gdDrawCoords) do
            glColor(colourList[wpiindex][1],colourList[wpiindex][2],colourList[wpiindex][3],colourList[wpiindex][4])
            for facindex, facvalue in pairs(wpivalue2) do
                for i=2, #facvalue.x do --length must be at least 2 to be in this table
                    local x1,y1,z1,x2,y2,z2 = facvalue.x[i-1],facvalue.y[i-1],facvalue.z[i-1],facvalue.x[i],facvalue.y[i],facvalue.z[i]
                    glLineStipple("springdefault")               
                    glBeginEnd(GL_LINE_STRIP, MakeLine, x1,y1,z1,x2,y2,z2)
                    --glColor(circleColor[1],circleColor[2],circleColor[3], .55*lineOpacityMultiplier)
                    if gdMarkers then
                        glLineStipple(false)
                        if facvalue.colour[i] == "Fight" then
                            glColor(cmdColours.fight)
                        elseif facvalue.colour[i] == "Patrol" then
                            glColor(cmdColours.patrol)
                        elseif facvalue.colour[i] == "Move" then
                            glColor(cmdColours.move)
                        end
                        glDrawGroundCircle(facvalue.x[i],facvalue.y[i],facvalue.z[i], 6,3)
                        glLineStipple("springdefault")
                        glColor(colourList[wpiindex][1],colourList[wpiindex][2],colourList[wpiindex][3],colourList[wpiindex][4])
                    end
                end
            end
        end
    end
end

function widget:Initialize()
    widgetHandler.actionHandler:AddAction(self, "extra_factory_rally", ExtraRallyAction1, { true }, "pR")
    widgetHandler.actionHandler:AddAction(self, "extra_factory_rally", ExtraRallyAction1, { false }, "r")
	local isSpectator = Spring.GetSpectatingState()
	if isSpectator then
	  widgetHandler:RemoveWidget(self)
	  return
	end
    local TeamID = Spring.GetMyTeamID()
    FindFactories(TeamID)
end

--icon related snippets
--local iconTypes = VFS.Include("gamedata/icontypes.lua")
--local folder = "LuaUI/Images/groupicons/"

-- local function ArrangeIcons()

--     for unitDefID, unitDef in pairs(UnitDefs) do
--         if unitDefID ==163 then
--         local xsize, zsize = unitDef.xsize, unitDef.zsize
--         icon[unitDefID] = {}
--             if unitDef.iconType and iconTypes[unitDef.iconType] and iconTypes[unitDef.iconType].bitmap then
--                 icon[unitDefID].icontype = iconTypes[unitDef.iconType].bitmap
--             end
--         end
--     end
-- end


-- DrawIcon = function(text)
--     local iconSize = 1.1
--     local textSize = 0.5
--     glPushMatrix()
--     glColor(0.95, 0.95, 0.95, 1)
--     glTexture(':n:LuaUI/Images/unit_market/buy_icon.png')
--     glBillboard()
-- 	glTranslate(0.4, 0.8, 0)
--     --glTranslate(12.0, 18.0, 24.0)
--     glTexRect(-iconSize/2, -iconSize/2, iconSize/2, iconSize/2)
--     if text ~= nil then
--         glTexture(false)
--         glTranslate(iconSize/2, -iconSize/2, 0)
--         --font:Begin()
--         font:Print(buyPriceBoldColor..text.."m", 0.6, 1.0, textSize)
--         --font:End()
--     end
--     glPopMatrix()
-- end