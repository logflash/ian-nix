#!/usr/bin/env python3
"""Check whether a Cloudflare DNS hostname already routes to a tunnel."""

import base64
import json
import os
import sys
import urllib.parse
import urllib.request


def main() -> int:
    hostname, tunnel_id = sys.argv[1:]
    cert_path = os.path.expanduser("~/.cloudflared/cert.pem")
    with open(cert_path, encoding="ascii") as cert_file:
        lines = cert_file.read().splitlines()
    cert = json.loads(base64.b64decode("".join(lines[1:-1])))
    query = urllib.parse.urlencode({"name": hostname, "per_page": 100})
    url = f"https://api.cloudflare.com/client/v4/zones/{cert['zoneID']}/dns_records?{query}"
    request = urllib.request.Request(
        url, headers={"Authorization": f"Bearer {cert['apiToken']}"}
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        data = json.load(response)
    if not data.get("success"):
        raise RuntimeError("Cloudflare rejected the DNS record lookup")

    records = [
        record
        for record in data["result"]
        if record.get("name", "").rstrip(".").lower() == hostname.lower()
        and record.get("type") in {"A", "AAAA", "CNAME"}
    ]
    target = f"{tunnel_id}.cfargotunnel.com"
    if not records:
        print("missing")
    elif (
        len(records) == 1
        and records[0]["type"] == "CNAME"
        and records[0].get("content", "").rstrip(".").lower() == target.lower()
    ):
        print("matching")
    else:
        print("conflict")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"Cloudflare DNS lookup failed: {error}", file=sys.stderr)
        sys.exit(1)
