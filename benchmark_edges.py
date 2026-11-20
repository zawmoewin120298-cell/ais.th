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


def write_outputs(ranked: list[dict], fastest: dict | None, json_out: str, md_out: str) -> None:
    generated_at = datetime.now(timezone.utc).isoformat()
    payload = {
        "generated_at": generated_at,
        "fastest": fastest,
        "results": ranked,
    }
    if json_out:
        os.makedirs(os.path.dirname(os.path.abspath(json_out)), exist_ok=True)
        with open(json_out, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=False)

    if md_out:
        os.makedirs(os.path.dirname(os.path.abspath(md_out)), exist_ok=True)
        lines = [
            "# Edge Route Benchmark Report",
            "",
            f"- **Generated (UTC):** `{generated_at}`",
            f"- **Fastest Route:** `{fastest['url']}` ({fastest['avg_total_ms']} ms, HTTP `{fastest['status']}`)"
            if fastest
            else "- **Fastest Route:** None",
            "",
            "| Rank | Status | Avg TTFB | Avg Total | Min Total | Success | Route |",
            "|---:|:---|---:|---:|---:|:---|:---|",
        ]
        for idx, r in enumerate(ranked, start=1):
            if r["reachable"]:
                lines.append(
                    f"| #{idx} | `{r['status']}` | {r['avg_ttfb_ms']} ms | {r['avg_total_ms']} ms | "
                    f"{r['min_total_ms']} ms | {r['success_rate']} | `{r['url']}` |"
                )
            else:
                err_msg = (r["error"] or "Failed").replace("|", "/")[:60]
                lines.append(
                    f"| #{idx} | `ERR` | - | - | - | {r['success_rate']} | `{r['url']}` ({err_msg}) |"
                )
        lines.append("")
        with open(md_out, "w", encoding="utf-8") as f:
            f.write("\n".join(lines))


def main():
    runs = int(os.environ.get("BENCHMARK_RUNS", "3"))
    timeout = float(os.environ.get("BENCHMARK_TIMEOUT", "10"))
    fastly_enabled = os.environ.get("FASTLY_ENABLED", "false").lower() == "true"
    origin_secret = os.environ.get("FASTLY_ORIGIN_SECRET", "").strip()

    json_out = os.environ.get("BENCHMARK_JSON_OUT", "benchmark_report.json").strip()
    md_out = os.environ.get("BENCHMARK_MD_OUT", "benchmark_report.md").strip()

    extra_headers = {}
    if fastly_enabled and origin_secret:
        extra_headers["X-Origin-Secret"] = origin_secret

    urls = load_urls()
    print(f"Benchmarking {len(urls)} route(s) | runs={runs} | timeout={timeout}s\n")

    results = [benchmark_url(u, runs=runs, timeout=timeout, extra_headers=extra_headers) for u in urls]
    ranked = sorted(
        results,
        key=lambda r: (0, r["avg_total_ms"]) if r["reachable"] else (1, float("inf")),
    )

    print(f"{'RANK':<4} {'STATUS':<8} {'AVG TTFB':<12} {'AVG TOTAL':<12} {'MIN TOTAL':<12} {'OK':<6} {'ROUTE'}")
    print("-" * 105)
    for idx, r in enumerate(ranked, start=1):
        if r["reachable"]:
            print(
                f"#{idx:<3} {r['status']:<8} {str(r['avg_ttfb_ms']) + 'ms':<12} "
                f"{str(r['avg_total_ms']) + 'ms':<12} {str(r['min_total_ms']) + 'ms':<12} "
                f"{r['success_rate']:<6} {r['url']}"
            )
        else:
            print(
                f"#{idx:<3} {'ERR':<8} {'-':<12} {'-':<12} {'-':<12} "
                f"{r['success_rate']:<6} {r['url']}  [ERR: {str(r['error'])[:50]}]"
            )

    fastest = next((r for r in ranked if r["reachable"]), None)
    write_outputs(ranked, fastest, json_out=json_out, md_out=md_out)

    print("\n" + "=" * 60)
    if fastest:
        print(f"FASTEST ROUTE : {fastest['url']}")
        print(f"HOST / STATUS : {fastest['host']} | HTTP {fastest['status']}")
        print(f"AVG RESPONSE  : {fastest['avg_total_ms']} ms (TTFB: {fastest['avg_ttfb_ms']} ms)")
    else:
        print("FASTEST ROUTE : None (All routes failed/unreachable)")
    if json_out:
        print(f"JSON REPORT   : {json_out}")
    if md_out:
        print(f"MD REPORT     : {md_out}")
    print("=" * 60)


if __name__ == "__main__":
    main()
    
