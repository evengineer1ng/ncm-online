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
        public const string Version = "0.3.0";
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
                    "/ksa/burn" => await OnGame(() => Burn(JsonNode.Parse(body.Length > 0 ? body : "{}") as JsonObject ?? new JsonObject())),
                    "/ksa/view" => await OnGame(() => View(JsonNode.Parse(body.Length > 0 ? body : "{}") as JsonObject ?? new JsonObject())),
                    "/ksa/spawn" => await OnGame(() => Spawn(JsonNode.Parse(body.Length > 0 ? body : "{}") as JsonObject ?? new JsonObject())),
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

        // ------------------------------------------------------------------------------------------ L336: the Machine's own body
        // The craft NCM hands over is the Machine itself: an NCM craft (content/NcmHella.xml: the Hella's body, its FD-1,
        // PT-500 and AC-6) registered from this mod's vehicles/ folder, built at the controlled craft's state, and made the
        // controlled vehicle. KSA's starting "Rocket" is left where it is.
        private static string ModDir => Path.GetDirectoryName(typeof(NcmKsa).Assembly.Location) ?? ".";
        private static Vehicle? _machine;
        private const double PT500_KG = 400.0;   // the PT-400 (KB-373; its design id keeps "pt500")

        /// <summary>
        /// Body: { body: "NcmHella", propellantKg: what is left in the PT-500 (NCM's record; default full) }.
        /// Spawns the NCM craft at the controlled craft's state (or re-takes control of it if it is already here).
        /// </summary>
        private static JsonObject Spawn(JsonObject req)
        {
            var (earth, v, why) = Ready();
            if (earth == null || v == null) return new JsonObject { ["ok"] = false, ["why"] = why };
            string body = (string?)req["body"] ?? "NcmHella";
            CelestialSystem sys = Universe.CurrentSystem!;
            Vehicle? stale = null;
            if (_machine != null && sys.Get(_machine.Id.ToString()) is Vehicle known && known == _machine)
            {
                // KB-378: the activation's test craft is fuelled full; when NCM says what is really left, the Machine is
                // built fresh with that fill (the first live handoff kept the test craft: 444 kg, a free full tank)
                if (req["propellantKg"] is null)
                {
                    TakeControl(_machine);
                    return new JsonObject { ["ok"] = true, ["reused"] = true, ["vehicle"] = VehicleState(earth, _machine) };
                }
                stale = _machine;
                _machine = null;
            }
            string dir = Path.Combine(ModDir, "vehicles", body);
            if (!Directory.Exists(dir)) return new JsonObject { ["ok"] = false, ["why"] = "no NCM craft '" + body + "' in " + Path.Combine(ModDir, "vehicles") };
            VehicleSave? save = DefaultVehicleSaves.FindSave(body) ?? UncompressedVehicleSave.FromDirectory(dir, defaultVehicle: true);
            PartInstance? root = save?.VehicleSaveData.RootPartInstance;
            if (root == null) return new JsonObject { ["ok"] = false, ["why"] = "craft '" + body + "' has no parts (vehicle.xml)" };
            Mod? core = ModLibrary.Find("Core");
            if (core == null) return new JsonObject { ["ok"] = false, ["why"] = "KSA's Core mod is not loaded" };
            // what is really left in the PT-500 (NCM's record), not a free full tank
            double fill = 1.0;
            if (req["propellantKg"] is JsonNode pk) fill = Math.Clamp((double)pk / PT500_KG, 0.0, 1.0);
            SetFill(root, fill);
            root.OnDataLoad(core);
            PartTree tree = PartTree.Deserialize(root);
            UniverseTime t = Universe.GetElapsedTime();
            // beside the craft KSA started with (50 m), at its velocity; the handoff then places it exactly
            double3 p = v.GetPositionCci() + new double3(50, 0, 0);
            Orbit orbit = Orbit.CreateFromStateCci(earth, t, p, v.GetVelocityCci(), v.OrbitColor);
            string id = "NCM " + body + " " + DateTime.UtcNow.ToString("HHmmss");
            Vehicle m = Vehicle.CreateVehicle(sys, v.Body2Cce, double3.Zero, earth, id, tree.Root, orbit);
            // as KSA itself spawns a craft built in code (InputEvents vehicle spawn): into its parent's children -- the per-frame
            // update -- and its per-frame data computed once; without it the HUD and view stay blank (bench, 2026-10-07)
            earth.Children.Add(m);
            m.UpdateAfterPartTreeModification();
            m.UpdatePerFrameData();
            // a craft built in code has no control point (KSA sets one only from a save or a docking): without it KSA's HUD,
            // attitude and camera frame are blank -- the grey screen of the first bench (2026-10-07). The root carries Control.
            m.SetControlPart(m.Parts.Root);
            _machine = m;
            TakeControl(m, v);
            // KSA's own starting craft has no part in the Machine's journey: remove it once control has passed (owner, 2026-10-07:
            // "why is the rocket still there?"). KSA's own clean removal; only a stock craft, never an NCM one.
            string removed = "";
            if (req["keepStock"] is null && v != m && !v.Id.StartsWith("NCM "))
            {
                removed = v.Id;
                Universe.DestroyVehicle(v, CrewDisposition.EndMission);
            }
            if (stale != null && stale != m)   // KB-378: the full test craft goes once the real Machine has control
            {
                removed = (removed.Length > 0 ? removed + ", " : "") + stale.Id;
                Universe.DestroyVehicle(stale, CrewDisposition.EndMission);
            }
            Log($"spawned {id} (PT-500 at {fill * 100:F0} %), mass {m.TotalMass:F0} kg, propellant {m.PropellantMass:F1} kg");
            return new JsonObject { ["ok"] = true, ["reused"] = false, ["fill"] = fill, ["meanRadiusM"] = m.MeanRadius, ["removed"] = removed, ["vehicle"] = VehicleState(earth, m) };
        }

        private static void SetFill(PartInstance pi, double fill)
        {
            foreach (var c in pi.Components)
                if (c is Tank.SaveData tank && (tank.InstanceOf == "PT500" || tank.InstanceOf == "PT500Trap"))
                    foreach (var mole in tank.Moles)
                    {
                        // the full-tank mass is kept beside the save so a second spawn scales from full, not from the last fill
                        string key = tank.InstanceOf + "/" + mole.SubstancePhaseId;
                        if (!_full.TryGetValue(key, out double full)) _full[key] = full = mole.Mass.Kg;
                        mole.Mass.Kg = full * fill;
                    }
            foreach (var sub in pi.SubPartInstances ?? new List<PartInstance>()) SetFill(sub, fill);
            foreach (var child in pi.Children ?? new List<PartInstance>()) SetFill(child, fill);
        }
        private static readonly Dictionary<string, double> _full = new();

        // ------------------------------------------------------------------------------------------ bench: does the FD-1 push?
        private static (double3 r, double3 v, double prop, double t, double mass)? _burn0;
        private static bool _staged;

        /// <summary>
        /// Bench burn of the controlled craft: { start: true } activates its first stage (once) and opens the throttle to
        /// 100 %; { stop: true } closes it and measures the burn: the velocity change with gravity taken out (Earth's pull at
        /// the burn's middle), the propellant used, and the mean thrust and Isp that follow from them.
        /// </summary>
        private static JsonObject Burn(JsonObject req)
        {
            var (earth, v, why) = Ready();
            if (earth == null || v == null) return new JsonObject { ["ok"] = false, ["why"] = why };
            // the pilot's inputs are a struct: read it boxed, change it, write it back (editing a copy did nothing, bench 2026-10-07)
            var mciField = typeof(Vehicle).GetField("_manualControlInputs", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
            if (mciField == null) return new JsonObject { ["ok"] = false, ["why"] = "no manual control inputs" };
            void Set(string f, object val)
            {
                object boxed = mciField.GetValue(v)!;
                boxed.GetType().GetField(f)?.SetValue(boxed, val);
                mciField.SetValue(v, boxed);
            }
            double t = Universe.GetElapsedTime().Seconds();
            if (req["start"] is JsonNode)
            {
                if (!_staged) { v.Parts.SequenceList.ActivateNextSequence(v); _staged = true; }
                Set("EngineOn", true);
                Set("EngineThrottle", 1f);
                _burn0 = (v.GetPositionCci(), v.GetVelocityCci(), v.PropellantMass, t, v.TotalMass);
                return new JsonObject { ["ok"] = true, ["started"] = t, ["thrustMaxN"] = v.ComputeActiveThrust(0f),
                    ["deltaVReadout"] = v.Parts.PerformanceSequences.FindActiveSequenceDeltaV() };
            }
            Set("EngineThrottle", 0f);
            Set("EngineOn", false);
            if (_burn0 is not { } b) return new JsonObject { ["ok"] = false, ["why"] = "no burn started" };
            _burn0 = null;
            double dt = t - b.t, used = b.prop - v.PropellantMass;
            double3 r1 = v.GetPositionCci(), v1 = v.GetVelocityCci();
            double3 rm = (b.r + r1) * 0.5;
            double mu = ((IParentBody)earth).Mu, rl = rm.Length();
            double3 g = rm * (-mu / (rl * rl * rl));
            double dvThrust = (v1 - b.v - g * dt).Length();
            double mMean = (b.mass + v.TotalMass) / 2;
            double thrust = dt > 0 ? dvThrust * mMean / dt : 0;
            return new JsonObject { ["ok"] = true, ["seconds"] = dt, ["deltaVThrustMps"] = dvThrust, ["propellantUsedKg"] = used,
                ["meanThrustN"] = thrust, ["ispS"] = used > 0 ? thrust * dt / used / 9.80665 : 0, ["massKg"] = v.TotalMass };
        }

        /// <summary>
        /// Bench view: { follow: "machine" | a vehicle id (e.g. "Rocket"), distanceM } -- what the camera follows and how far
        /// (KSA's orbit camera sits DistancePower x the target's mean radius away). Answers what it follows and where.
        /// </summary>
        private static JsonObject View(JsonObject req)
        {
            var (earth, v, why) = Ready();
            if (earth == null) return new JsonObject { ["ok"] = false, ["why"] = why };
            Camera cam = Program.GetMainCamera();
            string? follow = (string?)req["follow"];
            Vehicle? target = follow == null ? v : follow == "machine" ? _machine : Universe.CurrentSystem!.Get(follow) as Vehicle;
            if (follow != null && target == null) return new JsonObject { ["ok"] = false, ["why"] = "no vehicle '" + follow + "'" };
            if (target != null && follow != null) { cam.SetFollow(target, tidalLocking: true); Program.ControlledVehicle = target; }
            if (target != null && req["distanceM"] is JsonNode dm && target.MeanRadius > 0)
            {
                target.OrbitView.DistancePower = (double)dm / target.MeanRadius;
                Program.MainViewport.OrbitController.DistancePower = target.OrbitView.DistancePower;
            }
            var o = new JsonObject { ["ok"] = true, ["following"] = (cam.Following as Vehicle)?.Id, ["controlled"] = Program.ControlledVehicle?.Id };
            if (target != null)
            {
                o["target"] = target.Id;
                o["meanRadiusM"] = target.MeanRadius;
                o["distancePower"] = target.OrbitView.DistancePower;
                o["cameraDistanceM"] = (cam.PositionEcl - target.GetPositionEcl()).Length();
                o["parts"] = target.Parts.Parts.Length;
                // the rigid body: a NaN here blanks KSA's HUD and view while the (analytic) orbit still runs
                doubleQuat q = target.Body2Cce;
                o["body2Cce"] = new JsonArray(q.X, q.Y, q.Z, q.W);
                o["bodyRates"] = V(target.BodyRates);
                o["centerOfMassAsmb"] = V(target.CenterOfMassAsmb);
                o["massBody"] = target.TotalMassPropsBody.Mass;
                o["inertiaBody"] = target.TotalMassPropsBody.Inertia.ToString();
                o["controlPart"] = target.ControlPart != null;
            }
            return o;
        }

        // As KSA's own EVA spawn does (EVADoor.SpawnEva): follow the new craft and carry the orbit camera over, scaled by size
        // -- without that the camera keeps the old craft's distance, or sits inside the car (first bench, 2026-10-07)
        private static void TakeControl(Vehicle m, Vehicle? from = null)
        {
            try
            {
                Program.MainViewport.MapCamera.SetFollow(m, tidalLocking: false, changeControl: true, alert: false);
                Program.MainViewport.BaseCamera.SetFollow(m, tidalLocking: false, changeControl: true, alert: false);
                if (from != null && from != m && m.MeanRadius > 0)
                {
                    m.OrbitView.Azimuth = from.OrbitView.Azimuth;
                    m.OrbitView.Elevation = from.OrbitView.Elevation;
                    m.OrbitView.DistancePower = from.OrbitView.DistancePower * (from.MeanRadius / m.MeanRadius);
                    Program.MainViewport.OrbitController.DistancePower = m.OrbitView.DistancePower;
                }
            }
            catch (Exception e) { Log("camera follow: " + e.Message); }
            Program.ControlledVehicle = m;
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
