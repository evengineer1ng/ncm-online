# Remote cameras and world screens › Remote cameras and world screens

Render another viewpoint without replacing the player's camera. Use remote cameras for a security monitor, a picture-in-picture HUD, a world-space screen or a feed behind a transparent WebUI.

Available from **`2.31.13+op77.82`**, this feature is **experimental**. Rendering, source switching and long-session cleanup have known limitations; see [limits and troubleshooting](#limits-and-troubleshooting) before building a public resource around it.


## Remote cameras and world screens › Choose the right API

| Need | API | Runtime |
|---|---|---|
| Create a local capture and display it yourself | `Open77.remoteCamera` | Client |
| Share camera definitions, authorize viewers and manage remote replication interest | `exports.open77_remote_camera:*` | Server |
| Move or replace the player's view | [Scripted cameras](cameras.md), not remote cameras | Client |
| Customize the playable shoulder camera | [Third-person camera styles](third-person-camera.md) | Client |

Each viewer renders the feed on their own client. The server distributes definitions and access rules, **not video frames**. Native client handles and server camera IDs are different identifiers and cannot be substituted for each other.


## Remote cameras and world screens › Prerequisites

Use matching client/server builds and the Open77 archive containing the capture-slot assets. A client resource calling `Open77.remoteCamera` needs `camera.capture`; add `local.events` to subscribe to the lifecycle events below. Aim raycasts need `world.query`, and parent-frame conversions need `world.transform`.

For provider-managed cameras, start `open77_remote_camera` and declare this dependency in the consuming resource's `open77.lua`:

```lua
dependency "open77_remote_camera >=0.3.0"
```

A server-only consumer delegates capture to the provider and does not need client capture permissions. A custom client renderer still needs its own permissions and cleanup.


## Remote cameras and world screens › Minimal client HUD

Example `open77.lua`:

```lua
resource "security_monitor"
version "1.0.0"
client_script "client.lua"
