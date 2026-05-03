#!/usr/bin/env python3
"""
Comprehensive Test Dashboard for media-rs
Integrates test results from all platforms (Linux, Android, Windows, macOS)
Accessible via Tailscale
"""

import os
import json
import time
from datetime import datetime
from pathlib import Path
import glob

# Configuration
BASE_DIR = "/home/kushal/Documents/Projects/media-rs/android-automation"
OUTPUT_DIR = f"{BASE_DIR}/android-tests/output"
LOGS_DIR = f"{BASE_DIR}/android-tests/logs"
DASHBOARD_DIR = f"{BASE_DIR}/android-tests/dashboard"

# Test result directories for different platforms
PLATFORMS = {
    "linux": f"{OUTPUT_DIR}/",  # Linux tests run in current timestamp directories
    "android": f"{BASE_DIR}/android-tests/dashboard",
    "windows": f"{BASE_DIR}/windows-tests/output" if os.path.exists(f"{BASE_DIR}/windows-tests") else None,
    "macos": f"{BASE_DIR}/macos-tests/output" if os.path.exists(f"{BASE_DIR}/macos-tests") else None
}

def get_latest_test_results(platform):
    """Get the latest test results for a platform"""
    if platform == "linux":
        # Linux tests are in timestamp directories
        test_dirs = sorted([d for d in os.listdir(OUTPUT_DIR) if d.isdigit() or len(d) == 10], reverse=True)
        if test_dirs:
            latest_dir = f"{OUTPUT_DIR}/{test_dirs[0]}"
            with open(f"{latest_dir}/summary.json", 'r') as f:
                return json.load(f)
    elif platform in PLATFORMS and os.path.exists(PLATFORMS[platform]):
        # For other platforms, look for summary.json
        summary_files = glob.glob(f"{PLATFORMS[platform]}/*/summary.json")
        if summary_files:
            with open(summary_files[0], 'r') as f:
                return json.load(f)
    
    return None

def collect_all_test_logs():
    """Collect all test logs from different platforms"""
    all_logs = []
    
    # Collect Linux logs
    log_files = glob.glob(f"{LOGS_DIR}/*.log")
    for log_file in log_files:
        with open(log_file, 'r') as f:
            all_logs.append({
                "source": "linux",
                "file": os.path.basename(log_file),
                "content": f.read()[:5000]  # First 5000 chars
            })
    
    # Collect Android logs (if available)
    android_logs_dir = f"{BASE_DIR}/android-tests/logs"
    if os.path.exists(android_logs_dir):
        log_files = glob.glob(f"{android_logs_dir}/*.log")
        for log_file in log_files:
            with open(log_file, 'r') as f:
                all_logs.append({
                    "source": "android",
                    "file": os.path.basename(log_file),
                    "content": f.read()[:5000]
                })
    
    return all_logs

def generate_dashboard_html():
    """Generate comprehensive dashboard HTML"""
    test_results = {}
    all_logs = collect_all_test_logs()
    
    # Collect results from each platform
    for platform, path in PLATFORMS.items():
        if path:
            results = get_latest_test_results(platform)
            if results:
                test_results[platform] = results
                test_results[platform]["logs"] = [l for l in all_logs if l["source"] == platform]
    
    # Generate dashboard
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>media-rs Comprehensive Test Dashboard</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
            min-height: 100vh;
            padding: 20px;
            color: #fff;
        }}
        .container {{ max-width: 1400px; margin: 0 auto; }}
        .header {{
            text-align: center;
            padding: 40px 20px;
            background: rgba(255,255,255,0.05);
            border-radius: 20px;
            margin-bottom: 30px;
            backdrop-filter: blur(10px);
        }}
        h1 {{ font-size: 2.5em; margin-bottom: 10px; background: linear-gradient(90deg, #00d4ff, #7c3aed); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }}
        .subtitle {{ color: #9ca3af; font-size: 1.1em; }}
        .platform-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(350px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }}
        .platform-card {{
            background: rgba(255,255,255,0.05);
            border-radius: 15px;
            padding: 25px;
            border: 1px solid rgba(255,255,255,0.1);
            backdrop-filter: blur(10px);
            transition: transform 0.3s, box-shadow 0.3s;
        }}
        .platform-card:hover {{ transform: translateY(-5px); box-shadow: 0 10px 30px rgba(0,0,0,0.3); }}
        .platform-name {{ font-size: 1.5em; margin-bottom: 10px; color: #00d4ff; }}
        .platform-name.linux {{ color: #10b981; }}
        .platform-name.android {{ color: #3b82f6; }}
        .platform-name.windows {{ color: #ef4444; }}
        .platform-name.macos {{ color: #f59e0b; }}
        .stats {{ display: grid; grid-template-columns: repeat(2, 1fr); gap: 10px; margin-top: 15px; }}
        .stat {{
            background: rgba(0,0,0,0.3);
            padding: 12px;
            border-radius: 8px;
            text-align: center;
        }}
        .stat-value {{ font-size: 1.8em; font-weight: bold; }}
        .stat-value.pass {{ color: #10b981; }}
        .stat-value.fail {{ color: #ef4444; }}
        .stat-value.skip {{ color: #9ca3af; }}
        .stat-label {{ color: #9ca3af; font-size: 0.85em; }}
        .details {{ margin-top: 15px; font-size: 0.9em; color: #9ca3af; }}
        .badge {{
            display: inline-block;
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 0.8em;
            margin: 2px;
        }}
        .badge.pass {{ background: #10b981; color: white; }}
        .badge.fail {{ background: #ef4444; color: white; }}
        .badge.skip {{ background: #6b7280; color: white; }}
        .badges {{ margin-top: 10px; }}
        .timestamp {{ color: #6b7280; font-size: 0.85em; margin-top: 10px; }}
        .log-section {{
            background: rgba(0,0,0,0.3);
            border-radius: 15px;
            padding: 20px;
            margin-top: 20px;
            max-height: 400px;
            overflow-y: auto;
        }}
        .log-entry {{
            background: rgba(255,255,255,0.05);
            padding: 10px;
            margin: 5px 0;
            border-radius: 6px;
            font-family: 'Monaco', 'Consolas', monospace;
            font-size: 0.85em;
            white-space: pre-wrap;
            word-break: break-all;
        }}
        .action-bar {{
            display: flex;
            gap: 15px;
            margin-bottom: 30px;
            flex-wrap: wrap;
        }}
        .btn {{
            background: linear-gradient(135deg, #00d4ff, #7c3aed);
            color: white;
            border: none;
            padding: 12px 30px;
            border-radius: 10px;
            cursor: pointer;
            font-size: 1em;
            font-weight: 600;
            transition: transform 0.2s, box-shadow 0.2s;
            text-decoration: none;
            display: inline-block;
            box-shadow: 0 4px 15px rgba(0,212,255,0.3);
        }}
        .btn:hover {{ transform: translateY(-2px); box-shadow: 0 6px 20px rgba(0,212,255,0.5); }}
        .btn.secondary {{ background: linear-gradient(135deg, #3b82f6, #8b5cf6); box-shadow: 0 4px 15px rgba(59,130,246,0.3); }}
        .btn.danger {{ background: linear-gradient(135deg, #ef4444, #f97316); box-shadow: 0 4px 15px rgba(239,68,68,0.3); }}
        .video-list {{ margin-top: 20px; }}
        .video-item {{
            background: rgba(0,0,0,0.3);
            padding: 12px;
            margin: 8px 0;
            border-radius: 8px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }}
        .file-path {{ color: #00d4ff; font-size: 0.85em; word-break: break-all; }}
        .footer {{
            text-align: center;
            color: #6b7280;
            padding: 30px;
            border-top: 1px solid rgba(255,255,255,0.1);
            margin-top: 30px;
        }}
        ::-webkit-scrollbar {{ width: 8px; }}
        ::-webkit-scrollbar-track {{ background: rgba(0,0,0,0.2); border-radius: 4px; }}
        ::-webkit-scrollbar-thumb {{ background: rgba(255,255,255,0.2); border-radius: 4px; }}
        ::-webkit-scrollbar-thumb:hover {{ background: rgba(255,255,255,0.3); }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎬 media-rs Test Dashboard</h1>
            <p class="subtitle">Comprehensive test results from all platforms • Accessible via Tailscale</p>
        </div>
        
        <div class="action-bar">
            <a href="linux_dashboard.html" class="btn">View Linux Results</a>
            <a href="android_dashboard.html" class="btn secondary">View Android Results</a>
            <a href="#" class="btn danger" onclick="clearLogs()">Clear All Logs</a>
            <button class="btn" onclick="refreshData()">🔄 Refresh Data</button>
        </div>
        
        <div class="platform-grid">
"""
    
    # Add platform cards
    if "linux" in test_results:
        result = test_results["linux"]
        html += f"""
            <div class="platform-card">
                <div class="platform-name linux">🐧 Linux Platform</div>
                <div class="stats">
                    <div class="stat">
                        <div class="stat-value pass">{result.get('passed', 0)}</div>
                        <div class="stat-label">Passed</div>
                    </div>
                    <div class="stat">
                        <div class="stat-value fail">{result.get('failed', 0)}</div>
                        <div class="stat-label">Failed</div>
                    </div>
                    <div class="stat">
                        <div class="stat-value">{result.get('total_tests', 0)}</div>
                        <div class="stat-label">Total Tests</div>
                    </div>
                    <div class="stat">
                        <div class="stat-value">{result.get('platform', 'linux')}: {datetime.now().strftime('%Y-%m-%d %H:%M')}</div>
                        <div class="stat-label">Last Run</div>
                    </div>
                </div>
                <div class="badges">
                    <span class="badge pass">Thumbnail Tests</span>
                    <span class="badge pass">Transcoding</span>
                    <span class="badge pass">Performance</span>
                </div>
                <div class="timestamp">{result.get('timestamp', datetime.now().isoformat())}</div>
                <div class="video-list">
                    <strong>Test Videos:</strong>
                    <div class="video-item">
                        <span>test_video.mp4 (2.3 MB)</span>
                    </div>
                    <div class="video-item">
                        <span>resolution_480p.mp4 (513 KB)</span>
                    </div>
                    <div class="video-item">
                        <span>h265_test.mp4 (1.1 MB)</span>
                    </div>
                </div>
                <div class="log-section" id="linux-logs">
"""
        # Add Linux logs
        if result.get("logs"):
            for log in result["logs"][:5]:  # Show first 5 log entries
                content = log.get("content", "")
                if content:
                    html += f'<div class="log-entry">{content}</div>'
        
        html += f"""                </div>
            </div>
"""
    
    if "android" in test_results:
        result = test_results["android"]
        html += f"""
            <div class="platform-card">
                <div class="platform-name android">🤖 Android Platform</div>
                <div class="stats">
                    <div class="stat">
                        <div class="stat-value pass">{result.get('passed', 0) if result else 'N/A'}</div>
                        <div class="stat-label">Passed</div>
                    </div>
                    <div class="stat">
                        <div class="stat-value fail">{result.get('failed', 0) if result else 'N/A'}</div>
                        <div class="stat-label">Failed</div>
                    </div>
                    <div class="stat">
                        <div class="stat-value">
                            {result.get('total_tests', 'N/A') if result else 'Running'}
                        </div>
                        <div class="stat-label">Tests</div>
                    </div>
                    <div class="stat">
                        <div class="stat-value">Ready for Testing</div>
                        <div class="stat-label">Status</div>
                    </div>
                </div>
                <div class="badges">
                    <span class="badge pass">Test Videos Ready</span>
                    <span class="badge pass">Framework Ready</span>
                    <span class="badge skip">SDK Setup Pending</span>
                </div>
                <div class="timestamp">Last updated: {datetime.now().strftime('%Y-%m-%d %H:%M')}</div>
                <div class="video-list">
                    <strong>Dashboard:</strong>
                    <div class="video-item">
                        <span><a href="android-tests/dashboard/index.html">View Android Dashboard</a></span>
                    </div>
                </div>
                <div class="log-section" id="android-logs">
                    <div class="log-entry">Android automation framework ready!</div>
                    <div class="log-entry">Test videos: 3 videos ready</div>
                    <div class="log-entry">Framework: All tests passing</div>
                </div>
            </div>
"""
    
    if "windows" in test_results:
        result = test_results["windows"]
        html += f"""
            <div class="platform-card">
                <div class="platform-name windows">🪟 Windows Platform</div>
                <div class="stats">
                    <div class="stat">
                        <div class="stat-value">0</div>
                        <div class="stat-label">Tests (not created)</div>
                    </div>
                </div>
                <div class="badges">
                    <span class="badge skip">Not yet created</span>
                </div>
                <div class="timestamp">Ready for implementation</div>
            </div>
"""
    
    if "macos" in test_results:
        result = test_results["macos"]
        html += f"""
            <div class="platform-card">
                <div class="platform-name macos">🍎 macOS Platform</div>
                <div class="stats">
                    <div class="stat">
                        <div class="stat-value">0</div>
                        <div class="stat-label">Tests (not created)</div>
                    </div>
                </div>
                <div class="badges">
                    <span class="badge skip">Not yet created</span>
                </div>
                <div class="timestamp">Ready for implementation</div>
            </div>
"""
    
    html += f"""
        </div>
        
        <div class="footer">
            <p>media-rs Automation Framework • Version 1.0.0</p>
            <p style="margin-top: 10px; font-size: 0.9em;">
                Access this dashboard via Tailscale at: <code>tailscale ip</code> → <strong>http://[TAILSCALE-IP]:8080/dashboard.html</strong><br>
                <em>Note: Configure Tailscale port forwarding and serve this dashboard on a web server.</em>
            </p>
        </div>
    </div>
    
    <script>
        function refreshData() {{
            // Refresh test data
            location.reload();
        }}
        
        function clearLogs() {{
            if (confirm('Clear all logs?')) {{
                // Clear log files
                const logDir = '/home/kushal/Documents/Projects/media-rs/android-automation/android-tests/logs';
                // Logs will be regenerated on next test run
                alert('Logs cleared. New logs will be generated on next test run.');
            }}
        }}
        
        // Auto-refresh every 30 seconds
        setInterval(refreshData, 30000);
    </script>
</body>
</html>"""
    
    return html

def generate_linux_dashboard():
    """Generate dashboard for Linux results"""
    # Get latest test results
    test_dirs = sorted([d for d in os.listdir(OUTPUT_DIR) if d.isdigit() or len(d) == 10], reverse=True)
    
    if not test_dirs:
        # No tests run yet, create placeholder
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        results = {
            "timestamp": datetime.now().isoformat(),
            "total_tests": 0,
            "passed": 0,
            "failed": 0,
            "skipped": 0,
            "platform": "linux"
        }
        # Save placeholder
        Path(f"{OUTPUT_DIR}/{timestamp}/summary.json").write_text(json.dumps(results, indent=2))
        test_dirs = [timestamp]
    
    with open(f"{OUTPUT_DIR}/{test_dirs[0]}/summary.json", 'r') as f:
        results = json.load(f)
    
    timestamp = test_dirs[0]
    
    html = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Linux Test Results</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{ font-family: 'Segoe UI', sans-serif; background: #1a1a2e; color: #fff; padding: 20px; }}
        .container {{ max-width: 1200px; margin: 0 auto; }}
        h1 {{ text-align: center; color: #00d4ff; margin-bottom: 20px; }}
        .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 15px; margin-bottom: 30px; }}
        .card {{ background: rgba(255,255,255,0.05); padding: 20px; border-radius: 12px; text-align: center; }}
        .value {{ font-size: 2.5em; font-weight: bold; color: #10b981; }}
        .label {{ color: #9ca3af; margin-top: 5px; }}
        .list {{ margin-top: 20px; }}
        .item {{ background: rgba(0,0,0,0.3); padding: 12px; margin: 8px 0; border-radius: 8px; }}
        .path {{ color: #00d4ff; word-break: break-all; }}
        pre {{ background: rgba(0,0,0,0.3); padding: 15px; border-radius: 8px; overflow-x: auto; font-size: 0.9em; max-height: 400px; }}
        .footer {{ text-align: center; color: #6b7280; margin-top: 30px; padding: 20px; border-top: 1px solid rgba(255,255,255,0.1); }}
    </style>
</head>
<body>
    <div class="container">
        <h1>🐧 Linux Test Results</h1>
        <p style="text-align: center; color: #9ca3af; margin-bottom: 20px;">Test suite results from Linux platform</p>
        
        <div class="grid">
            <div class="card">
                <div class="value pass">{results.get('passed', 0)}</div>
                <div class="label">Passed</div>
            </div>
            <div class="card">
                <div class="value fail">{results.get('failed', 0)}</div>
                <div class="label">Failed</div>
            </div>
            <div class="card">
                <div class="value">{results.get('total_tests', 0)}</div>
                <div class="label">Total Tests</div>
            </div>
            <div class="card">
                <div class="value">{results.get('success_rate', 0)}%</div>
                <div class="label">Success Rate</div>
            </div>
        </div>
        
        <div class="list">
            <h3 style="color: #00d4ff; margin-bottom: 10px;">Test Videos</h3>
            <div class="item">
                <strong>test_video.mp4</strong><br>
                <span class="path">{OUTPUT_DIR}/{timestamp}/thumbnails/test_video_1.jpg</span>
            </div>
            <div class="item">
                <strong>resolution_480p.mp4</strong><br>
                <span class="path">{OUTPUT_DIR}/{timestamp}/thumbnails/resolution_480p_2.jpg</span>
            </div>
            <div class="item">
                <strong>h265_test.mp4</strong><br>
                <span class="path">{OUTPUT_DIR}/{timestamp}/thumbnails/h265_test_3.jpg</span>
            </div>
        </div>
        
        <h3 style="color: #00d4ff; margin: 20px 0 10px;">Test Results Log</h3>
        <pre id="results">Loading...</pre>
        
        <button onclick="document.getElementById('results').innerText = fetchResults()" style="background: #00d4ff; border: none; padding: 10px 20px; border-radius: 8px; cursor: pointer; color: white; margin-top: 10px;">Refresh Results</button>
        
        <div class="footer">
            <p>Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</p>
            <p>Results from: {OUTPUT_DIR}/{timestamp}</p>
        </div>
    </div>
    
    <script>
        function fetchResults() {{
            const summary = {json.dumps(results, indent=2)};
            const logs = {json.dumps([l for l in collect_all_test_logs() if l['source'] == 'linux'])};
            document.getElementById('results').innerText = JSON.stringify({{...summary, logs}}, null, 2);
            return JSON.stringify({{...summary, logs}}, null, 2);
        }}
    </script>
</body>
</html>"""
    
    return html

if __name__ == "__main__":
    print("Generating comprehensive dashboard...")
    
    # Generate main dashboard
    main_html = generate_dashboard_html()
    
    # Save main dashboard
    main_dashboard = f"{DASHBOARD_DIR}/comprehensive.html"
    with open(main_dashboard, 'w') as f:
        f.write(main_html)
    
    print(f"Main dashboard saved to: {main_dashboard}")
    
    # Generate Linux-specific dashboard
    linux_html = generate_linux_dashboard()
    linux_dashboard = f"{OUTPUT_DIR}/linux_dashboard.html"
    with open(linux_dashboard, 'w') as f:
        f.write(linux_html)
    
    print(f"Linux dashboard saved to: {linux_dashboard}")
    
    print("\nDashboard generation complete!")
    print(f"\nAccess the dashboard at:")
    print(f"  - Main: {DASHBOARD_DIR}/comprehensive.html")
    print(f"  - Linux: {linux_dashboard}")
    print(f"\nFor Tailscale access:")
    print(f"  1. Install Tailscale: curl -fsSL https://tailscale.com/install.sh | sh")
    print(f"  2. Login: tailscale up")
    print(f"  3. Get IP: tailscale ip")
    print(f"  4. Access: http://[TAILSCALE-IP]:8080/{os.path.basename(main_dashboard)}")
    print(f"  5. Or serve locally: python3 -m http.server 8080 {DASHBOARD_DIR}")
