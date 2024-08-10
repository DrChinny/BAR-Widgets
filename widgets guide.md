Beyond All Reason Getting Started with Widgets Guide, writen by Mr_Chinny.

# About This Guide

This guide is divided into several sections. Read from start to finish or skip to the relevent section:
- [What are Widgets in Beyond All Reason:](#what-are-widgets-in-beyond-all-reason) For an overview of Widgets and thier uses and limits.
- [Coding Environment:](#coding-environment) Getting set up with required software and lua.
- [Creating Our Widget:](#creating-our-widget) Complete guided walkthrough of making simple widget.
- [Widget Specific Tips:](#widget-specific-tips) Useful Tips to save headaches
- [End:](#end) Closing remarks.

<br>
<br>

# What are Widgets in Beyond All Reason?
In Beyond all reason (BAR), widgets play a huge part in how the game looks, plays and feels. 
This guide is aimed at anyone interested in making their own widget, but particularly those of us who may call themselves hobbyists, coming from non-computer science backgrounds, and knowing little to nothing about BAR coding.
BAR is great, but as most discussion takes place through GitHub and discord, it can be hard to know where to start, and where the resources are (spoiler - they are all over the place).
In this guide, we will walk through coding a simple widget and explain what and why we are doing each step, as well as going over common pitfalls that come with experience.
A certain amount of experience with coding is assumed, check out the 'Super Brief lua guide' further down for what we will be doing. 



## Quick Widget Introduction

Widgets files of lua code that run during a game of BAR. They can't affect the simulation directly but can issue commands to your own units. They are specialised to achieve a particular thing, and generally fall into the following categories:
- >`Display Some Info on the Screen` - This could be the topbar showing income, the player list of allies and enemies, range or radar circles, ghost outline of buildings at the start of the game, and many many more.
- >`Change Behaviour of a Unit` - Constructors auto guarding a factory, fighters patrolling out of the airlab, etc
- >`Extra Control Pptions and Features` - Bar's famous line drag control, grid building etc.



## Widgets and Gadgets
Similar to **widgets**, there are also things called **gadgets**. 
Gadgets are widgets' bigger stronger siblings! They are written in much the same way, but they have higher access to the functions and data that the game engine provides, and can change things directly within the game.

The reason for dividing widgets and gadgets is to control access and stop abuse - gadgets cannot be modified by the end user in a multiplayer match (this would cause sync errors) and are run by everyone. They have access to synced commands - basically things that can change something in the game that everyone else’s simulation needs to know about. If you make a gadget and want it added to the main game, you need to discuss with a dev in discord.

On the other hand, widgets are more limited. Although we can change our own units' behaviour, this is effectively achieved by giving the unit a series of commands (eg. fighters get a patrol command when leaving a factory), which otherwise could have been done with mouse clicks. Anything graphically doesn't impact the simulation, even if it provides useful data for the user.
Widgets are run locally, and only affect you. In fact you can take any widget in the game, tweak the code to your liking, and everything will be fine.

In summary, A gadget could delete an enemy unit or even player from the game entirely, whereas a widget could only set a self-destruct command to dispose of said unit.



## Widget Flow
Before we start actually coding, we should just touch on how code within widgets tend to work. The process diagram summarises what a widget will do when running.

>`A) Get Some Info from the Engine`     ----> `B) Process this Info Within the Widget`  ----> `Some Output or Action`

Some real examples:

1) >`Get your commander's hit points`   ----> `Check if hit points are reduced by a certain amount` ----> `Display a visual and audio warning that commander is low on hp.`
2) >`Get mouse position when clicked`   ----> `If clicks made rectangle, find units that fall with in` -----> `Select all combat units (but not constructors and buildings) `
3) >`Get position your launched nuke`   ----> `Lookup impact radius range and create Graphics for impact radius` ----> `Display warning to teammates of your nuke. `
4) >`Get position of a visable enemy`   ----> `Predict its position in 3 seconds based on current movement` ----> `Aim nearby friendly artillery to that spot. `

The last idea in this list (which too my knowledge I just made up), would likely give the user a big and unfair advantage, therefore be against the code of conduct, and not allowed. Better to check if unsure, before spending time making it. See [COC](#widget-specific-tips) xxx for more.


## What does a Widget have Access to?
We will need our widget to gather some data from within the game. I've divided this into two major categories

1) >`Read data from another file` -Look up information about something in the game, such as unit position or hit points. In the widget environment this is generally limited to things that the player could see if they were playing.
2) >`Use a call-in provided by the widget wrapper` -Get relevent information regarding an event that has just occurred in the game, such as when a unit is created or destroyed.


### Read Data from other Files

The engine keeps some accessible information about all sorts of stuff. There are many many many existing functions in spring engine that clever people have added in the past that give us a way of finding out about things in the game. In particular units and their stats, but also mouse coords, camera angles, team members and access to functions that other widgets provide. A few important ones are listed below:

- >`UnitDefs` -`UnitDefs` is a big kind of table that contains everything you will need to know about a unit **type**, based on the specific game settings. From its name, cost, weapons, initial hp, animations, sounds, types, to custom parameters (where everything else should be stored). It is created outside the widget and is very useful. We will be using this later. `UnitDefs` is populated from the individual unit files, weapons files and animations.
To explore it, we need a `unitDefID` (not to be confused with `unitID`). Every unit in the game has a unique `unitID`. Find this, translate it to its `unitDefID`, pull the corresponding entry in `UnitDefs`, and assuming you do it in the right way you can access these variables.

To avoid confusion, If we made 10 ticks, all would have the same `unitDefID` number, but each would have a unique `unitID`. It is simple to find the `unitDefID` given the `unitID`

- >`Get.Selection()` - Returns a table of the unitID of everything  currently selected in game.
- >`Spring.TraceScreenRay()` Translates mouse screen position to map coordinates. Very useful when needing to interact with the world using mouse.



### Events in Game

Events can be many things, pretty much when anything interesting happens in game, an event is made. Generally, we will be interested in triggering parts of our code when a particular event occurs, and grabbing variables (often `unitID`) assoicated with the event. Events occur when a unit is created, destroyed or transferred to an ally, or perhaps when something is clicked, typed, or even just every game frame. In widgets, we use them in the following format:
```lua
function widget:EventName(usefulVar1, usefulVar2)
--our code goes here
end
```
A few events are listed:
```lua 
-----------Control Events-----------
function widget:MousePress(mx,my,button) -- Click the mouse -> Event with position of mouse and button clicked.
end

function widget:KeyPress(key, mods, isRepeat) -- Press a key -> Event created with key pressed, any modifiers (eg shift, alt), and if its repeatedly been pressed
end

-----------Game Events-----------
function widget:UnitDestroyed(unitID, unitDefID, unitTeamID)) -- Widgets can only access this event for things destroyed in LOS.
end

function widget:UnitCreated(unitID, unitDefID, unitTeam, builderID) -- Whenever a new unit is created (includes resurections? xxx)
end

-----------Update events-----------
function widget:Update(dt) -- runs on every game tick, including when paused.
end

function widget:DrawScreen() --runs every update, openGL calls go in here.
end
```
There are dozens of callins. If you follow instuctions in Coding Environment:](#coding-environment) they can be found in `barwidgets.lua` within the game folder.The following are good places to see what there are, and what you can do with them (though they are not always up to date)

- [BAR github wiki](https://beyond-all-reason.github.io/spring/lua-api) Particually unsynced read and commands
- [Spring Engine Wiki](https://springrts.com/wiki/Lua:Main) older engine resource, 

That wraps out how widgets do their thing. we will soon get onto coding our own, but before we can make a widget we need software to help us...
<br>
<br>
<br>


# Coding Environment
Right, you have this great idea that will revolutionise the game (or maybe not), and want to get straight into making it happen. The first step is to get set up with the following

- > You need the best RTS around, Beyond All Reason. [BAR Download Link](https://www.beyondallreason.info/download)
- > You need an IDE (though technically you could use notepad...). I use VScode. [VScode](https://code.visualstudio.com/). You will need to get the lua extension also - I have the one by sumneko.

- > You want a copy of BAR dev branch from Github. There are separate guides that explain doing this [Bar Github Readme](https://github.com/beyond-all-reason/Beyond-All-Reason/blob/master/README.md) or in the discord. This is very useful for autosuggestions in vscode.



## Super Brief lua guide
A certain amount of coding knowledge is assumed, and as lua is the coding language for everything widget. If you can handle `ifs`, `loops` and know what a `function` is, you should be fine.
To get started here are the basics, if they make sense then read on, if not spend a few minutes playing around with lua outside of BAR first and google some tutorials.

### Conditionals
```lua
local a = 1
local b = 2
if a == b then
    print("a = b")
else
    print("a ~= b")
end

if a then --if a is not nil or false condition is satsified
    print(A) -- lua is case sensitive, this will print nil
end
```
### Loops and Tables
```lua
for i=1, 10 do
    print("i = "..i)
end

local emptyTable = {}
emptyTable[1] = "string of words"
print(emptyTable[1])

local tableArray = {"B","A","R"}
for key, value in ipairs(tableArray) do --ipairs only works for array like tables without any gaps. key is [1],[2],[3] and so on. Can use the # operator to find size
    print(value)
end

local tableDict = {x=2, y=10, z=4}
for key, value in pairs(tableDict) do --pairs works for named keys, order cycled through may not be constant
    print(key.."="..value)
end
```
### Functions
```lua
local function AreTickOP(bool)
    if bool == true then
        return "Yes, ticks are OP"
    else
        return "No, ticks are balanced"
    end
end
local theTruth = AreTickOP(true)
print(theTruth)
```
<br>
<br>
<br>

# Creating Our Widget
In this section we will go through step by step a simple widget.
<br>

## Make a Blank File and Adding GetInfo()
Finally, we can start making widgets! Start by making a blank file in vscode, save it as `your_widget_name.lua` in your widget folder (xxx make one). Make sure there are no spaces. Name for this example is `commander_health.lua`

Next (and don't worry too much why right now), we will copy another widget's header info, and change it to ours.
This allows the widget to be noticed by various other widgets within the game, and thus turned on and off from within the game. It also helps others see what your widget does at a glance.

Copy the code below to the beginning of your code, changing the various strings to your own.
```lua
function widget:GetInfo()
    return {
      name      = "Commander Health",
      desc      = "Displays current health of commanders",
      author    = "Your Name",
      date      = "Aug 2024",
      enabled   = true
    }
end
```

This will be the start of all our widget files. Our code will go underneath. We will keep an order to how we code, both for usability and readability, 
1) function widget:GetInfo()
2) Comments on widget, Version# etc
3) Declared Variables and Speedups
4) Our Functions
5) Widget call-in.

We should also comment a lot as we go, as it's easier for us and other do work out why we did what we did.

## Planning the Widget
It's a good idea to check the feasibility of your idea, and that you have a rough idea of how your code will work before starting, as the options available to widgets are vast but not infinite.

For now, let's come up with a very simple example widget.

**I want to display on the screen my commanders HP wherever I am, and even if commander is not selected.**

This seems feasible and (sort of) useful. It also touches upon graphics and a few callins.

Going back to the process flow list from the previous section:
> `A) Get Some Info from the Engine`     ----> `B) Process this Info Within the Widget`  ----> `Some Output or Action`

and translating this for our widget, might look something like this.

> `Get Commander's Hit points` ----> `Present this in Readable Form e.g. "1500/1500". Also Choose Place to Display Info on Screen` ----> `Display Graphic on Screen.`

There are many ways to code each of these steps, some better than others. We will start with something that works, then look at optimising and avoiding crashes. We won't worry too much about "edge cases" right now; that is rarer occurences when the widget may not work as intended.

## Get Commander's Hitpoints
With our process planned out, first we need the commander’s hit points. Fortunately for us, there's a method to get this:

`Spring.GetUnitHealth(unitID)`

Referring to the website: https://springrts.com/wiki/Lua_SyncedRead#GetUnitHealth
```lua
Spring.GetUnitHealth ( number unitID )
return: nil | number health, number maxHealth, number paralyzeDamage, number captureProgress, number buildProgress

    Build progress is returned as floating point number between 0.0 and 1.0.
```
Translating this to English: We provide the `UnitID` (which is a number type),
and we return EITHER: 
`nil` (if unitID doesn't exist), OR
`health,  maxHealth,  paralyzeDamage,  captureProgress, buildProgress` (if unit exist)

We need both the current health and the max health for our display. Arguablely the paralyzedDamage (emp) could be useful too, but for now we will keep things simple.

```lua 
local health, maxHealth, _ , _ , _ = Spring.GetUnitHealth (unitID)
```

In lua, _ is used for stuff we don't care about, we only need the first two returned vars.

For this to work we need to have the `unitID` of the commander.
There are multiple ways of getting this information, but we should consider a few things first before choosing ours. The answers will determine what code we need to use.

- `Whose commander do we want to display the HP of?` - Just ours.
- `When do we need to display current hit points?` - Always, but only when they change do I need to update the graphic.
- `Could we have more or less than exactly one commander?` - In team games, Yes, could be 0, or could be >1 with player transfers and reserects.
- `Do I wish to display more than one commanders HP should i own >1?` - Let's say yes for this.
- `Do I wish to display allies commanders HP?` - Not today.

That will do for now. Even for this very simple idea there are a fair few considerations, and we may come back and modify this list as we go. It's always worth considering the scope of the widget - We could display everyone's commanders in their own colours, on a lovely background, and clicking on the name would centre the camera on that commander and play a little tune. However, this is not a whole lot of use to a player, and probably just adds to screen clutter (at least that what we are deciding on for this example). We should also get it working before worrying too much about polish.

```lua
function widget:Update()
```

This callin is run every single update in the game. It's a bit overkill to run our 'Spring.GetUnitHealth (unitID)' every frame, but it will work. We could always use a counter so we only actually run our code every 10 updates, or every 100.
A better callin may be one that occurs when a unit is damaged, but we also need to consider regeneration of health and repair, so we will stick with 'Update()' now.

We still need to find the 'unitID' of the commander; that is the unique ID that belongs to our commander. One way of doing this is cycling through all the units in the game, and checking if they are a commander type. However, we can reduce load considerably as we only need to cycle through units belonging to us, not enemies, and not teammates.

Many existing widgets do exactly this, we could think of a similar widget (commander health warning, idle commander in our case) and adapt their code. Alternatively, we can refer back to the callin websites and have a look what's there to choose a decent option:

```lua
Spring.GetTeamUnits ( number teamID )
return: nil | table unitTable = { [1] = number unitID, ... }
```

This one looks hopeful, it returns a table containing all our units for a given `teamID`. `teamID` is often better thought as the ID of a member within of a larger them (see note below). But we need only our `teamID`, and then we will need to cycle through the table of `unitIDs` it returns to find any unit that is a commander. For this we will turn the `unitID` into the `unitDefID`, then check against the `UnitDefs` table to find if it is a commander - but we are getting ahead of ourselves.
- There's an important bit of the tutorial later focusing on the difference between `teamID`, `playerID`, `allyTeamID` and AIs. XXX in tutorial. 

```lua
myTeamID = Spring.GetMyTeamID()
```
This useful chap returns our (that is the person running the widget) teamID, which we will store in a variable 'myTeamID'.
Under nearly all circumstances, if playing, our teamID will not change. This isn't true for spectators, so if we wish the widget to work for spectators too, then we need to be a bit more careful. To not overcomplicate  things, we will address this later on. As grabbing the `teamID` doesn't cost much in CPU resources, we will grab it every update too.

Putting this all together, and adding in the looping code we may end up with something like this: (Note running this code will not produce an visable output in this example)

```lua
local myCommanderTable = {} -- This is outside the function so we can access it anywhere within the widget
local myTeamID = Spring.GetMyTeamID() --We will move this to init later.

function widget:Update()
    local myUnitTable = Spring.GetTeamUnits(myTeamID)
    for _, unitID in ipairs(myUnitTable) do
        local udid = GetUnitDefID(unitID)
        if UnitDefs[udid].name == "armcom" or UnitDef[udid].name == "corcom" then
            local health, maxHealth, _,_,_ = Spring.GetUnitHealth(unitID)
            local healthTable = {unitID, health, maxhealth}
            myCommanderTable[unitID] = healthTable
        end
    end
    --<run code we have yet to write that works with myCommanderTable>
end
```
if using a decent IDE set up properly, a few odd things should be underlined. There are two typos in the code that will both cause it to fail. These are `UnitDef[udid].name == "corcom"` missing an s in `UnitDefs` and `local healthTable = {unitID, health, maxhealth}` lowercase `maxHealth`. We won't actually run this bit of code as we are changing it below, but expect hundreds of hard to find crashes from silly typos like that!

### Reading the Code
When typos are fixed, and if all has gone to plan, this code will loop through all units we own, check if they are a commander, and if so grab their health. We record these values in a table called `myCommanderTable`, that we can access in a future function (as this was declared outside the function it is availble anywhere within the widget). We are using a dictionary type table for `myCommanderTable`, that is the keys in the table will be the `unitID`. As the `unitID` is unique to the unit, this will work for us.

## Improving. Get Commanders Hitpoints
The above should work, but there’s a number of improvements we can make. One thing we need to be careful of is hard coding anything that might change. **A BIG NO-NO is hard coding unitDefID, particularly [udid]**, as these can change if a new unit is added or removed, or if just using lua in certain ways, breaking the widget. We have forgotten legion coms for a start...

To fix this, most of the time, we can lookup differences between "types" of units within the `UnitDefs`. In our case, we want something that tells us if a unit is a commander. Fortunately, there is just the thing: within customparams, `iscommander = true` is present for all commanders.
This is more future proof, as anyone who adds a new commander unit to the game for a mod can (and should!) simply add this tag when creating it.
To find this we need to cycle through the `UnitDefs` using `pairs()`. Note that the `UnitDefs` need to be cycled through in this way to access the deeper tables nested within it, direct access does not work.

```lua
local commanderDefIDsList = {}
for udid, ud in pairs(UnitDefs) do --populate table with all units that are commanders
	if ud.customparams.iscommander then
		table.insert(commanderDefIDsList, udid)
	end
end
```

This will make a table containing the `udid` (shortened unitDefID) of all commanders, we can then use this in our condition checks. We can run this code once, so it can sit outside the function. With this, as it turns out we can skip the condition check all together...

Since we have `udid` of all commander types, we can actually search the resources and find a more suitable function to replace `Spring.GetTeamUnits(myTeamID)`.

```lua
Spring.GetTeamUnitsByDefs ( number teamID, number unitDefID | tableUnitDefs = { number unitDefID1, ... } )
return: nil | table unitTable = { [1] = number unitID, ... }
```

This function tells us if we provide the `teamID` and (`unitDefID` OR a `table of unitDefIDs`), we get back a table of `unitID`s.
this is ideal for us, since if we provide it with the conveniently made table: `commanderDefIDsList`, we will get only the `unitID` of commander type. 
The returned table will also be an array type, meaning we can check its size with the the length operator `#`. Thinking ahead, if nothing is returned, it means we have no commanders, if one commander is found, the table will have a length of 1, if two commanders are found, the length will be 2, and so on. This allows us an early exit should 0 commanders be found, as we don't need to continue wasting resources running the code.
Finally, rather than have all this code written in the callin `update()`, we are going to give it its own function, giving more control to when and where we run it, even if we still end up running it on `Update()` when we are done.


Putting that all together, our new code looks like this:
Do not bother copying this into your file yet, a little later on we produce something to test.
```lua

local myTeamID = Spring.GetMyTeamID() --We will move this to init later.
local myCommanderTable = {}
local commanderDefIDsList = {}

for udid, ud in pairs(UnitDefs) do --populate table with all units that are commanders
	if ud.customParams.iscommander then
		table.insert(commanderDefIDsList, udid)
	end
end

local function PopulateCommanderHealthTable() --Adds a commander type unitID to myCommanderTable
    local myUnitTable = Spring.GetTeamUnitsByDefs(myTeamID,commanderDefIDsList)
    for _, unitID in ipairs(myUnitTable) do
        local health, maxHealth, _,_,_ = Spring.GetUnitHealth (unitID)
        myCommanderTable[unitID] = {health, maxHealth}
    end
    Spring.Echo("Debugging1 commanderDefIDsList:",commanderDefIDsList)
    Spring.Echo("Debugging2 myCommanderTable:",myCommanderTable)
    --<run code we have yet to write that works with myCommanderTable>
end
```
### Spring.Echo()
At this point we should check everything is working. This is where `Spring.Echo()` and the `infolog.txt` come in.
Our biggest debugging tool is a highly helpful little chap called `Spring.Echo()`. Much like `print()` prints the output of code, `Spring.Echo()` will display, as a message in game,whatever is within the ().
This meeage is also recorded in the `infolog.txt`, along many other things each game. A finished widget should have all `Spring.Echo()` removed so as to not fill the info log up with anything. `infolog.txt` can be found in the game directory, and can be opened by vscode.

`Spring.Echo()` can display strings of the varible, multiple varlibles, and recently even the contents of tables! When using it, seperate the arguments with ",". eg `Spring.Echo("this is a counter ", counter, " that I made")`
`Spring.Echo()` has some anti spam protection: it will not display the exact same message in a row multiple times, it will however display messages that are not identical, so two `Spring.Echo("a")` and `Spring.echo("b")`, put in something that runs once per update, would flood your infolog very quickly! Large nested tables can also take up thousands of lines, so be careful.

To check our code is working, we need to print our lists and see if they contain our commander stats. I have snuck in the echos to the end of our function, so we will use a callin called `MousePress()` to activate the function once on a mouse press.
`MousePress()` gives us mx and my screen coords of the mouse (we dont care about these today), and which `button` it pressed (1 = left click)
```lua
function widget:MousePress(_, _, button)
    if button == 1 then
        PopulateCommanderHealthTable()
    end
end
```

## Running the Code

Now it's time to put everything together and see if we can run it! The code is not finished yet, but we are hoping to get a read out in the `infolog.txt`.
Please copy the code below into your blank file and save it.

```lua
function widget:GetInfo()
    return {
      name      = "Commander Health",
      desc      = "Displays Commander Health",
      author    = "Your Name",
      date      = "Aug 2024",
      enabled   = true
    }
end

local myTeamID = Spring.GetMyTeamID() --we will move this to init later.
local myCommanderTable = {}
local commanderDefIDsList = {}

for udid, ud in pairs(UnitDefs) do
	if ud.customParams.iscommander then
		table.insert(commanderDefIDsList, udid)
	end
end

local function PopulateCommanderHealthTable()
    local myUnitTable = Spring.GetTeamUnitsByDefs(myTeamID,commanderDefIDsList)
    for _, unitID in ipairs(myUnitTable) do
        local health, maxHealth, _,_,_ = Spring.GetUnitHealth (unitID)
        myCommanderTable[unitID] = {health, maxHealth}
    end
    Spring.Echo("Debugging1 commanderDefIDsList:",commanderDefIDsList)
    Spring.Echo("Debugging2 myCommanderTable:",myCommanderTable)
    --<run code we have yet to write that works with myCommanderTable>
end

function widget:MousePress(_, _, button)
    if button == 1 then
        PopulateCommanderHealthTable()
    end
end
```

If we add all the code so far together as above, and load up a skirmish against some inactive AI, we can check our code each time we left click. 
**WARNING:** MAKE SURE THAT THE CODE ISN'T IN THE `Update()` FUNCTION! or you will spam your info log and possibly freeze the game.

Mine looks like this, yours may differ. Turns out there are a fair number of units that identify as coms (the numbers in the first table, which are unitDefID). You can look up what they are by looping through UnitDefs if you like.

The second table shows our starting com, unitID is 12052, current HP is 3700 and max is 3700. Cool. If this doesn't work then check the widget is enabled, and you have left clicked once after the game starts. Also, although the infolog updates in real time, sometimes it only updates if there's several things to write to it. In a skirmish you can pause/unpause a few times if the `Spring.Echo()` isn't showing at the bottom yet (in a multiplayer game I minimise and maximise the screen which also writes to the log). If it's still not working ask for help in discord!

```log
[t=00:12:06.644854][f=0016907] Debugging1 commanderDefIDsList:, <table>
[t=00:12:06.644910][f=0016907] {
  49,
  50,
  51,
  52,
  53,
  54,
  55,
  56,
  57,
  58,
  59,
  281,
  282,
  283,
  284,
  285,
  286,
  287,
  288,
  289,
  290,
  291,
}
[t=00:12:06.644933][f=0016907] Debugging2 myCommanderTable:, <table>
[t=00:12:06.644944][f=0016907] {
  [12052]={
    3700,
    3700,
  },
}
```
## Processing Code: Get the Hit Points Ready to Display on the Screen

We can now move onto the processing step where we need to take the hit points and do any manipulations or checks, then get ready to display them.

BAR uses openGL to do it's drawing. If you don't know anything about openGL, it's a graphic API for vector graphics, and a pretty large topic, with many great guides online.
Fortunately the devs have made many tools to help us here so we don't need to start from scratch, nor massively concern ourselves with how it works. We will make use of another widget that is shipped with the game which handles the backend stuff and allows us to use a simple commands to draw text.

Draw callins - that is those which let us draw stuff, are `DrawScreen()` for drawing on the screen (think the UI), or the world `DrawWorld()` for drawing to the map (think radar overlay). These are resource expensive, so we keep as much code away from them as possible, and try to only use them to send our graphics to be drawn. If we can also reduce changing the drawing as much as possible, we greatly reduce the load on the CPU.

For our widget, we want to display, in reasonably big characters, the hit point of each commander we own, such as Com1: 3700 / 3700.
In this bit of code, we need to choose some position to display it, colours, size and font.
To make this work, we are going to create everything we eventually want to display, and put it in a single gl.list to be sent to the graphics card. We will only update the list if something has changed (e.g. commander hit points changed).

**Big Tip:** Its a very good idea to look over other widgets and see how they handle drawing. For simple text, the font widget will work.

Let's make a function to handle the list creation, and formatting. We will only call this function when the commander health has changed.
```lua
local healthToDraw
local function CreateHealthInfoTexture()
    if healthToDraw then
		gl.DeleteList(healthToDraw)
	end
    
    healthToDraw = gl.CreateList(function()

    --<Our formatting code will go here>

    end)
end
```

Notice first that we are creating a variable called healthToDraw outside of the function, we will set this to be the gl list we are creating. Inside the function, we declare it as `gl.CreateList(function()` which has an open ended bracket, and contains a `function()`. This bracket is closed after the first end, which represents the end of the function. We will put our code presenting the hit points between these.
At the beginning of the function, we also are checking if our gl list exists, and if it does deleting the whole thing and then making a new one (with updated info).

### Using the Font Widget:
Writing characters to screen in openGL directly is expensive. It's better to turn them into a texture and display that instead. Another widget deals with this for us without us needing to think about it. We need to reference the font widget when our widget loads. This is done in function `widget:Initialize()` - code that will run only once when the game is loaded and we have joined it, or when the widget it first turned on.
We will load a widget called 'fonts' which sets everything up, and we load a font from a list of BAR fonts shipped with the game through the widget. We don't need to know how or why this works right now, but you can look at the code in the font widget.
```lua
local fontfile2 = "fonts/" .. Spring.GetConfigString("bar_font2", "Exo2-SemiBold.otf") --This is the font, its stored in the BAR directly if you want to check it.
local font
function widget:Initialize()
    font =  WG['fonts'].getFont(fontfile2, 1.0, 0.25, 6) --xxx add argument meanings
end
```

After this, we can add some code that will help us display our hit points of commanders. We also need to choose a few values for positions and font size. We will need to come back and change the fixed values to be proportional to the user screen size and UI scales.

```lua
local posX,posZ = 512,512 --This Should be visable somewhere on screen (unless you have a very strange resolution - you will deal with it later.)
local fontsize = 20
local function CreateHealthInfoTexture()
    if healthToDraw then
		gl.DeleteList(healthToDraw)
	end
    healthToDraw = gl.CreateList(function()
    local counter = 0
        if myCommanderTable then
            for i,data in pairs(myCommanderTable) do
                --font:print(String, PosX left, Pos Z Top, fontsize, alignments)
                font:print((data[1].." / " data [2]) , (posX),(posZ (+ counter * fontsize)+10) , (fontsize) , ("cvos")) --"cvos" means center veritcal outline, shadow, see xxx.
                counter = counter + 1
    end)
end
```
We've put each argument in `font:print` in its own brackets for ease of reading, this won't affect the code.

`data` is the value in the `myCommanderTable` table, which is a list containing {health, maxHealth}. data[1] therefore is the health, data[2] is the maxHealth. We have also added a backslash in string form, and joined them all together. This is what we are displaying

The `X` and `Z` position are set to `512`, `512`, which depending on your resolution will be somewhere in the bottom left-hand part of the screen.
Note: x is left to right, z it up and down, y is in and out of screen. x = 0, z = 0 is the bottom left corner of screen.
The counter on the z position will space lines out if there’s more than one commander. It adds one fontsize, and 10 pixels of padding.

`fontsize` is `20`, this is readable on most screens.

`cvos` alignment translations are found at https://springrts.com/wiki/Lua_OpenGL_Api#Text

We would need to scale all these values based on screen resolution and UIScale, but won't bother with that in this tutorial.

### One More Conditional
We also need to decide when to run the `CreateHealthInfoTexture()` function. There's no point in rewriting this every frame if nothing has changed with commander hit points, so we can check against this in the previous function we wrote.
To do this we will check if the commander unit health (or max health due to promotions) from the last check is the same as now, and if it isn't flip an update variable. We also need to flip the update if there's we get a new commander. Finally, we need to remove dead commanders from the list, or they will always be displayed (but won't clutter the code below by adding this yet). You may also see there's a `drawer` and `counter` added. This will be used when we wish to display the code on screen.
Altogether, our (nearly completed) code will look like this.

```lua
local font
local fontfile2 = "fonts/" .. Spring.GetConfigString("bar_font2", "Exo2-SemiBold.otf")
local myTeamID = Spring.GetMyTeamID() --We will move this to init later.
local myCommanderTable = {}
local commanderDefIDsList = {}
local posX,posZ = 512,512
local fontsize = 20
local healthToDraw
local drawer = false --If true we draw, if false we don't

for udid, ud in pairs(UnitDefs) do
	if ud.customParams.iscommander then
		table.insert(commanderDefIDsList, udid)
	end
end

local function CreateHealthInfoTexture()
    drawer = false
    if healthToDraw then
		gl.DeleteList(healthToDraw)
	end
    healthToDraw = gl.CreateList(function()
    local counter = 0
        if myCommanderTable then
            for i,data in pairs(myCommanderTable) do
                font:print(data[1].." / " data [2],posX,posZ (+ counter * fontsize),fontsize,"cvos") --"cvos" means center veritcal outline, shadow, see xxx.
                counter = counter + 1
    end)
    if counter > 0 then
    drawer = true
end

function PopulateCommanderHealthTable()
    local myUnitTable = Spring.GetTeamUnitsByDefs(myTeamID,commanderDefIDsList)
    local update = false
    for _, unitID in ipairs(myUnitTable) do
        local health, maxHealth, _,_,_ = Spring.GetUnitHealth (unitID)
        if myCommanderTable[unitID] then
            if health ~= myCommanderTable[unitID][1] or maxHealth ~= myCommanderTable[unitID][2] then
                update = true
            end
        else
            update = true -- this is the case of a new commander
        end
        myCommanderTable[unitID] = {health, maxhealth}
    end
    if update then
        CreateHealthInfoTexture()
    end
end

function widget:Initialize()
    font =  WG['fonts'].getFont(fontfile2, 1.0, 0.25, 6) --xxx add argument meanings
end


```
## Display graphics on screen.
This step is now nice and quick, since we have everything we need from the previous step. When drawing to the screen, or the world we use:
```lua
function widget:DrawScreen() 
end
--or 
function widget:DrawWorld()
end
```

Since we want to draw to the screen, we use the first one.
Now we can use the 'drawer' variable from before. This will only flip to true if we have something to draw, so we can use this and the healthToDraw as conditions for drawing. Remember `DrawScreen()` can be expensive and activities every frame, so we want it off when possible.
`gl.CallList` will essentially activate the list of draw commands we sent.

```lua
function widget:DrawScreen()
    if drawer and healthToDraw then
        gl.CallList(healthToDraw)
    end
end
```

If we put everything together and run it our function on Update(), We should get something happening! Copy the completed code and save it, then run in a skirmish.
```lua
function widget:GetInfo()
    return {
      name      = "Commander Health",
      desc      = "Tutorial Commander Health",
      author    = "Your_Name",
      date      = "Aug 2024",
      enabled   = true
    }
end

local font
local fontfile2 = "fonts/" .. Spring.GetConfigString("bar_font2", "Exo2-SemiBold.otf")
local myTeamID = Spring.GetMyTeamID() --we will move this to init later.
local myCommanderTable = {}
local commanderDefIDsList = {}
local posX,posZ = 512,512
local fontsize = 20
local healthToDraw
local drawer = false --if true we draw, if false we don't

for udid, ud in pairs(UnitDefs) do
	if ud.customParams.iscommander then
		table.insert(commanderDefIDsList, udid)
	end
end

local function CreateHealthInfoTexture()
    drawer = false
    local counter = 0
    if healthToDraw then
		gl.DeleteList(healthToDraw)
	end
    healthToDraw = gl.CreateList(function()
        if myCommanderTable then
            for i,data in pairs(myCommanderTable) do
                font:Print(data[1].." / ".. data[2],posX,posZ + (counter * fontsize),fontsize,"cvos") --"cvos" means center veritcal outline, shadow, see xxx.
                counter = counter + 1
            end
        end
    end)
    if counter > 0 then
        drawer = true
    end
end

function PopulateCommanderHealthTable()
    local myUnitTable = Spring.GetTeamUnitsByDefs(myTeamID,commanderDefIDsList)
    local update = false
    for _, unitID in ipairs(myUnitTable) do
        local health, maxHealth, a,b,clearInstanceTable = Spring.GetUnitHealth(unitID)
        if myCommanderTable[unitID] then
            if health ~= myCommanderTable[unitID][1] or maxHealth ~= myCommanderTable[unitID][2] then
                update = true
            end
        else
            update = true -- this is the case of a new commander
        end
        myCommanderTable[unitID] = {health, maxHealth}
    end
    if update then
        CreateHealthInfoTexture()
    end
end

function widget:DrawScreen()
    if drawer and healthToDraw then
        gl.CallList(healthToDraw)
    end
end

function widget:Initialize()
    font =  WG['fonts'].getFont(fontfile2, 1.0, 0.25, 6)
end

function widget:Update()
        PopulateCommanderHealthTable()
end
```
## Cleaning Up
Hopefully it worked, but a few big bugs will have stood out - I noticed the position on screen makes no sense, the hit points become floats not Ints, and commanders that die don't get removed from the list. If we look at the widget profiler XXX, we can also see it's using quite a few resources, perhaps we shouldn't be running the code every update tick. May also be fun to change the colour of the text to Red <20%, and yellow for <50%.

The tutorial ends here, but try fixing the issues yourself. There's a file with my bug fixes in the github XXX to compare.

Some useful functions that may help are
```lua
math.floor() and math.ceil() --Round up or down to nearest int
widget:UnitDestroyed() --When a unit is destroyed
widget:UnitGiven() -- When a unit is transfered
Spring.GetViewGeometry() --Game resolution in pixel
widget:PlayerChanged() --When the player changes team.
```

# Widget Specific Tips
## About teamID, allyTeamID, playerID, GaiaID
One important thing that I want to address is the difference between the terms above, as they all have specific meaning, and are not interchangable. The person who originally named these was either drunk or a sadist.

Using English: In an a 8v8 match, there are two teams (red and blue), each with 8 members (various warm and cold colours respectivly), and (assuming no AI), each with 8 players.

Using Barish: In and 8v8 match, there are two allyTeamID (0 and 1). There is also Gaia who has an allyTeamID one higher than highest normal team (2). Scavs, raptors also may have their own allyTeamID.

Using Barish: each allyTeamID will have (8) teamIDs. These are unique, so 0,1,2,3,4,5,6,7 on allyTeamID 0, and 8,9,10,11,12,13,14,15 on allyTeamID 1. Gaia again takes one higher (16).

Using Barish: each player also gets a playerID which may or may not be the same as teamID (usally is). AI's don't have a playerID, they have an aiID (xxx check)

Though not common, a single teamID can have more than one player on it (think archon mode from sc2).

Spectators take the teamID and allyTeamID of the player they selected (but not the playerID?). They have their own playerID.

Things get weird when making a widget work with players, spectators, ai, raptors, scavs and gaia! Double check what arguments your the functions need.

## UnitDefs
UnitDefs is a metatable containing all the unit type info. The way to access the deeper parts of it is using pairs(). xxx expand
```lua
--WIP
for udid, ud in pairs(UnitDefs) do
	for wdid, weaponDef in pairs(ud.weapons) do
		if WeaponDefs[ud.weapons[wdid].weaponDef] the
        local type = WeaponDefs[ud.weapons[wdid].weaponDef].type
        break
        end
    end
end
```

# End
I hope this helped you get started into the world of widgets, and if you get a taste for it, contributing to BAR. We've barely scratched the surface of useful things, but I do hope you found this guided tutorial somewhat helpful. Please join the discord channels (take the dev role) and come chat, share ideas and ask questions, all the devs I've met there are friendly, encouraging and willing to help. BAR depends on contributions to continue to improve, and with limited human power, Every Little Helps (tm).

I've only a few months coding experience, so I'm sure there's a lot which is not correct in the guide, so please come and correct my mistakes (Cunningham's Law in action!)

Mr_Chinny / Chin

















