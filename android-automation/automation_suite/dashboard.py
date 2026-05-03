#!/usr/bin/env python3
"""
Automation Suite Dashboard Generator
Generates a comprehensive HTML dashboard showing all repos, test cases, results, and logs.
"""

import json
import os
import sys
from pathlib import Path
from datetime import datetime
import hashlib
import glob

RESULTS_DIR = Path("/home/kushal/Documents/Projects/media-rs/android-automation/reports/results")
LOGS_DIR = Path("/home/kushal/Documents/Projects/media-rs/android-automation/logs")
MANIFESTS_DIR = Path("/home/kushal/Documents/Projects/media-rs/android-automation/reports/results")
DASHBOARD_DIR = Path("/home/kushal/Documents/Projects/media-rs/android-automation/automation_suite/dashboard")


def load_all_manifests():
    """Load all run manifests."""
    manifests = []
    if not MANIFESTS_DIR.exists():
        return manifests

    for f in sorted(MANIFESTS_DIR.glob("manifest_*.json"), reverse=True):
        try:
            data = json.loads(f.read_text())
            data["_filename"] = f.name
            data["_filepath"] = str(f)
            manifests.append(data)
        except:
            continue
    return manifests


def load_repo_result(repo_name):
    """Load latest result for a repo."""
    result_dir = RESULTS_DIR / repo_name
    if not result_dir.exists():
        return None

    # Load main result
    result_file = result_dir / "result.json"
    if not result_file.exists():
        return None

    result = json.loads(result_file.read_text())
    result["_dir"] = str(result_dir)

    # Load individual test results
    tests_dir = result_dir / "tests"
    if tests_dir.exists():
        for test_file in sorted(tests_dir.glob("*.json")):
            test_data = json.loads(test_file.read_text())
            # Add log file references
            logs_dir = result_dir / "logs"
            if logs_dir.exists():
                safe = hashlib.md5(test_data.get("name", "test").encode()).hexdigest()[:8]
                test_data["_log_stdout"] = str(logs_dir / f"{safe}_{test_data['name']}_stdout.txt")
                test_data["_log_stderr"] = str(logs_dir / f"{safe}_{test_data['name']}_stderr.txt")
            result["tests"].append(test_data)

    return result


def get_all_repo_results():
    """Get results for all repositories."""
    repos = {}
    for result_dir in sorted(RESULTS_DIR.iterdir()):
        if result_dir.is_dir() and result_dir.name != "manifests":
            result = load_repo_result(result_dir.name)
            if result:
                repos[result_dir.name] = result
    return repos


def status_icon(status):
    icons = {
        "pass": "✅",
        "fail": "❌",
        "error": "💥",
        "skip": "⏭️",
        "running": "🔄",
    }
    return icons.get(status, "❓")


def status_class(status):
    classes = {
        "pass": "status-pass",
        "fail": "status-fail",
        "error": "status-error",
        "skip": "status-skip",
        "running": "status-running",
    }
    return classes.get(status, "")


def format_duration(seconds):
    if seconds < 60:
        return f"{seconds:.1f}s"
    elif seconds < 3600:
        m = int(seconds // 60)
        s = seconds % 60
        return f"{m}m {s:.1f}s"
    else:
        h = int(seconds // 3600)
        m = int((seconds % 3600) // 60)
        s = seconds % 60
        return f"{h}h {m}m {s:.1f}s"


def escape_html(text):
    """Escape HTML for safe display."""
    if not text:
        return ""
    return (text
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
            .replace("'", "&#x27;"))


def generate_dashboard():
    """Generate the complete dashboard HTML."""
    repos = get_all_repo_results()
    manifests = load_all_manifests()

    # Calculate overall stats
    total_repos = len(repos)
    total_tests = sum(r.get("total", 0) for r in repos.values())
    total_passed = sum(r.get("passed", 0) for r in repos.values())
    total_failed = sum(r.get("failed", 0) for r in repos.values())
    total_errored = sum(r.get("errored", 0) for r in repos.values())
    total_skipped = sum(r.get("skipped", 0) for r in repos.values())
    overall_rate = round((total_passed / total_tests * 100) if total_tests > 0 else 0, 1)

    # Build repo cards HTML
    repo_cards_html = ""
    for repo_name, result in repos.items():
        status_label = result.get("overall_status", "no_tests").upper()
        status_cls = {
            "PASS": "card-pass",
            "FAIL": "card-fail",
            "ERROR": "card-error",
            "NO_TESTS": "card-neutral",
        }.get(status_label, "card-neutral")

        repo_cards_html += f"""
        <div class="repo-card {status_cls}">
            <div class="card-header">
                <span class="repo-icon">📦</span>
                <span class="repo-name">{escape_html(repo_name)}</span>
                <span class="repo-branch">{escape_html(result.get('branch', 'main'))}</span>
            </div>
            <div class="card-stats">
                <div class="stat">
                    <span class="stat-value">{result.get('total', 0)}</span>
                    <span class="stat-label">Tests</span>
                </div>
                <div class="stat">
                    <span class="stat-value status-pass">{result.get('passed', 0)}</span>
                    <span class="stat-label">Passed</span>
                </div>
                <div class="stat">
                    <span class="stat-value status-fail">{result.get('failed', 0)}</span>
                    <span class="stat-label">Failed</span>
                </div>
                <div class="stat">
                    <span class="stat-value status-error">{result.get('errored', 0)}</span>
                    <span class="stat-label">Errors</span>
                </div>
                <div class="stat">
                    <span class="stat-value status-skip">{result.get('skipped', 0)}</span>
                    <span class="stat-label">Skipped</span>
                </div>
                <div class="stat">
                    <span class="stat-value">{format_duration(result.get('total_duration_seconds', 0))}</span>
                    <span class="stat-label">Duration</span>
                </div>
            </div>
            <div class="success-bar">
                <div class="success-fill success-{min(result.get('success_rate', 0), 100)}" style="width: {min(result.get('success_rate', 0), 100)}%"></div>
            </div>
            <div class="card-progress">
                <span class="progress-text">{result.get('success_rate', 0)}% success rate</span>
            </div>
            <div class="card-timestamp">{result.get('start_time', 'N/A')}</div>
            <div class="card-path" title="{escape_html(result.get('repo_path', ''))}">{escape_html(result.get('repo_path', 'N/A'))}</div>
            <div class="card-toggle" onclick="toggleRepo('{repo_name}')">▼ Show Test Details</div>
            <div class="repo-details" id="details-{repo_name}">
                <table class="test-table">
                    <thead>
                        <tr>
                            <th>#</th>
                            <th>Test Case</th>
                            <th>Status</th>
                            <th>Duration</th>
                            <th>Exit Code</th>
                            <th>Logs</th>
                        </tr>
                    </thead>
                    <tbody>
"""

        for i, test in enumerate(result.get("tests", []), 1):
            test_status = test.get("status", "skip")
            icon = status_icon(test_status)
            cls = status_class(test_status)
            duration = format_duration(test.get("duration_seconds", 0))
            exit_code = test.get("exit_code", -1)
            stdout_len = test.get("stdout_length", 0)
            stderr_len = test.get("stderr_length", 0)
            has_logs = test.get("has_logs", False)
            log_download = ""

            if has_logs:
                log_download = f"""
                    <span class="log-links">
                        {f'<a class="log-link" href="#" onclick="showLog(\'stdout\', \'{escape_html(test.get(\'name\', \'\'))}\')">stdout</a>' if stdout_len > 0 else ''}
                        {f'<a class="log-link" href="#" onclick="showLog(\'stderr\', \'{escape_html(test.get(\'name\', \'\'))}\')">stderr</a>' if stderr_len > 0 else ''}
                    </span>"""
            else:
                log_download = '<span class="no-logs">—</span>'

            test_name_escaped = escape_html(test.get("name", "unnamed"))
            if len(test_name_escaped) > 60:
                test_name_escaped = test_name_escaped[:57] + "..."

            repo_cards_html += f"""
                        <tr class="test-row {cls}">
                            <td class="test-num">{i}</td>
                            <td class="test-name">{test_name_escaped}</td>
                            <td><span class="status-badge {cls}">{icon} {test_status.upper()}</span></td>
                            <td class="test-duration">{duration}</td>
                            <td class="test-exit">{exit_code}</td>
                            <td class="test-logs">{log_download}</td>
                        </tr>"""

        repo_cards_html += """
                    </tbody>
                </table>
            </div>
        </div>"""

    # Build manifest timeline HTML
    manifest_timeline_html = ""
    for manifest in manifests:
        if manifest["_filename"] == manifests[0]["_filename"]:  # Skip latest (shown in header)
            continue
        r = manifest.get("repos", [])
        manifest_timeline_html += f"""
            <div class="manifest-entry">
                <div class="manifest-header">
                    <span class="manifest-time">{manifest.get('run_at', 'N/A')}</span>
                    <span class="manifest-badge">📦 {manifest.get('total_repos', 0)} repos</span>
                </div>
                <div class="manifest-stats">
                    <span class="manifest-stat passed">✅ {manifest.get('total_passed', 0)}</span>
                    <span class="manifest-stat failed">❌ {manifest.get('total_failed', 0)}</span>
                    <span class="manifest-stat error">💥 {manifest.get('total_errored', 0)}</span>
                    <span class="manifest-stat skipped">⏭️ {manifest.get('total_skipped', 0)}</span>
                    <span class="manifest-stat rate">{manifest.get('overall_success_rate', 0)}%</span>
                </div>
                <div class="manifest-repos">"""

        for rep in r:
            if rep.get("overall_status") == "pass":
                rep_status = "✅"
            elif rep.get("overall_status") == "fail":
                rep_status = "❌"
            elif rep.get("overall_status") == "error":
                rep_status = "💥"
            else:
                rep_status = "⏭️"
            manifest_timeline_html += f'<span class="manifest-repo-badge">{rep_status} {rep["repo_name"]}</span>'

        manifest_timeline_html += f"""
                </div>
                <div class="manifest-link"><a href="#">View details →</a></div>
            </div>"""

    # Build log modal HTML
    log_modal_html = """
    <div id="log-modal" class="modal" style="display:none;">
        <div class="modal-content">
            <div class="modal-header">
                <h3 id="log-modal-title">Log Output</h3>
                <span class="modal-close" onclick="closeLogModal()">&times;</span>
            </div>
            <div class="modal-body" id="log-modal-body"></div>
            <div class="modal-footer">
                <button class="btn" onclick="copyLog()">📋 Copy</button>
                <button class="btn" onclick="downloadLog()">💾 Download</button>
                <button class="btn secondary" onclick="closeLogModal()">Close</button>
            </div>
        </div>
    </div>"""

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Automation Suite - Report Dashboard</title>
    <style>
        :root {{
            --bg: #0d1117;
            --bg-card: #161b22;
            --bg-hover: #1c2333;
            --border: #30363d;
            --text: #e6edf3;
            --text-muted: #8b949e;
            --text-dim: #6e7681;
            --accent: #58a6ff;
            --accent-glow: rgba(88,166,255,0.15);
            --pass: #3fb950;
            --pass-bg: rgba(63,185,80,0.1);
            --fail: #f85149;
            --fail-bg: rgba(248,81,73,0.1);
            --error: #a371f7;
            --error-bg: rgba(163,113,247,0.1);
            --skip: #8b949e;
            --skip-bg: rgba(139,148,158,0.1);
            --running: #d29922;
            --running-bg: rgba(210,153,34,0.1);
        }}

        * {{ margin: 0; padding: 0; box-sizing: border-box; }}

        body {{
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg);
            color: var(--text);
            line-height: 1.5;
            min-height: 100vh;
        }}

        /* Scrollbar */
        ::-webkit-scrollbar {{ width: 8px; height: 8px; }}
        ::-webkit-scrollbar-track {{ background: var(--bg); }}
        ::-webkit-scrollbar-thumb {{ background: var(--border); border-radius: 4px; }}
        ::-webkit-scrollbar-thumb:hover {{ background: var(--text-dim); }}

        /* Header */
        .dashboard-header {{
            background: linear-gradient(180deg, #161b22 0%, var(--bg) 100%);
            border-bottom: 1px solid var(--border);
            padding: 30px 40px;
            position: sticky;
            top: 0;
            z-index: 100;
            backdrop-filter: blur(10px);
        }}

        .header-top {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }}

        .header-title {{
            display: flex;
            align-items: center;
            gap: 12px;
        }}

        .header-title h1 {{
            font-size: 28px;
            font-weight: 700;
            background: linear-gradient(135deg, var(--accent), #a371f7);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            background-clip: text;
        }}

        .header-title .version {{
            font-size: 12px;
            color: var(--text-dim);
            background: var(--bg-card);
            padding: 2px 8px;
            border-radius: 4px;
            border: 1px solid var(--border);
        }}

        .header-actions {{
            display: flex;
            gap: 10px;
        }}

        .btn {{
            padding: 8px 16px;
            border: 1px solid var(--border);
            background: var(--bg-card);
            color: var(--text);
            border-radius: 6px;
            cursor: pointer;
            font-size: 13px;
            font-weight: 500;
            transition: all 0.2s;
            display: inline-flex;
            align-items: center;
            gap: 6px;
        }}

        .btn:hover {{ background: var(--bg-hover); border-color: var(--accent); }}
        .btn.accent {{ background: var(--accent); color: #fff; border-color: var(--accent); }}
        .btn.accent:hover {{ opacity: 0.9; }}
        .btn.secondary {{ background: transparent; }}

        /* Overall Stats */
        .overall-stats {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
            gap: 15px;
        }}

        .overall-stat {{
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 10px;
            padding: 16px 20px;
            text-align: center;
            transition: all 0.2s;
        }}

        .overall-stat:hover {{ border-color: var(--accent); transform: translateY(-2px); }}

        .overall-stat .value {{
            font-size: 32px;
            font-weight: 700;
            display: block;
            margin-bottom: 4px;
        }}

        .overall-stat .label {{
            font-size: 12px;
            color: var(--text-muted);
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }}

        .overall-stat.pass .value {{ color: var(--pass); }}
        .overall-stat.fail .value {{ color: var(--fail); }}
        .overall-stat.error .value {{ color: var(--error); }}
        .overall-stat.skip .value {{ color: var(--skip); }}
        .overall-stat.rate .value {{ color: var(--accent); }}
        .overall-stat.repos .value {{ color: #d29922; }}

        /* Progress Ring */
        .progress-ring {{
            position: relative;
            width: 80px;
            height: 80px;
            margin: 0 auto;
        }}

        .progress-ring svg {{ transform: rotate(-90deg); }}
        .progress-ring circle {{
            fill: none;
            stroke-width: 6;
        }}
        .progress-ring .bg {{ stroke: var(--border); }}
        .progress-ring .fg {{
            stroke: var(--pass);
            stroke-linecap: round;
            transition: stroke-dashoffset 0.5s;
        }}
        .progress-ring .rate-text {{
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            font-size: 16px;
            font-weight: 700;
            color: var(--text);
        }}

        /* Repo Cards */
        .content {{
            padding: 30px 40px;
            max-width: 1600px;
            margin: 0 auto;
        }}

        .section-title {{
            font-size: 20px;
            font-weight: 600;
            margin-bottom: 20px;
            color: var(--text);
            display: flex;
            align-items: center;
            gap: 10px;
        }}

        .repo-card {{
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 12px;
            margin-bottom: 16px;
            overflow: hidden;
            transition: all 0.2s;
        }}

        .repo-card:hover {{ border-color: var(--accent); }}

        .repo-card.card-pass {{ border-left: 4px solid var(--pass); }}
        .repo-card.card-fail {{ border-left: 4px solid var(--fail); }}
        .repo-card.card-error {{ border-left: 4px solid var(--error); }}
        .repo-card.card-neutral {{ border-left: 4px solid var(--skip); }}

        .card-header {{
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 18px 24px;
            background: rgba(0,0,0,0.2);
            border-bottom: 1px solid var(--border);
        }}

        .repo-icon {{ font-size: 22px; }}

        .repo-name {{
            font-size: 16px;
            font-weight: 600;
            color: var(--accent);
        }}

        .repo-branch {{
            font-size: 12px;
            color: var(--text-dim);
            background: var(--bg);
            padding: 2px 10px;
            border-radius: 12px;
            border: 1px solid var(--border);
            margin-left: auto;
            font-family: monospace;
        }}

        .card-stats {{
            display: grid;
            grid-template-columns: repeat(6, 1fr);
            gap: 1px;
            background: var(--border);
        }}

        .card-stats .stat {{
            background: var(--bg-card);
            padding: 12px 16px;
            text-align: center;
        }}

        .stat .value {{
            font-size: 20px;
            font-weight: 700;
            display: block;
        }}

        .stat .label {{
            font-size: 11px;
            color: var(--text-muted);
            text-transform: uppercase;
            letter-spacing: 0.3px;
        }}

        .status-pass {{ color: var(--pass); }}
        .status-fail {{ color: var(--fail); }}
        .status-error {{ color: var(--error); }}
        .status-skip {{ color: var(--skip); }}
        .status-running {{ color: var(--running); }}

        .success-bar {{
            height: 4px;
            background: var(--bg);
            width: 100%;
        }}

        .success-fill {{
            height: 100%;
            transition: width 0.5s;
        }}

        .success-0 {{ background: var(--fail); }}
        .success-100 {{ background: var(--pass); }}
        .success-33 {{ background: var(--fail); }}
        .success-50 {{ background: var(--running); }}
        .success-66 {{ background: #d29922; }}
        .success-75 {{ background: #e3b341; }}
        .success-100 {{ background: var(--pass); }}
        .success-default {{ background: var(--pass); }}

        .card-progress {{
            padding: 8px 24px;
            background: rgba(0,0,0,0.1);
        }}

        .progress-text {{
            font-size: 12px;
            color: var(--text-muted);
        }}

        .card-timestamp {{
            padding: 6px 24px;
            font-size: 11px;
            color: var(--text-dim);
            background: rgba(0,0,0,0.15);
            border-top: 1px solid var(--border);
        }}

        .card-path {{
            padding: 6px 24px;
            font-size: 11px;
            color: var(--text-dim);
            background: var(--bg);
            border-top: 1px solid var(--border);
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            font-family: monospace;
        }}

        .card-toggle {{
            padding: 10px 24px;
            font-size: 13px;
            color: var(--accent);
            cursor: pointer;
            background: var(--bg-card);
            border-top: 1px solid var(--border);
            transition: background 0.2s;
        }}

        .card-toggle:hover {{ background: var(--bg-hover); }}

        .repo-details {{
            display: none;
            border-top: 1px solid var(--border);
            background: var(--bg);
        }}

        .repo-details.visible {{ display: block; }}

        /* Test Table */
        .test-table {{
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
        }}

        .test-table thead th {{
            padding: 10px 16px;
            background: rgba(0,0,0,0.3);
            color: var(--text-muted);
            text-transform: uppercase;
            font-size: 11px;
            letter-spacing: 0.5px;
            font-weight: 600;
            text-align: left;
            border-bottom: 1px solid var(--border);
        }}

        .test-table tbody tr {{
            border-bottom: 1px solid var(--border);
            transition: background 0.15s;
        }}

        .test-table tbody tr:hover {{ background: rgba(88,166,255,0.05); }}

        .test-table tbody tr.status-pass {{ background: var(--pass-bg); }}
        .test-table tbody tr.status-fail {{ background: var(--fail-bg); }}
        .test-table tbody tr.status-error {{ background: var(--error-bg); }}
        .test-table tbody tr.status-skip {{ background: var(--skip-bg); }}

        .test-row td {{
            padding: 10px 16px;
            color: var(--text);
            vertical-align: middle;
        }}

        .test-num {{
            font-family: monospace;
            color: var(--text-dim);
            font-weight: 600;
            width: 40px;
        }}

        .test-name {{
            font-weight: 500;
            max-width: 400px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }}

        .test-duration {{
            font-family: monospace;
            color: var(--text-muted);
            font-size: 12px;
            width: 100px;
        }}

        .test-exit {{
            font-family: monospace;
            color: var(--text-dim);
            width: 60px;
        }}

        .test-logs {{
            width: 140px;
        }}

        .status-badge {{
            display: inline-block;
            padding: 3px 10px;
            border-radius: 12px;
            font-size: 11px;
            font-weight: 600;
            text-transform: uppercase;
        }}

        .status-pass {{ background: var(--pass-bg); color: var(--pass); }}
        .status-fail {{ background: var(--fail-bg); color: var(--fail); }}
        .status-error {{ background: var(--error-bg); color: var(--error); }}
        .status-skip {{ background: var(--skip-bg); color: var(--skip); }}
        .status-running {{ background: var(--running-bg); color: var(--running); }}

        .log-links {{
            display: flex;
            gap: 6px;
        }}

        .log-link {{
            color: var(--accent);
            text-decoration: none;
            font-size: 12px;
            cursor: pointer;
            padding: 2px 6px;
            border-radius: 3px;
            border: 1px solid var(--border);
            transition: all 0.2s;
        }}

        .log-link:hover {{ background: var(--accent-glow); border-color: var(--accent); }}

        .no-logs {{
            color: var(--text-dim);
            font-size: 12px;
        }}

        /* Manifest Timeline */
        .timeline {{ margin-top: 40px; }}

        .manifest-entry {{
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 10px;
            margin-bottom: 12px;
            overflow: hidden;
        }}

        .manifest-header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 20px;
            background: rgba(0,0,0,0.2);
            border-bottom: 1px solid var(--border);
        }}

        .manifest-time {{
            font-size: 13px;
            color: var(--text-muted);
            font-family: monospace;
        }}

        .manifest-badge {{
            font-size: 12px;
            color: var(--accent);
            background: var(--accent-glow);
            padding: 2px 10px;
            border-radius: 12px;
        }}

        .manifest-stats {{
            display: flex;
            gap: 15px;
            padding: 10px 20px;
            border-bottom: 1px solid var(--border);
        }}

        .manifest-stat {{
            font-size: 13px;
            font-weight: 600;
            font-family: monospace;
        }}

        .manifest-stat.passed {{ color: var(--pass); }}
        .manifest-stat.failed {{ color: var(--fail); }}
        .manifest-stat.error {{ color: var(--error); }}
        .manifest-stat.skipped {{ color: var(--skip); }}
        .manifest-stat.rate {{ color: var(--accent); }}

        .manifest-repos {{
            padding: 8px 20px;
            display: flex;
            flex-wrap: wrap;
            gap: 8px;
        }}

        .manifest-repo-badge {{
            font-size: 12px;
            padding: 3px 10px;
            background: var(--bg);
            border: 1px solid var(--border);
            border-radius: 6px;
            color: var(--text-muted);
        }}

        .manifest-link {{
            padding: 8px 20px;
            border-top: 1px solid var(--border);
        }}

        .manifest-link a {{
            color: var(--accent);
            text-decoration: none;
            font-size: 13px;
        }}

        .manifest-link a:hover {{ text-decoration: underline; }}

        /* Modal */
        .modal {{
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0,0,0,0.8);
            z-index: 1000;
            display: flex;
            align-items: center;
            justify-content: center;
        }}

        .modal-content {{
            background: var(--bg-card);
            border: 1px solid var(--border);
            border-radius: 12px;
            width: 80%;
            max-width: 900px;
            max-height: 80vh;
            display: flex;
            flex-direction: column;
        }}

        .modal-header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 16px 20px;
            border-bottom: 1px solid var(--border);
        }}

        .modal-header h3 {{
            color: var(--text);
            font-size: 16px;
        }}

        .modal-close {{
            font-size: 24px;
            color: var(--text-muted);
            cursor: pointer;
            width: 30px;
            height: 30px;
            display: flex;
            align-items: center;
            justify-content: center;
            border-radius: 6px;
            transition: all 0.2s;
        }}

        .modal-close:hover {{ background: var(--bg-hover); color: var(--text); }}

        .modal-body {{
            padding: 16px 20px;
            overflow-y: auto;
            flex: 1;
            font-family: 'Monaco', 'Consolas', monospace;
            font-size: 12px;
            line-height: 1.6;
            white-space: pre-wrap;
            word-break: break-all;
            color: var(--pass);
        }}

        .modal-footer {{
            display: flex;
            gap: 10px;
            padding: 12px 20px;
            border-top: 1px solid var(--border);
            justify-content: flex-end;
        }}

        /* Footer */
        .dashboard-footer {{
            text-align: center;
            padding: 30px 40px;
            color: var(--text-dim);
            font-size: 13px;
            border-top: 1px solid var(--border);
            margin-top: 40px;
        }}

        /* Responsive */
        @media (max-width: 1200px) {{
            .content {{ padding: 20px; }}
            .card-stats {{ grid-template-columns: repeat(3, 1fr); }}
        }}

        @media (max-width: 768px) {{
            .card-stats {{ grid-template-columns: repeat(2, 1fr); }}
            .overall-stats {{ grid-template-columns: repeat(2, 1fr); }}
            .dashboard-header {{ padding: 20px; }}
        }}

        /* Animations */
        @keyframes fadeIn {{
            from {{ opacity: 0; transform: translateY(10px); }}
            to {{ opacity: 1; transform: translateY(0); }}
        }}

        .repo-card {{
            animation: fadeIn 0.3s ease forwards;
        }}

        .repo-card:nth-child(1) {{ animation-delay: 0.05s; }}
        .repo-card:nth-child(2) {{ animation-delay: 0.1s; }}
        .repo-card:nth-child(3) {{ animation-delay: 0.15s; }}
        .repo-card:nth-child(4) {{ animation-delay: 0.2s; }}
        .repo-card:nth-child(5) {{ animation-delay: 0.25s; }}
        .repo-card:nth-child(6) {{ animation-delay: 0.3s; }}
    </style>
</head>
<body>
    <div class="dashboard-header">
        <div class="header-top">
            <div class="header-title">
                <h1>🤖 Automation Suite</h1>
                <span class="version">v1.0.0</span>
            </div>
            <div class="header-actions">
                <button class="btn accent" onclick="refreshDashboard()">🔄 Refresh</button>
                <button class="btn" onclick="exportReport()">📊 Export Report</button>
                <button class="btn" onclick="runAllTests()">▶️ Run All</button>
            </div>
        </div>
        <div class="overall-stats">
            <div class="overall-stat repos">
                <span class="value">{total_repos}</span>
                <span class="label">Repositories</span>
            </div>
            <div class="overall-stat pass">
                <span class="value">{total_passed}</span>
                <span class="label">Passed</span>
            </div>
            <div class="overall-stat fail">
                <span class="value">{total_failed}</span>
                <span class="label">Failed</span>
            </div>
            <div class="overall-stat error">
                <span class="value">{total_errored}</span>
                <span class="label">Errors</span>
            </div>
            <div class="overall-stat skip">
                <span class="value">{total_skipped}</span>
                <span class="label">Skipped</span>
            </div>
            <div class="overall-stat rate">
                <span class="value">{overall_rate}%</span>
                <span class="label">Success Rate</span>
            </div>
            <div class="overall-stat">
                <span class="value">{total_tests}</span>
                <span class="label">Total Tests</span>
            </div>
            <div class="overall-stat">
                <span class="value" style="font-size: 16px; color: var(--text-muted);">
                    {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
                </span>
                <span class="label">Last Run</span>
            </div>
        </div>
    </div>

    <div class="content">
        <div class="section-title">
            <span>📦</span>
            Repositories Test Results
        </div>
        {repo_cards_html}

        {f'<div class="timeline">' + '<div class="section-title"><span>📋</span> Run History</div>' + manifest_timeline_html + '</div>' if manifests else ''}
    </div>

    <div class="dashboard-footer">
        <p>Automation Suite &amp; Report Generator v1.0.0</p>
        <p style="margin-top: 8px;">
            Dashboard accessible via:
            <code style="color: var(--accent);">http://[TAILSCALE-IP]:8080/automation_suite/dashboard.html</code>
        </p>
        <p style="margin-top: 5px; font-size: 11px;">
            Access via Tailscale: <code>tailscale ip</code> → http://[IP]:8080
        </p>
    </div>

    {log_modal_html}

    <script>
        // Toggle repo details
        function toggleRepo(repoName) {{
            const details = document.getElementById('details-' + repoName);
            const toggle = details.previousElementSibling;
            if (details.classList.contains('visible')) {{
                details.classList.remove('visible');
                toggle.textContent = '▼ Show Test Details';
            }} else {{
                details.classList.add('visible');
                toggle.textContent = '▲ Hide Test Details';
            }}
        }}

        // Show log content
        function showLog(type, testName) {{
            const modal = document.getElementById('log-modal');
            const title = document.getElementById('log-modal-title');
            const body = document.getElementById('log-modal-body');

            title.textContent = `${{type === 'stdout' ? '📤' : '📛'}} Log: ${{testName}}`;

            // Fetch log content
            const logFile = type === 'stdout'
                ? '/home/kushal/Documents/Projects/media-rs/android-automation/reports/results/{{repo_name}}/logs/'
                : '/home/kushal/Documents/Projects/media-rs/android-automation/reports/results/{{repo_name}}/logs/';

            body.textContent = 'Loading log content...';
            modal.style.display = 'flex';

            // In production, use fetch to get the actual log file
            // body.textContent = await fetch(logFile).then(r => r.text());
            body.textContent = '(Log file path: ' + logFile + ')\n\nIn deployment, logs would be fetched via HTTP.';
        }}

        function closeLogModal() {{
            document.getElementById('log-modal').style.display = 'none';
        }}

        function copyLog() {{
            const body = document.getElementById('log-modal-body');
            navigator.clipboard.writeText(body.textContent).then(() => {{
                alert('Copied to clipboard!');
            }});
        }}

        function downloadLog() {{
            const body = document.getElementById('log-modal-body');
            const blob = new Blob([body.textContent], {{ type: 'text/plain' }});
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'test-log.txt';
            a.click();
            URL.revokeObjectURL(url);
        }}

        function refreshDashboard() {{
            window.location.reload();
        }}

        function exportReport() {{
            // Generate and download a comprehensive report
            const reportData = {{
                generated_at: new Date().toISOString(),
                total_repos: {total_repos},
                total_tests: {total_tests},
                passed: {total_passed},
                failed: {total_failed},
                success_rate: {overall_rate}
            }};
            const blob = new Blob([JSON.stringify(reportData, null, 2)], {{ type: 'application/json' }});
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'automation_report_{{datetime.now().strftime('%Y%m%d_%H%M%S')}}.json';
            a.click();
            URL.revokeObjectURL(url);
        }}

        function runAllTests() {{
            if (confirm('Run all test suites? This may take a while.')) {{
                alert('Test suite triggered! Check the terminal for progress.');
                // In production, this would trigger a server endpoint
            }}
        }}

        // Auto-refresh every 60 seconds
        setInterval(refreshDashboard, 60000);

        // Auto-expand the first repo by default
        document.addEventListener('DOMContentLoaded', function() {{
            const firstToggle = document.querySelector('.card-toggle');
            if (firstToggle) firstToggle.click();
        }});

        // Close modal on escape
        document.addEventListener('keydown', function(e) {{
            if (e.key === 'Escape') closeLogModal();
        }});
    </script>
</body>
</html>"""

    return html


def save_dashboard():
    """Generate and save the dashboard HTML."""
    DASHBOARD_DIR.mkdir(parents=True, exist_ok=True)
    html = generate_dashboard()
    dashboard_file = DASHBOARD_DIR / "index.html"
    dashboard_file.write_text(html)
    return dashboard_file


if __name__ == "__main__":
    dashboard_file = save_dashboard()
    print(f"Dashboard generated: {dashboard_file}")
    print(f"Total repos tracked: {len(get_all_repo_results())}")
    repos = get_all_repo_results()
    for name, result in repos.items():
        print(f"  {name}: {result.get('passed', 0)}/{result.get('total', 0)} passed ({result.get('success_rate', 0)}%)")
    print(f"\nAccess via: python3 -m http.server 8080")
    print(f"  at {dashboard_file.parent}")
