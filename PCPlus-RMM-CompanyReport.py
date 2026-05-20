#!/usr/bin/env python3
"""
PC Plus 360 - Company-Wide Software Inventory Report Generator
Pulls software inventory from all agents in a Tactical RMM client/company
and generates one combined branded HTML report.

Usage:
  python3 PCPlus-RMM-CompanyReport.py --client "108 Avenue"
  python3 PCPlus-RMM-CompanyReport.py --site "ACME Glass"
  python3 PCPlus-RMM-CompanyReport.py --client "Rohan" --site "ACME Glass"
  python3 PCPlus-RMM-CompanyReport.py --list-clients
  python3 PCPlus-RMM-CompanyReport.py --all

Environment:
  TACTICAL_API_KEY - API key (or use --api-key)
  TACTICAL_API_URL - Base URL (default: https://api.pcpluscomputing.com)
"""

import argparse
import base64
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

LOGO_SVG = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 60 60" width="48" height="48">
  <defs>
    <linearGradient id="shieldGrad" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#2596be"/>
      <stop offset="100%" style="stop-color:#0d4b71"/>
    </linearGradient>
  </defs>
  <path d="M30 3 L54 14 V30 C54 45 42 54 30 58 C18 54 6 45 6 30 V14 Z" fill="url(#shieldGrad)" stroke="white" stroke-width="1.5"/>
  <path d="M30 8 L50 17 V30 C50 43 40 51 30 54 C20 51 10 43 10 30 V17 Z" fill="none" stroke="rgba(255,255,255,0.3)" stroke-width="1"/>
  <text x="30" y="28" text-anchor="middle" fill="white" font-family="Segoe UI,Arial" font-size="11" font-weight="700">PC+</text>
  <text x="30" y="40" text-anchor="middle" fill="rgba(255,255,255,0.9)" font-family="Segoe UI,Arial" font-size="7" font-weight="600">360</text>
</svg>"""


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


def get_agents(client_name=None, site_name=None):
    data = api_get("/agents/")
    if not data:
        return []
    if client_name:
        data = [a for a in data if a["client_name"].lower() == client_name.lower()]
    if site_name:
        data = [a for a in data if a.get("site_name", "").lower() == site_name.lower()]
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


def generate_report(report_name, agents_data, output_dir, site_name=None):
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    safe_name = "".join(c if c.isalnum() or c in " -_" else "" for c in report_name).strip().replace(" ", "-")
    filename = f"PCPlus360-CompanyInventory-{safe_name}-{timestamp}.html"
    filepath = os.path.join(output_dir, filename)

    total_software = 0
    total_flagged = 0
    all_publishers = Counter()
    all_flags = []
    machine_count = len(agents_data)
    online_count = sum(1 for a in agents_data if a["info"]["status"] == "online")
    overdue_count = sum(1 for a in agents_data if a["info"]["status"] == "overdue")

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

    software_presence = defaultdict(set)
    for agent in agents_data:
        for sw in agent["software"]:
            if not is_management_agent(sw["name"]):
                software_presence[sw["name"]].add(agent["info"]["hostname"])

    common_software = sorted(
        [(name, len(machines)) for name, machines in software_presence.items() if len(machines) > 1],
        key=lambda x: -x[1]
    )[:30]

    unique_software = sum(1 for name, machines in software_presence.items() if len(machines) == 1)

    flag_counts = Counter(f["type"] for f in all_flags)
    machines_with_flags = len(set(f["machine"] for f in all_flags))
    flag_pct = (machines_with_flags / machine_count * 100) if machine_count else 0
    eol_penalty = min(flag_counts.get("eol", 0) * 3, 25)
    outdated_penalty = min(flag_counts.get("outdated", 0) * 2, 15)
    risky_penalty = min(flag_counts.get("risky", 0) * 2, 20)
    unwanted_penalty = min(flag_counts.get("unwanted", 0) * 1, 10)
    health_score = max(0, 100 - eol_penalty - outdated_penalty - risky_penalty - unwanted_penalty)
    health_color = "#27ae60" if health_score >= 80 else "#e67e22" if health_score >= 50 else "#e74c3c"

    logo_svg_b64 = base64.b64encode(LOGO_SVG.encode()).decode()

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Software Inventory - {report_name} - PC Plus Computing</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap');
* {{ margin: 0; padding: 0; box-sizing: border-box; }}
body {{ font-family: 'Inter', 'Segoe UI', sans-serif; background: #f0f2f5; color: #1a1a2e; line-height: 1.6; }}

.header {{
    background: linear-gradient(135deg, #0a3d5c 0%, #0d4b71 30%, #1a6da3 70%, #2596be 100%);
    color: white;
    padding: 0;
    position: relative;
    overflow: hidden;
}}
.header::before {{
    content: '';
    position: absolute;
    top: -50%;
    right: -10%;
    width: 400px;
    height: 400px;
    background: radial-gradient(circle, rgba(37,150,190,0.15) 0%, transparent 70%);
    border-radius: 50%;
}}
.header::after {{
    content: '';
    position: absolute;
    bottom: -30%;
    left: 20%;
    width: 300px;
    height: 300px;
    background: radial-gradient(circle, rgba(255,255,255,0.05) 0%, transparent 70%);
    border-radius: 50%;
}}
.header-inner {{
    display: flex;
    align-items: center;
    padding: 28px 40px;
    position: relative;
    z-index: 1;
}}
.header-logo {{
    width: 52px;
    height: 52px;
    margin-right: 18px;
    flex-shrink: 0;
    filter: drop-shadow(0 2px 4px rgba(0,0,0,0.3));
}}
.header-brand h1 {{
    font-size: 22px;
    font-weight: 700;
    letter-spacing: -0.3px;
    margin-bottom: 2px;
}}
.header-brand .tagline {{
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 2px;
    opacity: 0.7;
    font-weight: 500;
}}
.header-report {{
    margin-left: auto;
    text-align: right;
}}
.header-report .report-title {{
    font-size: 18px;
    font-weight: 600;
    margin-bottom: 2px;
}}
.header-report .report-client {{
    font-size: 14px;
    opacity: 0.9;
    font-weight: 400;
}}
.header-bar {{
    background: rgba(0,0,0,0.15);
    padding: 8px 40px;
    display: flex;
    justify-content: space-between;
    font-size: 12px;
    opacity: 0.85;
    position: relative;
    z-index: 1;
}}

.container {{ max-width: 1400px; margin: 0 auto; padding: 28px; }}

.summary-cards {{
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    gap: 14px;
    margin-bottom: 24px;
}}
.card {{
    background: white;
    border-radius: 12px;
    padding: 20px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.06), 0 4px 12px rgba(0,0,0,0.04);
    position: relative;
    overflow: hidden;
    transition: transform 0.15s, box-shadow 0.15s;
}}
.card:hover {{ transform: translateY(-2px); box-shadow: 0 4px 16px rgba(0,0,0,0.1); }}
.card::before {{
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 3px;
    background: #2596be;
}}
.card.success::before {{ background: #27ae60; }}
.card.warning::before {{ background: #e67e22; }}
.card.danger::before {{ background: #e74c3c; }}
.card.health::before {{ background: {health_color}; }}
.card h3 {{ font-size: 30px; font-weight: 800; color: #0d4b71; margin-bottom: 2px; letter-spacing: -1px; }}
.card p {{ font-size: 12px; color: #888; font-weight: 500; text-transform: uppercase; letter-spacing: 0.5px; }}
.card .card-icon {{ position: absolute; right: 16px; top: 16px; font-size: 28px; opacity: 0.12; }}
.card.health h3 {{ color: {health_color}; }}

.section {{
    background: white;
    border-radius: 12px;
    padding: 24px 28px;
    margin-bottom: 20px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.06), 0 4px 12px rgba(0,0,0,0.04);
}}
.section h2 {{
    font-size: 16px;
    font-weight: 700;
    color: #0d4b71;
    margin-bottom: 16px;
    padding-bottom: 10px;
    border-bottom: 2px solid #eef2f7;
    display: flex;
    align-items: center;
    gap: 8px;
}}
.section h2 .icon {{ font-size: 18px; }}

table {{ width: 100%; border-collapse: collapse; font-size: 13px; }}
th {{
    background: #f8fafc;
    color: #64748b;
    font-weight: 600;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    text-align: left;
    padding: 10px 14px;
    border-bottom: 2px solid #e2e8f0;
}}
td {{ padding: 9px 14px; border-bottom: 1px solid #f1f5f9; }}
tr:hover td {{ background: #f8fafc; }}
.flag-outdated {{ color: #e67e22; font-weight: 600; font-size: 11px; padding: 2px 8px; background: #fef3e2; border-radius: 4px; }}
.flag-eol {{ color: #e74c3c; font-weight: 600; font-size: 11px; padding: 2px 8px; background: #fde8e8; border-radius: 4px; }}
.flag-risky {{ color: #9b59b6; font-weight: 600; font-size: 11px; padding: 2px 8px; background: #f3e8ff; border-radius: 4px; }}
.flag-unwanted {{ color: #64748b; font-weight: 600; font-size: 11px; padding: 2px 8px; background: #f1f5f9; border-radius: 4px; }}

.bar-row {{ display: flex; align-items: center; gap: 10px; margin-bottom: 8px; }}
.bar-name {{ width: 180px; font-size: 12px; font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: #475569; }}
.bar {{ height: 22px; background: linear-gradient(90deg, #2596be, #0d4b71); border-radius: 4px; min-width: 3px; transition: width 0.3s; }}
.bar-count {{ font-size: 12px; font-weight: 600; color: #0d4b71; min-width: 30px; }}

.machine-section {{ margin-bottom: 4px; }}
.machine-header {{
    background: #f8fafc;
    padding: 12px 18px;
    border-radius: 8px;
    display: flex;
    align-items: center;
    gap: 12px;
    cursor: pointer;
    transition: background 0.15s;
    border: 1px solid transparent;
}}
.machine-header:hover {{ background: #eef2f7; border-color: #e2e8f0; }}
.machine-header h3 {{ font-size: 14px; font-weight: 600; color: #0d4b71; }}
.machine-header .badge {{
    background: linear-gradient(135deg, #2596be, #0d4b71);
    color: white;
    padding: 2px 10px;
    border-radius: 12px;
    font-size: 11px;
    font-weight: 600;
}}
.machine-header .flag-badge {{
    background: #e74c3c;
    color: white;
    padding: 2px 8px;
    border-radius: 10px;
    font-size: 11px;
    font-weight: 600;
}}
.machine-header .status {{ margin-left: auto; font-size: 12px; font-weight: 500; }}
.status-online {{ color: #27ae60; }}
.status-offline {{ color: #e74c3c; }}
.status-overdue {{ color: #e67e22; }}
.machine-table {{ display: none; padding: 0 8px; }}
.machine-section.expanded .machine-table {{ display: block; margin-top: 8px; margin-bottom: 12px; }}
.toggle-icon {{ transition: transform 0.2s; font-size: 10px; color: #94a3b8; }}
.machine-section.expanded .toggle-icon {{ transform: rotate(90deg); }}

.common-grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 6px; }}
.common-item {{
    display: flex;
    justify-content: space-between;
    padding: 7px 12px;
    background: #f8fafc;
    border-radius: 6px;
    font-size: 12px;
    border: 1px solid #f1f5f9;
}}
.common-item:hover {{ border-color: #e2e8f0; }}
.common-item .count {{ color: #0d4b71; font-weight: 700; }}

.footer {{
    text-align: center;
    padding: 24px;
    font-size: 12px;
    color: #94a3b8;
    border-top: 1px solid #e2e8f0;
    margin-top: 10px;
}}
.footer a {{ color: #2596be; text-decoration: none; }}
.footer .brand {{ font-weight: 600; color: #64748b; }}

.legend {{
    display: flex;
    gap: 16px;
    padding: 12px 16px;
    background: #f8fafc;
    border-radius: 8px;
    margin-bottom: 14px;
    font-size: 12px;
    flex-wrap: wrap;
}}
.legend-item {{ display: flex; align-items: center; gap: 6px; }}

@media print {{
    .machine-table {{ display: block !important; }}
    .header, .card::before {{ -webkit-print-color-adjust: exact; print-color-adjust: exact; }}
    .card:hover {{ transform: none; }}
    body {{ background: white; }}
}}
</style>
</head>
<body>

<div class="header">
    <div class="header-inner">
        <img class="header-logo" src="data:image/svg+xml;base64,{logo_svg_b64}" alt="PC Plus 360">
        <div class="header-brand">
            <h1>PC Plus Computing</h1>
            <div class="tagline">Your Security, Our Priority</div>
        </div>
        <div class="header-report">
            <div class="report-title">Software Inventory Report</div>
            <div class="report-client">{report_name}</div>
        </div>
    </div>
    <div class="header-bar">
        <span>604-760-1662 | 236-500-2700 | pcpluscomputing.com</span>
        <span>Generated: {datetime.now().strftime("%B %d, %Y at %I:%M %p")}</span>
    </div>
</div>

<div class="container">
    <div class="summary-cards">
        <div class="card">
            <span class="card-icon">&#128187;</span>
            <h3>{machine_count}</h3>
            <p>Total Machines</p>
        </div>
        <div class="card success">
            <span class="card-icon">&#9889;</span>
            <h3>{online_count}</h3>
            <p>Online Now</p>
        </div>
        <div class="card">
            <span class="card-icon">&#128230;</span>
            <h3>{total_software:,}</h3>
            <p>Software Installed</p>
        </div>
        <div class="card {"danger" if total_flagged > 10 else "warning" if total_flagged > 0 else ""}">
            <span class="card-icon">&#9888;</span>
            <h3>{total_flagged}</h3>
            <p>Flagged Items</p>
        </div>
        <div class="card health">
            <span class="card-icon">&#128737;</span>
            <h3>{health_score}%</h3>
            <p>Health Score</p>
        </div>
    </div>
"""

    # Flagged items
    if all_flags:
        html += """    <div class="section">
        <h2><span class="icon">&#9888;</span> Flagged Software</h2>
        <div class="legend">
            <div class="legend-item"><span class="flag-eol">EOL</span> End of Life - no security patches</div>
            <div class="legend-item"><span class="flag-outdated">OUTDATED</span> Newer version available</div>
            <div class="legend-item"><span class="flag-risky">RISKY</span> Unauthorized remote access</div>
            <div class="legend-item"><span class="flag-unwanted">UNWANTED</span> Potentially unwanted</div>
        </div>
        <table>
            <thead><tr><th>Machine</th><th>Software</th><th>Version</th><th>Flag</th><th>Reason</th></tr></thead>
            <tbody>
"""
        for f in sorted(all_flags, key=lambda x: ({"eol": 0, "outdated": 1, "risky": 2, "unwanted": 3}.get(x["type"], 4), x["machine"])):
            html += f'            <tr><td><strong>{f["machine"]}</strong></td><td>{f["name"]}</td><td>{f["version"]}</td><td><span class="flag-{f["type"]}">{f["type"].upper()}</span></td><td>{f["reason"]}</td></tr>\n'
        html += """            </tbody>
        </table>
    </div>
"""

    # Top publishers
    html += """    <div class="section">
        <h2><span class="icon">&#127970;</span> Top Software Publishers</h2>
"""
    for pub, count in top_publishers:
        bar_width = int((count / max_pub_count) * 350)
        html += f"""        <div class="bar-row">
            <div class="bar-name" title="{pub}">{pub}</div>
            <div class="bar" style="width:{bar_width}px"></div>
            <div class="bar-count">{count}</div>
        </div>
"""
    html += "    </div>\n"

    # Common software
    if common_software:
        html += """    <div class="section">
        <h2><span class="icon">&#128279;</span> Common Software Across Machines</h2>
        <div class="common-grid">
"""
        for name, count in common_software:
            pct = int((count / machine_count) * 100)
            html += f'            <div class="common-item"><span>{name}</span><span class="count">{count}/{machine_count} ({pct}%)</span></div>\n'
        html += """        </div>
    </div>
"""

    # Per-machine sections
    html += f"""    <div class="section">
        <h2><span class="icon">&#128421;</span> Per-Machine Software Inventory</h2>
        <p style="font-size:12px;color:#94a3b8;margin-bottom:16px">{machine_count} machines | Click to expand full software list | {unique_software} unique applications found only on one machine</p>
"""
    for agent in agents_data:
        info = agent["info"]
        sw_list = [s for s in agent["software"] if not is_management_agent(s["name"])]
        sw_list.sort(key=lambda s: s["name"].lower())
        status = info["status"]
        if status == "online":
            status_class, status_dot = "status-online", "&#9679;"
        elif status == "overdue":
            status_class, status_dot = "status-overdue", "&#9675;"
        else:
            status_class, status_dot = "status-offline", "&#9675;"

        os_info = info.get("operating_system", "")
        os_short = os_info[:40] + "..." if len(os_info) > 40 else os_info

        flagged_on_machine = sum(1 for s in sw_list if flag_software(s["name"], s.get("version", ""))[0])
        flag_badge = f' <span class="flag-badge">{flagged_on_machine} flagged</span>' if flagged_on_machine else ""

        html += f"""        <div class="machine-section" onclick="this.classList.toggle('expanded')">
            <div class="machine-header">
                <span class="toggle-icon">&#9654;</span>
                <h3>{info["hostname"]}</h3>
                <span class="badge">{len(sw_list)} programs</span>{flag_badge}
                <span style="font-size:11px;color:#94a3b8;margin-left:8px">{os_short}</span>
                <span class="status {status_class}">{status_dot} {status}</span>
            </div>
            <div class="machine-table">
                <table>
                    <thead><tr><th>Software</th><th>Version</th><th>Publisher</th><th>Size</th><th>Flag</th></tr></thead>
                    <tbody>
"""
        for sw in sw_list:
            flag_type, flag_reason = flag_software(sw["name"], sw.get("version", ""))
            flag_cell = f'<span class="flag-{flag_type}">{flag_reason}</span>' if flag_type else ""
            size = sw.get("size", "")
            if size == "0 B":
                size = ""
            html += f'                    <tr><td>{sw["name"]}</td><td>{sw.get("version", "")}</td><td>{sw.get("publisher", "")}</td><td style="color:#94a3b8">{size}</td><td>{flag_cell}</td></tr>\n'

        html += """                    </tbody>
                </table>
            </div>
        </div>
"""
    html += "    </div>\n"

    # Footer
    html += f"""</div>
<div class="footer">
    <div class="brand">PC Plus Computing</div>
    pcpluscomputing.com | 604-760-1662 | 236-500-2700<br>
    Report generated {datetime.now().strftime("%Y-%m-%d %H:%M:%S")} | PC Plus 360 v2.6.0<br>
    Confidential - prepared for {report_name}
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
    parser.add_argument("--site", help="Filter by site name (e.g. 'ACME Glass')")
    parser.add_argument("--all", action="store_true", help="Generate reports for ALL clients")
    parser.add_argument("--list-clients", action="store_true", help="List all available clients and sites")
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
        print("\nAvailable Clients & Sites:")
        print("-" * 60)
        clients = get_clients()
        agents = get_agents()
        for c in clients:
            client_agents = [a for a in agents if a["client_name"] == c["name"]]
            if not client_agents:
                continue
            sites = Counter(a.get("site_name", "Default") for a in client_agents)
            print(f"\n  {c['name']} ({len(client_agents)} agents)")
            for site, count in sorted(sites.items()):
                print(f"    └─ {site} ({count} agents)")
        print()
        return

    if args.site and not args.client:
        agents = get_agents(site_name=args.site)
        if not agents:
            print(f"No agents found for site '{args.site}'.")
            sys.exit(1)
        client_name = agents[0]["client_name"]
        report_name = args.site
        print(f"\n{'='*60}")
        print(f"Generating report for site: {args.site} (under {client_name})")
        print(f"{'='*60}")
        print(f"  Found {len(agents)} agents. Pulling software inventory...")
        agents_data = []
        for i, agent in enumerate(agents):
            print(f"  [{i+1}/{len(agents)}] {agent['hostname']}...", end=" ", flush=True)
            software = get_software(agent["agent_id"])
            sw_list = (software if isinstance(software, list) else []) if software else []
            agents_data.append({"info": agent, "software": sw_list})
            print(f"{len(sw_list)} programs")
        filepath = generate_report(report_name, agents_data, args.output, site_name=args.site)
        print(f"\n  Report saved: {filepath}")
        total_sw = sum(len(a["software"]) for a in agents_data)
        print(f"  Total: {len(agents_data)} machines, {total_sw} software entries")
        print(f"\nDone! Reports saved to: {os.path.abspath(args.output)}")
        return

    if not args.client and not args.all:
        parser.print_help()
        print("\nError: Specify --client 'Name', --site 'Name', --all, or --list-clients")
        sys.exit(1)

    if args.all:
        agents_all = get_agents()
        client_names = sorted(set(a["client_name"] for a in agents_all))
    else:
        client_names = [args.client]

    for client_name in client_names:
        print(f"\n{'='*60}")
        print(f"Generating report for: {client_name}")
        print(f"{'='*60}")

        agents = get_agents(client_name, site_name=args.site)
        if not agents:
            print(f"  No agents found for '{client_name}'{' site ' + args.site if args.site else ''}. Skipping.")
            continue

        report_name = f"{client_name} - {args.site}" if args.site else client_name
        print(f"  Found {len(agents)} agents. Pulling software inventory...")

        agents_data = []
        for i, agent in enumerate(agents):
            print(f"  [{i+1}/{len(agents)}] {agent['hostname']}...", end=" ", flush=True)
            software = get_software(agent["agent_id"])
            sw_list = (software if isinstance(software, list) else []) if software else []
            agents_data.append({"info": agent, "software": sw_list})
            print(f"{len(sw_list)} programs")

        filepath = generate_report(report_name, agents_data, args.output, site_name=args.site)
        print(f"\n  Report saved: {filepath}")
        total_sw = sum(len(a["software"]) for a in agents_data)
        print(f"  Total: {len(agents_data)} machines, {total_sw} software entries")

    print(f"\nDone! Reports saved to: {os.path.abspath(args.output)}")


if __name__ == "__main__":
    main()
