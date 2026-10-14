#!/usr/bin/env python3
"""
VPN Auto Subdomain Switcher
────────────────────────────
Subdomain တွေရဲ့ latency ကို တိုင်းပြီး အနည်းဆုံး (lowest ms) subdomain ကို
Sing-box config ထဲမှာ auto update လုပ်ပေးတယ်။
"""

import sys
import json
import time
import socket
import logging
from pathlib import Path
from statistics import median
from concurrent.futures import ThreadPoolExecutor, as_completed

import yaml

# ─── Paths ────────────────────────────────────────────
ROOT = Path(__file__).resolve().parent
CONFIG_YML = ROOT / "subdomain.yml"


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


log = logging.getLogger(__name__)


# ─── Load YAML ────────────────────────────────────────
def load_config(path: Path) -> dict:
    if not path.exists():
        log.error(f"Config file not found: {path}")
        sys.exit(1)
    with path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f)


# ─── Latency Measurement ──────────────────────────────
def measure_latency(host: str, port: int, timeout: int, samples: int) -> tuple[str, float, bool]:
    """
    Host ရဲ့ TCP connect latency ကို samples ကြိမ် တိုင်းပြီး
    median latency (ms) ကို ပြန်ပေးတယ်။
    """
    results = []
    for _ in range(samples):
        start = time.perf_counter()
        try:
            with socket.create_connection((host, port), timeout=timeout):
                latency = (time.perf_counter() - start) * 1000  # ms
                results.append(latency)
        except (socket.timeout, OSError):
            pass
        time.sleep(0.1)

    if not results:
        return (host, float("inf"), False)

    return (host, median(results), True)


def find_best_subdomain(hosts: list[str], port: int, timeout: int, samples: int) -> tuple[str, float] | None:
    """
    Subdomain အားလုံးကို တစ်ပြိုင်နက် တိုင်းပြီး
    latency အနည်းဆုံး (lowest median ms) ကို ရွေးပေးတယ်။
    """
    results = []

    log.info(f"Measuring {len(hosts)} subdomain(s)…")
    with ThreadPoolExecutor(max_workers=len(hosts)) as ex:
        futures = {
            ex.submit(measure_latency, h, port, timeout, samples): h
            for h in hosts
        }
        for fut in as_completed(futures):
            host, latency, ok = fut.result()
            if ok:
                log.info(f"  ✅ {host:<40} {latency:>7.1f} ms")
                results.append((host, latency))
            else:
                log.warning(f"  ❌ {host:<40} unreachable")

    if not results:
        return None

    results.sort(key=lambda x: x[1])   # lowest ms first
    return results[0]


# ─── Config Update ────────────────────────────────────
def update_singbox_config(config_file: Path, tag: str, best_host: str) -> bool:
    """
    Sing-box config ထဲက selector tag ရဲ့ default ကို best_host နဲ့ update လုပ်တယ်။
    """
    if not config_file.exists():
        log.error(f"Config file not found: {config_file}")
        return False

    with config_file.open("r", encoding="utf-8") as f:
        cfg = json.load(f)

    updated = False
    for out in cfg.get("outbounds", []):
        if out.get("tag") == tag:
            old = out.get("default")
            if old != best_host:
                out["default"] = best_host
                log.info(f"  Selector '{tag}': {old} → {best_host}")
                updated = True
            else:
                log.info(f"  Selector '{tag}' already points to {best_host}")
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
    setup_logging(ROOT / settings.get("log_file", "switcher.log"))

    log.info("═" * 60)
    log.info("VPN Auto Subdomain Switcher — start")
    log.info("═" * 60)

    vless = cfg.get("vless", {})
    port = vless.get("port", 443)

    timeout = settings.get("timeout", 3)
    samples = settings.get("samples", 3)
    config_file = ROOT / settings.get("config_file", "config.json")
    outbound_tag = settings.get("outbound_tag", "auto")

    hosts = [
        s["hostname"]
        for s in cfg.get("subdomains", [])
        if s.get("enabled", True)
    ]

    if not hosts:
        log.error("No subdomains enabled in subdomain.yml")
        sys.exit(1)

    result = find_best_subdomain(hosts, port, timeout, samples)

    if not result:
        log.error("No healthy subdomain found")
        sys.exit(2)

    best_host, best_latency = result
    log.info(f"🏆 Best subdomain: {best_host}  ({best_latency:.1f} ms)")

    update_singbox_config(config_file, outbound_tag, best_host)
    log.info("Done.")


if __name__ == "__main__":
    main()
