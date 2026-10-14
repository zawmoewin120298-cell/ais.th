#!/usr/bin/env python3
"""
Cloudflare IP Scanner
─────────────────────
Cloudflare IP list ကို scan ပြီး latency အနည်းဆုံး IP ကို
Sing-box config ထဲမှာ auto update လုပ်ပေးတယ်။
"""

import sys
import ssl
import json
import time
import socket
import logging
from pathlib import Path
from statistics import median
from concurrent.futures import ThreadPoolExecutor, as_completed

import yaml


ROOT = Path(__file__).resolve().parent
CONFIG_YML = ROOT / "subdomain.yml"
log = logging.getLogger(__name__)


# ─── Logging ──────────────────────────────────────────
def setup_logging(log_file: Path):
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
        handlers=[
            logging.FileHandler(log_file, encoding="utf-8"),
            logging.StreamHandler(sys.stdout),
        ],
    )


# ─── Load YAML ────────────────────────────────────────
def load_config(path: Path) -> dict:
    if not path.exists():
        log.error(f"Config file not found: {path}")
        sys.exit(1)
    with path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f)


# ─── TLS Handshake ────────────────────────────────────
def tls_handshake_latency(ip: str, domain: str, port: int, timeout: int, samples: int) -> tuple[str, float, bool]:
    """
    IP ဆီ TLS handshake လုပ်ပြီး latency ကို samples ကြိမ် တိုင်းတယ်။
    SNI ကို domain နဲ့ ထည့်တဲ့အတွက် Cloudflare က မှန်ကန်တဲ့ tunnel ကို route လုပ်ပေးတယ်။
    """
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    results = []
    for _ in range(samples):
        start = time.perf_counter()
        try:
            with socket.create_connection((ip, port), timeout=timeout) as sock:
                with ctx.wrap_socket(sock, server_hostname=domain):
                    latency = (time.perf_counter() - start) * 1000
                    results.append(latency)
        except (socket.timeout, ssl.SSLError, OSError):
            pass
        time.sleep(0.05)

    if not results:
        return (ip, float("inf"), False)

    return (ip, median(results), True)


# ─── Scan All IPs ─────────────────────────────────────
def scan_ips(ips: list[str], domain: str, port: int, timeout: int, samples: int, max_workers: int) -> list[tuple[str, float]]:
    results = []
    total = len(ips)

    log.info(f"Scanning {total} Cloudflare IP(s)…")
    with ThreadPoolExecutor(max_workers=max_workers) as ex:
        futures = {
            ex.submit(tls_handshake_latency, ip, domain, port, timeout, samples): ip
            for ip in ips
        }

        done = 0
        for fut in as_completed(futures):
            ip, latency, ok = fut.result()
            done += 1
            if done % 10 == 0 or done == total:
                log.info(f"  Progress: {done}/{total}")

            if ok:
                results.append((ip, latency))

    results.sort(key=lambda x: x[1])
    return results


# ─── Update Sing-box Config ───────────────────────────
def update_config(config_file: Path, tag: str, best_ip: str) -> bool:
    if not config_file.exists():
        log.error(f"Config file not found: {config_file}")
        return False

    with config_file.open("r", encoding="utf-8") as f:
        cfg = json.load(f)

    updated = False
    for out in cfg.get("outbounds", []):
        if out.get("tag") == tag:
            old = out.get("server")
            if old != best_ip:
                out["server"] = best_ip
                log.info(f"  Server: {old} → {best_ip}")
                updated = True
            else:
                log.info(f"  Server already correct: {best_ip}")
            break

    if updated:
        with config_file.open("w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2, ensure_ascii=False)
        log.info(f"  Config saved: {config_file}")

    return updated


# ─── Main ─────────────────────────────────────────────
def main():
    cfg = load_config(CONFIG_YML)
    settings = cfg.get("settings", {})
    setup_logging(ROOT / settings.get("log_file", "scanner.log"))

    log.info("═" * 60)
    log.info("Cloudflare IP Scanner — start")
    log.info("═" * 60)

    vless = cfg.get("vless", {})
    domain = vless["domain"]
    port = vless.get("port", 443)

    ips = cfg.get("cloudflare_ips", [])
    if not ips:
        log.error("No Cloudflare IPs found in subdomain.yml")
        sys.exit(1)

    timeout = settings.get("timeout", 2)
    samples = settings.get("samples", 3)
    max_workers = settings.get("max_workers", 100)
    top_n = settings.get("top_n", 5)
    config_file = ROOT / settings.get("config_file", "config.json")
    tag = settings.get("server_outbound_tag", "cf-ip")

    results = scan_ips(ips, domain, port, timeout, samples, max_workers)

    if not results:
        log.error("No reachable Cloudflare IP found")
        sys.exit(2)

    log.info("")
    log.info(f"🏆 Top {top_n} IPs:")
    for i, (ip, lat) in enumerate(results[:top_n], 1):
        log.info(f"  {i}. {ip:<18} {lat:>7.1f} ms")

    best_ip, best_latency = results[0]
    log.info("")
    log.info(f"✅ Best IP: {best_ip}  ({best_latency:.1f} ms)")
    update_config(config_file, tag, best_ip)
    log.info("Done.")


if __name__ == "__main__":
    main()
