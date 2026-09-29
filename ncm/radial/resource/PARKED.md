# Parked resource (KB-182)

This is the `ncm_radial` OPEN//77 resource, moved OUT of `ncm/online/resources/` on 2026-09-28 so that
`tools/deploy-staging.ps1` cannot redeploy it. With the radial deployed, the owner's gamepad was turned into
keyboard-and-mouse from resource start and stayed that way across reconnects. The radial (this resource and the
`ncm-radial` required mod) was pulled from Online at 17:55 UTC. Do not move it back until KB-182 is understood
and a live pad test on the dev server passes.
