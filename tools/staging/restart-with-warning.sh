#!/usr/bin/env bash
# Restart staging with a broadcast countdown (L86). Run ON the box.
#   bash restart-with-warning.sh [seconds]      default 60
#
# L86: a reset is announced and counted down; players are never dropped without warning. KB-5 still stands --
# prefer restarting with nobody connected -- but when a restart must happen anyway, this is how.
#
# Order matters: the announce must go out BEFORE the sleep, from Warden's Live Console:
#     ncm.restart 60
# then run this with the same number. NCM cannot restart its own host, so the countdown and the restart are two
# halves that have to be started together. IDEA-130 tracks closing that seam.
set -euo pipefail
SECS="${1:-60}"

echo "players connected right now:"
grep -E 'ncm_world\] (connected|disconnected)' /opt/ncm/logs/server.log | tail -n 5 || true
echo
echo "Run this in Warden's Live Console NOW, then leave this running:"
echo "    ncm.restart ${SECS}"
echo
read -r -p "announced? press enter to start the ${SECS}s countdown, ctrl-c to abort " _ || true

for t in $(seq "${SECS}" -10 10); do
  echo "  restarting in ${t}s"
  sleep 10
done
echo "restarting now"
sudo systemctl restart ncm-server
echo "waiting for the service to come back (stop timeout is ~90s)"
until [ "$(systemctl is-active ncm-server)" = "active" ]; do sleep 5; done
sleep 20
grep -E 'scheduler started: [0-9]+ series' /opt/ncm/logs/server.log | tail -n 1 || echo "WARNING: no scheduler line - check the boot log"
