-- ncm_paddock / server / wallet -- player money through the ledger, the way Economy v1 moves it.
--
-- The ledger is the only balance truth (L84). Every debit is serialized per driver by the `economy_balance_lock`
-- row protocol of `NcmEconomy.withBalanceLocks` (ncm_league/server/economy.lua), restated here because this is
-- another VM. `tools/test-paddock-host.lua` holds the two statement shapes equal. Idempotency is the ledger's
-- unique `idem_key`: a retried credit is a no-op, never a second payment.
PaddockWallet = {}

local U = PaddockUtil

function PaddockWallet.balance(driverId)
    if not driverId then return 0 end
    return tonumber(MySQL.scalar.await("SELECT COALESCE(SUM(amount),0) FROM ledger WHERE ncm_driver_id=? AND server_id=?",
        { driverId, U.sid() })) or 0
end

--- Prefix `tx` with the balance-lock rows for `driverIds` (sorted, deduplicated): identical to economy.lua.
function PaddockWallet.withBalanceLocks(tx, driverIds)
    local seen, ordered = {}, {}
    for _, driverId in ipairs(driverIds or {}) do
        if type(driverId) == "string" and driverId ~= "" and not seen[driverId] then seen[driverId] = true; ordered[#ordered + 1] = driverId end
    end
    table.sort(ordered)
    local out = {}
    for _, driverId in ipairs(ordered) do
        out[#out + 1] = { query = "INSERT IGNORE INTO economy_balance_lock (server_id,ncm_driver_id,revision) VALUES (?,?,0)", values = { U.sid(), driverId } }
    end
    for _, driverId in ipairs(ordered) do
        out[#out + 1] = { query = "UPDATE economy_balance_lock SET revision=revision+1 WHERE server_id=? AND ncm_driver_id=?", values = { U.sid(), driverId } }
    end
    for _, step in ipairs(tx or {}) do out[#out + 1] = step end
    return out
end

--- A ledger row that is written only when the driver can afford `-amount` (a debit), guarded by the balance lock.
function PaddockWallet.debitStep(driverId, kind, amount, idem, ref, note)
    return { query = [[INSERT IGNORE INTO ledger (ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key)
        SELECT ?,?,?,?,'eddies',?,?,? FROM DUAL
        WHERE (SELECT COALESCE(SUM(amount),0) FROM ledger WHERE ncm_driver_id=? AND server_id=?) >= ?]],
        values = { driverId, U.sid(), kind, -math.abs(amount), ref or "", note or "", idem, driverId, U.sid(), math.abs(amount) } }
end

function PaddockWallet.creditStep(driverId, kind, amount, idem, ref, note)
    return { query = [[INSERT IGNORE INTO ledger (ncm_driver_id,server_id,kind,amount,currency,ref,note,idem_key)
        VALUES (?,?,?,?,'eddies',?,?,?)]],
        values = { driverId, U.sid(), kind, math.abs(amount), ref or "", note or "", idem } }
end

--- True when a ledger row with this idem key exists (the debit actually landed).
function PaddockWallet.landed(idem)
    return (tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM ledger WHERE idem_key=?", { idem })) or 0) > 0
end
