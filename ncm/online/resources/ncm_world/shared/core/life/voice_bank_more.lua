-- ncm-core data: life.voice_bank_more -- the second pass, appended to moves the first three parts opened. Written
-- after the first demo showed neutral voices drawing from pools of one or two lines ("Filling up. Eddies straight
-- into the tank." from three different street mouths). Every register gets a broad base in every move, and the
-- warmth/temper variants deepen. Format and tags: see life/voice_bank.lua.
local Core = NcmCore

Core.define("life.voice_bank_more", function()
    local M = {}
    M.ORDER = {
        "greet_first", "greet_again", "greet_regular", "close",
        "act_eat", "act_loiter", "act_fuel", "act_hang", "act_errand", "act_hustle", "act_work",
        "weather_clear", "weather_grey", "weather_rain", "weather_fog", "weather_smog", "weather_sand",
        "time_late", "time_dawn", "time_morning", "time_midday", "time_afternoon", "time_evening", "time_night",
        "district_lockdown", "district_open_war", "district_gang_rule", "district_oligarchy", "district_scene_town",
        "district_fracture", "district_neglect", "district_balance",
        "topic_next", "topic_last_win", "topic_last_podium", "topic_last_finish", "topic_last_dnf", "topic_tag",
        "topic_series", "topic_role_driver", "topic_role_engineer", "topic_role_strategist", "topic_role_manager",
        "topic_role_owner",
    }
    M.MOVES = {}

    M.MOVES.greet_first = {
        "[street] Sup.",
        "[street] Help you with something?",
        "[street] You look like you're looking for somebody. It's not me. Probably.",
        "[street] Don't think I've seen you round {district} before.",
        "[street] Yo. You new?",
        "[street warm] Hey, you alright? You look like you've had a night.",
        "[street warm] Welcome, stranger. Pull up a bit of wall.",
        "[street warm] Hey! Nice to see a new face that isn't trying to sell me something.",
        "[street cold] Something I can do for you? Didn't think so.",
        "[street cold] You're in my light.",
        "[street cold] I don't know you.",
        "[street edgy] Hands where I can see 'em. Joking. Mostly.",
        "[street edgy] You a cop? You look like a cop. Everybody looks like a cop tonight.",
        "[street calm] Hey. Easy night so far. Let's keep it that way.",
        "[street calm] Evening, stranger. Nothing to see here but me.",
        "[plain] Hello there.",
        "[plain] Hi. Can't say I know you.",
        "[plain] Hey. First time round here?",
        "[plain] Sorry, have we met?",
        "[plain warm] Hi, hello. Always nice to meet somebody new.",
        "[plain warm] Oh, hello! You look friendly. Don't prove me wrong.",
        "[plain cold] Can I help you?",
        "[plain cold] I'm not really in the mood for company.",
        "[plain edgy] Whoa, you startled me.",
        "[plain edgy] Can we make this quick? I'm not having a great day.",
        "[plain calm] Hello. No rush, whatever it is.",
        "[plain calm] Hi there. Nice evening for a wander.",
        "[tech] Hello. Are you lost, or curious? Curious is fine.",
        "[tech] Hi. Sorry, I'm halfway through a sum.",
        "[tech] Oh. A person. Hello.",
        "[tech warm] Hello! Sorry, I'll put this away. Hi.",
        "[tech cold] If this isn't about the car, I'm not the one to ask.",
        "[tech edgy] Please don't stand behind me, I'm thinking.",
        "[tech calm] Hello. Nice to talk to someone who isn't a spreadsheet.",
        "[corp] Hello. I don't believe we've met.",
        "[corp] Good day. Are you with someone?",
        "[corp] How do you do.",
        "[corp warm] Hello! Forgive me, I'm terrible with names. Actually, I've never had yours.",
        "[corp cold] Is there something you need?",
        "[corp edgy] I have about two minutes. Use them.",
        "[corp calm] Good evening. Take your time.",
    }

    M.MOVES.greet_again = {
        "[street] You again. What's good?",
        "[street] Look who it is.",
        "[street calm] Hey. Figured I'd see you round.",
        "[plain] Oh, hi again.",
        "[plain] We keep bumping into each other.",
        "[plain edgy] Oh. You again. Hi.",
        "[tech] Hello again. Still curious?",
        "[tech edgy] You're back. I'm still thinking. Different thought.",
        "[corp] Hello again. Nice to see a familiar face.",
        "[corp edgy] Back again. I hope it's quick this time.",
    }

    M.MOVES.greet_regular = {
        "[street] My favourite pest.",
        "[street calm] You. Figures. Sit, if you want.",
        "[plain] Oh, hi. Of course it's you.",
        "[plain warm] My favourite visitor!",
        "[tech] Hello again. You're becoming a fixture.",
        "[tech cold] You again. I've stopped being surprised.",
        "[corp] Ah. The regular.",
        "[corp cold] You again. I'll have to start billing you.",
    }

    M.MOVES.close = {
        "[street] Watch your back out there.",
        "[street] Stay frosty.",
        "[street] Later.",
        "[street calm] Easy, yeah?",
        "[plain] Take care.",
        "[plain] See you.",
        "[plain] Look after yourself.",
        "[plain warm] Stay safe out there, okay?",
        "[tech] Right. Where was I.",
        "[tech] Okay. Back to it.",
        "[tech edgy] Right, I need to get back to this before I lose it.",
        "[corp] Do take care.",
        "[corp] Until next time.",
        "[corp edgy] Now if you'll excuse me.",
    }

    M.MOVES.act_eat = {
        "[street] Eating. Want some? Don't answer, you can't have any.",
        "[street] First food since yesterday. Don't judge.",
        "[street] Grabbing a bite at {place}. Cheapest in {district}.",
        "[street] Noodles. The only reliable thing in this city.",
        "[street calm] Eating slow. Nowhere to be for ten minutes. Bliss.",
        "[street edgy] Can't even eat in peace round here.",
        "[plain] Just having a quick bite.",
        "[plain] Lunch. Or dinner. Some meal.",
        "[plain] This is my third coffee and my first food. Don't tell my mum.",
        "[plain] Stopped for something to eat before the next thing.",
        "[plain calm] Nice to just sit and eat for once.",
        "[plain cold] I'd like to finish this while it's hot.",
        "[tech] Eating. Thinking. Mostly thinking.",
        "[tech] Quick bite, then back to the data.",
        "[tech] I eat here because it's fast. That's the whole review.",
        "[tech calm] Food first. Problems after.",
        "[corp] Grabbing something light. Long evening ahead.",
        "[corp] A working dinner, of sorts. Just without the work. Or the dinner.",
        "[corp warm] Do join me, if you're hungry. I'm paying. Company card.",
        "[corp edgy] I have eleven minutes to eat this.",
    }

    M.MOVES.act_loiter = {
        "[street] Just posted up for a while.",
        "[street] Watching traffic. You learn a lot watching traffic.",
        "[street] Hanging round {place}. Nothing better on.",
        "[street calm] Nice to stand still for once.",
        "[plain] Just taking a break.",
        "[plain] Needed to get out for a bit.",
        "[plain] Killing a bit of time before the next thing.",
        "[plain] Just stretching my legs.",
        "[plain warm] Nice to see people out and about.",
        "[tech] Taking a minute. My brain overheats faster than the car.",
        "[tech] Just thinking something through.",
        "[tech calm] Letting a problem sit. Sometimes it solves itself.",
        "[tech edgy] I can't think in the garage. Too many people asking me things.",
        "[corp] Stepping out for a moment.",
        "[corp] Just a moment's air between calls.",
        "[corp edgy] My phone won't stop. I'm pretending it's on silent.",
    }

    M.MOVES.act_fuel = {
        "[street] Fuel stop. Gotta keep her fed.",
        "[street] Tank was on fumes. So was I.",
        "[street] Filling up before somebody jacks the price again.",
        "[street] Quick splash of gas. Then gone.",
        "[street calm] Nice slow fill. Only quiet minute I get.",
        "[street edgy] Pump's slower than my grandma. And she's dead.",
        "[street warm] Filling up. You good for gas? This place does it cheap.",
        "[plain] Getting some fuel.",
        "[plain] Tank was nearly empty.",
        "[plain] Filling up while it's quiet.",
        "[plain] Just grabbing fuel on the way.",
        "[plain warm] Fuel stop. Always feels like a little holiday, weirdly.",
        "[plain cold] Pump's taking its time.",
        "[tech] Fuelling. Every litre's weight, remember.",
        "[tech] Quick top up. I like knowing exactly what's in there.",
        "[tech] Filling up. Checking the octane too. Trust no pump.",
        "[tech edgy] This pump reads wrong. I'd bet money on it.",
        "[corp] Refuelling. Glamorous, I know.",
        "[corp] Just filling up. The chauffeur's off tonight.",
        "[corp warm] Filling up. I rather like these places, actually. Honest work.",
    }

    M.MOVES.act_hang = {
        "[street] Just checking out the rides.",
        "[street] Good crowd tonight.",
        "[street] Meet's decent. Seen worse, seen better.",
        "[plain] Just here for the cars.",
        "[plain] Came to watch.",
        "[plain warm] Good atmosphere tonight, isn't it?",
        "[tech] Watching what people are running. Research.",
        "[tech] You learn more at a meet than in a wind tunnel.",
        "[corp] Keeping an eye on the talent.",
        "[corp] Seeing what the street's up to.",
    }

    M.MOVES.act_errand = {
        "[street] Picking up some bits.",
        "[street] Out for supplies.",
        "[plain] Running a couple of errands.",
        "[plain] Popping into {place} for something.",
        "[tech] Hunting for a part. Or a replacement for a part.",
        "[tech] Getting supplies. Never enough supplies.",
        "[corp] A quick errand.",
        "[corp] Collecting something. Personally, for once.",
    }

    M.MOVES.act_hustle = {
        "[street] Just seeing a man about a thing.",
        "[street] Side job. Everybody's got one.",
        "[plain] Bit of extra work.",
        "[plain] Picking up whatever pays.",
        "[tech] Doing a favour for somebody. A paid favour.",
        "[corp] A small side matter. Nothing interesting.",
    }

    M.MOVES.act_work = {
        "[street] On the clock.",
        "[street] Garage time.",
        "[street] Work never stops round here.",
        "[plain] Busy, busy.",
        "[plain] On shift.",
        "[plain] Working, but I can talk.",
        "[tech] Deep in it today.",
        "[tech] Running checks.",
        "[tech] Busy with the car. Always busy with the car.",
        "[corp] Working, I'm afraid.",
        "[corp] Busy day. They're all busy days.",
    }

    M.MOVES.weather_clear = {
        "[street] Clear night. You can almost see a star. Almost.",
        "[street] Nice out. Makes a change.",
        "[plain] Nice day for it.",
        "[plain] Weather's being kind, for once.",
        "[plain calm] Beautiful out, really.",
        "[tech] Good grip day. Warm and dry.",
        "[tech] Dry conditions. The car should like that.",
        "[corp] Rather nice out.",
        "[corp] Good weather is good for turnout.",
    }

    M.MOVES.weather_grey = {
        "[street] Grey sky, grey city.",
        "[street] Overcast. Looks like rain but won't commit.",
        "[plain] Grey again.",
        "[plain] Can't tell if it's going to rain or not.",
        "[tech] Cloud cover's keeping the temperature down.",
        "[tech] Neutral conditions. Nothing to blame.",
        "[corp] Grey. How fitting.",
    }

    M.MOVES.weather_rain = {
        "[street] Soaked through. Don't even care any more.",
        "[street] This rain won't quit.",
        "[street warm] You're wet through, come stand under here.",
        "[plain] It's pouring.",
        "[plain] Rain's not letting up, is it.",
        "[plain calm] I don't mind the rain, really. Washes things.",
        "[tech] Standing water everywhere. Aquaplaning weather.",
        "[tech] Wet running. Tyres are going to be the whole story.",
        "[corp] Dreadful weather.",
        "[corp] One of those evenings, weather-wise.",
    }

    M.MOVES.weather_fog = {
        "[street] Fog's thick tonight.",
        "[plain] Can barely see across the street.",
        "[plain calm] I quite like the fog, actually. City goes quiet.",
        "[tech] Humidity's through the roof. Engines hate it.",
        "[corp] One can't see a thing.",
    }

    M.MOVES.weather_smog = {
        "[street] Smog's bad. Tastes like pennies.",
        "[plain] Awful air today.",
        "[plain edgy] Can't breathe in this.",
        "[tech] Air's thick. Engines lose power in this muck.",
        "[corp] The air today is simply awful.",
    }

    M.MOVES.weather_sand = {
        "[street] Sand everywhere. Everywhere.",
        "[plain] Dusty one today.",
        "[tech] Dust in the air. Filters will be black by tonight.",
        "[corp] The dust gets into everything. Including my mood.",
    }

    M.MOVES.time_late = {
        "[street] Way past bedtime.",
        "[street] Late. City's all ours now.",
        "[plain] It's so late.",
        "[plain calm] Quiet at this hour. I like it.",
        "[tech] Late one. Best thinking time.",
    }
    M.MOVES.time_dawn = {
        "[street] Almost morning. Didn't even notice.",
        "[plain] Up early.",
        "[tech] Early start. Quiet garage.",
    }
    M.MOVES.time_morning = {
        "[street] Too early for this.",
        "[plain] Morning. Just about.",
        "[tech] Mornings are for coffee and bad news.",
    }
    M.MOVES.time_midday = {
        "[street] Middle of the day. Hot as hell.",
        "[plain] Middle of the day already.",
        "[tech] Hottest part of the day. Track'll be greasy.",
    }
    M.MOVES.time_afternoon = {
        "[street] Afternoon drag.",
        "[plain] Long afternoon.",
        "[corp] Afternoons are for meetings, usually.",
    }
    M.MOVES.time_evening = {
        "[street] Getting dark. Good.",
        "[plain] Evening already.",
        "[tech] Cooling off. Good for grip.",
    }
    M.MOVES.time_night = {
        "[street] Dark out. My kind of hours.",
        "[plain] Late night.",
        "[tech] Night work. Nobody bothers you.",
    }

    M.MOVES.district_lockdown = {
        "[street] Can't go two blocks in {district} without a checkpoint.",
        "[plain] It's very, uh, supervised round here these days.",
        "[tech] Security's so tight nobody can test anything on the street.",
    }
    M.MOVES.district_open_war = {
        "[street] {district}'s a warzone right now.",
        "[plain] I don't feel safe in {district} right now.",
        "[tech] Lost a delivery to a shootout last week. The parts, not the driver.",
    }
    M.MOVES.district_gang_rule = {
        "[street] You know who runs {district}. Everybody knows.",
        "[plain] You don't say no to certain people round here.",
        "[corp] One must be pragmatic about local powers.",
    }
    M.MOVES.district_oligarchy = {
        "[street] Same crew owns every block round here.",
        "[plain] Hard to find anything round here that isn't owned by the same people.",
    }
    M.MOVES.district_scene_town = {
        "[street] Racing's all anybody talks about round here right now.",
        "[plain] You can't move in {district} for car people at the moment.",
        "[plain dry] {district} has gone car mad. I've given up resisting.",
    }
    M.MOVES.district_fracture = {
        "[street] Nobody helps nobody round here any more.",
        "[plain] Everyone's on edge in {district}.",
    }
    M.MOVES.district_neglect = {
        "[street] {district}'s forgotten. By everybody.",
        "[plain] Nobody's fixed anything round here in months.",
    }
    M.MOVES.district_balance = {
        "[street] Quiet round here. Too quiet.",
        "[plain] Nothing much going on round here, for once.",
        "[plain warm] It's nice, honestly. Calm, for {district}.",
    }

    M.MOVES.topic_next = {
        "[street] Racing {route} later. {when}.",
        "[street] We're on at {when}. {route}.",
        "[street calm] {route} at {when}. We'll see how it goes.",
        "[plain] Got a race at {when}. {route}.",
        "[plain] {route} tonight. {when}.",
        "[plain warm] You should come watch at {when}! {route}.",
        "[tech] {route}, {when}. I'm still not happy with the rear.",
        "[tech] Next is {route} at {when}. Low grip, I think.",
        "[tech calm] {route} at {when}. We're as ready as we'll be.",
        "[corp] {route}, at {when}. Our preparation is, I'm told, thorough.",
        "[corp] The next event is {route}. {when}.",
    }
    M.MOVES.topic_last_win = {
        "[street] Took the win on {lastRoute}. Still riding that.",
        "[plain] Last time out we won. {lastRoute}.",
        "[tech] {lastRoute} was a win. The setup was right for once.",
        "[corp] We won on {lastRoute}. Good for morale, better for sponsors.",
    }
    M.MOVES.topic_last_podium = {
        "[street] {lastPlace} last time. {lastRoute}. Not bad.",
        "[plain] Got {lastPlace} on {lastRoute}.",
        "[tech] {lastPlace}. The gap to the win was mostly tyres.",
        "[corp] {lastPlace} on {lastRoute}. Solid.",
    }
    M.MOVES.topic_last_finish = {
        "[street] {lastPlace} on {lastRoute}. Whatever.",
        "[plain] {lastPlace} last time. We'll get there.",
        "[tech] {lastPlace}. Not the car. Probably not the car.",
        "[corp] {lastPlace}. A learning experience.",
    }
    M.MOVES.topic_last_dnf = {
        "[street] Didn't make the end of {lastRoute}. Car's still sulking.",
        "[plain] We had a bad one on {lastRoute}.",
        "[tech] Retirement on {lastRoute}. Found the cause. Too late.",
        "[corp] Our last outing ended early. We've moved on.",
    }
    M.MOVES.topic_tag = {
        "[street] {tagLabel}. That's the word on us.",
        "[tech] {tagLabel}, apparently. I'd have said 'well engineered'.",
    }
    M.MOVES.topic_series = {
        "[street] The {series} is where it's at.",
        "[plain] The {series} keeps us busy.",
        "[tech] Competition in the {series} is brutal this year.",
        "[corp] The {series} is very competitive commercially.",
    }
    M.MOVES.topic_role_driver = {
        "[street] Just want to drive. Everything else is noise.",
        "[street edgy] One more mistake and they'll find somebody else. I know it.",
        "[plain] Driving's the easy bit. Everything else is hard.",
        "[plain cold] I drive. That's all anyone needs to know.",
        "[tech] I like understanding why the car does what it does. Makes me quicker.",
        "[corp] My job is to deliver for the team and the partners.",
    }
    M.MOVES.topic_role_engineer = {
        "[street] Every night I tear it down, every morning it's still broken.",
        "[plain] There's always something to fix.",
        "[plain calm] Slow and steady. Car gets a bit better every week.",
        "[tech calm] We'll get there. It's just sums.",
        "[tech edgy] Nobody listens to the data until the car's in a wall.",
    }
    M.MOVES.topic_role_strategist = {
        "[plain] I try to see the race before it happens.",
        "[plain calm] Most races are won by not doing anything stupid.",
        "[tech edgy] If the driver followed the plan once, just once.",
        "[tech calm] Patience wins more races than speed. Don't tell the drivers.",
    }
    M.MOVES.topic_role_manager = {
        "[plain calm] It's a good group. Mostly I just stay out of the way.",
        "[street] Somebody's got to keep the lights on.",
        "[tech] I manage people like a car. Find the weak part, fix it.",
    }
    M.MOVES.topic_role_owner = {
        "[plain calm] It's a slow build. I'm patient.",
        "[street edgy] Every month I say it's the last month. Every month I pay.",
        "[tech] I own it but I still turn wrenches when nobody's looking.",
    }

    return M
end)
