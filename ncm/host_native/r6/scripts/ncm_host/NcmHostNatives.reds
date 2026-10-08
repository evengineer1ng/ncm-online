// NCM Host -- the natives `ncm_host.dll` registers (L338, KB-385).
//
// **This file must never declare a `module`** (KB-182): RED4ext matches every `native func` by its fully qualified
// name, and a module would rename them and stop the game before it starts.
//
// The game calls NcmHost_Call (NcmHostRuntime.reds; L340: no CET) with a command and a JSON payload; the answer is JSON,
// or LINES for the redscript commands (session/frame/tapes/choose/leave). The simulation runs in the plugin's Lua 5.4.

public static native func NcmHost_Call(cmd: String, payload: String) -> String
public static native func NcmHost_Ready() -> Bool

// The same two calls as a scriptable system, for CET builds that do not expose global natives on `Game`.
public class NcmHostBridge extends ScriptableSystem {
    public func Call(cmd: String, payload: String) -> String { return NcmHost_Call(cmd, payload); }
    public func Ready() -> Bool { return NcmHost_Ready(); }
}
