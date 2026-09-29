#include "bridge.hpp"

#include "direct_input.hpp"
#include "feel.hpp"
#include "log.hpp"
#include "net_guard.hpp"
#include "state.hpp"

#include <nlohmann/json.hpp>

#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <tlhelp32.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <string>
#include <vector>

namespace ncm::rig {
namespace {
using json = nlohmann::json;
constexpr uint16_t kPortSpan = 4;
constexpr const char* kWebSocketGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

// The surface NCM loads from this port. It is also the ONLY way the F6 panel reaches the gamepad API (KB-210):
// the panel is a bundled page with no network at all (MASTER_TEST §AJ1), while this page is plain-HTTP loopback.
// `ncm:pad.req` comes in from Lua, the page fetches the API, and the reply goes back as `ncm:pad.part` strings
// of at most 3,000 characters, because the WebUI bridge silently drops large messages (KB-63).
const char* kPage = R"HTML(<!doctype html><html><head><meta charset="utf-8"><title>NCM Rig Bridge</title></head>
<body style="margin:0;background:transparent"><script>(function(){
var ws=null,ready=false;
function tell(e,d){try{if(window.Open77&&Open77.emit)Open77.emit(e,{detail:String(d)});}catch(x){}}
function relay(p){if(ready&&ws){try{ws.send(JSON.stringify(p));}catch(x){}}}
function connect(){try{ws=new WebSocket("ws://"+location.host+"/rig");}catch(x){tell("ncm:ffb.closed",x);return;}
ws.onopen=function(){ready=true;tell("ncm:ffb.ready",location.origin);};
ws.onmessage=function(e){try{var m=JSON.parse(e.data);if(!m||!window.Open77||!Open77.emit)return;
if(m.device)Open77.emit("ncm:ffb.device",m.device);if(m.rig)Open77.emit("ncm:rig.health",m.rig);}catch(x){}};
ws.onclose=function(){ready=false;tell("ncm:ffb.closed","socket closed");setTimeout(connect,2000);};
ws.onerror=function(){ready=false;};}
if(window.Open77&&Open77.on){Open77.on("ncm:ffb.frame",relay);
Open77.on("ncm:ffb.idle",function(p){relay({v:(p&&p.v)||1,idle:true});});
Open77.on("ncm:ffb.settings",function(p){relay({cmd:"settings",settings:p||{}});});
Open77.on("ncm:ffb.test",function(p){relay({cmd:"test",test:p||{}});});
Open77.on("ncm:ffb.bind",function(p){relay({cmd:"bind",bind:p||{}});});
Open77.on("ncm:pad.req",padReq);}connect();
function padReq(p){if(!p||!p.id)return;var path=p.path==="/pad/cmd"?"/pad/cmd":"/pad/state";
var base=p.base||("http://127.0.0.1:"+((+location.port||38520)+10));
var o=path==="/pad/cmd"?{method:"POST",headers:{"Content-Type":"text/plain"},body:String(p.body||"{}")}:{};
fetch(base+path,o).then(function(r){if(!r.ok)throw new Error("HTTP "+r.status);return r.text();}).then(function(s){
var n=Math.max(1,Math.ceil(s.length/3000));for(var i=0;i<n;i++)Open77.emit("ncm:pad.part",{id:p.id,i:i+1,n:n,s:s.substr(i*3000,3000)});
}).catch(function(e){Open77.emit("ncm:pad.fail",{id:p.id,error:String((e&&e.message)||e)});});}})();
</script></body></html>)HTML";

struct Sha1 {
    uint32_t h[5]{0x67452301u,0xEFCDAB89u,0x98BADCFEu,0x10325476u,0xC3D2E1F0u};
    static uint32_t rol(uint32_t v,int n){return(v<<n)|(v>>(32-n));}
    std::array<uint8_t,20> operator()(const std::string& input){
        std::string msg=input; const uint64_t bits=static_cast<uint64_t>(msg.size())*8; msg.push_back(static_cast<char>(static_cast<uint8_t>(0x80u)));
        while(msg.size()%64!=56)msg.push_back('\0'); for(int i=7;i>=0;--i)msg.push_back(char((bits>>(i*8))&0xff));
        for(size_t chunk=0;chunk<msg.size();chunk+=64){uint32_t w[80]{};
            for(int i=0;i<16;++i)w[i]=(uint8_t(msg[chunk+i*4])<<24)|(uint8_t(msg[chunk+i*4+1])<<16)|(uint8_t(msg[chunk+i*4+2])<<8)|uint8_t(msg[chunk+i*4+3]);
            for(int i=16;i<80;++i)w[i]=rol(w[i-3]^w[i-8]^w[i-14]^w[i-16],1);
            uint32_t a=h[0],b=h[1],c=h[2],d=h[3],e=h[4];
            for(int i=0;i<80;++i){uint32_t f,k;if(i<20){f=(b&c)|(~b&d);k=0x5A827999u;}else if(i<40){f=b^c^d;k=0x6ED9EBA1u;}else if(i<60){f=(b&c)|(b&d)|(c&d);k=0x8F1BBCDCu;}else{f=b^c^d;k=0xCA62C1D6u;}uint32_t t=rol(a,5)+f+e+k+w[i];e=d;d=c;c=rol(b,30);b=a;a=t;}
            h[0]+=a;h[1]+=b;h[2]+=c;h[3]+=d;h[4]+=e;}
        std::array<uint8_t,20> out{};for(int i=0;i<5;++i)for(int j=0;j<4;++j)out[i*4+j]=uint8_t((h[i]>>(24-j*8))&0xff);return out;}
};

std::string base64(const uint8_t* data,size_t length){static const char* t="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";std::string out;
    for(size_t i=0;i<length;i+=3){uint32_t n=(data[i]<<16)|((i+1<length?data[i+1]:0)<<8)|(i+2<length?data[i+2]:0);out.push_back(t[(n>>18)&63]);out.push_back(t[(n>>12)&63]);out.push_back(i+1<length?t[(n>>6)&63]:'=');out.push_back(i+2<length?t[n&63]:'=');}return out;}
std::string acceptKey(const std::string& key){Sha1 sha;auto d=sha(key+kWebSocketGuid);return base64(d.data(),d.size());}

std::string header(const std::string& request,const std::string& wanted){std::string low;for(char c:request)low.push_back(char(std::tolower(static_cast<unsigned char>(c))));
    auto at=low.find(wanted);if(at==std::string::npos)return{};auto colon=low.find(':',at);if(colon==std::string::npos)return{};auto end=low.find("\r\n",colon);
    std::string value=request.substr(colon+1,end-colon-1);while(!value.empty()&&(value.front()==' '||value.front()=='\t'))value.erase(value.begin());while(!value.empty()&&(value.back()==' '||value.back()=='\r'))value.pop_back();return value;}
bool sendAll(SOCKET s,const char* p,size_t n){size_t done=0;while(done<n){int sent=send(s,p+done,static_cast<int>(n-done),0);if(sent<=0)return false;done+=sent;}return true;}
bool sendText(SOCKET s,const std::string& p){std::string h;h.push_back(static_cast<char>(static_cast<uint8_t>(0x81u)));if(p.size()<126)h.push_back(char(p.size()));else{h.push_back(126);h.push_back(char((p.size()>>8)&0xff));h.push_back(char(p.size()&0xff));}return sendAll(s,h.data(),h.size())&&sendAll(s,p.data(),p.size());}
bool recvExact(SOCKET s,char* p,size_t n){size_t got=0;while(got<n){int r=recv(s,p+got,static_cast<int>(n-got),0);if(r<=0)return false;got+=r;}return true;}
bool readFrame(SOCKET s,int& opcode,std::string& payload){char h[2];if(!recvExact(s,h,2))return false;opcode=h[0]&15;bool masked=(h[1]&0x80)!=0;uint64_t n=h[1]&0x7f;
    if(n==126){char e[2];if(!recvExact(s,e,2))return false;n=(uint8_t(e[0])<<8)|uint8_t(e[1]);}else if(n==127)return false;if(n>(1u<<20))return false;
    char mask[4]{};if(masked&&!recvExact(s,mask,4))return false;payload.assign(static_cast<size_t>(n),'\0');if(n&&!recvExact(s,payload.data(),static_cast<size_t>(n)))return false;
    if(masked)for(size_t i=0;i<payload.size();++i)payload[i]^=mask[i%4];return true;}
}

Bridge::Bridge(uint16_t port, DirectInputRig& rig, std::wstring directory)
    : directory_(std::move(directory)), port_(port), rig_(rig) {}
Bridge::~Bridge(){stop();}
void Bridge::start(){if(running_.exchange(true))return;thread_=std::thread([this]{run();});}
void Bridge::stop(){if(!running_.exchange(false))return;if(auto s=client_.exchange(0))closesocket(static_cast<SOCKET>(s));if(auto s=listener_.exchange(0))closesocket(static_cast<SOCKET>(s));if(thread_.joinable())thread_.join();listening_=false;state().setBridgeConnected(false);}

void Bridge::run()
{
    WSADATA data{};if(WSAStartup(MAKEWORD(2,2),&data)!=0){RIG_ERR("Winsock unavailable");return;}
    SOCKET listener=INVALID_SOCKET;
    for(uint16_t candidate=port_;candidate<port_+kPortSpan;++candidate){SOCKET s=socket(AF_INET,SOCK_STREAM,IPPROTO_TCP);if(s==INVALID_SOCKET)continue;
        BOOL exclusive=TRUE;setsockopt(s,SOL_SOCKET,SO_EXCLUSIVEADDRUSE,reinterpret_cast<const char*>(&exclusive),sizeof(exclusive));
        sockaddr_in address{};address.sin_family=AF_INET;address.sin_port=htons(candidate);inet_pton(AF_INET,"127.0.0.1",&address.sin_addr);
        if(bind(s,reinterpret_cast<sockaddr*>(&address),sizeof(address))!=SOCKET_ERROR&&listen(s,2)!=SOCKET_ERROR){listener=s;port_=candidate;break;}closesocket(s);}
    if(listener==INVALID_SOCKET){RIG_ERR("no free rig bridge port in configured four-port range");WSACleanup();return;}
    listener_=static_cast<uintptr_t>(listener);listening_=true;RIG_INFO("rig bridge listening on http://127.0.0.1:%u/bridge.html",port_);
    while(running_.load()){SOCKET client=accept(listener,nullptr,nullptr);if(client==INVALID_SOCKET)break;
        uint32_t peer=peerPid(client);if(!sameProcessTree(peer,GetCurrentProcessId())){RIG_WARN("refused bridge peer pid=%u outside this game's process tree",peer);closesocket(client);continue;}
        client_=static_cast<uintptr_t>(client);std::string request(4096,'\0');int got=recv(client,request.data(),4095,0);if(got>0){request.resize(got);auto key=header(request,"sec-websocket-key");if(key.empty())serveHttp(client_);else serveWebSocket(client_,key);}closesocket(client);client_=0;}
    listening_=false;closesocket(listener);listener_=0;WSACleanup();
}

void Bridge::serveHttp(uintptr_t value){SOCKET s=static_cast<SOCKET>(value);std::string body=kPage;std::string response="HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nContent-Length: "+std::to_string(body.size())+"\r\nConnection: close\r\n\r\n"+body;sendAll(s,response.data(),response.size());}
void Bridge::serveWebSocket(uintptr_t value,const std::string& key){SOCKET s=static_cast<SOCKET>(value);std::string response="HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: "+acceptKey(key)+"\r\n\r\n";if(!sendAll(s,response.data(),response.size()))return;
    state().setBridgeConnected(true);RIG_INFO("NCM WebUI connected to Rig Bridge");sendSnapshot();int opcode=0;std::string payload;while(running_.load()&&readFrame(s,opcode,payload)){if(opcode==8)break;if(opcode==1){try{dispatch(payload);}catch(const std::exception& e){RIG_WARN("bridge message dropped: %s",e.what());}}}
    state().setBridgeConnected(false);RIG_INFO("NCM WebUI disconnected from Rig Bridge");}

void Bridge::sendSnapshot()
{
    if (!client_.load()) return;
    json info = json::parse(rig_.deviceJson());
    const auto& roles = info["roles"];
    auto roleName = [&roles](const char* key) -> std::string {
        if (!roles.contains(key)) return {};
        const auto& r = roles[key];
        if (r.value("bound", false)) return r.value("name", std::string());
        return r.value("missing", false) ? std::string("BOUND DEVICE NOT CONNECTED") : std::string();
    };
    const std::string steering = roleName("steering");
    std::string pedals;
    for (const char* k : {"throttle", "brake", "clutch"}) {
        const auto n = roleName(k);
        if (n.empty()) continue;
        if (pedals.find(n) == std::string::npos) pedals += (pedals.empty() ? "" : " + ") + n;
    }
    std::string name = roleName("ffb");
    if (name.empty()) name = steering.empty() ? "no wheel detected" : steering;

    // The ladder is the device class's, and the reported rung is the INDEX the panel sent -- derived by
    // matching, never by threshold. A threshold is how the panel and the device came to disagree before.
    const float ceiling = rig_.ffbCeiling();
    const float fraction = rig_.ffbFraction();
    const float strength = fraction * ceiling;

    json device{{"name", name}, {"class", feel::nameOf(rig_.deviceClass())}, {"armed", rig_.ffbArmed()},
        {"strength", fraction}, {"magnitude", strength}, {"ceiling", ceiling},
        {"steerDegrees", rig_.config().steerDegrees}, {"wheelRange", rig_.config().wheelRangeDegrees},
        {"classes", {"gear", "belt", "direct_drive", "unknown"}},
        {"caps", {{"spring", true}, {"damper", true}, {"sine", rig_.hasFfb()}, {"constant", rig_.hasFfb()}}},
        {"tune", {{"spring", rig_.ffbSpring()}, {"damper", rig_.ffbDamper()}, {"engine", rig_.ffbEngine()},
                  {"road", rig_.ffbRoad()}, {"texture", rig_.ffbTexture()},
                  {"collision", rig_.ffbCollision()}}},
        {"rig", {{"steering", steering}, {"pedals", pedals},
                 {"rigLive", state().playerVehicle() != nullptr},
                 // `rig` is passed through whole by the Lua, so anything the panel reads is safest here.
                 {"steerDegrees", rig_.config().steerDegrees},
                 {"wheelRange", rig_.config().wheelRangeDegrees},
                 // Inside `rig` on purpose: `carrier_bridge.lua` rebuilds the device payload field by
                 // field and passes `rig` through as a whole table. A sibling of `rig` never arrives.
                 {"devices", info["devices"]},
                 {"roles", info["roles"]},
                 // The gamepad layer's own loopback API. The panel fetches it directly: a whole profile through
                 // page:send would be silently dropped past its size limit (KB-63).
                 {"padApi", state().padApiPort() ? "http://127.0.0.1:" + std::to_string(state().padApiPort()) : std::string()},
                 // What the output is actually doing, in words a tester can screenshot.
                 {"ffb", info.value("ffbOutput", json::object())}}}};
    json root{{"device", device}, {"rig", {{"version", NCM_RIG_BRIDGE_VERSION}, {"provider", "directinput"},
        {"hook", true}, {"devices", info["devices"]}, {"roles", info["roles"]}}}};
    sendText(static_cast<SOCKET>(client_.load()), root.dump());
}

void Bridge::dispatch(const std::string& payload)
{
    json message = json::parse(payload);
    if (!message.is_object()) return;
    const std::string cmd = message.value("cmd", "");

    if (cmd == "settings") {
        const auto& s = message["settings"];
        if (s.contains("armed")) rig_.setFfbArmed(s["armed"].get<bool>());
        // **Continuous, not a ladder.** The rungs came from the companion, where a fixed ladder made a
        // tuning session reproducible between testers. For one driver on their own wheel that is just a
        // coarser control, so `strength` is a 0..1 fraction of the class ceiling and the cap survives:
        // 100% is the ceiling, never past it.
        if (s.contains("class")) rig_.setDeviceClass(s["class"].get<std::string>());
        if (s.contains("strength")) rig_.setFfbFraction(s["strength"].get<float>());
        if (s.contains("ratedNm")) rig_.setRatedTorque(s["ratedNm"].get<float>());
        // Rides `settings` rather than a new command, so no Lua or relay change is needed to carry it.
        if (s.value("resetPeaks", false)) rig_.resetFfbPeaks();
        if (s.contains("rung")) {   // older panels
            const auto rungs = feel::ladder(rig_.deviceClass());
            const int index = std::clamp(s["rung"].get<int>(), 1, static_cast<int>(rungs.size()));
            rig_.setFfbStrength(rungs[static_cast<size_t>(index - 1)]);
        }
        if (s.contains("spring")) rig_.setFfbSpring(s["spring"].get<float>());
        if (s.contains("damper")) rig_.setFfbDamper(s["damper"].get<float>());
        if (s.contains("texture")) rig_.setFfbTexture(s["texture"].get<float>());
        if (s.contains("engine")) rig_.setFfbEngine(s["engine"].get<float>());
        if (s.contains("road")) rig_.setFfbRoad(s["road"].get<float>());
        if (s.contains("collision")) rig_.setFfbCollision(s["collision"].get<float>());
        if (s.contains("steerDegrees")) rig_.setSteerDegrees(s["steerDegrees"].get<float>());
        // **Settings were never written down.** Only `bind` persisted, so the wheel type and the force
        // level were lost on every restart -- and, worse, any code path that reloaded config put them
        // back to the shipped defaults while the player watched.
        rig_.persist(directory_);
        sendSnapshot();
        return;
    }
    if (cmd == "test") { rig_.testPulse(); return; }

    // The panel assigning a role to a device. One role per message, so a half-finished setup is never
    // written as a complete one.
    if (cmd == "bind") {
        const auto& b = message["bind"];
        rig_.bind(b.value("role", std::string()), b.value("device", std::string()),
                  b.value("axis", std::string()), b.value("invert", false),
                  b.contains("deadzone") ? b["deadzone"].get<float>() : -1.0f);
        rig_.persist(directory_);
        sendSnapshot();
        return;
    }

    // ---- an ordinary telemetry frame -----------------------------------------------------------
    //
    // **Every field is optional and absent is not zero.** The client sends what it could read off the
    // vehicle snapshot; a channel it could not read must stay unset so the mix holds rather than
    // reporting a car that is perfectly still. Earlier builds read only speed, steering and suspLong and
    // discarded the rest, which is why road texture and slip could never be felt.
    auto frame = state().feedback();
    auto& tm = frame.telemetry;
    tm = feel::Telemetry{};
    frame.updated = std::chrono::steady_clock::now();
    frame.inVehicle = !message.value("idle", false) && state().playerVehicle() != nullptr;

    auto take = [&message](const char* key, bool& has, float& out) {
        if (message.contains(key) && message[key].is_number()) { out = message[key].get<float>(); has = true; }
    };
    take("engine", tm.hasEngine, tm.engine);
    take("speed", tm.hasSpeed, tm.speed);
    take("steering", tm.hasSteering, tm.steering);
    take("slipLong", tm.hasSlipLong, tm.slipLong);
    take("slipLat", tm.hasSlipLat, tm.slipLat);
    take("slipTotal", tm.hasSlipTotal, tm.slipTotal);
    take("suspLong", tm.hasSuspLong, tm.suspLong);
    take("suspLat", tm.hasSuspLat, tm.suspLat);
    if (tm.hasSpeed) tm.speed = std::fabs(tm.speed);

    state().publishFeedback(frame);

    // **The axis meters have to move while a pedal is pressed**, or the dropdowns are back to guesswork.
    // Snapshots used to go out only on connect and on change, so the panel showed a frozen number. The
    // client sends telemetry (or an idle beat) continuously, so ride that rather than adding a thread --
    // rate-limited, because a snapshot re-reads every device and the panel only needs to look live.
    const auto now = std::chrono::steady_clock::now();
    if (now - lastSnapshot_ >= std::chrono::milliseconds(150)) {
        lastSnapshot_ = now;
        sendSnapshot();
    }
}
}
