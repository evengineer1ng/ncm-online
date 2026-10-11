"""Fact sources: where canonical rows come from.

    MySqlSource    the dev server's MariaDB directly (pymysql), read-only SELECTs
    SshSource      NCM Online: the same SELECTs through `ssh <host> sudo mariadb <db> -B -e ...` (read-only)
    FixtureSource  a JSONL replay of rows in the SAME table shapes (tests, demos, offline); every fact it yields is
                   sourced 'fixture:<table>' so a trace can never mistake it for the canonical world

All three yield (table, rows) batches into normalize.Normalizer. Nothing here writes to NCM.
Cursors live in the Chronicle so a restart resumes where it stopped.
"""
from __future__ import annotations

import json
import re
import subprocess
import time
from typing import Any, Dict, Iterable, List, Optional, Tuple

Batch = Tuple[str, List[Dict[str, Any]]]


def _lit(v: Any) -> str:
    if v is None:
        return "NULL"
    if isinstance(v, (int, float)):
        return repr(v)
    return "'" + str(v).replace("\\", "\\\\").replace("'", "''") + "'"


class SqlSource:
    """The canonical reads. `q(sql, params)` is supplied by the transport."""

    poll_interval = 2.0

    def __init__(self, tape: str, player_driver_ids: Iterable[str], chronicle, lookback_s: int = 6 * 3600):
        self.tape = tape
        self.drivers = [d for d in player_driver_ids if d]
        self.chron = chronicle
        self.lookback_s = lookback_s
        self.names_at = 0.0
        self.live_races: Dict[str, float] = {}
        self.warmed = False

    def q(self, sql: str, params: Tuple) -> List[Dict[str, Any]]:
        raise NotImplementedError

    def _cur(self, key: str, default):
        return self.chron.cursor(self.prefix + key, default)

    def _set(self, key: str, value):
        self.chron.set_cursor(self.prefix + key, value)

    prefix = ""

    def poll(self, now: float) -> List[Batch]:
        out: List[Batch] = []
        sid = self.tape
        since = now - self.lookback_s
        if now - self.names_at > 600:
            out.append(("paddock_person", self.q("SELECT person_id, display FROM paddock_person WHERE server_id=%s", (sid,))))
            out.append(("paddock_series", self.q("SELECT series_id, name FROM paddock_series WHERE server_id=%s", (sid,))))
            self.names_at = now
        out.append(("racing_week_run", self.q("SELECT * FROM racing_week_run WHERE server_id=%s ORDER BY run_index", (sid,))))
        for table, col, key in (("racing_week_event", "at", "ref"), ("racing_week_moody", "at", "roll_n"),
                                ("racing_week_verdict", "at", "boundary_h"), ("paddock_event", "at", "event_id"),
                                ("paddock_news", "at", "story_id"), ("chrome_event", "occurred_at", "event_id")):
            c = self._cur(table, since)
            if not self.warmed:
                c = min(c, now - 3600)    # first poll: refill the last hour for the pulse's digest (`seen` stops re-speech)
            extra = " AND (kind='step' OR ref LIKE 'radio:%%')" if table == "racing_week_event" else ""
            rows = self.q(f"SELECT * FROM {table} WHERE server_id=%s AND {col} >= %s{extra} ORDER BY {col} LIMIT 500",
                          (sid, int(c)))
            if rows:
                last = max(_secs(r.get(col)) for r in rows)
                self._set(table, last)        # >= with the Chronicle's `seen` dedup: nothing lost on equal timestamps
            out.append((table, rows))
        self.warmed = True
        if self.drivers:
            ph = ",".join(["%s"] * len(self.drivers))
            c = self._cur("paddock_entry", since)
            entries = self.q(f"SELECT * FROM paddock_entry WHERE server_id=%s AND ncm_driver_id IN ({ph}) AND entered_at >= %s",
                             (sid, *self.drivers, c))
            out.append(("paddock_entry", entries))
            for e in entries:
                self.live_races[str(e["race_id"])] = now
            c = self._cur("paddock_result", since)
            res = self.q(f"""SELECT r.* FROM paddock_result r WHERE r.server_id=%s AND r.race_id IN (
                    SELECT race_id FROM paddock_entry WHERE server_id=%s AND ncm_driver_id IN ({ph}))
                    AND r.race_id IN (SELECT race_id FROM paddock_result WHERE server_id=%s AND at >= %s)""",
                         (sid, sid, *self.drivers, sid, c))
            if res:
                self._set("paddock_result", max(_secs(r.get("at")) for r in res))
            out.append(("paddock_result", res))
            # live crossings carry no wall time: poll the player's recent races and diff (the normalizer dedups)
            for race, seen_at in list(self.live_races.items()):
                if now - seen_at > 3 * 3600:
                    del self.live_races[race]
                    continue
                rows = self.q("SELECT * FROM paddock_live_crossing WHERE server_id=%s AND race_id=%s", (sid, race))
                for r in rows:
                    r.setdefault("at", int(now))
                out.append(("paddock_live_crossing", rows))
        return out


def _secs(v: Any) -> float:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return 0.0
    return x / 1000.0 if x > 1e11 else x


class MySqlSource(SqlSource):
    prefix = "mysql:"

    def __init__(self, dsn: Dict[str, Any], *a, **kw):
        super().__init__(*a, **kw)
        import pymysql
        self.conn = pymysql.connect(cursorclass=pymysql.cursors.DictCursor, autocommit=True, charset="utf8mb4", **dsn)

    def q(self, sql, params):
        with self.conn.cursor() as c:
            c.execute(sql, params)
            return list(c.fetchall())


class SshSource(SqlSource):
    """One persistent `ssh <host> sudo mariadb <db> -B` session, read-only, queries over stdin.

    Each query is followed by a sentinel SELECT; the reader collects lines until the sentinel. A failed or silent
    session (60 s) is killed and reopened on the next query. The session starts with READ ONLY, so a mistake in this
    file cannot write to NCM's database.
    """
    prefix = "ssh:"
    poll_interval = 5.0

    def __init__(self, ssh: List[str], database: str, *a, **kw):
        super().__init__(*a, **kw)
        self.ssh = ssh
        self.database = database
        self.proc = None
        self.lines = None
        self.n = 0

    def _open(self):
        import queue
        import threading
        self.close()
        self.proc = subprocess.Popen(self.ssh + [f"sudo mariadb {self.database} -B --unbuffered"],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                     text=True, encoding="utf-8", bufsize=1)
        self.lines = queue.Queue()
        proc, lines = self.proc, self.lines

        def pump(stream, tag):
            for ln in stream:
                lines.put((tag, ln.rstrip("\r\n")))
            lines.put((tag, None))
        threading.Thread(target=pump, args=(proc.stdout, "out"), daemon=True).start()
        threading.Thread(target=pump, args=(proc.stderr, "err"), daemon=True).start()
        self._send("SET SESSION TRANSACTION READ ONLY")

    def close(self):
        if self.proc:
            try:
                self.proc.kill()
            except OSError:
                pass
        self.proc = None

    def _send(self, text: str) -> List[str]:
        import queue
        self.n += 1
        tag = f"NCC_END_{self.n}"
        self.proc.stdin.write(text.rstrip(";") + f";\nSELECT '{tag}' AS ncc_end;\n")
        self.proc.stdin.flush()
        out: List[str] = []
        while True:
            try:
                kind, ln = self.lines.get(timeout=60)
            except queue.Empty:
                self.close()
                raise RuntimeError("ssh/mariadb session silent for 60 s; reopening on the next query")
            if kind == "err":
                if ln is None:
                    continue
                msg = [ln]
                end = time.time() + 1.0          # batch mode prints the statement first; the ERROR line follows
                while time.time() < end and not any(m.startswith("ERROR") for m in msg):
                    try:
                        msg.append(self.lines.get(timeout=0.2)[1] or "")
                    except queue.Empty:
                        pass
                self.close()
                err = next((m for m in msg if m.startswith("ERROR")), " ".join(msg))
                raise RuntimeError("mariadb: " + err[:300])
            if ln is None:
                self.close()
                raise RuntimeError("ssh session closed")
            if ln == tag:
                return out[:-1] if out and out[-1] == "ncc_end" else out
            out.append(ln)

    def q(self, sql, params):
        parts = sql.split("%s")
        text = parts[0] + "".join(_lit(p) + s for p, s in zip(params, parts[1:]))
        text = " ".join(text.split())
        if self.proc is None or self.proc.poll() is not None:
            self._open()
        lines = self._send(text)
        if not lines:
            return []
        head = lines[0].split("\t")
        rows = []
        for ln in lines[1:]:
            vals = [None if v == "NULL" else v.replace("\\n", "\n").replace("\\t", "\t") for v in ln.split("\t")]
            rows.append(dict(zip(head, vals)))
        return rows


class FixtureSource:
    """Replays `{"t": <s from start>, "table": ..., "row": {...}}` lines. Values like "@+90" are times relative to
    the replay's start (unix seconds), so a fixture is always 'now'."""

    poll_interval = 0.25
    prefix = "fixture:"

    def __init__(self, path: str, speed: float = 1.0, start: Optional[float] = None):
        self.items = []
        with open(path, encoding="utf-8") as f:
            for ln in f:
                ln = ln.strip()
                if ln and not ln.startswith("//"):
                    self.items.append(json.loads(ln))
        self.items.sort(key=lambda d: d["t"])
        self.speed = speed
        self.wall0 = time.time()
        self.base = start if start is not None else self.wall0
        self.i = 0

    def clock(self) -> float:
        return self.base + (time.time() - self.wall0) * self.speed

    def done(self) -> bool:
        return self.i >= len(self.items)

    def _resolve(self, v):
        if isinstance(v, str):
            m = re.fullmatch(r"@([+-]?\d+(?:\.\d+)?)", v)
            if m:
                return int(self.base + float(m.group(1)))
        if isinstance(v, dict):
            return {k: self._resolve(x) for k, x in v.items()}
        return v

    def poll(self, now: float) -> List[Batch]:
        out: List[Batch] = []
        elapsed = now - self.base
        while self.i < len(self.items) and self.items[self.i]["t"] <= elapsed:
            it = self.items[self.i]
            self.i += 1
            row = self._resolve(it["row"])
            for k in ("facts", "entities", "cause_refs", "data_json", "state_json"):
                if k in row and not isinstance(row[k], str):
                    row[k] = json.dumps(row[k])
            if out and out[-1][0] == it["table"]:
                out[-1][1].append(row)
            else:
                out.append((it["table"], [row]))
        return out
