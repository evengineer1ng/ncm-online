-- ncm-core data: life.voice_bank_topics -- what a Paddock person talks ABOUT: their next race, their last result,
-- what people call them, their own work, their series. Format and tags: see life/voice_bank.lua.
-- Truth rule: {route} {when} {series} {lastRoute} {lastPlace} {lastDriver} {tagLabel} {tagSubject} are public
-- Paddock facts; a line whose slot has no fact is never said. "The board" is Billie's word, not everyone's.
local Core = NcmCore

Core.define("life.voice_bank_topics", function()
    local M = {}
    M.ORDER = {
        "topic_next", "topic_last_win", "topic_last_podium", "topic_last_finish", "topic_last_dnf", "topic_tag",
        "topic_series", "topic_role_driver", "topic_role_engineer", "topic_role_strategist", "topic_role_manager",
        "topic_role_owner",
    }
    M.MOVES = {}

    M.MOVES.topic_next = {
        "[street] We run {route} at {when}. Come watch us eat everybody's lunch.",
        "[street warm] {route}, {when}. You should come, it's gonna be {good}.",
        "[street cold] {when}, {route}. Don't bother wishing us luck.",
        "[street edgy] {route} at {when} and the car's still in pieces. Love that for me.",
        "[street cocky] {route}, {when}. Already know how it ends.",
        "[street joker] {when} we run {route}. If we win, drinks. If we lose, also drinks.",
        "[street dry] {route}. {when}. Same as it ever was.",
        "[plain] We're racing {route} at {when}.",
        "[plain warm] Next one's {route} at {when}. Fingers crossed!",
        "[plain cold] {route}, {when}. That's all there is to say.",
        "[plain edgy] {when}. {route}. Nobody's ready. Nobody's ever ready.",
        "[plain calm] {route} at {when}. Plenty of time.",
        "[plain humble] We've got {route} at {when}. Hoping we just get a clean one.",
        "[plain cocky] {route} at {when}. Tell your friends.",
        "[plain dry] {when}, {route}. My blood pressure's already booked it.",
        "[tech] {route} at {when}. I've got a setup in mind. Half a setup.",
        "[tech] {when}, {route}. Short run to turn one, so qualifying matters. Well, grid position does.",
        "[tech dry] {route}, {when}. The simulation says we'll be fine. The simulation has never been to {route}.",
        "[tech cocky] {route} at {when}. We've found something. Can't say what.",
        "[corp] We have {route} at {when}. We expect to be competitive.",
        "[corp warm] {route}, {when}. Do come and watch, it's good for everyone.",
        "[corp dry] {route} at {when}. My schedule has been rearranged around it, naturally.",
        "[driver] {route}'s at {when}. I've driven it a hundred times in my head.",
        "[driver edgy] {when} I'm on {route}. Can't sit still till then.",
        "[driver humble] {route} at {when}. Just want to bring it home in one piece this time.",
        "[engineer] Car has to be right for {route} by {when}. It isn't yet.",
        "[strategist] {route} at {when}. I'm watching the sky more than the car.",
        "[manager] {route}, {when}. My job is getting everyone there on time and sober.",
        "[owner] {route} at {when}. Every one of these costs me money, win or lose.",
    }

    M.MOVES.topic_last_win = {
        "[street] {lastDriver} took {lastRoute}. Whole garage is still buzzing.",
        "[street warm] Did you see {lastRoute}? {lastDriver} won it! We're still celebrating.",
        "[street cold] We won {lastRoute}. Moving on.",
        "[street cocky] {lastRoute}? Ours. Obviously.",
        "[street joker] Won {lastRoute}. Nobody knows how, least of all us.",
        "[plain] We won on {lastRoute}.",
        "[plain warm] {lastDriver} won {lastRoute}! I'm still not over it.",
        "[plain humble] We won {lastRoute}. Still feels like a mistake, honestly.",
        "[plain dry] We won {lastRoute}, so naturally everyone now expects it every time.",
        "[tech] Won {lastRoute}. The data says we were lucky. I say we were ready.",
        "[tech dry] {lastRoute}: a win. I'll allow myself one minute of happiness.",
        "[corp] A win on {lastRoute}. Very pleasing for all our partners.",
        "[corp cocky] {lastRoute}. First place. The strategy is working.",
        "[driver] Won {lastRoute}. Still feel it in my hands.",
        "[driver cocky] Won {lastRoute}. Didn't even need the last lap.",
        "[driver humble] I won {lastRoute}. Car did most of it, really.",
        "[engineer] Car was perfect on {lastRoute}. Won it. I'll never get it that right again.",
        "[owner] We won {lastRoute}. Worth every eddie. Nearly.",
    }

    M.MOVES.topic_last_podium = {
        "[street] {lastPlace} on {lastRoute}. Podium's a podium.",
        "[street warm] {lastDriver} got {lastPlace} on {lastRoute}! Not bad for us, right?",
        "[street edgy] {lastPlace}. So close I can still taste it.",
        "[plain] {lastPlace} on {lastRoute} last time.",
        "[plain warm] {lastPlace} on {lastRoute}! We'll take it.",
        "[plain cold] {lastPlace}. Not first.",
        "[plain humble] {lastPlace} on {lastRoute}. Honestly more than we hoped.",
        "[plain cocky] {lastPlace} on {lastRoute}. We're coming for the top step.",
        "[tech] {lastPlace} on {lastRoute}. Two tenths off the win, I think. I know where they are.",
        "[tech dry] {lastPlace}. Close enough to hurt, not close enough to celebrate.",
        "[corp] A podium on {lastRoute}. Encouraging.",
        "[driver] {lastPlace} on {lastRoute}. Should've been better.",
        "[driver calm] {lastPlace} on {lastRoute}. Good points. Good day.",
        "[owner] {lastPlace}. The sponsors like podiums. I like wins.",
    }

    M.MOVES.topic_last_finish = {
        "[street] {lastPlace} on {lastRoute}. Mid-pack. Invisible.",
        "[street edgy] {lastPlace}. Don't wanna talk about it.",
        "[street dry] {lastPlace} on {lastRoute}. Nobody writes songs about {lastPlace}.",
        "[plain] We came {lastPlace} on {lastRoute}.",
        "[plain warm] {lastPlace} on {lastRoute}. Not great, but everyone got home.",
        "[plain cold] {lastPlace}. We'll do better. We'd better.",
        "[plain humble] {lastPlace}. We're still learning.",
        "[tech] {lastPlace} on {lastRoute}. The car was {bad} in the middle sector. I know why now.",
        "[tech dry] {lastPlace}. The data is very clear about whose fault it was. It was mine.",
        "[corp] {lastPlace} on {lastRoute}. We are reviewing.",
        "[corp dry] {lastPlace}. Not a result I'll be putting in the newsletter.",
        "[driver] {lastPlace} on {lastRoute}. Traffic, mostly. And me, a bit.",
        "[driver cocky] {lastPlace}, but I passed half the field. Put that in the paper.",
        "[engineer] {lastPlace}. Car was {bad}. My fault.",
        "[manager] {lastPlace}. Points are points when you're counting them for the owner.",
    }

    M.MOVES.topic_last_dnf = {
        "[street] Didn't finish {lastRoute}. Car's in bits.",
        "[street edgy] {lastRoute}. Don't. Just don't.",
        "[street joker] {lastRoute} went great, right up until it didn't.",
        "[street dry] We DNF'd {lastRoute}. Car's recovering. I'm not.",
        "[plain] We didn't finish on {lastRoute}.",
        "[plain warm] Rough one on {lastRoute}, we didn't make the end. Everyone's okay though.",
        "[plain cold] We crashed out of {lastRoute}. That's it.",
        "[plain humble] We didn't make it home on {lastRoute}. Bit embarrassing.",
        "[tech] Retired on {lastRoute}. I've got a theory. I've got six theories.",
        "[tech dry] {lastRoute} ended early. The car had other plans.",
        "[corp] A disappointing retirement on {lastRoute}.",
        "[corp cold] We don't discuss {lastRoute}.",
        "[driver] Binned it on {lastRoute}. My fault. All mine.",
        "[driver cocky] {lastRoute}? Somebody else's mistake. I was just there.",
        "[engineer] Car came back from {lastRoute} in a bag. We're rebuilding.",
        "[owner] {lastRoute} cost me a car. That's the business.",
    }

    M.MOVES.topic_tag = {
        "[street] People call {tagSubject} {tagLabel}. They ain't wrong.",
        "[street cocky] {tagLabel}. That's what they call us now. I'll take it.",
        "[plain] You heard what they call {tagSubject}? {tagLabel}.",
        "[plain warm] {tagLabel}, that's us apparently! Somebody made it up and it stuck.",
        "[plain dry] {tagLabel}. Could be worse. Could be accurate.",
        "[tech] {tagLabel}. The data backs it, for once.",
        "[corp] The press have taken to calling {tagSubject} {tagLabel}. We don't discourage it.",
        "[driver] They call me {tagLabel} now. I'm trying to earn it.",
        "[driver humble] Apparently I'm {tagLabel}. Nobody asked me.",
    }

    M.MOVES.topic_series = {
        "[street] The {series}. Best racing in the city, don't let anyone tell you different.",
        "[street dry] The {series}. Glamour, prestige, and a hundred people who can't pay rent.",
        "[plain] We race in the {series}.",
        "[plain warm] The {series} is hard, but I love it.",
        "[plain edgy] The {series} is getting meaner every week.",
        "[tech] The {series} is so close now. Tenths decide everything.",
        "[corp] The {series} is where we need to be, commercially.",
        "[corp dry] The {series}. A fine product, badly run.",
        "[driver] Every week in the {series} somebody new shows up quick.",
        "[old] The {series} used to be a gentleman's game. Now it's a knife fight.",
    }

    M.MOVES.topic_role_driver = {
        "[street] All I think about is the next start. Lights go, everything goes quiet.",
        "[street edgy] My hands don't stop shaking till the lights go out. Then they're steady.",
        "[street cocky] Put me on any road in this city, I'll find the line.",
        "[street joker] My mom still thinks I'm an accountant.",
        "[plain] It's a lot of waiting around for a few minutes of driving.",
        "[plain warm] Honestly, I just love driving. Always have.",
        "[plain humble] Still figuring out how to be quick every week, not just sometimes.",
        "[plain dry] Racing driver. Very glamorous. I eat standing up.",
        "[tech] I talk to my engineer more than my family. The engineer listens better.",
        "[young] One day I'll be in the premier cars. You'll see.",
        "[old] Been driving longer than some of these kids have been alive. Still learning.",
        "[calm] The car tells you everything if you're quiet enough to listen.",
    }

    M.MOVES.topic_role_engineer = {
        "[street] Car's held together by zip ties and prayer. My zip ties, my prayer.",
        "[street joker] I fix it, they break it. Circle of life.",
        "[plain] Car's getting there. Slowly.",
        "[plain warm] I love this bit. Making it a little better every day.",
        "[plain edgy] Everyone wants it faster, nobody wants to pay for it.",
        "[tech] We've been fighting understeer for three races. I think it's the rear, not the front.",
        "[tech] Tyre temps were {bad} last time. Working on the pressures.",
        "[tech cocky] Give me a week and this car will be the fastest thing in the series.",
        "[tech humble] I'm not sure I've got the setup right. I'm never sure.",
        "[tech dry] Somebody put the diff in backwards once. It wasn't me. It was probably me.",
        "[corp] Our engineering programme is very well resourced. Allegedly.",
        "[old] You used to be able to fix a car with a wrench. Now you need a degree and a prayer.",
    }

    M.MOVES.topic_role_strategist = {
        "[plain] I spend all day guessing what everyone else will do.",
        "[plain edgy] Strategy's easy until it rains. Then it's chaos.",
        "[tech] Tyre life's the whole game this season. Whoever manages it, wins.",
        "[tech] I've got four plans for the next one. Three of them need it not to rain.",
        "[tech dry] My job is predicting the future. I'm usually wrong. So is everyone.",
        "[tech cocky] I call the pit window before anyone else sees it.",
        "[tech humble] Last race I called it wrong. Still thinking about it.",
        "[corp] Strategy is ninety percent information. We invest accordingly.",
        "[street] Strategy? Drive fast, turn left. Kidding. Mostly.",
    }

    M.MOVES.topic_role_manager = {
        "[plain] Half my job is keeping people from killing each other.",
        "[plain warm] It's a good team. Stressed, but good.",
        "[plain edgy] Everybody wants something from me. All at once. Always.",
        "[plain dry] I manage. That's the whole job title. I manage.",
        "[street] Keeping this crew together is harder than racing.",
        "[street edgy] One more argument in that garage and I'm quitting. Again.",
        "[tech] Budget, schedule, people. Pick two.",
        "[corp] My job is to deliver results on budget. Mostly the budget part.",
        "[corp cold] I don't discuss team matters with people outside the team.",
        "[corp cocky] This team runs like a machine because I built the machine.",
    }

    M.MOVES.topic_role_owner = {
        "[plain] Owning a team is mostly paying for things.",
        "[plain warm] I love this team. Even when it's bleeding me dry.",
        "[plain dry] Want to make a small fortune in motorsport? Start with a big one.",
        "[street] I built this team out of nothing. Nothing and a lot of loans.",
        "[street cocky] Everybody said a crew like ours couldn't last. Still here.",
        "[corp] Our partners have been very supportive this season.",
        "[corp cold] Ownership is a business decision, not a hobby.",
        "[corp dry] The accountants tell me racing is a marketing expense. The accountants are very optimistic.",
        "[corp cocky] In five years, every team in the {series} will want to be us.",
        "[old] I've owned teams that won and teams that folded. This one's somewhere in between.",
    }

    return M
end)
