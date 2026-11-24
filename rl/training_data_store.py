#!/usr/bin/env python3
"""Keep rollout training data in Supabase Storage (free tier, 1 GB).

Files go to the private bucket ``rl-training-data`` under ``<run>/<name>``;
stored LZMA-compressed (``meta.codec = "xz"``: the npz caches are only
zlib-compressed; xz makes them ~2.3x smaller, ~50 bytes per labelled
decision) and decompressed on download; one row per file in
``public.rl_training_files`` (migration
``supabase/migrations/20261119000000_rl_training_data.sql``) records run,
iteration, size, decision count and checksums. Files above the free plan's
50 MB upload limit are stored as ``<name>.partNN`` chunks and joined again on
download.

Needs the project's **secret** key (``sb_secret_...`` or the legacy
service_role JWT; the public app key cannot read the bucket):

  export SUPABASE_SECRET_KEY=sb_secret_...
  # SUPABASE_URL defaults to the tichu project

  rl/.venv/bin/python rl/training_data_store.py upload --run=v7 rl/outputs/v7/data/*.npz
  rl/.venv/bin/python rl/training_data_store.py list [--run=v7]
  rl/.venv/bin/python rl/training_data_store.py download --run=v7 --dest=rl/outputs/v7/data

``rollout_loop.py --upload-run=v7`` uploads every new data file itself. In a
cloud session whose network secrets inject the key for the Supabase host,
leave SUPABASE_SECRET_KEY unset.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import lzma
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

DEFAULT_URL = "https://fujbfizzxdxufetszvbe.supabase.co"
BUCKET = "rl-training-data"
TABLE = "rl_training_files"
PART_BYTES = 48 * 1024 * 1024  # free plan: 50 MB per uploaded object


def _base() -> str:
    return os.environ.get("SUPABASE_URL", DEFAULT_URL).rstrip("/")


def _headers(extra: dict[str, str] | None = None) -> dict[str, str]:
    h = dict(extra or {})
    key = os.environ.get("SUPABASE_SECRET_KEY") or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if key:
        h["apikey"] = key
        if key.startswith("eyJ"):  # legacy JWT keys also go in Authorization
            h["Authorization"] = f"Bearer {key}"
    return h


def _request(method: str, url: str, body: bytes | None = None, headers: dict[str, str] | None = None) -> bytes:
    req = urllib.request.Request(url, data=body, method=method, headers=_headers(headers))
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:500]
        raise RuntimeError(f"{method} {url}: HTTP {e.code} {detail}") from None


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _object_url(path: str) -> str:
    return f"{_base()}/storage/v1/object/{BUCKET}/{urllib.parse.quote(path)}"


def manifest(run: str = "") -> list[dict]:
    q = "select=*&order=run.asc,iteration.asc,path.asc"
    if run:
        q += f"&run=eq.{urllib.parse.quote(run)}"
    return json.loads(_request("GET", f"{_base()}/rest/v1/{TABLE}?{q}"))


def _npz_counts(path: Path) -> tuple[int, int]:
    try:
        import numpy as np

        with np.load(path) as d:
            starts = d["starts"]
            return int(starts.size - 1), int(starts[-1])
    except (OSError, ValueError, EOFError, KeyError, IndexError, zipfile.BadZipFile):
        # not a readable npz cache: counts unknown
        return 0, 0


def upload_file(
    path: Path,
    *,
    run: str,
    policy: Path | None = None,
    skip_existing: bool = True,
    xz: bool = True,
) -> bool:
    """Upload one file (xz-compressed, chunked if needed) and upsert its
    manifest row. ``sha256`` is the checksum of the original file.

    Returns False when an identical file is already stored.
    """
    original = path.read_bytes()
    xz = xz and not path.name.endswith((".gz", ".xz"))  # already compressed
    digest = _sha256(original)
    obj = f"{run}/{path.name}"
    old = json.loads(
        _request("GET", f"{_base()}/rest/v1/{TABLE}?select=sha256,meta&path=eq.{urllib.parse.quote(obj)}")
    )
    if skip_existing and old and digest in (
        old[0]["sha256"],
        (old[0].get("meta") or {}).get("file_sha256"),
    ) and ((old[0].get("meta") or {}).get("codec") == ("xz" if xz else None)):
        return False
    if old:  # replacing: remove the old pieces first (their count may differ)
        n_old = int((old[0].get("meta") or {}).get("parts", 1))
        _request(
            "DELETE",
            f"{_base()}/storage/v1/object/{BUCKET}",
            json.dumps({"prefixes": [obj] if n_old == 1 else [f"{obj}.part{i:02d}" for i in range(n_old)]}).encode(),
            {"Content-Type": "application/json"},
        )
    file_digest = digest
    if xz and path.suffix == ".npz":
        # The npz cache is zlib-compressed inside, which xz cannot shrink:
        # store the arrays uncompressed under xz (~2.3x smaller than the
        # cache) and rebuild the compressed cache on download.
        import io

        import numpy as np

        buf = io.BytesIO()
        with np.load(path) as d:
            np.savez(buf, **{k: d[k] for k in d.files})
        original = buf.getvalue()
        digest = _sha256(original)
    data = lzma.compress(original, preset=6) if xz else original
    parts = [data[i : i + PART_BYTES] for i in range(0, len(data), PART_BYTES)] or [b""]
    names = [obj] if len(parts) == 1 else [f"{obj}.part{i:02d}" for i in range(len(parts))]
    for name, chunk in zip(names, parts):
        _request(
            "POST",
            _object_url(name),
            chunk,
            {"Content-Type": "application/octet-stream", "x-upsert": "true"},
        )
    m = re.match(r"it(\d+)_(.+)\.npz$", path.name)
    decisions, rows_n = _npz_counts(path)
    row = {
        "path": obj,
        "run": run,
        "iteration": int(m.group(1)) if m else None,
        "kind": m.group(2) if m else path.stem,
        "decisions": decisions,
        "rows": rows_n,
        "bytes": len(data),
        "sha256": digest,
        "policy_sha256": _sha256(policy.read_bytes()) if policy and policy.exists() else None,
        "meta": {
            **({"parts": len(names)} if len(names) > 1 else {}),
            **({"codec": "xz", "original_bytes": len(original), "file_sha256": file_digest} if xz else {}),
        },
    }
    _request(
        "POST",
        f"{_base()}/rest/v1/{TABLE}",
        json.dumps(row).encode(),
        {"Content-Type": "application/json", "Prefer": "resolution=merge-duplicates,return=minimal"},
    )
    print(
        f"   uploaded {obj} ({len(data) / 1e6:.1f} MB stored, {len(original) / 1e6:.1f} MB original, "
        f"{decisions} decisions)",
        flush=True,
    )
    return True


def delete_run(run: str) -> int:
    """Delete every stored object of ``run`` (incl. multi-part pieces) and
    its manifest rows. Returns the number of manifest rows removed."""
    rows = manifest(run)
    names = []
    for r in rows:
        parts = int((r.get("meta") or {}).get("parts", 1))
        names += [r["path"]] if parts == 1 else [f"{r['path']}.part{i:02d}" for i in range(parts)]
    for i in range(0, len(names), 100):
        _request(
            "DELETE",
            f"{_base()}/storage/v1/object/{BUCKET}",
            json.dumps({"prefixes": names[i : i + 100]}).encode(),
            {"Content-Type": "application/json"},
        )
    _request("DELETE", f"{_base()}/rest/v1/{TABLE}?run=eq.{urllib.parse.quote(run)}")
    print(f"deleted run {run}: {len(rows)} files ({len(names)} objects)")
    return len(rows)


def download(run: str, dest: Path, *, overwrite: bool = False) -> list[Path]:
    dest.mkdir(parents=True, exist_ok=True)
    out = []
    for row in manifest(run):
        target = dest / Path(row["path"]).name
        out.append(target)
        if target.exists() and not overwrite and (
            (row.get("meta") or {}).get("codec") == "xz"
            or _sha256(target.read_bytes()) == row["sha256"]
        ):
            continue
        n = int((row.get("meta") or {}).get("parts", 1))
        names = [row["path"]] if n == 1 else [f"{row['path']}.part{i:02d}" for i in range(n)]
        data = b"".join(_request("GET", _object_url(name)) for name in names)
        meta = row.get("meta") or {}
        if meta.get("codec") == "xz":
            data = lzma.decompress(data)
        if _sha256(data) != row["sha256"]:
            raise RuntimeError(f"checksum mismatch for {row['path']}")
        tmp = target.with_suffix(target.suffix + ".tmp")
        if meta.get("codec") == "xz" and target.suffix == ".npz":
            import io

            import numpy as np

            with np.load(io.BytesIO(data)) as d:
                with tmp.open("wb") as fh:
                    np.savez_compressed(fh, **{k: d[k] for k in d.files})
        else:
            tmp.write_bytes(data)
        tmp.rename(target)
        print(f"   downloaded {target} ({len(data) / 1e6:.1f} MB)", flush=True)
    return out


def main() -> None:
    p = argparse.ArgumentParser(description="RL training data in Supabase Storage")
    sub = p.add_subparsers(dest="cmd", required=True)
    up = sub.add_parser("upload")
    up.add_argument("--run", required=True)
    up.add_argument("--policy", default="", help="play net that generated the data (checksum only)")
    up.add_argument("--force", action="store_true", help="re-upload identical files")
    up.add_argument("files", nargs="+")
    ls = sub.add_parser("list")
    ls.add_argument("--run", default="")
    rm = sub.add_parser("delete", help="delete every file of a run")
    rm.add_argument("--run", required=True)
    dl = sub.add_parser("download")
    dl.add_argument("--run", required=True)
    dl.add_argument("--dest", required=True)
    dl.add_argument("--overwrite", action="store_true")
    args = p.parse_args()

    if args.cmd == "upload":
        policy = Path(args.policy) if args.policy else None
        for f in args.files:
            if not upload_file(Path(f), run=args.run, policy=policy, skip_existing=not args.force):
                print(f"   {f}: already stored", flush=True)
    elif args.cmd == "delete":
        delete_run(args.run)
    elif args.cmd == "list":
        rows = manifest(args.run)
        total = sum(r["bytes"] for r in rows)
        for r in rows:
            print(f"{r['path']:40s} it={r['iteration']!s:>3} {r['decisions']:8d} dec {r['bytes'] / 1e6:7.1f} MB")
        print(f"{len(rows)} files, {total / 1e6:.1f} MB (free plan: 1000 MB)")
    else:
        download(args.run, Path(args.dest), overwrite=args.overwrite)


if __name__ == "__main__":
    sys.exit(main())
