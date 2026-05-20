#!/usr/bin/env python3
"""
PC Plus 360 - Company-Wide Software Inventory Report Generator
Pulls software inventory from all agents in a Tactical RMM client/company
and generates one combined branded HTML report.

Usage:
  python3 PCPlus-RMM-CompanyReport.py --client "108 Avenue"
  python3 PCPlus-RMM-CompanyReport.py --client "108 Avenue" --output /tmp/reports
  python3 PCPlus-RMM-CompanyReport.py --list-clients
  python3 PCPlus-RMM-CompanyReport.py --all

Environment:
  TACTICAL_API_KEY - API key (or use --api-key)
  TACTICAL_API_URL - Base URL (default: https://api.pcpluscomputing.com)
"""

import argparse
import json
import os
import sys
import urllib.request
import urllib.error
from datetime import datetime
from collections import Counter, defaultdict

API_URL = os.environ.get("TACTICAL_API_URL", "https://api.pcpluscomputing.com")
API_KEY = os.environ.get("TACTICAL_API_KEY", "WDHX6IPCKJ9BISAFVOUJFFXVKKN5HMZV")

OUTDATED_PATTERNS = [
    ("Java 8", "java", "1.8"),
    ("Java 7", "java", "1.7"),
    (".NET Framework 3.5", ".net framework", "3.5"),
    (".NET Framework 4.0", ".net framework", "4.0"),
    ("Adobe Reader DC (old)", "adobe acrobat reader", "15."),
    ("Adobe Reader DC (old)", "adobe acrobat reader", "17."),
    ("Adobe Reader DC (old)", "adobe acrobat reader", "19."),
    ("Adobe Reader DC (old)", "adobe acrobat reader", "20."),
]

EOL_PATTERNS = [
    "adobe flash player", "microsoft silverlight", "internet explorer",
    "windows media center", "skype for business", "paint 3d",
    "3d viewer", "mixed reality portal",
]

RISKY_PATTERNS = [
    "teamviewer", "anydesk", "ultraviewer", "rustdesk",
    "ammyy admin", "supremo", "logmein",
]

UNWANTED_PATTERNS = [
    "toolbar", "adware", "coupon", "shopping", "browser helper",
    "ask.com", "babylon", "conduit", "delta search", "sweetpacks",
    "mywebsearch", "mindspark", "web companion",
]

MANAGEMENT_AGENTS = [
    "tactical rmm", "mesh agent", "meshcentral",
]


def api_get(endpoint):
    url = f"{API_URL}/{endpoint.lstrip('/')}"
    req = urllib.request.Request(url, headers={"X-API-KEY": API_KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        print(f"  API Error {e.code}: {endpoint}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"  Error: {e}", file=sys.stderr)
        return None


def get_clients():
    data = api_get("/clients/")
    if not data:
        return []
    return sorted(data, key=lambda c: c["name"])


def get_agents(client_name=None):
    data = api_get("/agents/")
    if not data:
        return []
    if client_name:
        data = [a for a in data if a["client_name"].lower() == client_name.lower()]
    return sorted(data, key=lambda a: (a.get("site_name", ""), a["hostname"]))


def get_software(agent_id):
    data = api_get(f"/software/{agent_id}/")
    if not data:
        return []
    return data.get("software", []) if isinstance(data, dict) else data


def flag_software(name, version):
    name_lower = name.lower()
    version_lower = (version or "").lower()

    for label, pattern, ver_pattern in OUTDATED_PATTERNS:
        if pattern in name_lower and ver_pattern in version_lower:
            return "outdated", label

    for pattern in EOL_PATTERNS:
        if pattern in name_lower:
            return "eol", "End of Life"

    for pattern in RISKY_PATTERNS:
        if pattern in name_lower:
            return "risky", "Remote Access Tool"

    for pattern in UNWANTED_PATTERNS:
        if pattern in name_lower:
            return "unwanted", "Potentially Unwanted"

    return None, None


def is_management_agent(name):
    name_lower = name.lower()
    return any(p in name_lower for p in MANAGEMENT_AGENTS)


def generate_report(client_name, agents_data, output_dir):
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    safe_name = "".join(c if c.isalnum() or c in " -_" else "" for c in client_name).strip().replace(" ", "-")
    filename = f"PCPlus360-CompanyInventory-{safe_name}-{timestamp}.html"
    filepath = os.path.join(output_dir, filename)

    total_software = 0
    total_flagged = 0
    all_publishers = Counter()
    all_flags = []
    machine_count = len(agents_data)
    online_count = sum(1 for a in agents_data if a["info"]["status"] == "online")

    for agent in agents_data:
        for sw in agent["software"]:
            if not is_management_agent(sw["name"]):
                total_software += 1
                pub = sw.get("publisher") or "Unknown"
                all_publishers[pub] += 1
            flag_type, flag_reason = flag_software(sw["name"], sw.get("version", ""))
            if flag_type:
                total_flagged += 1
                all_flags.append({
                    "machine": agent["info"]["hostname"],
                    "name": sw["name"],
                    "version": sw.get("version", ""),
                    "type": flag_type,
                    "reason": flag_reason
                })

    top_publishers = all_publishers.most_common(15)
    max_pub_count = top_publishers[0][1] if top_publishers else 1

    # Common software across machines
    software_presence = defaultdict(set)
    for agent in agents_data:
        for sw in agent["software"]:
            if not is_management_agent(sw["name"]):
                software_presence[sw["name"]].add(agent["info"]["hostname"])

    common_software = sorted(
        [(name, len(machines)) for name, machines in software_presence.items() if len(machines) > 1],
        key=lambda x: -x[1]
    )[:30]

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Software Inventory - {client_name} - PC Plus Computing</title>
<style>
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{ font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f7fa; color: #333; line-height: 1.5; }}
.header {{ background: linear-gradient(135deg, #0d4b71 0%, #1a6da3 100%); color: white; padding: 30px 40px; display: flex; align-items: center; gap: 20px; }}
.header h1 {{ font-size: 24px; font-weight: 600; }}
.header .subtitle {{ opacity: 0.85; font-size: 14px; margin-top: 4px; }}
.header .meta {{ margin-left: auto; text-align: right; font-size: 13px; opacity: 0.9; }}
.container {{ max-width: 1400px; margin: 0 auto; padding: 30px; }}
.summary-cards {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 30px; }}
.card {{ background: white; border-radius: 10px; padding: 20px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); border-left: 4px solid #2596be; }}
.card.warning {{ border-left-color: #e67e22; }}
.card.danger {{ border-left-color: #e74c3c; }}
.card.success {{ border-left-color: #27ae60; }}
.card h3 {{ font-size: 28px; color: #0d4b71; margin-bottom: 4px; }}
.card p {{ font-size: 13px; color: #666; }}
.section {{ background: white; border-radius: 10px; padding: 24px; margin-bottom: 24px; box-shadow: 0 2px 8px rgba(0,0,0,0.06); }}
.section h2 {{ font-size: 18px; color: #0d4b71; margin-bottom: 16px; padding-bottom: 10px; border-bottom: 2px solid #eef2f7; }}
table {{ width: 100%; border-collapse: collapse; font-size: 13px; }}
th {{ background: #f8fafc; color: #555; font-weight: 600; text-align: left; padding: 10px 12px; border-bottom: 2px solid #e2e8f0; }}
td {{ padding: 8px 12px; border-bottom: 1px solid #f0f0f0; }}
tr:hover td {{ background: #f8fafc; }}
.flag-outdated {{ color: #e67e22; font-weight: 600; }}
.flag-eol {{ color: #e74c3c; font-weight: 600; }}
.flag-risky {{ color: #9b59b6; font-weight: 600; }}
.flag-unwanted {{ color: #7f8c8d; font-weight: 600; }}
.bar-container {{ display: flex; align-items: center; gap: 8px; }}
.bar {{ height: 18px; background: linear-gradient(90deg, #2596be, #0d4b71); border-radius: 3px; min-width: 2px; }}
.bar-label {{ font-size: 12px; color: #666; white-space: nowrap; }}
.machine-section {{ margin-bottom: 20px; }}
.machine-header {{ background: #f8fafc; padding: 12px 16px; border-radius: 8px; margin-bottom: 10px; display: flex; align-items: center; gap: 12px; cursor: pointer; }}
.machine-header h3 {{ font-size: 15px; color: #0d4b71; }}
.machine-header .badge {{ background: #2596be; color: white; padding: 2px 10px; border-radius: 12px; font-size: 12px; }}
.machine-header .status {{ margin-left: auto; font-size: 12px; }}
.status-online {{ color: #27ae60; }}
.status-offline {{ color: #e74c3c; }}
.machine-table {{ display: none; }}
.machine-section.expanded .machine-table {{ display: block; }}
.toggle-icon {{ transition: transform 0.2s; }}
.machine-section.expanded .toggle-icon {{ transform: rotate(90deg); }}
.footer {{ text-align: center; padding: 20px; color: #999; font-size: 12px; }}
.common-grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 8px; }}
.common-item {{ display: flex; justify-content: space-between; padding: 6px 10px; background: #f8fafc; border-radius: 4px; font-size: 13px; }}
.common-item .count {{ color: #2596be; font-weight: 600; }}
@media print {{
    .machine-table {{ display: block !important; }}
    .header {{ -webkit-print-color-adjust: exact; print-color-adjust: exact; }}
}}
</style>
</head>
<body>
<div class="header">
    <div>
        <h1>Company Software Inventory Report</h1>
        <div class="subtitle">{client_name}</div>
    </div>
    <div class="meta">
        <div>PC Plus Computing</div>
        <div>604-760-1662 | 236-500-2700</div>
        <div>{datetime.now().strftime("%B %d, %Y at %I:%M %p")}</div>
    </div>
</div>

<div class="container">
    <div class="summary-cards">
        <div class="card">
            <h3>{machine_count}</h3>
            <p>Total Machines</p>
        </div>
        <div class="card success">
            <h3>{online_count}</h3>
            <p>Currently Online</p>
        </div>
        <div class="card">
            <h3>{total_software:,}</h3>
            <p>Total Software Installed</p>
        </div>
        <div class="card {"danger" if total_flagged > 10 else "warning" if total_flagged > 0 else ""}">
            <h3>{total_flagged}</h3>
            <p>Flagged Items</p>
        </div>
    </div>
"""

    # Flagged items section
    if all_flags:
        html += """    <div class="section">
        <h2>Flagged Software</h2>
        <table>
            <thead><tr><th>Machine</th><th>Software</th><th>Version</th><th>Flag</th><th>Reason</th></tr></thead>
            <tbody>
"""
        for f in sorted(all_flags, key=lambda x: (x["type"], x["machine"])):
            css_class = f"flag-{f['type']}"
            html += f'            <tr><td>{f["machine"]}</td><td>{f["name"]}</td><td>{f["version"]}</td><td class="{css_class}">{f["type"].upper()}</td><td>{f["reason"]}</td></tr>\n'
        html += """            </tbody>
        </table>
    </div>
"""

    # Top publishers
    html += """    <div class="section">
        <h2>Top Software Publishers</h2>
"""
    for pub, count in top_publishers:
        bar_width = int((count / max_pub_count) * 300)
        html += f"""        <div class="bar-container" style="margin-bottom:6px">
            <div style="width:180px;font-size:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="{pub}">{pub}</div>
            <div class="bar" style="width:{bar_width}px"></div>
            <div class="bar-label">{count}</div>
        </div>
"""
    html += "    </div>\n"

    # Common software
    if common_software:
        html += """    <div class="section">
        <h2>Common Software (Installed on Multiple Machines)</h2>
        <div class="common-grid">
"""
        for name, count in common_software:
            html += f'            <div class="common-item"><span>{name}</span><span class="count">{count}/{machine_count}</span></div>\n'
        html += """        </div>
    </div>
"""

    # Per-machine sections
    html += """    <div class="section">
        <h2>Per-Machine Software Inventory</h2>
        <p style="font-size:13px;color:#666;margin-bottom:16px">Click a machine to expand its full software list.</p>
"""
    for agent in agents_data:
        info = agent["info"]
        sw_list = [s for s in agent["software"] if not is_management_agent(s["name"])]
        sw_list.sort(key=lambda s: s["name"].lower())
        status_class = "status-online" if info["status"] == "online" else "status-offline"
        status_dot = "&#9679;" if info["status"] == "online" else "&#9675;"

        flagged_on_machine = sum(1 for s in sw_list if flag_software(s["name"], s.get("version", ""))[0])
        flag_badge = f' <span style="background:#e74c3c;color:white;padding:1px 8px;border-radius:10px;font-size:11px;margin-left:8px">{flagged_on_machine} flagged</span>' if flagged_on_machine else ""

        html += f"""        <div class="machine-section" onclick="this.classList.toggle('expanded')">
            <div class="machine-header">
                <span class="toggle-icon">&#9654;</span>
                <h3>{info["hostname"]}</h3>
                <span class="badge">{len(sw_list)} programs</span>{flag_badge}
                <span class="status {status_class}">{status_dot} {info["status"]}</span>
            </div>
            <div class="machine-table">
                <table>
                    <thead><tr><th>Software</th><th>Version</th><th>Publisher</th><th>Flag</th></tr></thead>
                    <tbody>
"""
        for sw in sw_list:
            flag_type, flag_reason = flag_software(sw["name"], sw.get("version", ""))
            flag_cell = f'<span class="flag-{flag_type}">{flag_reason}</span>' if flag_type else ""
            html += f'                    <tr><td>{sw["name"]}</td><td>{sw.get("version", "")}</td><td>{sw.get("publisher", "")}</td><td>{flag_cell}</td></tr>\n'

        html += """                    </tbody>
                </table>
            </div>
        </div>
"""
    html += "    </div>\n"

    # Footer
    html += f"""</div>
<div class="footer">
    PC Plus Computing | pcpluscomputing.com | 604-760-1662 | 236-500-2700<br>
    Report generated {datetime.now().strftime("%Y-%m-%d %H:%M:%S")} | PC Plus 360 v2.6.0
</div>
</body>
</html>"""

    os.makedirs(output_dir, exist_ok=True)
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(html)

    return filepath


def main():
    parser = argparse.ArgumentParser(description="PC Plus 360 - Company-Wide Software Inventory Report")
    parser.add_argument("--client", help="Client/company name to generate report for")
    parser.add_argument("--all", action="store_true", help="Generate reports for ALL clients")
    parser.add_argument("--list-clients", action="store_true", help="List all available clients")
    parser.add_argument("--output", default="./reports", help="Output directory (default: ./reports)")
    parser.add_argument("--api-key", help="Tactical RMM API key (or set TACTICAL_API_KEY env)")
    parser.add_argument("--api-url", help="Tactical RMM API URL (or set TACTICAL_API_URL env)")
    args = parser.parse_args()

    global API_KEY, API_URL
    if args.api_key:
        API_KEY = args.api_key
    if args.api_url:
        API_URL = args.api_url

    if args.list_clients:
        print("\nAvailable Clients:")
        print("-" * 50)
        clients = get_clients()
        agents = get_agents()
        client_counts = Counter(a["client_name"] for a in agents)
        for c in clients:
            count = client_counts.get(c["name"], 0)
            if count > 0:
                print(f"  {c['name']:<30} ({count} agents)")
        print()
        return

    if not args.client and not args.all:
        parser.print_help()
        print("\nError: Specify --client 'Name' or --all or --list-clients")
        sys.exit(1)

    if args.all:
        clients = get_clients()
        agents_all = get_agents()
        client_names = sorted(set(a["client_name"] for a in agents_all))
    else:
        client_names = [args.client]

    for client_name in client_names:
        print(f"\n{'='*60}")
        print(f"Generating report for: {client_name}")
        print(f"{'='*60}")

        agents = get_agents(client_name)
        if not agents:
            print(f"  No agents found for '{client_name}'. Skipping.")
            continue

        print(f"  Found {len(agents)} agents. Pulling software inventory...")

        agents_data = []
        for i, agent in enumerate(agents):
            print(f"  [{i+1}/{len(agents)}] {agent['hostname']}...", end=" ", flush=True)
            software = get_software(agent["agent_id"])
            if software is None:
                software = []
            sw_list = software if isinstance(software, list) else []
            agents_data.append({"info": agent, "software": sw_list})
            print(f"{len(sw_list)} programs")

        filepath = generate_report(client_name, agents_data, args.output)
        print(f"\n  Report saved: {filepath}")
        total_sw = sum(len(a["software"]) for a in agents_data)
        print(f"  Total: {len(agents_data)} machines, {total_sw} software entries")

    print(f"\nDone! Reports saved to: {os.path.abspath(args.output)}")


if __name__ == "__main__":
    main()
