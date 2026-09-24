# NCM apparel — first slice and durable direction

**Status:** starter clothing built locally; entitlement/store/mod integration designed, not implemented.
**Constraint:** economy remains held by L85. No apparel price, purchase, resale or paid upgrade is active.

## 1. The split of authority

OPEN//77 already solves the hard visual problem. `open77_appearance` owns the authenticated character and the
durable `open77_character_presentation` row; `open77_equipment` attaches and replicates worn records;
`open77_wardrobe` applies seven visual overlays; `open77_wardrobe_ui` previews and commits changes with revision
checks. NCM must not duplicate or directly edit those records.

NCM will own **entitlement**: which apparel a driver has been issued, earned, bought, found or otherwise unlocked.
An entitlement permits selection; OPEN//77 remains the authority for what is currently visible.

```text
race / shop / find / sponsor
            |
            v
    NCM apparel entitlement  ---- future eligibility/effect evaluation
            |
            v
    approved equip request
            |
            v
 OPEN//77 presentation record ---- attachment, persistence, replication
```

The wardrobe is not a wallet, and the ownership ledger is not an attachment system.

## 2. Slice 1 — nobody arrives half-dressed

`ncm_world/client/apparel.lua` listens for OPEN//77's authoritative `open77:equipment:self` snapshot. Once per
client session, it fills only missing everyday slots:

| Slot | Starter record |
|---|---|
| InnerChest | `Items.Q000_StreetKid_TShirt` |
| Legs | `Items.Q000_StreetKid_Pants` |
| Feet | `Items.Q000_StreetKid_Shoes` |

All three records are in the build-pinned 2.31 catalogue, selectable for both body families. Requests go through
the platform's existing `open77:equipment:slot` validation and persistence path. Existing saved values are never
replaced. Head, face, outerwear, full-body outfit and underwear choices are untouched.

This is intentionally a presentation default, not yet an NCM-owned reward. Live proof must cover a fresh/empty
presentation, a returning dressed character, persistence after reconnect, and visibility from a second client.

## 3. The entitlement record

The next data slice should add an NCM-owned row keyed by driver and stable apparel identity. It should not store
the currently equipped slot.

```text
owned_apparel
  apparel_id          stable NCM content id
  ncm_driver_id
  item_record         OPEN//77/TweakDB clothing record
  source_kind         starter | race_reward | achievement | purchase | world_find | sponsor | admin
  source_ref          event, achievement, store offer, find, sponsor contract, etc.
  acquired_at
  variant             optional visual variant
  grade               optional future progression tier; starts at 0
  metadata_json       bounded provenance/content metadata, never arbitrary effects
  UNIQUE(ncm_driver_id, apparel_id)
```

Every acquisition path calls one idempotent grant operation. A store adds a ledger debit and entitlement in one
transaction only after L85's idempotency migration. A find or reward creates the same entitlement without money.

## 4. Earned, bought and found

- **Issued:** starter street clothes, team racewear, event-mandated safety gear. Zero-cost and non-resellable where
  fiction says it belongs to the team or organiser.
- **Earned:** championship placement, badge tier, clean-driving milestone, special event souvenir. The settlement or
  accomplishment reference is the idempotency key.
- **Bought:** an authored store offer debits NCM eddies and grants the entitlement atomically. Freeroam money never
  participates (L84).
- **Found:** a server-authored world pickup or discovery grants once by stable find ID. The client may detect the
  interaction; the server decides and persists it.
- **Sponsored:** temporary or permanent issue tied to a team/contract. Temporary gear needs an expiry/revocation
  policy before it exists; do not fake ownership by deleting presentation rows.

The stock wardrobe currently exposes the whole base-game catalogue. That is useful as an alpha fitting room but it
cannot enforce NCM ownership. A later NCM closet must show only entitlements, or OPEN//77 must add an allowlist/filter
hook to its wardrobe UI. Until then, ownership can be recorded and rewarded but not honestly enforced as scarcity.

## 5. Upgrade paths and effects

Apparel progression should begin with identity and access, not unexplained driving stats.

Safe first effects:

- visual variant or prestige tier;
- Driver Card / paddock identity and collection completion;
- access requirement for sanctioned sessions or team presentation (helmet/suit supplied if mandatory);
- sponsor, team or achievement affiliation;
- bounded reputation or dialogue tags when those systems exist.

Not approved:

- top speed, grip, acceleration or handling bonuses from clothing;
- client-asserted protection or economy modifiers;
- arbitrary effect scripts embedded in apparel metadata;
- upgrades that silently replace a driver's chosen visual item.

If protective gear later affects injury/damage rules, the server evaluates a declared apparel capability from the
entitlement catalogue at session entry. The clothing record itself never becomes trusted game logic.

An “upgrade” may unlock another visual variant or capability tier while retaining provenance. Whether that mutates
one entitlement or grants a new apparel ID remains open until the first real upgrade family is authored.

## 6. Modded racing gear

The desired racing suits, helmets and other Nexus apparel are inert content in principle: archives plus
ArchiveXL/TweakXL records. Four independent gates apply:

1. **Rights:** inspect each mod's permission and obtain author consent where redistribution is not explicitly
   allowed. Attribution and dependency terms travel with the item.
2. **Delivery:** KB-8 still blocks reliable hosted required mods. TW1 can install approved content manually, but a
   public apparel economy cannot sell or award an asset the launcher cannot guarantee is installed.
3. **Stable records:** every item/variant needs an immutable NCM apparel ID mapped to an exact TweakDB record and
   content-package version.
4. **Platform catalogue registration:** the build-pinned wardrobe validates against its static audited catalogue.
   There is no discovered public server API for registering a custom clothing record or filtering the menu by an
   NCM entitlement set. Custom clothes will be rejected until OPEN//77 exposes an extension hook or the platform
   formally adopts those records.

Do not patch the platform's private `PresentationCatalog` table from NCM or depend on internal resource VM state.
The concrete platform request is a server-owned clothing-catalogue registration API plus an optional per-player
selection filter/provider.

## 7. Next slices

1. Live-validate starter clothing.
2. Catalogue the desired racing-gear mods: record IDs, body-family coverage, slot, variants, dependencies, rights.
3. Ask OPEN//77 for catalogue registration and entitlement filtering; verify against build-pinned cards when it
   lands.
4. Add the idempotent `owned_apparel` grant/read API and NCM closet, initially with zero-price/base-game rewards.
5. After L85 lifts, add atomic store purchases and authored prices.
6. Only then design the first upgrade family and any server-evaluated effect.

