-- ncm-core data: life.voice_bank_scene -- the moment: what they are doing, the weather, the hour, the district's
-- climate reading. Format and tags: see life/voice_bank.lua. {place} is where they are standing ("Fuel Station
-- 19", "a Glen food stall"); {district} their district.
local Core = NcmCore

Core.define("life.voice_bank_scene", function()
    local M = {}
    M.ORDER = {
        "act_eat", "act_loiter", "act_fuel", "act_hang", "act_errand", "act_hustle", "act_work",
        "weather_clear", "weather_grey", "weather_rain", "weather_fog", "weather_smog", "weather_sand",
        "time_late", "time_dawn", "time_morning", "time_midday", "time_afternoon", "time_evening", "time_night",
        "district_lockdown", "district_open_war", "district_gang_rule", "district_oligarchy", "district_scene_town",
        "district_fracture", "district_neglect", "district_balance",
        "district_open_war_crisis", "district_gang_rule_crisis", "district_fracture_crisis", "district_neglect_crisis",
        "district_balance_crisis", "district_scene_town_crisis",
    }
    M.MOVES = {}

    -- ------------------------------------------------------------------------------------------------ activities
    M.MOVES.act_eat = {
        "[street] Grabbing some scop before it gets cold. Or colder.",
        "[street] Don't look at what's in this. I'm not looking at it either.",
        "[street warm] You hungry? This place is gonk-looking but the noodles are {good}.",
        "[street cold] I'm eating. That's what this is.",
        "[street edgy] If you're here to watch me eat, pull up a stool and pay for it.",
        "[street joker] Protein bar number four today. My body is sixty percent vending machine.",
        "[street dry] Nothing says fine dining like {place}.",
        "[plain] Just grabbing something to eat.",
        "[plain warm] You should try the dumplings here. Honestly, best thing in {district}.",
        "[plain cold] I've got about ten minutes to eat this, so.",
        "[plain edgy] First food I've had all day and you want to chat.",
        "[plain calm] Nothing like a quiet meal. Well. Quiet-ish.",
        "[plain humble] Sorry, I'm a mess, I eat like a racoon.",
        "[plain joker] My doctor says I should eat more greens. This is green. Sort of.",
        "[plain dry] I'd recommend it, but I have standards. Low ones, but standards.",
        "[plain old] Used to be a proper diner here. Now it's this. Still eat here.",
        "[tech] Refuelling the driver. Well, the {role}.",
        "[tech] Calories in. Brain back on in five minutes.",
        "[tech dry] It's roughly food. I've tested it.",
        "[tech warm] Want half? I always order too much when I'm thinking.",
        "[corp] Forgive me, it's the first chance I've had to eat today.",
        "[corp dry] Not quite the restaurant I'd have chosen. Needs must.",
        "[corp cold] I'd rather not talk business over this.",
        "[driver] Carbs before the car. Old habit.",
        "[driver cocky] Eating light. Every gram counts, even mine.",
    }

    M.MOVES.act_loiter = {
        "[street] Just hanging. Watching the world go sideways.",
        "[street] Killing time. Time's winning.",
        "[street warm] Nowhere to be for once. Feels weird, honestly.",
        "[street cold] I'm not doing anything and I'd like to keep it that way.",
        "[street edgy] Waiting on somebody. Somebody late.",
        "[street joker] I'm people-watching. You're people. Congrats.",
        "[street dry] This is what we call a break around here. Standing.",
        "[street young] Everyone hangs round {place}. It's like, the spot.",
        "[plain] Just taking five.",
        "[plain warm] Honestly, sometimes you've got to stand still and let the city do its thing.",
        "[plain cold] Needed some air. Still need it.",
        "[plain edgy] If I stay home I'll just stare at the walls, so. Here I am, staring at these ones.",
        "[plain calm] Nice spot, this. Well. Nice enough.",
        "[plain humble] I come here to think. Doesn't always work.",
        "[plain joker] I'm very busy doing nothing. It's harder than it looks.",
        "[plain dry] My therapist says I should get out more. This is out.",
        "[plain old] I've stood on this corner for twenty years. Corner's held up better than me.",
        "[tech] Thinking. Easier away from the car.",
        "[tech] My best ideas happen when I'm doing nothing. My worst too.",
        "[tech dry] Standing about is underrated. Nobody asks you for data.",
        "[corp] Stepping away from the office. Don't tell anyone.",
        "[corp dry] Apparently this is what normal people do on a break.",
        "[corp warm] I like to see the streets. Reminds me who actually watches the races.",
        "[driver] Clearing my head before the next one.",
        "[manager] Hiding from my phone, if I'm honest.",
    }

    M.MOVES.act_fuel = {
        "[street] Filling up. Eddies straight into the tank.",
        "[street] Car drinks more than I do. And I drink.",
        "[street warm] Topping up. You need fuel too? {place} is the only place round here that doesn't water it down.",
        "[street cold] Paying for gas. Riveting, I know.",
        "[street edgy] Price at this pump is a crime. And I'd know.",
        "[street joker] Every time I fill up, a little piece of me dies. The wallet piece.",
        "[street dry] Fuel's up again. Must be a day ending in y.",
        "[plain] Just filling up.",
        "[plain warm] Quick fuel stop, then back to it.",
        "[plain cold] I'm getting fuel. That's all this is.",
        "[plain edgy] If this pump eats my card one more time.",
        "[plain calm] Nothing wrong with a slow fill. Gives you a minute.",
        "[plain joker] Filling up at {place}. Living the dream.",
        "[plain dry] You'd think by now cars would run on something cheaper. Like disappointment.",
        "[tech] Topping off. Want it right for the weight check.",
        "[tech] Fuel load matters more than people think. A few litres is a few tenths.",
        "[tech dry] Fuel. The only consumable nobody argues about.",
        "[corp] One does still have to buy fuel, apparently.",
        "[corp dry] I was told the company card works here. We'll see.",
        "[driver] Full tank, empty head. Best way to drive.",
        "[driver cocky] Fuelling up. Don't stand too close, I leave fast.",
        "[engineer] Checking what they're pumping. You'd be amazed what ends up in these tanks.",
    }

    M.MOVES.act_hang = {
        "[street] The meet's where it's at tonight.",
        "[street] You hear the engines? That's the whole reason to be here.",
        "[street warm] Look at all these rides. This is church, {addr}.",
        "[street cold] I come for the cars, not the company.",
        "[street edgy] Somebody's gonna start something tonight. Always does.",
        "[street joker] Half of these cars are held together with tape and the other half with hope.",
        "[street dry] Same cars, same people, same arguments. I love it here.",
        "[street young] Tonight's gonna be {good}. I can feel it.",
        "[street old] The meets were bigger back in the day. Louder too.",
        "[plain] Came down for the meet.",
        "[plain warm] I love it down here. Everyone's just, into it.",
        "[plain edgy] Too many people, too much noise. Perfect.",
        "[plain dry] I'm told this counts as a social life.",
        "[tech] Good place to see what everyone's running. Nobody hides anything at a meet.",
        "[tech] Look at the ride height on that one. That's a choice.",
        "[tech dry] Half these setups would make an engineer cry. I'm an engineer. I'm fine.",
        "[corp] Scouting. Everyone pretends they don't, at these.",
        "[corp dry] Somebody told me these are good for brand visibility.",
        "[driver] You get a feel for who's quick just by standing here.",
        "[driver cocky] Half of this lot talk big. I'll be watching which half.",
    }

    M.MOVES.act_errand = {
        "[street] Running errands. Glamorous, right?",
        "[street cold] Picking something up. Not your business what.",
        "[street joker] Shopping. For what, I'll know it when I see it.",
        "[plain] Just picking a few things up.",
        "[plain warm] Errands. The glamorous side of motorsport.",
        "[plain edgy] Three shops, no luck. This is the fourth.",
        "[plain dry] Everything I need is always in the last place I look.",
        "[plain humble] My list says three things. I've forgotten two.",
        "[tech] Picking up parts. Or something close to parts.",
        "[tech dry] They didn't have it. They never have it.",
        "[corp] Personal errand. Even I get those.",
        "[corp dry] My assistant's off today. Hence this.",
        "[engineer] Came for a torque wrench, leaving with three things I don't need.",
        "[driver] Somebody's got to pick up the new gloves. Apparently it's me.",
        "[old] In my day you could get everything in one shop. It sold bolts and noodles.",
    }

    M.MOVES.act_hustle = {
        "[street] Working an angle. Don't ask which.",
        "[street] Rent's due. You do what you do.",
        "[street cold] Business. The kind that doesn't have a receipt.",
        "[street edgy] If you're here to talk to the fixer, get in line behind me.",
        "[street joker] I'm a freelance opportunity consultant. It's a real job. Sort of.",
        "[street dry] Racing doesn't pay the bills. This barely does either.",
        "[street young] Gotta make eddies somehow, yeah?",
        "[plain] Picking up some extra work.",
        "[plain edgy] Team money's late again. So here I am.",
        "[plain humble] Bit embarrassing, but a side job's a side job.",
        "[plain dry] Motorsport. Glamour. Side gigs. In that order, backwards.",
        "[tech] Freelance diagnostics. Somebody always needs a car looked at.",
        "[tech dry] Consulting. Which is fixing someone else's mistakes for cash.",
        "[corp dry] Networking. That's what we call it at my level.",
        "[driver] Courier work between races. Good practice, honestly.",
    }

    M.MOVES.act_work = {
        "[street] On shift. The car's not gonna fix itself.",
        "[street warm] Busy, but go on, I can talk and wrench.",
        "[street cold] Working. Make it quick.",
        "[street edgy] Whatever it is, the car comes first.",
        "[street joker] Welcome to the office. Mind the oil, it's decorative.",
        "[plain] Busy day in the garage.",
        "[plain warm] Come in, come in. Don't touch the red things.",
        "[plain cold] We're working here.",
        "[plain edgy] Everything's broken and it's all due yesterday.",
        "[plain calm] Busy, but that's the job.",
        "[plain dry] Another glamorous day at the office.",
        "[tech] Just going through the data from last time out.",
        "[tech] Mid-setup. Don't breathe on anything.",
        "[tech dry] The car and I are having a disagreement. The car is winning.",
        "[corp] You've caught us at work. I'll allow it.",
        "[corp dry] Please don't tell anyone how chaotic it looks in here.",
        "[driver] Seat fitting. My back will never forgive this team.",
        "[engineer] Suspension's apart. Everything's apart, actually.",
        "[strategist] Running the numbers on the next one. The numbers are running from me.",
        "[manager] I'm here to make sure nobody kills anybody. Harder than it sounds.",
        "[owner] Checking where my money goes. Mostly into that car.",
    }

    -- ------------------------------------------------------------------------------------------------ weather
    M.MOVES.weather_clear = {
        "[street] Nice night for it. Or day. Whatever.",
        "[street warm] Clear sky. Don't get many of those.",
        "[street dry] Sun's out. Something's definitely about to go wrong.",
        "[plain] Lovely weather, at least.",
        "[plain warm] Can't complain about the weather today.",
        "[plain dry] Clear skies. Enjoy them, it won't last.",
        "[plain edgy] Too bright. Hurts my eyes.",
        "[tech] Dry and warm. Track'll have grip.",
        "[tech] Good conditions. No excuses for anyone.",
        "[tech dry] Perfect weather. Which means if we're slow, it's us.",
        "[corp] Pleasant, for a change.",
        "[corp dry] The one day the weather cooperates and I'm stuck outside a shop.",
        "[driver] Dry road. The kind of day you can actually push.",
        "[joker] Sun's out. Somebody check the city's not on fire.",
        "[old] Weather was better when I was young. Everything was.",
    }

    M.MOVES.weather_grey = {
        "[street] Grey again. City looks better in the dark anyway.",
        "[street dry] Overcast. Very on brand.",
        "[plain] Bit gloomy today.",
        "[plain warm] Grey out, but it's not raining. I'll take it.",
        "[plain dry] Clouds. Night City's natural state.",
        "[plain edgy] Sky can't decide whether to rain or not. Neither can I.",
        "[tech] Cloud keeps the track temperature down. Could go either way.",
        "[tech] Overcast's fine. Tyres'll take longer to switch on, that's all.",
        "[corp] Rather dreary, isn't it.",
        "[corp dry] The weather matches the quarterly figures.",
        "[driver] Grey days are sneaky. Looks dry, grips like it's damp.",
        "[joker] Sky's the colour of my bank balance.",
    }

    M.MOVES.weather_rain = {
        "[street] Rain again. Streets are gonna be glass tonight.",
        "[street warm] Get under here, you're soaked.",
        "[street edgy] Rain makes everybody drive like a gonk.",
        "[street dry] Rain in Night City. It's like normal rain, but it stings.",
        "[street joker] At least the rain washes the blood off the pavement. Kidding. Mostly.",
        "[plain] Wet one today.",
        "[plain warm] Horrible out, isn't it. Stay dry.",
        "[plain cold] Rain. Great.",
        "[plain edgy] I hate the rain. Everything smells like wet circuits.",
        "[plain dry] My umbrella has been in the car for three years. I have never once remembered it.",
        "[tech] Wet track changes everything. Setup, tyres, the lot.",
        "[tech] Rain's a lottery for strategy. I hate lotteries.",
        "[tech dry] Standing water in turn one, I'd bet on it.",
        "[corp] Frightful weather.",
        "[corp dry] Wonderful. My shoes were a considerable investment.",
        "[driver] Rain's the great equaliser. Loves a brave driver, hates a stupid one.",
        "[driver cocky] Let it rain. Rain's where you find out who's actually good.",
        "[driver humble] I'm not great in the wet. Don't tell anyone.",
    }

    M.MOVES.weather_fog = {
        "[street] Can't see ten metres. City's hiding something tonight.",
        "[street dry] Fog. Perfect weather for bad decisions.",
        "[plain] Foggy one.",
        "[plain edgy] I hate the fog. Anything could be out there.",
        "[plain warm] Watch yourself driving in this, visibility's awful.",
        "[tech] Fog's a nightmare for spotters. Nobody sees anything till it's too late.",
        "[tech dry] Visibility near zero. Much like our budget.",
        "[corp] Rather atmospheric, if you like that sort of thing.",
        "[driver] Racing in fog is ninety percent memory.",
        "[joker] It's like the city's vaping.",
    }

    M.MOVES.weather_smog = {
        "[street] Air's filthy today. Breathe shallow.",
        "[street edgy] This smog's gonna kill somebody. Probably me.",
        "[street dry] Smog day. The city exhaling.",
        "[plain] Air's bad today.",
        "[plain warm] Keep your mask on if you've got one, the air's awful.",
        "[plain cold] I can taste the air. That's never good.",
        "[tech] Pollution clogs the intakes. We'll be cleaning filters all week.",
        "[tech dry] Air quality today is a strong argument for staying indoors.",
        "[corp] Somebody's factory is having a productive day.",
        "[corp dry] I'm told it's fine to breathe. I'm told a lot of things.",
        "[old] Air was never this bad. Well. It was. We just didn't have the numbers.",
    }

    M.MOVES.weather_sand = {
        "[street] Dust storm rolling in off the Badlands. Everything's gonna be gritty for a week.",
        "[street dry] Sand in my teeth. Sand in my soul.",
        "[plain] Dust everywhere today.",
        "[plain edgy] This dust gets in everything. Everything.",
        "[tech] Sand's murder on filters and bearings. We'll pay for today later.",
        "[tech dry] The Badlands delivering itself by air again.",
        "[corp] One grows tired of the sand.",
        "[driver] Can't see a thing in this. Pure feel.",
        "[joker] Free exfoliation. The city gives back.",
    }

    -- ------------------------------------------------------------------------------------------------ the hour
    M.MOVES.time_late = {
        "[street] Late one. City's more honest at this hour.",
        "[street dry] Nothing good happens after two. Here I am.",
        "[street young] Night's still young. I'm still young. Let's go.",
        "[plain] Bit late for this, isn't it.",
        "[plain warm] Can't sleep either?",
        "[plain edgy] I should be in bed. I'm never in bed.",
        "[plain dry] Ah, the witching hour. The rent is still due.",
        "[tech] Best time to think. Nobody asks questions at this hour.",
        "[corp] I don't usually keep these hours.",
        "[corp dry] Apparently the city doesn't sleep. Neither, it transpires, do I.",
        "[old] At my age you don't sleep, you just wait for morning.",
        "[driver] Night racing does your body clock no favours.",
    }

    M.MOVES.time_dawn = {
        "[street] Sun's coming up. Or trying to.",
        "[street dry] Dawn. Everybody's either getting up or going down.",
        "[plain] Early start.",
        "[plain warm] Nice this early, isn't it. Almost peaceful.",
        "[plain edgy] Why is everyone awake. Why am I awake.",
        "[tech] Early. Good. The garage is quiet.",
        "[corp] One gets more done before the city wakes.",
        "[old] Always been an early riser. The city's always been a late one.",
        "[joker] Dawn. The worst part of the night.",
    }

    M.MOVES.time_morning = {
        "[street] Morning. Allegedly.",
        "[street warm] Morning! You eaten? You look like you haven't eaten.",
        "[plain] Morning.",
        "[plain warm] Good morning! Well. Morning.",
        "[plain edgy] Not a morning person. Don't ask me anything hard.",
        "[plain dry] Mornings. A mistake the calendar keeps making.",
        "[tech] Morning. Coffee's on, brain isn't.",
        "[corp] Good morning.",
        "[corp dry] Mornings are for meetings. This is not a meeting.",
        "[young] Morning! Or, like, whatever.",
    }

    M.MOVES.time_midday = {
        "[street] Middle of the day and I'm already done with it.",
        "[plain] Lunchtime already.",
        "[plain warm] Halfway through the day. Nearly there.",
        "[plain dry] Noon. Half the day wasted, half to go.",
        "[tech] Midday. Track's at its hottest about now.",
        "[corp] I have a lunch at one. I'll be late. I'm always late.",
        "[edgy] Middle of the day, nothing's going right, standard.",
    }

    M.MOVES.time_afternoon = {
        "[street] Slow afternoon.",
        "[plain] Afternoon.",
        "[plain warm] Good afternoon! Lovely time of day, this.",
        "[plain dry] Afternoon. The part of the day that lasts forever.",
        "[tech] Afternoon's when the setup work gets done. Mornings are for coffee.",
        "[corp] Good afternoon.",
        "[old] Afternoons used to mean a nap. Now they mean this.",
        "[young] Afternoon's dead. Wait till tonight.",
    }

    M.MOVES.time_evening = {
        "[street] Evening. The city's starting to wake up.",
        "[street warm] Good evening! This is when {district} gets fun.",
        "[plain] Evening.",
        "[plain warm] Nice evening for it.",
        "[plain dry] Evening. The sun's clocking off. Wish I could.",
        "[tech] Evening. Temperatures dropping, grip coming up.",
        "[corp] Good evening.",
        "[corp dry] Evening already. The day escaped me.",
        "[driver] Evening sessions are the best. Cool air, fast cars.",
    }

    M.MOVES.time_night = {
        "[street] Night's when everything happens round here.",
        "[street young] This is the good part of the day.",
        "[street dry] Night in {district}. Keep one eye open.",
        "[plain] Getting late.",
        "[plain warm] Lovely night, really. For here.",
        "[plain edgy] I don't love being out this late.",
        "[tech] Night running. Different car in the dark, honestly.",
        "[corp] I should be at home. Evidently I'm not.",
        "[driver] Night racing. Nothing like it.",
        "[joker] Night time. When the cars come out and the sense goes in.",
    }

    -- ------------------------------------------------------------------------------------------------ the district
    -- Keyed by `life.climate` regime. Lines react to how {district} READS right now; nobody names the mechanism.
    M.MOVES.district_lockdown = {
        "[street] Corpo security on every corner in {district}. Can't even breathe without a permit.",
        "[street edgy] Got stopped twice on the way here. Twice.",
        "[street dry] {district}'s so locked down you need a pass to have a thought.",
        "[plain] Lot of security about lately.",
        "[plain warm] It's safe, at least. Feels a bit watched, but safe.",
        "[plain edgy] You notice the drones? I notice the drones.",
        "[tech] No street meets with this much security. It's killing the scene.",
        "[corp] Order is good for business. Mostly.",
        "[corp dry] One does appreciate the security. One would appreciate fewer checkpoints.",
        "[driver] Can't find a road to run on round here without a cop on it.",
    }
    M.MOVES.district_open_war = {
        "[street] Streets are hot. Keep your head down in {district}.",
        "[street edgy] Somebody got capped two blocks from here last night. Nobody even looked up.",
        "[street dry] War's on again in {district}. It's always on.",
        "[plain] It's not safe round here right now.",
        "[plain warm] Be careful going home, okay? It's bad out there.",
        "[plain edgy] I heard gunshots again last night.",
        "[tech] Half our parts suppliers won't deliver into {district} right now.",
        "[corp] We've paused some activities in the area. For obvious reasons.",
        "[driver] Can't run a street race when the street's a warzone.",
    }
    M.MOVES.district_gang_rule = {
        "[street] Everybody pays somebody in {district}. That's how it works.",
        "[street edgy] Don't wear the wrong colours round here.",
        "[street dry] The gangs run {district}. The cops just visit.",
        "[plain] Best not to ask who's in charge round here.",
        "[plain edgy] You pay the right people or you don't open. Simple.",
        "[tech] Garage pays protection. It's in the budget next to tyres.",
        "[corp] Local arrangements are a cost of doing business in {district}.",
        "[driver] Some roads you don't race without asking first.",
    }
    M.MOVES.district_oligarchy = {
        "[street] One outfit owns {district}. Everybody else just rents.",
        "[plain] Everything round here belongs to the same people, have you noticed?",
        "[plain dry] {district}: one owner, many tenants, zero choices.",
        "[tech] Same supplier for everything round here. Take it or leave it.",
        "[corp] Market consolidation. It's very efficient, if you're the consolidator.",
        "[driver] You race here on their terms or not at all.",
    }
    M.MOVES.district_scene_town = {
        "[street] {district}'s buzzing. Racing scene's never been this {good}.",
        "[street warm] You feel it? Whole district's about the cars right now.",
        "[street young] Every kid in {district} wants to be a racer this month.",
        "[plain] Everyone round here's mad about racing right now.",
        "[plain warm] Honestly, {district}'s the best it's been in years.",
        "[tech] Scene's so busy you can't get a garage slot. Good problem to have.",
        "[corp] The local enthusiasm is very good for visibility.",
        "[driver] Meets every night. Best time to be racing round here.",
        "[driver cocky] {district}'s racing crazy. Good. More people to beat.",
    }
    M.MOVES.district_fracture = {
        "[street] Nobody trusts nobody in {district} right now.",
        "[plain] It's every person for themselves round here lately.",
        "[plain warm] Used to know my neighbours. Now I just know their locks.",
        "[tech] Can't borrow a tool round here any more. Everyone hoards.",
        "[corp] Community sentiment is, let's say, fragmented.",
    }
    M.MOVES.district_neglect = {
        "[street] Nobody's watching {district}. Not cops, not corps, nobody.",
        "[street dry] If you broke down here you'd rust before a tow truck came.",
        "[plain] Place is falling apart. Nobody cares.",
        "[plain edgy] Streetlights have been out for a month. A month.",
        "[tech] Road surface round here is a joke. Destroys suspension.",
        "[corp] The area is, shall we say, underinvested.",
    }
    M.MOVES.district_balance = {
        "[street] {district}'s quiet, for now. Don't trust it.",
        "[plain] Things are calm round here at the moment.",
        "[plain dry] Nothing much happening in {district}. Suspicious.",
        "[tech] Quiet week. Good for getting work done.",
        "[corp] Stable. We like stable.",
    }
    M.MOVES.district_open_war_crisis = {
        "[street] {district}'s burning, {addr}. People are leaving.",
        "[plain] Half the shops round here are shuttered. People are scared.",
        "[plain warm] Honestly, if you don't have to be in {district} right now, don't be.",
        "[tech] Lost two suppliers this week. Just gone.",
        "[corp] We are reviewing our presence in {district}.",
    }
    M.MOVES.district_gang_rule_crisis = {
        "[street] Protection money doubled and nobody's got it. Something's gonna give.",
        "[plain] Everyone round here's broke and scared. Bad mix.",
        "[tech] Garage down the road closed. Couldn't pay what they were asking.",
    }
    M.MOVES.district_fracture_crisis = {
        "[street] Whole district's coming apart. Nobody's got anybody's back.",
        "[plain] It's bad round here right now. Really bad.",
        "[corp] The situation in {district} is not something I'd put in a brochure.",
    }
    M.MOVES.district_neglect_crisis = {
        "[street] {district}'s dying and nobody's even here to watch.",
        "[plain] No money, no work, no nothing round here any more.",
    }
    M.MOVES.district_balance_crisis = {
        "[street] Looks calm, but everybody's broke. Calm won't last.",
        "[plain] Money's tight for everyone round here right now.",
    }
    M.MOVES.district_scene_town_crisis = {
        "[street] Scene's big but everyone's skint. Racing on fumes.",
        "[plain] Everyone wants to race, nobody can afford to.",
    }

    return M
end)
