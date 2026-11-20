#!/usr/bin/env python3
import json
import os
import statistics
import sys
import time
from datetime import datetime, timezone
from urllib.parse import urlparse
import requests

DEFAULT_URLS = [
    "https://deepen-landing-carnival.ngrok-free.dev/health",
    "https://wetv.rtafmith.kdns.fr/",
    "https://cck.trueth.kdns.fr/",
    "https://app.rtafmith.kdns.fr/",
    "https://www.rtafmith.kdns.fr/",
    "https://apps.rtafmith.kdns.fr/",
    "https://m.rtafmith.kdns.fr/",
    "https://th.opentwitter.de5.net/",
]


def _extract_urls_from_obj(obj) -> list[str]:
    found = []
    if isinstance(obj, str) and obj.startswith(("http://", "https://")):
        found.append(obj.strip())
    elif isinstance(obj, list):
        for item in obj:
            found.extend(_extract_urls_from_obj(item))
    elif isinstance(obj, dict):
        for k in ("url", "target_url", "destination", "domain", "hostname"):
            val = obj.get(k)
            if isinstance(val, str) and val.strip():
                v = val.strip()
                if not v.startswith(("http://", "https://")):
                    v = f"https://{v}"
                found.append(v)
        for v in obj.values():
            if isinstance(v, (dict, list)):
                found.extend(_extract_urls_from_obj(v))
    return found


def load_urls() -> list[str]:
    urls: list[str] = []

    # 1. CLI arguments
    if len(sys.argv) > 1:
        urls.extend([u.strip() for u in sys.argv[1:] if u.strip()])

    # 2. EDGE_URLS env (comma or newline separated)
    env_urls = os.environ.get("EDGE_URLS", "").strip()
    if env_urls:
        urls.extend([u.strip() for u in env_urls.replace("\n", ",").split(",") if u.strip()])

    # 3. Optional JSON or TXT file (e.g., urls.json or /tmp/redirect_pizza.json)
    urls_file = os.environ.get("EDGE_URLS_FILE", "").strip()
    if urls_file and os.path.exists(urls_file):
        with open(urls_file, "r", encoding="utf-8") as f:
            raw = f.read().strip()
        if raw:
            try:
                parsed = json.loads(raw)
                urls.extend(_extract_urls_from_obj(parsed))
            except json.JSONDecodeError:
                for line in raw.splitlines():
                    line = line.strip()
                    if line and not line.startswith("#"):
                        if not line.startswith(("http://", "https://")):
                            line = f"https://{line}"
                        urls.append(line)

    if not urls:
        urls = list(DEFAULT_URLS)

    # Deduplicate while preserving order
    seen = set()
    unique_urls = []
    for u in urls:
        if u not in seen:
            seen.add(u)
            unique_urls.append(u)
    return unique_urls


def measure_once(url: str, timeout: float = 10.0, extra_headers: dict | None = None) -> dict:
    headers = {"User-Agent": "GitHubEdgeBenchmark/2.0"}
    if extra_headers:
        headers.update(extra_headers)

    t0 = time.perf_counter()
    try:
        resp = requests.get(
            url,
            headers=headers,
            timeout=timeout,
            allow_redirects=False,
            stream=True,
        )
        t_first_byte = time.perf_counter()
        _ = resp.content
        t_end = time.perf_counter()

        return {
            "ok": True,
            "status": resp.status_code,
            "ttfb_ms": round((t_first_byte - t0) * 1000.0, 2),
            "total_ms": round((t_end - t0) * 1000.0, 2),
            "error": None,
        }
    except Exception as exc:
        t_end = time.perf_counter()
        return {
            "ok": False,
            "status": None,
            "ttfb_ms": None,
            "total_ms": round((t_end - t0) * 1000.0, 2),
            "error": str(exc),
        }


def benchmark_url(url: str, runs: int = 3, timeout: float = 10.0, extra_headers: dict | None = None) -> dict:
    # Warm-up request
    _ = measure_once(url, timeout=timeout, extra_headers=extra_headers)

    samples = [measure_once(url, timeout=timeout, extra_headers=extra_headers) for _ in range(runs)]
    ok_samples = [s for s in samples if s["ok"]]

    if not ok_samples:
        last_err = samples[-1]["error"] if samples else "Unknown error"
        return {
            "url": url,
            "host": urlparse(url).netloc,
            "reachable": False,
            "status": None,
            "avg_ttfb_ms": None,
            "avg_total_ms": None,
            "min_total_ms": None,
            "success_rate": f"0/{runs}",
            "error": last_err,
        }

    statuses = sorted({str(s["status"]) for s in ok_samples})
    return {
        "url": url,
        "host": urlparse(url).netloc,
        "reachable": True,
        "status": ",".join(statuses),
        "avg_ttfb_ms": round(statistics.mean(s["ttfb_ms"] for s in ok_samples), 2),
        "avg_total_ms": round(statistics.mean(s["total_ms"] for s in ok_samples), 2),
        "min_total_ms": round(min(s["total_ms"] for s in ok_samples), 2),
        "success_rate": f"{len(ok_samples)}/{runs}",
        "error": None,
    }


def write_outputs(ranked: list[dict], fastest: dict | None,

