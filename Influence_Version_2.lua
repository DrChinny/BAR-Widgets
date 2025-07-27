function widget:GetInfo()
    return {
      name      = "Influence_version_2",
      desc      = "An overlay that shows influence of each player on the battlefield",
      author    = "Mr_Chinny",
      date      = "July 2024",
      handler   = true,
      enabled   = false,
      layer = 0
    }
end


local spamChecker = 0 -- counter to stop spamming echos 
-- if spamChecker < 10 then
--     Spring.Echo()
--     spamChecker = spamChecker + 1 
-- end

--- xxx change dps calcs to improve coverage - considering diving dps by range (or function of) to weaken long range units dps, increase short range influence.
--- xxx split to two widgets - one for real time overlay only (widget), one for end game stat replay only (gadget). real time one could get data from gadget one?
--- xxx playback controls under minimap/move minimap?
--- xxx change everything in exlcustion lists to use udid rather than UnitDefs[udid].name to increase performance
--- xxx settings / stored settings / change settings
--- xxx textures - improve, consider a blue/red tint for team games
--- xxx total influence strength of each player on replay?
--- xxx drawroutines: 1) speed up y coord lookup by storing the values once. 2) push/pull (requires reworking the function - need advice) 
--- spread out updates
--- xxx if true gameover, need to include a few more replay frames so skulls finish coming in. should update the replay ONLY when gameover is true.
--- xxx add some more animations to destroyed things from \animis
--- xxx perminent important buildings on replay minimap.

-----------Settings-----------
local onlyAllyTeamColours = false --if true, only allyteam colours will be displayed (EG Red Vs Blue in an 8v8), as opposed to all team colours.
local gridResolution = 128 --measured in map pixels. each performance roughly n^2
local chunkDimension = 8 --measured in cells xxx link this to res/16? xxx
local moveDistance = math.min(gridResolution,128) --bodge, but should basically allow adjacent cells to up update when needed but reduce cpu load. xxx check performance, aim for res/2
local spamDisabled = false


----------Speed Ups---------------
local min, max = math.min, math.max
local floor, ceil = math.floor, math.ceil
local insert = table.insert
local gl_CreateList             = gl.CreateList
local gl_DeleteList             = gl.DeleteList
local gl_CallList               = gl.CallList
local glVertex                  = gl.Vertex
local glBeginEnd                = gl.BeginEnd
local glColor                   = gl.Color
local spGetUnitPosition         = Spring.GetUnitPosition
local spGetUnitAllyTeam         = Spring.GetUnitAllyTeam
local spGetUnitDefID            = Spring.GetUnitDefID
local spGetUnitTeam             = Spring.GetUnitTeam
local spGetTeamColor            = Spring.GetTeamColor
local spGetGroundHeight         = Spring.GetGroundHeight
local UiUnit
local orgIconTypes = VFS.Include("gamedata/icontypes.lua")
local iconTypes = {skull = "icons/skull.png"} --building specific ones are added later in code. xxx bomb types, nuke types.
local glTexture = gl.Texture

----Essential Variables--------
local UnitTakenDebug = {} --address a bug in unittaken/unitgiven where it is called twice in sequence.
local staticUnitAlreadyProcessedList = {} ---This is a list of unitID for buildings that have been processed and are not able to move, thus don't need to be reprocessed each time.
local unitLastPosition = {} ---List of unitid with {x = cx, z = cz, dps = dps, range=range, squares= squares, teamid = teamID, allyteamid = allyTeamID, udid = udID} of all live units with positions.                          -- When they move I need to both update new squares, but also reduce old ones. perhaps can work out onl y those squares which fall into these group, ignoring mid ones.
local CoordUpdateList = {}       -- List of coords that have seen a change, to run through
local gridList = {} --Main Master Table that will hold the influence. Consider changing name!
local backup_gridList = {} --a copy of girdlist full of 0
local drawInfluenceChunk = {} ---A list of GLdraws divided into the chunk#, so only need to update one at a time
local drawMiniMap = {}          ---A list of GLDraws divided into frames for End game display
local drawMiniMapIcons = {}
local chunkUpdateList = {} ---list indexed by chunk number. value is need to update.
local totalsForDraw = {} --version of table ready to draw from, with owners teamID and releative Strength, as well as mapcoords.
local captainColour = {} -- colours of each teams captain (eg Red team, Blue team)
local quickRefList = {} --{[unitdefID] = {squares, dps, range}, where squares is based on 0,0 position for translation
local replayList = {} --This list will store state of every cell with single {teamID, event Icon} every X frames.
local IntensityLookup = { --xxx these values need tweaking to get required contrast
    [10]        = 0.1, 
    [20]        = 0.1,
    [30]        = 0.1,
    [40]        = 0.1,
    [50]        = 0.2,
    [60]        = 0.2,
    [70]        = 0.2,
    [80]        = 0.25,
    [90]        = 0.3,
    [100]       = 0.4,
    ["medium"]  = 0.5,
    ["high"]    = 0.6,
    ["max"]     = 0.75
 }

--------Calculated Variables------
---cells---
local mapSizeX = Game.mapSizeX -- eg 12288
local mapSizeZ = Game.mapSizeZ --eg 10240
local numberOfSquaresInX = mapSizeX/gridResolution
local numberOfSquaresInZ = mapSizeZ/gridResolution
local totalNumberofChunkX = ceil(numberOfSquaresInX / chunkDimension)
local totalNumberofChunkZ = ceil(numberOfSquaresInZ / chunkDimension)
local vsx, vsy                  = Spring.GetViewGeometry()
local numberOfTeams = Spring.Utilities.GetAllyTeamCount()
if Spring.Utilities.GetScavTeamID() then
    numberOfTeams =numberOfTeams+1
end
if Spring.Utilities.GetRaptorTeamID() then
    numberOfTeams =numberOfTeams+1
end

local gaiaTeamId                = Spring.GetGaiaTeamID()
local gaiaAllyTeamID = select(6, Spring.GetTeamInfo(gaiaTeamId, false))
local defaultdamagetag = Game.armorTypes['default'] --position that default is in on the weapon lists (0)
local spectator, fullview = Spring.GetSpectatingState()

---Counters---
local updateCounter = 0
local deathTimer = 25  -- how long an interesting units death it displayed, unit is in replayframes
local chunkUpdateCounter = 1 --must start at 1, max of #chunkUpdateList
local replayFrame = 0
local drawFrame = 1
local drawUpdateCounter = 0
local gameOver = false
---Drawing---
---
local drawer
local drawInfluence

---updating exclusion lists---
local excludeRange = {} --manually inputted. all stockpiling units except thor, also rag and calm. xxx legion, automate to check for weapon stockpiling
for i, name in ipairs({ "armjuno","corjuno","armemp","corantiship","corcarry","armamd","armmercury","cortron","armantiship","armcarry","armseadragon",
"cormabm","corjuno","corfmd","cordesolator","armsilo","corscreamer","armscab","corsilo", "armvulc","armbrtha","corbuzz","corint"}) do
    excludeRange[UnitDefNames[name].id] = true
end 
local excludeUnits = { --Units to ignore completly,currently. all flying, plus rez bots .YYY change all to unitDefID rather than name.
    [UnitDefNames["armrectr"].id]   = true,
    [UnitDefNames["cornecro"].id]   = true, 
    [UnitDefNames["cordrag"].id]    = true, 
    [UnitDefNames["armdrag"].id]    = true
}
local isMexList =   {}
local spamUnits = {
    [UnitDefNames["armflea"].id]    =true,
    [UnitDefNames["armpw"].id]      =true,
    [UnitDefNames["corak"].id]      =true,
    [UnitDefNames["armfav"].id]     =true,
    [UnitDefNames["corfav"].id]     =true
}--should probably automate this + legion. Is there a custom spam tag?
local tempList = {} --xxx for debugging
local bombersList ={} --air units that go on bombing runs
local interestingDeathsTypes ={} -- commanders, fusion, afus, rags 
local interestingDeathsList ={}
local interestingBuildingList = {}
local weaponlessBuilding = {}  --list of all non combat buildings. These need to be treated differently to give influence.
--xxx nuke icons?
for unitDefID, unitDef in pairs(UnitDefs) do
    if unitDef.canFly then --isBuilding or unitDef.speed == 0)
        excludeUnits[unitDefID] = true
        --YYY if bombertype then
    end
    if #unitDef.weapons == 0 then
        weaponlessBuilding[unitDefID] = true
    end
    if unitDef.customParams.metal_extractor then -- this should find all extractors
        isMexList[unitDefID]     = {dps = 30,  range = 200}
    end
    if unitDef.customParams.iscommander then -- this should find all extractors
        interestingDeathsTypes[unitDefID]   = true
        iconTypes[unitDef.name] = orgIconTypes[unitDef.iconType].bitmap--orgIconTypes['armcom'].bitmap
    end
    if unitDef.name =='armafus' or unitDef.name =='corafus' or unitDef.name =='legafus' or unitDef.isFactory == true then --can i not hardcode the afus? xxx
        interestingDeathsTypes[unitDefID]   = true
        iconTypes[unitDef.name]             = orgIconTypes[unitDef.iconType].bitmap-- orgIconTypes[unitDef.name].bitmap 
    end

end
isMexList[UnitDefNames["cormoho"].id]    = {dps = 100, range = 600}
isMexList[UnitDefNames["armmoho"].id]    = {dps = 100, range = 600}
local vertexList = {}

----------Functions------------------
---Chunks and Cells---

local function FindChunkNumber(x,z) --takes x,z from (coord), returns the Chunk that a particular gridcoord is in, as an index #in chunklist
    local chunkNumber = floor(x/chunkDimension) + (floor(z/chunkDimension) *totalNumberofChunkX) + 1
    return chunkNumber
end

local function ExpandChunk(chunkNumber) --- returns minx, maxx, minz, maxz of cells in a chunk. use return to dertmine if a coord is in said chunk.
    chunkNumber = chunkNumber -1
    local x = chunkNumber % totalNumberofChunkX
    local z = math.modf(chunkNumber / totalNumberofChunkX)
    local minX = x * (chunkDimension)+0
    local maxX = x * (chunkDimension)+(chunkDimension-1)
    local minZ = z * (chunkDimension)+0
    local maxZ = z * (chunkDimension)+(chunkDimension-1)
    return minX,maxX,minZ,maxZ
end

local function MakeWorldVertexList(coord,x,z)
    local x1,x2 = x*gridResolution, (x+1) *gridResolution--can get these all once and read from table.
    local z1,z2 = z*gridResolution, (z+1) *gridResolution--can get these all once and read from table.
    local height1 = spGetGroundHeight(x1,z1) --can get these all once and read from table.
    local height2 = spGetGroundHeight(x2,z1)
    local height3 = spGetGroundHeight(x2,z2)
    local height4 = spGetGroundHeight(x1,z2)
    return {{x1, height1, z1},{x2, height2, z1},{x2, height3, z2},{x1, height4, z2}}
end

local function PopulateGrid() ---Populates the gridlist with : [coords][teamAllyID][teamID]. Also populates team color for 2 colour games. Ran once only at game start or cell resolution change.
    for x=0, mapSizeX/gridResolution do
        for z = 0, mapSizeZ/gridResolution do
            local coord = tostring(x)..","..tostring(z)
            
            gridList[coord] = {}
            vertexList[coord] = MakeWorldVertexList(coord,x,z)
            --replayList[coord] = {}
            for n = 0, numberOfTeams-1 do --ignores Gaia
                gridList[coord][n+1] = {}
                for _,teamID in pairs(Spring.GetTeamList(n)) do
                    gridList[coord][n+1][teamID] = 0
                end
            end
        end
    end
    for n = 0, numberOfTeams-1 do
        local lowestID = 9999 --find the lowest teamid, which will be captain colour.
        for _,teamID in pairs(Spring.GetTeamList(n)) do
            if teamID < lowestID then
                lowestID = teamID
            end
        end
        local r,g,b = spGetTeamColor(lowestID)
        captainColour[n+1] = {r=r,g=g,b=b}
    end
    backup_gridList = table.copy(gridList) --xxx full copy of 0-ed table, useful for resetting.
end

---squares within range---

local function TranslateSquares(squares,transX,transZ)
    local translatedSquareTable = {}
    for i,coord in pairs(squares) do
        local gridX, gridZ = coord.x + transX, coord.z + transZ
        if gridX < 0 or gridZ < 0 or gridX > numberOfSquaresInX or gridZ > numberOfSquaresInZ then  
        else
            translatedSquareTable[i] = gridX..","..gridZ
        end
    end
    return translatedSquareTable
end

local function SquaresInCircleForTranslating(cx, cz, r, grid_size)
    local squares = {}
    if not cx then
        Spring.Echo("cx is nil",cx,cz,r,grid_size)
    end
    local squareIAmInX = floor(cx / grid_size)
    local squareIAmInZ = floor(cz / grid_size)
    local minX = floor((cx - r) / grid_size)
    local maxX = ceil ((cx + r) / grid_size)
    local minZ = floor((cz - r) / grid_size)
    local maxZ = ceil((cz + r) / grid_size)
    for x = minX, maxX do
        local square_center_x = x * grid_size + grid_size / 2
        for z = minZ, maxZ do
            local square_center_z = z * grid_size + grid_size / 2
            local dx = square_center_x - cx
            local dy = square_center_z - cz
            if dx * dx + dy * dy <= r * r then
                squares[#squares+1] = {x = x, z = z}
            end
            if squares == {} then --adds square we are in if not already done.
                squares = {{x = squareIAmInX, z = squareIAmInZ}}
                --insert(squares, {x = squareIAmInX, z = squareIAmInY})
            end
        end
    end
    return squares
end

local function TableDifferences(a,b) --Returns a list of of values. true means in a not b, false means in b not a.
    local a_inverse, b_inverse, differences = {},{},{}
    for k,v in ipairs(a) do
        a_inverse[v] = k
    end
    for k,v in ipairs(b) do
        if a_inverse[v] == nil then
            differences[v] =false
        end
        b_inverse[v] = k
    end
    for k,v in ipairs(a) do
        if b_inverse[v] == nil then
            differences[v] = true
        end
    end
    return differences
end
------------------------



local function MakePolygon(coord) --note i need to start in topleft corner and go round.
    glVertex(vertexList[coord][1])
    glVertex(vertexList[coord][2])
    glVertex(vertexList[coord][3])
    glVertex(vertexList[coord][4])
end

local function MakePolygonMap(x1,y1,x2,y2) --note i need to start in topleft corner and go round.
    glVertex(x1,y1)
	glVertex(x2,y1)
    glVertex(x2,y2)
	glVertex(x1,y2)
end


---Influence Calculations---
---
local function AddInfluence(coord,AllyTeamID,TeamID,value) ---Adds a single unit's influence to single cell
    gridList[coord][AllyTeamID+1][TeamID] = gridList[coord][AllyTeamID+1][TeamID] + value
    CoordUpdateList[coord] = true
end

local function ReduceInfluence(coord,allyTeamID,teamID,value) ---Reduces a single unit influence to single cell
    gridList[coord][allyTeamID+1][teamID] = gridList[coord][allyTeamID+1][teamID] - value
    CoordUpdateList[coord] = true

    if gridList[coord][allyTeamID+1][teamID] <-0.1 then --to allow for missing rounding? xxx
        Spring.Echo("reduced influence to below 0, shouldn't be possible",coord,allyTeamID,"teamID",teamID,"value",value, "original value in Gridlist",gridList[coord][allyTeamID+1][teamID]+ value)
        gridList[coord][allyTeamID+1][teamID] = 0
        return "error"
    end
end

local function ProcessUnit(unitID,unitDefID,teamID,destroyed) --This should be run once when a unit is created and when it dies (or taken/given). add spam check
    if staticUnitAlreadyProcessedList[unitID] then
        local allyTeamID = staticUnitAlreadyProcessedList[unitID].allyteamid
        local dps = staticUnitAlreadyProcessedList[unitID].dps
        local squares = staticUnitAlreadyProcessedList[unitID].squares
        for i,coord in pairs(squares) do
            if not destroyed then
                AddInfluence(coord, allyTeamID, teamID, dps)
            else
                if ReduceInfluence(coord, allyTeamID, teamID, dps) == 'error' then
                    Spring.Echo("Error in reduce influence from Process Static:",unitID,UnitDefs[unitDefID].name,squares )
                end
                staticUnitAlreadyProcessedList[unitID] = nil       
            end
       end 
    elseif
        unitLastPosition[unitID] then
        local allyTeamID = unitLastPosition[unitID].allyteamid
        local dps = unitLastPosition[unitID].dps
        local squares = unitLastPosition[unitID].squares
        for i,coord in pairs(squares) do
            if not destroyed then
                AddInfluence(coord, allyTeamID, teamID, dps)
            else
                if ReduceInfluence(coord, allyTeamID, teamID, dps) == 'error' then
                    Spring.Echo("Error in reduce influence from Process Moving:",unitID,UnitDefs[unitDefID].name,squares )
                end
                unitLastPosition[unitID] = nil
            end
        end 
    else
        --Spring.Echo("Unit Excluded",UnitDefs[unitDefID].humanName)
    end
end

local function CalculateCellInfluence(coord) ---Updates totals table totals with the strongest player, their percent owned.
    local x,z = string.match(coord, "(%d+),(%d+)")
    if x and z then
        x, z  = tonumber(x), tonumber(z)
    end
    CoordUpdateList[coord] = nil
    local allyTeamInfluenceInfluence = {}

    for allyTeamID, teamList in pairs(gridList[coord]) do
        local maxValue, secondMaxValue, cumTotal = 0 , 0 , 0 --hehe cumTotal. maxValue is the highest individual value
        local maxValueID, secondMaxValueID --These are the TeamIDs of the players 
        for teamID, value in pairs(teamList) do
            if value > 0 then
                cumTotal = cumTotal + value
                if value > maxValue then
                    secondMaxValue = maxValue --second highest value  
                    secondMaxValueID = maxValueID --second highest teamID
                    maxValue = value
                    maxValueID = teamID
                end
            end
        end
        allyTeamInfluenceInfluence[allyTeamID] = {cumtotal = cumTotal, maxValue = maxValue, maxvalueid = maxValueID, secondMaxValue = secondMaxValue, secondMaxValueID = secondMaxValueID }
    end
    --determine who is strongest, and by how much
    local highestAllyTeamCum, allTotal, percentOwned= 0,0,0
    local maxAllyTeamID

    for allyTeamID, data in pairs(allyTeamInfluenceInfluence) do
        if data.cumtotal >0 and data.cumtotal > highestAllyTeamCum then
            highestAllyTeamCum = data.cumtotal
            maxAllyTeamID = allyTeamID
        end
        allTotal = allTotal + data.cumtotal
    end
    if allTotal >0 then
        percentOwned = floor(((highestAllyTeamCum/allTotal)*10)+0.5)*10 --Actually a decimal, rounded to 1dp. Will always be 0.5 or above in 2team games.
        if percentOwned == 0 then percentOwned = 10 end --catches case where a square is so contested that no team has above 5% ownership (FFA only i guess)
    end

    --has something changed, find the chunk
    if totalsForDraw[coord] then
        local chunkNumber
        if totalsForDraw[coord].strongestallyteamid ~= maxAllyTeamID then --update when allyteamowner has changed. Edge cases thast don't require update exist for contested ground.
            chunkNumber= FindChunkNumber(x,z)
            chunkUpdateList[chunkNumber]  = true
        end

        if math.abs(percentOwned - totalsForDraw[coord].prevpercentowned) >= 10 then --any change in percentowned. old code in if >>>percentOwned ~= totalsForDraw[coord].prevpercentowned and 
            chunkNumber = FindChunkNumber(x,z)
            chunkUpdateList[chunkNumber]  = true
        end  
        if allTotal > 0 then
            if totalsForDraw[coord].strongestteamid ~= allyTeamInfluenceInfluence[maxAllyTeamID].maxvalueid then --only flip within own team if big enough difference in value.
                if secondMaxValue and maxValue then
                    if secondMaxValue / maxValue >= 0.8 then
                        local chunkNumber = FindChunkNumber(x,z)
                        chunkUpdateList[chunkNumber]  = true
                    else
                        allyTeamInfluenceInfluence[maxAllyTeamID].maxvalueid = totalsForDraw[coord].strongestteamid --not going to let this flip unless change is bigger
                    end
                end
            end
        end
    end
    if percentOwned >0 then
        totalsForDraw[coord] = {percentowned = percentOwned, strongestallyteamid = maxAllyTeamID, strongestteamid = allyTeamInfluenceInfluence[maxAllyTeamID].maxvalueid, x=x, z=z, prevpercentowned = percentOwned , prevteamid = allyTeamInfluenceInfluence[maxAllyTeamID].maxvalueid, highestallyteamcum=highestAllyTeamCum}
    else
        totalsForDraw[coord] = {percentowned = nil , strongestallyteamid = nil, strongestteamid = nil, x=x, z=z, prevpercentowned = 0, prevteamid = nil, highestallyteamcum=nil}
    end
end



local function MovedUnitCalcsTranslation(unitID,udID,cx,cz,allyTeamID,teamID) --should be less cpu intensive compared to standard calc as don't need to update all square influences.
    local squares = TranslateSquares(quickRefList[udID].translatablesquares,floor(cx / gridResolution),floor(cz / gridResolution))
    local changedSquares = TableDifferences(squares,unitLastPosition[unitID].squares) --new squares will be true, old squares will be false
    --Can very likely make savings here by calculating changeSquares based on X,Z position change, rather than comparing circle overlaps
    for coord,bool in pairs(changedSquares) do
        if bool == true then
            AddInfluence(coord, allyTeamID, teamID, unitLastPosition[unitID].dps)
        else
            if ReduceInfluence(coord, allyTeamID, teamID, unitLastPosition[unitID].dps) == 'error' then
                Spring.Echo("Error in reduce influnene from Moved Unit Moving:",unitID,UnitDefs[udID].name,squares)
            end
        end
    end

--changed to manaully removing and recounting all, rather than using difference, checking for bugs xxx
    -- local squaresOld =  unitLastPosition[unitID].squares
    -- for _,coord in pairs(squaresOld) do
    --     if ReduceInfluence(coord, allyTeamID, teamID, unitLastPosition[unitID].dps) == 'error' then
    --         Spring.Echo("Error in reduce influnene from Moved Unit Moving:",unitID,UnitDefs[udID].name,squares)
    --     end
    -- end
    -- for i,coord in pairs(squares) do
    --     AddInfluence(coord, allyTeamID, teamID, unitLastPosition[unitID].dps)
    -- end


    unitLastPosition[unitID].squares = squares
end

local function MovingUnitsInfluence(unitID,teamID,cx,cz)
    local unit = unitLastPosition[unitID]
    cx,cz = floor(cx),floor(cz)
    if not unit then
        Spring.Echo("MovingUnitInfluence Error",unitID,unitLastPosition[unitID])
    end
    if teamID ~= unit.teamid then
        Spring.Echo("MovingUnitInfluence Error Non Matching teamID",unitID,unitLastPosition[unitID],teamID)
    end
    if math.abs(cx-unit.x) >= moveDistance or math.abs(cz - unit.z) >= moveDistance then --strickly speaking should use pythagos here, but can bodge for now.
        MovedUnitCalcsTranslation(unitID,unit.udid,cx,cz,unit.allyteamid,unit.teamid)
        unitLastPosition[unitID].x,unitLastPosition[unitID].z = cx,cz
        return
    else
        return --nothings changed, leave function
    end
end

local function GetColourAndIntensity(data)
    local r,g,b,intensity
    local strength = data.percentowned
    if strength >60 then
        if not onlyAllyTeamColours then        
            r,g,b = spGetTeamColor(data.strongestteamid)
        else
            r,g,b = captainColour[data.strongestallyteamid].r,captainColour[data.strongestallyteamid].g,captainColour[data.strongestallyteamid].b
        end
        if data.highestallyteamcum >= 3000 then
            strength = "max"
        elseif data.highestallyteamcum >=2000 then
            strength = "high"
        elseif data.highestallyteamcum >=1000 then
            strength = "medium"
        end
         intensity = IntensityLookup[strength] --clearer on minimap
    else
        r,g,b = 0,0,0 --colour for no mans land
        intensity = 0.6
    end
    return r,g,b,intensity
end

local function DrawNextInfluenceChunk(chunkNumber) -- xxx i should only be running this if the chunk is updated. do i have a check to this outside of the function?
    if drawInfluenceChunk[chunkNumber] then
         gl_DeleteList(drawInfluenceChunk[chunkNumber])
    end
    drawInfluenceChunk[chunkNumber] = gl_CreateList(function()
        local minX,maxX,minZ,maxZ =  ExpandChunk(chunkNumber)
        for x = minX,maxX do
            for z = minZ,maxZ do
                local coord = tostring(x..","..z)
                if totalsForDraw[coord] then
                    local data = totalsForDraw[coord]
                    if data.percentowned then
                        local r,g,b,intensity = GetColourAndIntensity(data)
                        -- local r,g,b,intensity
                        -- local strength = data.percentowned --xxx could just use fraction rather than percent? is passing floats worse than ints and dividing? 
                        -- if strength >70 then
                        --     if not onlyAllyTeamColours then        
                        --         r,g,b = spGetTeamColor(data.strongestteamid)
                        --     else
                        --         r,g,b = captainColour[data.strongestallyteamid].r,captainColour[data.strongestallyteamid].g,captainColour[data.strongestallyteamid].b
                        --     end
                        --     if data.highestallyteamcum >= 3000 then
                        --         strength = "max"
                        --     elseif data.highestallyteamcum >=2000 then
                        --         strength = "high"
                        --     elseif data.highestallyteamcum >=1000 then
                        --         strength = "medium"
                        --     end
                        --     intensity = IntensityLookup[strength]
                            
                        -- else
                        --     r,g,b = 0,0,0
                        --     intensity = 0.6
                        -- end
                        if r and g and b then
                            glColor(r,g,b,intensity)
                            --glBeginEnd(GL.POLYGON,MakePolygon, data.x, data.z)
                            glBeginEnd(GL.POLYGON,MakePolygon, coord)
                        end
                    end
                end
            end
        end
    end)
end

local function CheckForSkippables(unitID, allyTeamID, udID)
    local skippable = false
    if allyTeamID == nil then
        skippable = true
        Spring.Echo("Error 001; no AllyTeamID", udID,unitID,allyTeamID)
    elseif allyTeamID == gaiaAllyTeamID then --gaia
        skippable = true
    elseif excludeUnits[udID] then --excluded
        skippable = true
    elseif not udID then
        Spring.Echo("Error 003; udID", udID,unitID,allyTeamID)
    elseif spamDisabled then --ignore spam units when enabled.
            if spamUnits[udID] then
                skippable = true
            end
    end 
    return skippable
end

local function DisableSpam()
    for unitID,data in pairs(unitLastPosition) do
        if spamUnits[data.udid] then
            ProcessUnit(unitID,data.udid,data.teamid,true)
        end
    end
    Spring.Echo("Spam disabled")
    spamDisabled = true
end

local function EnableSpam() -- ZZZ change here, need to change #ll units to visibleunits.
    spamDisabled = false
    Spring.Echo("Spam Re-enabled")
    local visibleUnitsList = WG['unittrackerapi'].visibleUnits
    if visibleUnitsList then
        for unitID, unitDefID in pairs(visibleUnitsList) do
            if spamUnits[unitDefID] then
                if select(5,Spring.GetUnitHealth(unitID)) == 1 then    
                    local unprocessed, unitDefID, teamID = GetUnitStrength(unitID)
                    if unprocessed then
                        ProcessUnit(unitID,unitDefID,teamID, false) 
                    end
                end
            end
        end
    end 
    -- local allunits = Spring.GetAllUnits() --for now update all units, in future this may need to split the list over serval updateticks
    -- if allunits then
    --     for i = 1, #allunits do
    --         local unitID = allunits[i]
    --         local udid= spGetUnitDefID(unitID)
    --         if spamUnits[udid] then
    --             if select(5,Spring.GetUnitHealth(unitID)) == 1 then     
    --                 local bool, unitDefID,teamID = GetUnitStrength(unitID)
    --                 if bool then
    --                     ProcessUnit(unitID,unitDefID,teamID,false)
    --                 end
    --             end
    --         end
    --     end
    -- end
end

local function GetUnitStrength(unitID,teamID) --Produces the range, dps, and squares for a unitid. first time unittype is made, will update a link with these values for future units.
    local allyTeamID = spGetUnitAllyTeam(unitID)
    local udID = spGetUnitDefID(unitID)
    if CheckForSkippables(unitID,allyTeamID,udID) then --check what units can be skipped to save on cpu
        return false ,udID, false --remove 2nd and 4rd arguments later (unitDefID,teamID)
    end
    -----------------------
    local unitDef = UnitDefs[udID]
    if not teamID then --take team ID when unittaken called.
         teamID = spGetUnitTeam(unitID)
    else
        allyTeamID = spGetUnitAllyTeam(unitID) --need to add this case for captures that don't work.
    end
    local cx,y,cz = spGetUnitPosition(unitID)
    cx = floor(cx)
    cz = floor(cz)
    local range = 100 --min range xxx make variable?
    local dps =0
    local translatableSquares = {}
    -----------------------
    if quickRefList[udID] then --if unit has already been calculated once, stored value so don't need to run through again.
        range = quickRefList[udID].range
        dps = quickRefList[udID].dps
        translatableSquares = quickRefList[udID].translatablesquares
    else
        local normalUnit = true
        if excludeRange[udID] then
            normalUnit =  false
        elseif weaponlessBuilding[udID] then
            normalUnit = false
        end
        if unitDef.weapons and normalUnit == true then --could massively reduce this by creating alist on init that has all range/dps to be read.
            for _, weapon in ipairs(unitDef.weapons) do
                if weapon.weaponDef then
                    local weaponDef = WeaponDefs[weapon.weaponDef]
                    if weaponDef then
                        if weaponDef.canAttackGround and not (weaponDef.type == "Shield") then --maybe add more types to avoid?
                            local damage = weaponDef.damages[defaultdamagetag]
                            local reload = weaponDef.reload
                            if weaponDef.type == "BeamLaser" then
                                damage = damage/2
                            elseif weaponDef.type == "StarburstLauncher" then --expection for thor missles
                                damage = 100
                                range = 100
                            end
                            local temp_dps = min(floor(damage / (reload or 1)),2000)--limit dgun power
                            if weaponDef.range > range and weaponDef.type ~= "StarburstLauncher" then --only update to biggest dps/range. may cause some funny behvaior for some units.
                                range = min(weaponDef.range,2000)
                            end
                            if temp_dps > dps then
                                dps = temp_dps
                            end
                        elseif weaponDef.canattackground == false then --This is all AA?
                            local metal =  UnitDefs[udID].metalCost + floor((UnitDefs[udID].energyCost / 70))
                            range = min(max(floor((metal / 10) + 0.5),256),1000) --this factor may need to be variable. xxx could simple add square and next squares rather than calculate
                            dps =  max(floor ((metal / 10) + 0.5),5)
                        end
                    end
                end
            end
        elseif not normalUnit then
            if isMexList[udID] then  --treat mex differently to allow more map infulence
                dps = isMexList[udID].dps
                range = isMexList[udID].range
            else
                local metal =  UnitDefs[udID].metalCost + floor((UnitDefs[udID].energyCost / 70))
                range = min(max(floor((metal / 10) + 0.5),256),1000) --this factor may need to be variable. xxx could simple add square and next squares rather than calculate
                dps =  max(floor ((metal / 10) + 0.5),5)
            end
        end
        translatableSquares = SquaresInCircleForTranslating(0 + (gridResolution/2), 0 + (gridResolution/2), range, gridResolution) --squares when at centre of position of 0,0
        quickRefList[udID] = {name = UnitDefs[udID].name, range = range, dps = dps, translatablesquares = translatableSquares}
    end
    -- if range > 0 and dps >0 then
    --local squares = SquaresInCircle(cx, cz, range, gridResolution)

    local gridCoordX = floor(cx/ gridResolution)
    local gridCoordZ = floor(cz/ gridResolution)
    if translatableSquares == nil then
        Spring.Echo("Error 020:",range,dps,UnitDefs[udID].name)
    end
    local squares = TranslateSquares(translatableSquares,gridCoordX,gridCoordZ)
    -- for i,coord in pairs(squares) do
    --     if not destroyed then
    --         AddInfluence(coord, allyTeamID, teamID, dps)
    --     else
    --         ReduceInfluence(coord, allyTeamID, teamID, dps)
    --         unitLastPosition[unitID] = nil
    --         staticUnitAlreadyProcessedList[unitID] = nil       
    --     end
    -- end
    if unitDef.speed >0 then --xxx edge case of transportable towers, if theres a callin I can hangle it there.
        unitLastPosition[unitID] = {x = cx, z = cz, dps = dps, range=range, squares= squares, teamid = teamID, allyteamid = allyTeamID, udid = udID} -- i should be able to use this to quickly add and remove dps every time i update.
    else
        staticUnitAlreadyProcessedList[unitID] = {dps = dps, range=range, squares= squares, teamid = teamID, allyteamid = allyTeamID, udid = udID} 
    end
    return true,udID,teamID
end



local function StoreReplayList(updateNumber)
    replayList[updateNumber] = {}
    for coord, data in pairs(totalsForDraw) do
            replayList[updateNumber][coord] = data
    end
end

local function DrawMiniMapFrame(frameNumber,scaleX,scaleY,sizex, sizeY)
    drawMiniMap[frameNumber] = gl_CreateList(function()
        for coord, data in pairs(replayList[frameNumber]) do
            if data.percentowned and frameNumber > 1 then --colour of the cell
                local r,g,b,intensity = GetColourAndIntensity(data)
                if r and g and b then
                    local x1,x2 = data.x*scaleX, (data.x+1)*scaleX--can get these all once and read from table.
                    local y1,y2 = data.z*scaleY*-1+sizeY, (data.z+1)*scaleY*-1+sizeY--can get these all once and read from table.
                    glColor(r,g,b,intensity)
                    glBeginEnd(GL.POLYGON,MakePolygonMap, x1,y1,x2,y2)
                end
            end
        end
    end)
    drawMiniMapIcons[frameNumber] = gl_CreateList(function()     
        for coord, data in pairs(replayList[frameNumber]) do  
            if interestingDeathsList[coord] then
                    if next(interestingDeathsList[coord]) == nil then -- if table is empty
                        interestingDeathsList[coord] = nil
                        break
                    end
                    --for i = 1, #interestingDeathsList[coord] do --change whole loop to pairs i think.
                    for i,death in pairs(interestingDeathsList[coord]) do
                        --local death = interestingDeathsList[coord][i]
                        if death.timer ~= "alive" then --kill off building
                            --uniticon
                            local intensity = min(death.timer/deathTimer,1)
                            glColor(death.colour[1],death.colour[2],death.colour[3],intensity)
                            local x1,x2 = death.x*scaleX, (death.x+1)*scaleX-- xxx can get these all once and read from table.
                            local y1,y2 = death.z*scaleY*-1+sizeY, (death.z+1)*scaleY*-1+sizeY--can get these all once and read from table.
                            local resize = max(8,12-(x2-x1)) --resize will be depend on radar grid size, needs to be big enough icon to see.
                            UiUnit(
                                x1-resize,y2-resize,x2+resize,y1+resize,
                                nil,
                                nil,nil,nil,nil,
                                0,
                                nil, 0,
                                iconTypes[death.name],
                                nil,nil,nil,nil
                            )
                            --skull
                            local timeOffset = 1
                            resize = min(deathTimer+timeOffset - death.timer,10)
                            if deathTimer - death.timer <=timeOffset then --first offSet (3) frames
                                intensity = 0
                            elseif death.timer <= 10 then --last ten frames
                                intensity = death.timer/10
                            else
                                intensity =1 -- middle frames
                            end

                            glColor(0.2,0,0.1,intensity) --very dark purple>
                            UiUnit(
                                x1-resize,y2-resize,x2+resize,y1+resize,
                                nil,
                                nil,nil,nil,nil,
                                0,
                                nil, 0,
                                iconTypes['skull'],
                                nil,nil,nil,nil
                            )
                            death.timer = death.timer - 1
                            if death.timer <= 0 then
                                table.remove(interestingDeathsList[coord][i]) --xxx need to remove from list and ensure reorderd, may be wrong table function.
                            end
                        else --building, not fading
                            local intensity = 1
                            glColor(death.colour[1],death.colour[2],death.colour[3],intensity)
                            --glColor(1,1,1,intensity)
                            local x1,x2 = death.x*scaleX, (death.x+1)*scaleX-- xxx can get these all once and read from table.
                            local y1,y2 = death.z*scaleY*-1+sizeY, (death.z+1)*scaleY*-1+sizeY--can get these all once and read from table.
                            local resize = max(8,12-(x2-x1)) --resize will be depend on radar grid size, needs to be big enough icon to see.
                            UiUnit(
                                x1-resize,y2-resize,x2+resize,y1+resize,
                                nil,
                                nil,nil,nil,nil,
                                0,
                                nil, 0,
                                iconTypes[death.name],
                                nil,nil,nil,nil
                            )
                        end
                    end
                
            end
        end
    end)
    
end

local function RunReplayList(frameNumber) --This needs to cycle through the replaylist frame by frame, and draw the colours over the mini map.
    local posX, posY, sizeX, sizeY, minimized, maximized = Spring.GetMiniMapGeometry()
    local scaleX = (sizeX/numberOfSquaresInX)
    local scaleY = (sizeY/numberOfSquaresInZ)
    --Spring.Echo("scaleX,scaleY",scaleX,scaleY)
    DrawMiniMapFrame(frameNumber,scaleX,scaleY,sizeX, sizeY)
end

--building built -> set deathtime nil, don't need to update again
--death, set deathtime to 40m, don't update x and y for either building or com.
--if multiple interesting on one square, need to process them each uniquly

local function RecordMiniMapEvent (unitID, unitDefID, teamID, attackerID, attackerDefID, attackerTeam, type) --Any interesting thing that occurs. These are Commander Death, Afus blow, Bombing Runs.
    if interestingDeathsTypes[unitDefID] and type then
        local cx,_,cz = spGetUnitPosition(unitID)
        local x,z = floor(cx / gridResolution),floor(cz / gridResolution)
        local coord = tostring(floor(cx / gridResolution)..","..floor(cz / gridResolution))
        local r,g,b = spGetTeamColor(teamID)
            if not interestingDeathsList[coord] then
                interestingDeathsList[coord] = {}
            end
            if type == "death" then
                --Spring.Echo("interesting Death",coord,UnitDefs[unitDefID].name ,x, z)
                interestingDeathsList[coord][unitDefID] = {name = UnitDefs[unitDefID].name, x=x,z=z, timer = deathTimer, colour = {r,g,b}}
            elseif type == "built" and not UnitDefs[unitDefID].customParams.iscommander then
                --Spring.Echo("interesting Built",coord,UnitDefs[unitDefID].name ,x, z)
                if not interestingDeathsList[coord][unitDefID] then --catches a refresh if a unit is dying already.
                    interestingDeathsList[coord][unitDefID] = {name = UnitDefs[unitDefID].name, x=x,z=z, timer = "alive", colour = {r,g,b}}
                end
            end
    end
    if attackerDefID then
        if bombersList[attackerDefID] then
            --add small bomb icon
            if (UnitDefs[unitDefID].metalCost + UnitDefs[unitDefID].energyCost/70) > 1000 then
            -- big bomb icon
            end
        end
    end
    --maybe need to count accumlated damage by the bomber (to include chains reactions) and decide icon based on that. This will allow icons for large eco damage
    --but reduce them for single unit snipes.
end

local function ResetGridList() --resets all varibles for a refresh of unit influence
    gridList = table.copy(backup_gridList)
    staticUnitAlreadyProcessedList = {}
    unitLastPosition ={}
    drawer = false
end

local function RepopulateGridList(visibleUnitsList) --Populate based on visible units. Only run if player is spec fullview)
    spectator, fullview = Spring.GetSpectatingState()
    if not fullview then
        Spring.Echo("not in full view, cannot run influence")
        return
    end
    drawer = true
    if visibleUnitsList then
        --Spring.Echo("visibleUnitsList exists")
        for unitID, test in pairs(visibleUnitsList) do--#allunits do
            if select(5,Spring.GetUnitHealth(unitID)) == 1 then    
                local unprocessed, unitDefID, teamID = GetUnitStrength(unitID)
                local count = 0
                if unprocessed then
                    ProcessUnit(unitID,unitDefID,teamID, false)
                    RecordMiniMapEvent(unitID, unitDefID, teamID, nil, nil, nil, "built")
                    count = count+1
                    
                end
            end
        end
    end 
    for coord, _ in pairs(gridList) do
        CalculateCellInfluence(coord)
    end
    for i=1, #chunkUpdateList do
        chunkUpdateList[i] = true
    end
    Spring.Echo("ResetRepoulateGridList has ran")
end


function widget:DrawInMiniMap(sx,sy)
    -- if drawer == true then
    --     if drawMiniMap[replayFrame] then
    --         gl_CallList(drawMiniMap[replayFrame])
    --     end
    -- end
    if drawer and gameOver then
        if drawMiniMap[drawFrame] then
            gl_CallList(drawMiniMap[drawFrame])
        end
        if drawMiniMapIcons[drawFrame] then
            gl_CallList(drawMiniMapIcons[drawFrame])
        end
    end
    if drawUpdateCounter % 3 ==0 and gameOver then
        drawFrame = drawFrame +1
        if drawFrame >= replayFrame then
            drawFrame = 1
        end
    end
    drawUpdateCounter = drawUpdateCounter+1
end

function widget:GameOver()
	gameOver = true
    Spring.Echo("Game Over is True GameOver()")
end

function widget:Initialize()
    UiUnit = WG.FlowUI.Draw.Unit
    --UiElement = WG.FlowUI.Draw.Element
    --Spring.Echo("mapSizeX",mapSizeX,"mapSizeZ",mapSizeZ,"numberOfSquaresInX",numberOfSquaresInX,"numberOfSquaresInZ",numberOfSquaresInZ,"totalNumberofChunkX",totalNumberofChunkX,"totalNumberofChunkZ",totalNumberofChunkZ,"chunkUpdateList",#chunkUpdateList)
    fullview = select(2, Spring.GetSpectatingState())
    --Spring.Echo("spectator, fullview",spectator,fullview)
    ----Reset all lists------used for debuging
    drawInfluenceChunk = {}
    chunkUpdateList = {}
    unitLastPosition = {}
    CoordUpdateList = {}
    for n = 1, totalNumberofChunkZ do --creates the chunkupdatelist
        for m = 1, totalNumberofChunkX do
        chunkUpdateList[((n-1)*totalNumberofChunkX)+m] = true
        end
    end
    gridList = {} --table that holds all values
    backup_gridList = {} --a copy of gridlist full of 0, used to reset if something gets out of sync
    totalsForDraw = {} --version of table ready to draw from, with owners teamID and releative Strength, as well as mapcoords.
    -------------------------------
    PopulateGrid()
    if fullview then
        widget:VisibleUnitsChanged(WG['unittrackerapi'].visibleUnits, nil)
    end
    Spring.Echo("end Initialize")
    drawer = true
end
 
--function widget:DrawWorld()
function widget:DrawWorldPreUnit()
    if drawer == true then
        for i,j in pairs(drawInfluenceChunk) do
            gl_CallList(drawInfluenceChunk[i])
        end
    end
end

function widget:TextCommand(command)
    if string.find(command, "inf show", nil, true) then
        drawer = true

    elseif string.find(command, "inf hide", nil, true) then
        drawer = false

    elseif string.find(command, "inf refresh", nil, true) then
        widget:VisibleUnitsChanged(WG['unittrackerapi'].visibleUnits, nil)
    elseif string.find(command, "inf colours", nil, true) or string.find(command, "inf colors", nil, true)  then
        if onlyAllyTeamColours then
            onlyAllyTeamColours = false
            Spring.Echo("Individual colours enabled")
        else
            onlyAllyTeamColours = true
            Spring.Echo("Captain colours enabled")
        end

    elseif string.find(command, "inf replay", nil, true) then
        Spring.Echo("Removed unit icons from minimap, type '/minimap unitsize 5 to bring them back'")
        Spring.SendCommands("minimap unitsize " .. 0)
        gameOver = true
        drawer = true
    elseif string.find(command, "inf spam", nil, true) then      
        if spamDisabled then
            EnableSpam()
        else
            DisableSpam()
        end
    end
end


-- function widget:MousePress(mx, my, button) --sets the way point if hotkey is pressed and factory type selected.
--     fullview = select(2, Spring.GetSpectatingState())
--     if button == 1 then
--         -- local _ , pos = Spring.TraceScreenRay(mx, my, true)
--         -- if pos then
--         --     local cx, cy, cz = pos[1],pos[2],pos[3]
--         --     local coordX = floor(pos[1]/ gridResolution)
--         --     local coordZ = floor(pos[3]/ gridResolution)
--         --     Spring.Echo("square coord [X,Z] =", coordX,coordZ,pos[1],pos[2],pos[3],mx, my)
--         --     local c = 0
--         --     for _,_ in pairs(unitLastPosition) do
--         --         c=c+1
--         --     end
--         --     Spring.Echo("unitLastPosition length", c)
--         -- end
--         -- --Spring.Echo("map geo",Spring.GetMiniMapGeometry())

--         -- --Spring.Echo("replayList[49,43]:",replayList["49,43"])
--     end
--     if button == 2 and fullview then
--         gridList = table.copy(backup_gridList) -- only needed if resetting the girdlist, which i shouldn't every need to do?
--         staticUnitAlreadyProcessedList = {}
--         unitLastPosition ={}
--         local allunits = Spring.GetAllUnits() --for now update all units, in future this may need to split the list over serval updateticks
--         if allunits then
--             for i = 1, #allunits do--#allunits do
--                 local unitID = allunits[i]
--                 if select(5,Spring.GetUnitHealth(unitID)) == 1 then    
--                     local bool, unitDefID,teamID = GetUnitStrength(unitID)
--                     if bool then
--                         ProcessUnit(unitID,unitDefID,teamID, false)
--                         RecordMiniMapEvent(unitID, unitDefID, teamID, nil, nil, nil, "built")
--                     else
--                         --Spring.Echo("This unit wasn't processed",unitID, UnitDefs[unitDefID].translatedHumanName)
--                     end
--                 end
--             end
--         end
--         local count = 0
--         for i,j in pairs(CoordUpdateList) do
--             count = count +1
--         end
--         Spring.Echo("length of CoordUpdateList", count)
--         for i, j in pairs(gridList) do
--                 CalculateCellInfluence(i)
--         end
--         for i=1, #chunkUpdateList do
--             chunkUpdateList[i] = true
--         end
--         Spring.Echo("end MousePress")
--         drawer = true
--     end
--     if button == 3 then
--         if spamDisabled then
--             EnableSpam()
--         else
--             DisableSpam()
--         end
--         drawer = true
--         gameOver = true
--         for i,j in ipairs(replayList) do
--             --Spring.Echo(replayList[i]["49,43"])
--             --RunReplayList()
--             --displayFrameCounter = 1
--         end
--     end
--     if button == 4 then
--         if onlyAllyTeamColours then
--             onlyAllyTeamColours = false
--             Spring.Echo("All colours")
--         else
--             onlyAllyTeamColours = true
--             Spring.Echo("Two colours")
--         end
--     end
--     if button == 5 then
--         Spring.Echo("remove from minimap")
--         Spring.SendCommands("minimap unitsize " .. 0)
--     end
-- end





function widget:Shutdown() --release all values
    if drawMiniMap then
        for i,_ in pairs(drawMiniMap) do
		    gl_DeleteList(drawMiniMap[i])
        end
	end
    if drawInfluence then
		gl_DeleteList(drawInfluence)
	end
end

function widget:PlayerChanged()
    spectator, fullview = Spring.GetSpectatingState()
end

function widget:Update()
    if Spring.IsGameOver() ==true then
        gameOver = true
        if spamChecker < 2 then
            Spring.Echo("Game Over is True update()")
            spamChecker = spamChecker + 1 
        end
    end
end

function widget:GameFrame()
    updateCounter = updateCounter + 1
    if updateCounter % 4 == 0 then --show new chunks
        local simuChunks = 4
        for i = chunkUpdateCounter, (chunkUpdateCounter + simuChunks) do
            if chunkUpdateList[i] == true then
                DrawNextInfluenceChunk(i)
                chunkUpdateList[i] = false
            end
        end
        if chunkUpdateCounter >= #chunkUpdateList then
            chunkUpdateCounter = 1
        else
            chunkUpdateCounter = chunkUpdateCounter + simuChunks
        end   
    end
    local fraction = 16
    for unitID, data in pairs(unitLastPosition) do 
        if (unitID % fraction) == (updateCounter % fraction) then
            local cx,_,cz = spGetUnitPosition(unitID)
            if cx then --no cx means destroyed.
                local teamID = data.teamid
                MovingUnitsInfluence(unitID,teamID,cx,cz)
            else
                local teamID = data.teamid
                local udID = data.udid
                ProcessUnit(unitID,udID,teamID,true) --update ran before unit was destored, remove here. xxx may need destroyed unit check?
            end
        end
    end

    if updateCounter % 10 == 0 then
        for coords, _ in pairs(gridList) do
            if CoordUpdateList[coords] then
                CalculateCellInfluence(coords)
            end
        end
    end

    if updateCounter == 150 then --every 5 sec
        if replayFrame ==0 then --I want to store the first 5 frames as static to allow stuff to load at game start when lots of icons. xxx this is bodge
            for i = 1,4 do
                StoreReplayList(i)
                RunReplayList(i)
            end
            replayFrame = 4
        end
        replayFrame = replayFrame + 1
        updateCounter = 0
        StoreReplayList(replayFrame)
        RunReplayList(replayFrame)
        UnitTakenDebug = {} --xxx very very small chance that this could reset before the UnitTakenDebug stops a repeat call from occuring
    end

end

-- function widget:UnitFinished(unitID,unitDefID,teamID) 
--     if GetUnitStrength(unitID) then
--         ProcessUnit(unitID,unitDefID,teamID,false)
--         RecordMiniMapEvent(unitID, unitDefID, teamID, nil, nil, nil, "built")
--     end

-- end



-- function widget:UnitDestroyed(unitID, unitDefID, teamID, attackerID, attackerDefID, attackerTeamID) --I process moving units in the frameupdate.
--     if staticUnitAlreadyProcessedList[unitID] or unitLastPosition[unitID] then
--         if staticUnitAlreadyProcessedList[unitID] then
--             ProcessUnit(unitID,unitDefID,teamID,true)
--         end
--         if select(5,Spring.GetUnitHealth(unitID)) == 1 then --this should not include reclaims. non finished units won't be on these lists in the first place.
--             RecordMiniMapEvent(unitID, unitDefID, teamID, attackerID, attackerDefID, attackerTeamID,"death")
--         end    
--     end  
-- end


-- function widget:UnitTaken(unitID, unitDefID, oldTeam, newTeam) --This is called before `UnitGiven` and in that moment unit is still assigned to the oldTeam, so destroy old influ
--     --Spring.Echo("unitTaken1",unitID, unitDefID, newTeam, oldTeam, Spring.GetUnitTeam(unitID))
--     if select(5,Spring.GetUnitHealth(unitID)) == 1 and not UnitTakenDebug[unitID] then
--         UnitTakenDebug[unitID] = true
--         ProcessUnit(unitID,unitDefID,oldTeam,true) --destroy unit infu
--         if GetUnitStrength(unitID,newTeam) then --remake unit
--             ProcessUnit(unitID,unitDefID,newTeam,false) --add unit influe
--         end
--     end
-- end

-- function widget:UnitGiven(unitID, unitDefID, newTeam, oldTeam) --This is called after `UnitTaken` and in that moment unit is assigned to the newTeam. xxx may need to consider upgradable buildings - EG mex T2, geo etc
--     --Spring.Echo("unitGiven1",unitID, unitDefID, newTeam, oldTeam, Spring.GetUnitTeam(unitID))
-- end


function widget:UnitLoaded(unitID, unitDefID, unitTeam, transportID, transportTeam)
    ProcessUnit(unitID,unitDefID,unitTeam,true)
    Spring.Echo("unit Loaded",unitID, UnitDefs[unitDefID].name, unitTeam)
end

function widget:UnitUnloaded(unitID, unitDefID, unitTeam, transportID, transportTeam)
    if GetUnitStrength(unitID) then --remake unit
        ProcessUnit(unitID,unitDefID,unitTeam,false)
        Spring.Echo("unit Unloaded",unitID, UnitDefs[unitDefID].name, unitTeam)
    end
end

-- a unit is added on visible units multiple times - when created, when finished, when transfered
-- a unit is removed when transfered, when dies
--visiable unit changed are (extVisibleUnits, extNumVisibleUnits)
--therefore i need to always check the unit is finished, then add on VisibleUnitAdded and remove on visibleunitremoved. I also need call visible units changed when changing spectator status.

function widget:VisibleUnitAdded(unitID, unitDefID, teamID)
    if select(5,Spring.GetUnitHealth(unitID)) == 1 then --i've removed the double as the api shouldn't need it process check here.
        if GetUnitStrength(unitID) then
            ProcessUnit(unitID,unitDefID,teamID,false)
            RecordMiniMapEvent(unitID, unitDefID, teamID, nil, nil, nil, "built")
        end
    end
    --Spring.Echo("visibleUnitAdded",unitID, UnitDefs[unitDefID].name, teamID,select(5,Spring.GetUnitHealth(unitID)))
end

function widget:VisibleUnitRemoved(unitID, unitDefID, teamID)
    if staticUnitAlreadyProcessedList[unitID] or unitLastPosition[unitID] then
        if staticUnitAlreadyProcessedList[unitID] then
            ProcessUnit(unitID,unitDefID,teamID,true)
        end
        if select(5,Spring.GetUnitHealth(unitID)) == 1 then --this should not include reclaims. non finished units won't be on these lists in the first place.
            RecordMiniMapEvent(unitID, unitDefID, teamID, nil, nil, nil, "death")
        end    
    end  
    --Spring.Echo("visibleUnitRemoved",unitID, UnitDefs[unitDefID].name, teamID,select(5,Spring.GetUnitHealth(unitID)))
end

function widget:VisibleUnitsChanged(extVisibleUnits, extNumVisibleUnits) --xxx need to check if in spec before dealing with these?
    Spring.Echo("visibleUnitChanged")
    --Spring.Echo(a)
    Spring.Echo("extNumVisibleUnits",extNumVisibleUnits)
    spectator, fullview = Spring.GetSpectatingState()
    Spring.Echo("spectator, fullview",spectator, fullview)
    if fullview then --repopulate list
        ResetGridList()
        RepopulateGridList(extVisibleUnits)
    else -- not in fullview, so need to remove all influence.
        ResetGridList()
    end
end