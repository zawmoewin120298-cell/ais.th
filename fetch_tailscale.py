import json
import os
import sys
import requests

api_key = os.environ.get("TAILSCALE_API_KEY", "").strip()
tailnet = os.environ.get("TAILSCALE_TAILNET", "-").strip()
output_path = os.environ.get("TAILSCALE_OUTPUT_FILE", "/tmp/tailscale_devices.json").strip()

if not api_key:
    print("Error: TAILSCALE_API_KEY environment variable is missing.", file=sys.stderr)
    sys.exit(1)

url = f"https://api.tailscale.com/api/v2/tailnet/{tailnet}/devices"
headers = {"Authorization": f"Bearer {api_key}"}

try:
    resp = requests.get(url, headers=headers, timeout=15)
    resp.raise_for_status()
    payload = resp.json()
    devices = payload.get("devices", [])

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(devices, f, indent=2, ensure_ascii=False)

    print(f"Fetched {len(devices)} devices -> saved to {output_path}")
    for d in devices:
        print(
            f"- {d.get('hostname')} | IPs: {d.get('addresses')} | Online: {d.get('online')}"
        )
except requests.exceptions.RequestException as e:
    print(f"Tailscale API request failed: {e}", file=sys.stderr)
    sys.exit(1)

