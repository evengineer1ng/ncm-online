// NcmKsa -- Night City Motorsports' Kitten Space Agency adapter (L334, IDEA-1169).
//
// KSA is the host past NCM Deep: at Earth's sphere of influence the Machine leaves Deep and continues here, at the same
// state. This StarMap code mod is the KSA side of that handoff. It does three things and nothing else:
//
//   * answers on http://127.0.0.1:47712 (the NCM host bridge is 47710) -- never on another interface;
//   * READS: KSA's Earth (mean radius, mu, KSA's own sphere-of-influence radius) and the controlled craft's state
//     (inertial position and velocity, Earth-fixed latitude, longitude, altitude, mass, situation, KSA time);
//   * PLACES the controlled craft at a state NCM hands it, with KSA's own code: Orbit.CreateFromStateCci + Teleport.
//
// Frames. KSA's Earth-fixed frame (Celestial.GetDirCcfFromLatLon: x through 0N 0E, z north) is the same convention as
// NCM's Deep frame (space.deep llaToEcef), so a Deep state maps by latitude/longitude/altitude, and its INERTIAL
// velocity (space.deep.inertialVel), expressed on the Earth-fixed axes, is rotated to KSA's inertial frame with KSA's
// own GetCcf2Cci at KSA's current time. Nothing is guessed: the self-test places a craft and reads it back.
//
// Every KSA call happens on KSA's thread (the StarMap per-frame hook); the HTTP listener only queues work and waits.
// Written against KSA 2026.10.10.5554 and StarMap 0.4.7. NCM-original code; references KSA's public types only.
using System.Collections.Concurrent;
using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Brutal.Numerics;
using KSA;
using StarMap.API;

namespace Ncm.Ksa
{
    [StarMapMod]
    public class NcmKsa
    {
        public const string Version = "0.2.0";
        private const string Prefix = "http://127.0.0.1:47712/";
        private static HttpListener? _http;
        private static readonly ConcurrentQueue<Work> _queue = new();
        private static long _frames;
        private static string _log = "";

        private sealed class Work
        {
            public required Func<JsonObject> Run;
            public readonly TaskCompletionSource<JsonObject> Done = new(TaskCreationOptions.RunContinuationsAsynchronously);
        }

        [StarMapAllModsLoaded]
        public void OnLoaded()
        {
            try
            {
                _http = new HttpListener();
                _http.Prefixes.Add(Prefix);
                _http.Start();
                Task.Run(Serve);
                Log($"NcmKsa {Version} listening on {Prefix}");
            }
            catch (Exception e) { Log("NcmKsa could not listen: " + e.Message); }
        }

        [StarMapUnload]
        public void OnUnload()
        {
            try { _http?.Stop(); } catch { }
            _http = null;
        }

        // KSA's thread: run what the listener queued (a few per frame at most)
        [StarMapAfterGui]
        public void OnAfterGui(double dt)
        {
            _frames++;
            for (int i = 0; i < 4 && _queue.TryDequeue(out Work? w); i++)
            {
                try { w.Done.TrySetResult(w.Run()); }
                catch (Exception e) { w.Done.TrySetResult(new JsonObject { ["ok"] = false, ["error"] = e.GetType().Name + ": " + e.Message }); }
            }
        }

        private static void Log(string s)
        {
            Console.WriteLine("[NcmKsa] " + s);
            _log = s;
        }

        // ------------------------------------------------------------------------------------------ HTTP
        private static async Task Serve()
        {
            while (_http != null && _http.IsListening)
            {
                HttpListenerContext ctx;
                try { ctx = await _http.GetContextAsync(); } catch { break; }
                _ = Task.Run(() => Handle(ctx));
            }
        }

        private static async Task Handle(HttpListenerContext ctx)
        {
            JsonObject result;
            try
            {
                string path = ctx.Request.Url?.AbsolutePath ?? "/";
                string body = "";
                if (ctx.Request.HasEntityBody)
                {
                    using var r = new StreamReader(ctx.Request.InputStream, Encoding.UTF8);
                    body = await r.ReadToEndAsync();
                }
                result = path switch
                {
                    "/ksa/ping" => new JsonObject { ["ok"] = true, ["mod"] = "NcmKsa", ["version"] = Version, ["frames"] = _frames, ["last"] = _log },
                    "/ksa/state" => await OnGame(State),
                    "/ksa/place" => await OnGame(() => Place(JsonNode.Parse(body) as JsonObject ?? new JsonObject())),
                    "/ksa/selftest" => await OnGame(SelfTest),
                    _ => new JsonObject { ["ok"] = false, ["error"] = "no such path " + path },
                };
            }
            catch (Exception e) { result = new JsonObject { ["ok"] = false, ["error"] = e.Message }; }
            byte[] bytes = Encoding.UTF8.GetBytes(result.ToJsonString());
            ctx.Response.ContentType = "application/json";
            ctx.Response.ContentLength64 = bytes.Length;
            try { await ctx.Response.OutputStream.WriteAsync(bytes); ctx.Response.Close(); } catch { }
        }

        private static async Task<JsonObject> OnGame(Func<JsonObject> f)
        {
            var w = new Work { Run = f };
            _queue.Enqueue(w);
            Task done = await Task.WhenAny(w.Done.Task, Task.Delay(10000));
            return done == w.Done.Task ? w.Done.Task.Result
                : new JsonObject { ["ok"] = false, ["error"] = "KSA's frame loop did not run the request within 10 s (loading, paused, or not in a flight)" };
        }

        // ------------------------------------------------------------------------------------------ the game side
        private static JsonArray V(double3 v) => new JsonArray(v.X, v.Y, v.Z);
        private static double3 D3(JsonNode? n) => new double3((double)n![0]!, (double)n[1]!, (double)n[2]!);

        private static (Celestial? earth, Vehicle? vehicle, string why) Ready()
        {
            CelestialSystem? sys = Universe.CurrentSystem;
            if (sys == null) return (null, null, "no system loaded (main menu?)");
            Celestial? earth = sys.HomeBody as Celestial;
            if (earth == null) return (null, null, "the system has no home body");
            Vehicle? v = Program.ControlledVehicle;
            if (v == null) return (earth, null, "no controlled vehicle (not in a flight)");
            return (earth, v, "");
        }

        private static JsonObject EarthInfo(Celestial earth) => new()
        {
            ["id"] = earth.Id,
            ["meanRadiusM"] = earth.MeanRadius,
            ["mu"] = ((IParentBody)earth).Mu,
            ["soiRadiusM"] = earth.ComputeSphereOfInfluenceRadius(),
        };

        private static JsonObject VehicleState(Celestial earth, Vehicle v)
        {
            UniverseTime t = Universe.GetElapsedTime();
            double3 pCci = v.GetPositionCci();
            double3 vCci = v.GetVelocityCci();
            double3 pCcf = pCci.Transform(earth.GetCci2Ccf(t));
            double r = pCci.Length();
            return new JsonObject
            {
                ["id"] = v.Id,
                ["parent"] = v.Parent?.Id,
                ["positionCci"] = V(pCci),
                ["velocityCci"] = V(vCci),
                ["positionCcf"] = V(pCcf),
                ["lat"] = Celestial.GetLatitudeFromCcf(pCcf),
                ["lon"] = Celestial.GetLongitudeFromCcf(pCcf),
                ["altM"] = r - earth.MeanRadius,
                ["radiusM"] = r,
                ["inertialSpeed"] = vCci.Length(),
                ["massKg"] = v.TotalMass,
                ["propellantKg"] = v.PropellantMass,
                ["situation"] = v.Situation.ToString(),
            };
        }

        private static JsonObject State()
        {
            var (earth, v, why) = Ready();
            var o = new JsonObject { ["ok"] = earth != null && v != null, ["why"] = why, ["mod"] = Version,
                ["timeS"] = Universe.GetElapsedTime().Seconds(), ["simSpeed"] = Universe.GetSimulationSpeed() };
            if (earth != null) o["earth"] = EarthInfo(earth);
            if (earth != null && v != null) o["vehicle"] = VehicleState(earth, v);
            return o;
        }

        /// <summary>
        /// Place the controlled craft. Body: { lat, lon, altM, velocityInertialCcf: [x,y,z] } -- the INERTIAL velocity on the
        /// Earth-fixed axes at this instant (NCM space.deep.inertialVel). Altitude is above KSA's mean radius.
        /// </summary>
        private static JsonObject Place(JsonObject req)
        {
            var (earth, v, why) = Ready();
            if (earth == null || v == null) return new JsonObject { ["ok"] = false, ["why"] = why };
            double lat = (double)req["lat"]!, lon = (double)req["lon"]!, alt = (double)req["altM"]!;
            double3 velCcfAxes = D3(req["velocityInertialCcf"]);
            UniverseTime t = Universe.GetElapsedTime();
            // KSA can only hold an EARTH orbit inside its own Earth sphere of influence (measured: a state outside it makes
            // CreateFromStateCci throw "UniverseTime from NaN")
            double soi = earth.ComputeSphereOfInfluenceRadius();
            if (!double.IsNaN(soi) && earth.MeanRadius + alt >= soi)
                return new JsonObject { ["ok"] = false, ["why"] = $"outside KSA's Earth sphere of influence ({(earth.MeanRadius + alt) / 1000:F0} km >= {soi / 1000:F0} km)" };
            doubleQuat ccf2cci = earth.GetCcf2Cci(t);
            double3 up = earth.GetDirCcfFromLatLon(lat, lon);
            double3 pCcf = up * (earth.MeanRadius + alt);
            // a perfectly radial velocity has no angular momentum -- a degenerate orbit KSA's Kepler maths divides by (any
            // sideways part works, measured down to 1 cm/s): nudge it sideways by 1 cm/s, said in the log
            double3 side = velCcfAxes - up * double3.Dot(velCcfAxes, up);
            bool nudged = false;
            if (side.Length() < 0.005)
            {
                double3 east = double3.Cross(new double3(0, 0, 1), up);
                if (east.Length() < 1e-9) east = new double3(1, 0, 0);
                velCcfAxes = velCcfAxes + east.Normalized() * 0.01;
                nudged = true;
            }
            double3 pCci = pCcf.Transform(ccf2cci);
            double3 vCci = velCcfAxes.Transform(ccf2cci);
            Orbit orbit = Orbit.CreateFromStateCci(earth, t, pCci, vCci, v.OrbitColor);
            v.Teleport(orbit, null, null);
            Log($"placed {v.Id} at {lat:F4},{lon:F4} alt {alt / 1000:F1} km, inertial {vCci.Length():F0} m/s{(nudged ? " (radial: nudged 1 cm/s sideways)" : "")}");
            return new JsonObject { ["ok"] = true, ["nudged"] = nudged, ["placed"] = VehicleState(earth, v) };
        }

        /// <summary>
        /// Put the craft where NCM's border handoff would -- 98 % of KSA's own Earth sphere of influence over Night City, 148 km/s
        /// outward (a state OUTSIDE the sphere is not an Earth orbit in KSA: CreateFromStateCci fails, measured 2026-10-07) --
        /// read it back, compare, then put it back where it was. Tolerances: radius 1 km, speed 1 m/s, lat/lon 0.01 deg.
        /// </summary>
        private static JsonObject SelfTest()
        {
            var (earth, v, why) = Ready();
            if (earth == null || v == null) return new JsonObject { ["ok"] = false, ["why"] = why };
            UniverseTime t = Universe.GetElapsedTime();
            double3 p0 = v.GetPositionCci(), v0 = v.GetVelocityCci();
            const double lat = 35.37, lon = -120.85;
            double rTest = 0.98 * earth.ComputeSphereOfInfluenceRadius();
            double alt = rTest - earth.MeanRadius, speed = 148_000.0;
            double3 up = earth.GetDirCcfFromLatLon(lat, lon);
            // a real border arrival: almost all outward, a few m/s sideways left from the Earth's spin
            double3 east = double3.Cross(new double3(0, 0, 1), up).Normalized();
            var place = Place(new JsonObject { ["lat"] = lat, ["lon"] = lon, ["altM"] = alt, ["velocityInertialCcf"] = V(up * speed + east * 3.0) });
            var back = VehicleState(earth, v);
            double dR = Math.Abs((double)back["radiusM"]! - rTest);
            double dV = Math.Abs((double)back["inertialSpeed"]! - speed);
            double dLat = Math.Abs((double)back["lat"]! - lat);
            double dLon = Math.Abs((((double)back["lon"]! - lon) + 540) % 360 - 180);
            bool pass = (bool)place["ok"]! && dR < 1000 && dV < 1 && dLat < 0.01 && dLon < 0.01 && (string?)back["parent"] == earth.Id;
            // put it back
            v.Teleport(Orbit.CreateFromStateCci(earth, t, p0, v0, v.OrbitColor), null, null);
            return new JsonObject
            {
                ["ok"] = pass, ["earth"] = EarthInfo(earth), ["readBack"] = back,
                ["errors"] = new JsonObject { ["radiusM"] = dR, ["speedMps"] = dV, ["latDeg"] = dLat, ["lonDeg"] = dLon },
                ["restored"] = true,
            };
        }
    }
}
