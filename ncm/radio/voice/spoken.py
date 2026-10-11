"""Spoken forms of the finite slot domains (doc 59 §4).

The director (Lua, `ncm_radio/server/spoken.lua`) turns a fact into exactly these strings, and the render tool voices
exactly these strings, so a clip key is the same on both sides. `tests/spoken_cases.lua` is written from `cases()`
and the Lua test asserts the director agrees with every case.
"""
import re

ONES = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve',
        'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen']
TENS = ['', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', 'eighty', 'ninety']
ORD = {'one': 'first', 'two': 'second', 'three': 'third', 'five': 'fifth', 'eight': 'eighth', 'nine': 'ninth',
       'twelve': 'twelfth', 'twenty': 'twentieth', 'thirty': 'thirtieth', 'forty': 'fortieth'}
NUMBER_MAX = 99
ORDINAL_MAX = 40


def number(n):
    n = int(n)
    if n < 0 or n > NUMBER_MAX:
        return None
    if n < 20:
        return ONES[n]
    t, o = divmod(n, 10)
    return TENS[t] + ('' if o == 0 else '-' + ONES[o])


def ordinal(n):
    n = int(n)
    if n < 1 or n > ORDINAL_MAX:
        return None
    w = number(n)
    head, sep, last = w.rpartition('-')
    if last in ORD:
        last = ORD[last]
    elif last.endswith('y'):
        last = last[:-1] + 'ieth'
    else:
        last = last + 'th'
    return head + sep + last


def day(n):
    w = number(n)
    return None if w is None or n < 1 else 'Day ' + w.capitalize()


def margin(seconds):
    """A finishing gap as a broadcaster says it: tenths under two seconds, halves under ten, whole seconds to a minute."""
    s = float(seconds)
    if s < 0:
        return None
    if s < 0.05:
        return 'less than a tenth of a second'
    if s < 1.95:
        tenths = int(round(s * 10))
        if tenths < 10:
            return ('one tenth' if tenths == 1 else number(tenths) + ' tenths') + ' of a second'
        whole, frac = divmod(tenths, 10)
        if frac == 0:
            return 'one second' if whole == 1 else number(whole) + ' seconds'
        return number(whole) + ' point ' + number(frac) + ' seconds'
    if s < 9.75:
        halves = int(round(s * 2))
        whole, half = divmod(halves, 2)
        return number(whole) + (' and a half seconds' if half else ' seconds')
    if s < 59.5:
        return number(int(round(s))) + ' seconds'
    return 'more than a minute'


def clock(hour, minute):
    """A wall-clock time in Night City (US-Eastern, the Paddock's clock), to the quarter hour."""
    h, m = int(hour) % 24, int(minute)
    q = int(round(m / 15.0)) * 15
    if q == 60:
        h, q = (h + 1) % 24, 0
    if h == 0 and q == 0:
        return 'midnight'
    if h == 12 and q == 0:
        return 'noon'
    h12 = h % 12 or 12
    head = number(h12)
    if q == 0:
        tail = " o'clock"
    elif q == 15:
        tail = ' fifteen'
    elif q == 30:
        tail = ' thirty'
    else:
        tail = ' forty-five'
    return head + tail + (' in the morning' if h < 12 else ' in the afternoon' if h < 18 else ' at night')


def odds(price):
    """Billie's decimal price as fractional-style radio odds (price 6.0 -> 'five to one')."""
    p = float(price)
    if p < 1.05:
        return None
    against = p - 1.0
    if against < 1.0:
        n = int(round(1.0 / against))
        if n > 20:
            return None
        return 'even money' if n <= 1 else number(n) + ' to one on'
    if against < 3.0:
        halves = int(round(against * 2))
        if halves % 2 == 1:
            return number(halves) + ' to two'
        return 'even money' if halves == 2 else number(halves // 2) + ' to one'
    n = int(round(against))
    return None if n > NUMBER_MAX else number(n) + ' to one'


def slug(text):
    return re.sub(r'[^a-z0-9]+', '-', text.lower()).strip('-')


def builtin_domains():
    """Every value of every finite built-in class, spoken."""
    out = {'number': [number(n) for n in range(0, NUMBER_MAX + 1)],
           'ordinal': [ordinal(n) for n in range(1, ORDINAL_MAX + 1)],
           'day': [day(n) for n in range(1, 15)],
           'margin': sorted({margin(x / 100.0) for x in range(0, 6000, 1)} | {'more than a minute'}),
           'clock': sorted({clock(h, m) for h in range(24) for m in (0, 15, 30, 45)}),
           'odds': sorted({o for o in (odds(1.0 + x / 20.0) for x in range(1, 2000)) if o})}
    return out


def cases():
    """Fixed probes the Lua side must reproduce."""
    c = []
    for n in (0, 1, 7, 13, 20, 21, 42, 99):
        c.append(['number', n, number(n)])
    for n in (1, 2, 3, 4, 11, 12, 20, 21, 22, 23, 30, 40):
        c.append(['ordinal', n, ordinal(n)])
    for n in (1, 2, 7):
        c.append(['day', n, day(n)])
    for s in (0.01, 0.04, 0.1, 0.42, 0.95, 1.0, 1.04, 1.37, 1.96, 2.2, 3.74, 9.8, 12.4, 59.4, 75):
        c.append(['margin', s, margin(s)])
    for hm in ((0, 0), (0, 7), (9, 14), (12, 0), (13, 30), (18, 45), (23, 53)):
        c.append(['clock', list(hm), clock(*hm)])
    for p in (1.5, 2.0, 2.4, 6.0, 12.75, 1.25):
        c.append(['odds', p, odds(p)])
    return c
