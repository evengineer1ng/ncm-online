## Replicated state bags › Who sees what

| Bag | Audience |
|---|---|
| `global` | every connected player, every routing bucket |
| `player(id)` | every player in that player's routing bucket, including the subject |
| `entity(kind, id)` | exactly the players streaming that entity — the registry's own viewer set |

An entity bag's audience **is** the entity's audience, which is what makes stream-in,
stream-out and bucket changes correct without a second interest pass to keep in sync.

**Routing buckets are isolated.** A player in another bucket does not receive the value and
is not told to ignore it: a bag carries gameplay secrets, so shipping it to a client that
is merely asked not to look is an information leak with no bandwidth saving. Moving bucket
drops the player's whole mirror and re-sends what the new bucket holds, atomically with the
move.

A late joiner, a streamed-in entity and a resynchronising client all receive a **full
snapshot**, chunked across several events when it is large. Everything else is a **delta**
carrying only the keys that moved.

---


## Replicated state bags › Lifecycle

- A bag **dies with its subject**: removing a prop, vehicle or NPC destroys its bag, and a
  disconnecting player takes theirs with them. Every holder is told to drop it, and every
  key raises a change so a handler watching one key sees it go.
- A resource **stopping** retires its change subscriptions and its `allowRequest`
  validators. A requestable key whose validator went down with its resource stops being
  requestable, rather than accepting whatever the client sends.
- The client mirror lives in the host, not in a resource, so it **survives a resource
  restart**: a resource coming back up reads the current values immediately.
- A new server session drops the mirror and asks for a fresh one, so the previous server's
  bags never linger.

---


## Replicated state bags › Caps

Nothing truncates. A write that breaches a cap is refused by name and the bag is left
exactly as it was — no partial apply, no key dropped to make room.

| Cap | Value | Refusal |
|---|---|---|
| Keys per bag | 64 | `bag_key_limit` |
| Key name | 64 bytes, `[A-Za-z][A-Za-z0-9_.-]*` | `invalid_state_key` |
| Value, serialized | 4 KiB | `state_value_too_large` |
| Value depth / nodes | 8 / 256 | `state_value_not_serializable` |
| Bytes per bag | 16 KiB | `bag_byte_limit` |
| Bags per server | 8 192 | `bag_limit` |
| Total bag bytes | 8 MiB | `bag_byte_limit` |
| Client requests | 4 per second per session | `state_request_rate_limit` |
| Server writes | 20 000 per second per resource | `state_write_rate_limit` |

The value budget is deliberately tighter than the 48 KiB export envelope: an export payload
crosses once, a bag value is re-sent to every viewer on every change and again in every
snapshot.

The server write budget is a safety valve, not a bandwidth control — ten writes to one key
in one tick already collapse into one delta carrying the final value, so outbound cost
follows the number of distinct keys that *moved*. A resource that trips it is named in the
server log, once per window, so the failure is attributable.


### Replicated state bags › Every failure reason

| Reason | Means |
|---|---|
| `invalid_state_key` | The key name is empty, too long, or outside `[A-Za-z][A-Za-z0-9_.-]*`. |
| `invalid_state_selector` | The kind is not one of `global`/`player`/`vehicle`/`npc`/`prop`, or the id is not a non-negative integer. |
| `state_value_too_large` | Over 4 KiB serialized. |
| `state_value_not_serializable` | A function, a coroutine, a cycle, or deeper than 8 / more than 256 nodes. |
| `bag_key_limit` | A 65th key. |
| `bag_byte_limit` | Over 16 KiB in one bag, or 8 MiB across the server. |
| `bag_limit` | An 8 193rd bag. |
| `unknown_bag` | Clearing a key or a bag that does not exist. |
| `permission_denied:state.write` | Writing without the manifest permission. |
| `requires_server_arbitration` | `set`/`clear` called on the client. |
| `not_requestable` | A client asked for a key no resource opted in. |
| `state_request_rate_limit` | More than 4 client requests a second from one session. |
| `state_write_rate_limit` | More than 20 000 server writes a second from one resource. |
| `state_unavailable` | The host has no bag registry (a fixture that does not replicate). |

---

