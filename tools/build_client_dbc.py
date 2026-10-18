#!/usr/bin/env python3
"""Build a client-side Spell.dbc that ADDS era-talents' custom VISIBLE spells (debuffs the player
must SEE on a target, e.g. the Improved Blizzard chill) on top of the base 3.3.5a client DBC, so
the client renders their icon + name. Base records/strings are kept verbatim; only new rows are
appended -- this is NOT the shelved "recreate every player spell" approach, just the handful of
custom auras the client needs to display.

Each custom row is built from tools/gen_era_talents.py's SAME field logic as the server `spell_dbc`
(helper_overrides + _row_values). Display text comes from the locale YAML entries;
SpellIconID comes from the helper's `client:` block. Building both paths from
one source keeps them in lock-step (a divergence would rubber-band the client
on any cast of that spell).

Usage:
    python3 tools/build_client_dbc.py --dataset era-data/vanilla/mage.yaml \
        --base-dbc data/client/patch/base/Spell.dbc --out /tmp/Spell.dbc
"""
from __future__ import annotations
import argparse
import pathlib
import struct
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import gen_era_talents as G   # noqa: E402

HEADER_FMT = "<4siiii"
HEADER_SIZE = struct.calcsize(HEADER_FMT)
RECORD_SIZE = 936
FIELD_COUNT = 234

COLTYPES = [ln.split()[1] for ln in
            (pathlib.Path(__file__).parent / "spell_dbc_coltypes.txt").read_text().splitlines()
            if ln.strip()]
assert len(COLTYPES) == FIELD_COUNT == len(G.COLS), (len(COLTYPES), FIELD_COUNT, len(G.COLS))
_IDX = {c: i for i, c in enumerate(G.COLS)}


class StringPool:
    """Appends new NUL-terminated strings after the base string block; offset 0 is the base block's
    mandatory empty string, reused for any empty value."""
    def __init__(self, base_block: bytes):
        self._chunks: list[bytes] = []
        self._offsets: dict[str, int] = {"": 0}
        self._next = len(base_block)

    def intern(self, value: str) -> int:
        if value in self._offsets:
            return self._offsets[value]
        off = self._next
        enc = value.encode("utf-8") + b"\x00"
        self._chunks.append(enc)
        self._offsets[value] = off
        self._next += len(enc)
        return off

    def appended(self) -> bytes:
        return b"".join(self._chunks)


def _encode_record(values: list, pool: StringPool) -> bytes:
    out = bytearray()
    for i, v in enumerate(values):
        t = COLTYPES[i]
        if t == "float":
            out += struct.pack("<f", float(v))
        elif t == "string":
            off = pool.intern(v) if isinstance(v, str) else int(v)
            out += struct.pack("<I", off & 0xFFFFFFFF)
        elif t == "signed":
            out += struct.pack("<i", int(v))
        else:  # unsigned
            out += struct.pack("<I", int(v) & 0xFFFFFFFF)
    assert len(out) == RECORD_SIZE, (len(out), RECORD_SIZE)
    return bytes(out)


def _client_rows(dataset_paths: list[str], templates: dict) -> dict[int, list]:
    """id -> full 234-value row for every helper carrying a `client:` block, across datasets. A
    helper with a `template:` clones that real record (via the SAME clone-and-override path as the
    server SQL) so cast-relevant fields — SpellVisual, cast time, attributes — match the server row
    and the client renders a real cast animation instead of the aura popping in silently."""
    rows: dict[int, list] = {}
    for p in dataset_paths:
        d = G._load(p)
        G._resolve_routed_ids(d)
        locales = {
            loc: G._load_locale(d, p, loc) for loc in ("enUS", "ruRU")
        }
        for h in d.get("helpers", []) or []:
            c = h.get("client")
            if not c:
                continue
            h = dict(h)
            key = G._spell_locale_key(h)
            en_text = locales["enUS"].get("texts", {}).get(key, {})
            h["name"] = en_text.get("serverName", en_text.get("name", ""))
            tid = h.get("template")
            tmpl = templates.get(int(tid)) if tid is not None else None
            if tid is not None and tmpl is None:
                raise SystemExit(f"helper {h['id']}: template spell {tid} not in base DBC")
            over = G.helper_overrides(h, templated=(tid is not None))
            G.apply_helper_locale(over, h, locales)
            over["SpellIconID"] = int(c.get("icon", 1))
            # Never inherit a stock WotLK aura tooltip for an era helper.
            if "auraDescription" not in en_text and tmpl is not None:
                tmpl_aura_desc = tmpl[_IDX["AuraDescription_Lang_enUS"]]
                # Authored effects overwrite all template slots; with none authored the
                # template's own effects ship wholesale, so check THOSE (a standalone
                # client-patch build doesn't run the generator lint that rejects that shape).
                if h.get("effects"):
                    applies_aura = any(int(e.get("effect", 0)) == 6 for e in h["effects"])
                else:
                    applies_aura = any(int(tmpl[_IDX[f"Effect_{i}"]]) == 6 for i in (1, 2, 3))
                if tmpl_aura_desc and applies_aura:
                    raise SystemExit(
                        f"helper {h['id']}: template {tid} has a non-empty AuraDescription "
                        f"(the buff tooltip would show the stock WotLK text) — author "
                        f"{key}.auraDescription in the locale YAML")
            rows[int(h["id"])] = G._row_values(over, tmpl)
    return rows


def _sentinel_row(stamp: str) -> list:
    """Hidden generation-canary spell. The addon reads GetSpellInfo(932999) and compares the
    stamp embedded in the NAME against the server-sent one (era_talent_meta). Passive + no
    effects: never castable, never in a spellbook; it exists only to smuggle the stamp into
    the client's Spell.dbc."""
    name = f"EraTalents Gen {stamp}"
    return G._row_values({
        "ID": G.SENTINEL_SPELL_ID, "Attributes": G.PASSIVE_ATTR,
        "CastingTimeIndex": 1, "RangeIndex": 1, "SpellIconID": 1,
        "Name_Lang_enUS": name, "Name_Lang_zhTW": name, "Name_Lang_ruRU": name,
        "Name_Lang_Mask": 16712190 | (1 << 8) | (1 << 11),
    })


def build(dataset_paths: list[str], base_dbc: pathlib.Path, out: pathlib.Path,
          stamp: str | None = None) -> int:
    raw = base_dbc.read_bytes()
    magic, rec_count, field_count, rec_size, str_size = struct.unpack(HEADER_FMT, raw[:HEADER_SIZE])
    if magic != b"WDBC" or field_count != FIELD_COUNT or rec_size != RECORD_SIZE:
        raise SystemExit(f"unexpected base DBC: magic={magic} fields={field_count} recsize={rec_size}")
    rec_start = HEADER_SIZE
    str_start = rec_start + rec_count * rec_size
    base_records = raw[rec_start:str_start]
    base_block = raw[str_start:str_start + str_size]

    # Templates for clone-and-override come from the SAME base DBC being extended (stock spells like
    # 10060/15286 live in it), so a cloned custom row stays consistent with what the client already has.
    templates = G.read_dbc_templates(base_dbc)
    custom = _client_rows(dataset_paths, templates)
    if not custom:
        raise SystemExit("no client-visible helpers (a `client:` block) found in the datasets")
    if stamp:
        custom[G.SENTINEL_SPELL_ID] = _sentinel_row(stamp)

    # Index base records by ID so a custom row REPLACES a same-id base row (idempotent: re-running
    # the merge onto an already-merged DBC updates in place instead of appending a duplicate);
    # a brand-new id is appended.
    id_off = _IDX["ID"] * 4
    recs = [base_records[i * rec_size:(i + 1) * rec_size] for i in range(rec_count)]
    pos_by_id = {struct.unpack_from("<i", rec, id_off)[0]: i for i, rec in enumerate(recs)}

    pool = StringPool(base_block)
    appended = []
    for cid, values in sorted(custom.items()):
        encoded = _encode_record(values, pool)
        if cid in pos_by_id:
            recs[pos_by_id[cid]] = encoded
        else:
            appended.append(encoded)

    new_block = base_block + pool.appended()
    total = len(recs) + len(appended)
    header = struct.pack(HEADER_FMT, b"WDBC", total, FIELD_COUNT, RECORD_SIZE, len(new_block))
    out.write_bytes(header + b"".join(recs) + b"".join(appended) + new_block)
    return len(custom)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dataset", nargs="+", required=True)
    ap.add_argument("--base-dbc", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--stamp", help="generation stamp to embed as sentinel spell 932999")
    a = ap.parse_args()
    n = build(a.dataset, pathlib.Path(a.base_dbc), pathlib.Path(a.out), a.stamp)
    print(f"wrote {a.out} (+{n} custom client spell rows)")


if __name__ == "__main__":
    main()
