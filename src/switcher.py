#!/usr/bin/env python3
"""
Auto Subdomain Switch
Subdomain တွေကို စစ်ပြီး အကောင်းဆုံးကို config ထဲ update လုပ်ပေးတယ်။
"""

import sys
import json
import socket
import logging
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

import yaml

# ─── Logging ─────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

# ─── Paths ───────────────────────────────────────────────
ROOT = Path(__file__).resolve().parent.parent
CONFIG_YAML = ROOT / "config" / "subdomains.yaml"


# ─── Load Config ─────────────────────────────────────────
def load_yaml(path: Path) -> dict:
    if not path.exists():
        log.error(f"Config file not found: {path}")
        sys.exit(1)
    with path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f)


# ─── Health Check ────────────────────────────────────────
def check_host(host: str, port: int, timeout: int) -> tuple[str, bool, float]:
    """TCP connection စမ်းသပ်ပြီး (host, ok, latency) ပြန်ပေးတယ်။"""
    import time
    start = time.time()
    try:
        with socket.create_connection((host, port), timeout=timeout):
            latency = (time.time() - start) * 1000  # ms
            return (host, True, latency)
    except (socket.timeout, socket.error, OSError):
        return (host, False, float("inf"))


def find_best_subdomain(hosts: list[str], port: int, timeout: int) -> str | None:
    """Subdomain အားလုံးကို တစ်ပြိုင်နက် စစ်ပြီး အကောင်းဆုံးကို ရွေးတယ်။"""
    results = []
    with ThreadPoolExecutor(max_workers=len(hosts)) as ex:
        futures = {ex.submit(check_host, h, port, timeout): h for h in hosts}
        for fut in as_completed(futures):
            host, ok, latency = fut.result()
            status = f"✅ {latency:.0f}ms" if ok else "❌"
            log.info(f"  {host} → {status}")
            if ok:
                results.append((host, latency))

    if not results:
        return None

    results.sort(key=lambda x: x[1])  # latency အနည်းဆုံးကို ရွေး
    return results[0][0]


# ─── Update Config ───────────────────────────────────────
def update_config(config_file: Path, outbound_tag: str, best_host: str) -> bool:
    """Config ထဲက server ကို best_host နဲ့ update လုပ်တယ်။"""
    if not config_file.exists():
        log.error(f"Config file not found: {config_file}")
        return False

    with config_file.open("r", encoding="utf-8") as f:
        cfg = json.load(f)

    updated = False
    for out in cfg.get("outbounds", []):
        if out.get("tag") == outbound_tag:
            old = out.get("server")
            if old != best_host:
                out["server"] = best_host
                # TLS server_name ကိုလည်း update လုပ်ပါ
                if "tls" in out and isinstance(out["tls"], dict):
                    out["tls"]["server_name"] = best_host
                log.info(f"  Server: {old} → {best_host}")
                updated = True
            else:
                log.info(f"  Server already correct: {best_host}")

    if updated:
        with config_file.open("w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2, ensure_ascii=False)
        log.info(f"  Config updated: {config_file}")

    return updated


# ─── Main ────────────────────────────────────────────────
def main():
    log.info("═" * 50)
    log.info("Auto Subdomain Switch — start")
    log.info("═" * 50)

    cfg = load_yaml(CONFIG_YAML)
    settings = cfg.get("settings", {})
    timeout = settings.get("timeout", 3)
    port = settings.get("port", 443)
    config_file = ROOT / settings.get("config_file", "config/singbox-config.json")
    outbound_tag = settings.get("outbound_tag", "proxy")

    hosts = [
        s["hostname"]
        for s in cfg.get("subdomains", [])
        if s.get("enabled", True)
    ]

    if not hosts:
        log.error("Subdomain list is empty")
        sys.exit(1)

    log.info(f"Checking {len(hosts)} subdomain(s)…")
    best = find_best_subdomain(hosts, port, timeout)

    if not best:
        log.error("Healthy subdomain မရှိပါ")
        sys.exit(2)

    log.info(f"Best subdomain → {best}")
    update_config(config_file, outbound_tag, best)
    log.info("Done.")


if __name__ == "__main__":
    main()
