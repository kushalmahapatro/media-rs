#!/usr/bin/env python3
"""
Automation Suite Engine
- Discovers all git repos under base_path
- Runs test commands per repo
- Collects results (pass/fail, duration, stdout/stderr logs)
- Saves structured results for dashboard consumption
"""

import os
import sys
import json
import subprocess
import time
import hashlib
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any, Optional

BASE_DIR = Path("/home/kushal/Documents/Projects/media-rs/android-automation")
DATA_DIR = BASE_DIR / "data"
REPORTS_DIR = BASE_DIR / "reports"
RESULTS_DIR = REPORTS_DIR / "results"
LOGS_DIR = BASE_DIR / "automation_logs"
BASE_PATH = "/home/kushal/Documents/Projects"


def format_duration(seconds):
    if seconds < 1:
        return f"{seconds*1000:.0f}ms"
    elif seconds < 60:
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


class TestResult:
    def __init__(self, name, repo_name, status="running", duration=0.0, exit_code=-1, stdout="", stderr=""):
        self.name = name
        self.repo_name = repo_name
        self.status = status
        self.duration = duration
        self.exit_code = exit_code
        self.stdout = stdout
        self.stderr = stderr
        self.timestamp = datetime.now().isoformat()
        self.log_id = hashlib.md5(f"{repo_name}:{name}".encode()).hexdigest()[:12]

    def to_dict(self):
        return {
            "name": self.name,
            "repo": self.repo_name,
            "status": self.status,
            "duration_seconds": round(self.duration, 3),
            "duration_human": format_duration(self.duration),
            "exit_code": self.exit_code,
            "stdout_length": len(self.stdout),
            "stderr_length": len(self.stderr),
            "timestamp": self.timestamp,
            "log_id": self.log_id,
        }

    def save_logs(self, repo_name):
        log_dir = LOGS_DIR / repo_name / self.log_id
        log_dir.mkdir(parents=True, exist_ok=True)
        if self.stdout:
            (log_dir / "stdout.txt").write_text(self.stdout)
        if self.stderr:
            (log_dir / "stderr.txt").write_text(self.stderr)


class RepoResult:
    def __init__(self, name, path, branch="main", repo_type="unknown"):
        self.name = name
        self.path = path
        self.branch = branch
        self.repo_type = repo_type
        self.tests = []
        self.started = datetime.now()
        self.ended = None

    @property
    def total_duration(self):
        end = self.ended or datetime.now()
        return (end - self.started).total_seconds()

    @property
    def passed(self):
        return sum(1 for t in self.tests if t.status == "pass")

    @property
    def failed(self):
        return sum(1 for t in self.tests if t.status == "fail")

    @property
    def errored(self):
        return sum(1 for t in self.tests if t.status == "error")

    @property
    def skipped(self):
        return sum(1 for t in self.tests if t.status == "skip")

    @property
    def total(self):
        return len(self.tests)

    @property
    def success_rate(self):
        return (self.passed / self.total * 100) if self.total else 0.0

    @property
    def status_label(self):
        if self.total == 0:
            return "no_tests"
        if self.failed == 0 and self.errored == 0:
            return "pass"
        if self.failed > 0:
            return "fail"
        return "error"

    def add_test(self, tr):
        self.tests.append(tr)

    def finish(self):
        self.ended = datetime.now()

    def to_dict(self):
        return {
            "name": self.name,
            "path": self.path,
            "branch": self.branch,
            "type": self.repo_type,
            "total": self.total,
            "passed": self.passed,
            "failed": self.failed,
            "errored": self.errored,
            "skipped": self.skipped,
            "success_rate": round(self.success_rate, 1),
            "duration_seconds": round(self.total_duration, 3),
            "duration_human": format_duration(self.total_duration),
            "start": self.started.isoformat(),
            "end": self.ended.isoformat() if self.ended else None,
            "status_label": self.status_label,
            "tests": [t.to_dict() for t in self.tests],
        }

    def save(self):
        repo_dir = RESULTS_DIR / self.name
        repo_dir.mkdir(parents=True, exist_ok=True)
        (repo_dir / "result.json").write_text(json.dumps(self.to_dict(), indent=2))
        tests_dir = repo_dir / "tests"
        tests_dir.mkdir(exist_ok=True)
        for tr in self.tests:
            tr_dir = tests_dir / tr.log_id
            tr_dir.mkdir(parents=True, exist_ok=True)
            (tr_dir / "test.json").write_text(json.dumps(tr.to_dict(), indent=2))
            tr.save_logs(self.name)


def test_commands(repo):
    p = Path(repo["path"])
    cmds = []
    if repo["type"] == "flutter":
        cmds.append(("flutter test", f"cd {p} && flutter test --machine 2>&1", 600))
    elif repo["type"] == "nodejs":
        if (p / "package.json").exists():
            cmds.append(("npm test", f"cd {p} && npm test 2>&1", 300))
    elif repo["type"] == "rust":
        if (p / "Cargo.toml").exists():
            cmds.append(("cargo test", f"cd {p} && cargo test 2>&1", 300))
    elif repo["type"] == "python":
        for tf in list(p.glob("test_*.py")) + list(p.glob("*_test.py")):
            cmds.append((f"python test: {tf.name}", f"cd {p} && python3 {tf} 2>&1", 300))
    elif repo["type"] == "generic":
        if (p / "Makefile").exists():
            cmds.append(("make test", f"cd {p} && make test 2>&1", 300))
    # shell scripts
    for sh in p.glob("*.sh"):
        low = sh.name.lower()
        if "test" in low or "run" in low or "check" in low:
            cmds.append((f"bash: {sh.name}", f"cd {p} && bash {sh} 2>&1", 300))
    if not cmds:
        cmds.append(("test scan", f"find {p} -maxdepth 3 -name '*test*' -o -name '*Test*' 2>/dev/null | head -30", 30))
    return cmds


def run_one(name, cmd, timeout, cwd):
    start = time.time()
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout, cwd=cwd)
        elapsed = time.time() - start
        status = "pass" if r.returncode == 0 else ("skip" if "no tests" in r.stderr.lower() else "fail")
        return TestResult(name=name, repo_name="", status=status, duration=elapsed, exit_code=r.returncode, stdout=r.stdout, stderr=r.stderr)
    except subprocess.TimeoutExpired:
        elapsed = time.time() - start
        return TestResult(name=name, repo_name="", status="error", duration=elapsed, exit_code=-1, stdout="", stderr=f"timed out after {timeout}s")
    except Exception as e:
        elapsed = time.time() - start
        return TestResult(name=name, repo_name="", status="error", duration=elapsed, exit_code=-1, stdout="", stderr=str(e))


def discover_repos(base_path):
    repos = []
    seen = set()
    for root, dirs, files in os.walk(base_path):
        if ".git" in dirs:
            rp = Path(root)
            if rp.name in seen:
                dirs.clear()
                continue
            seen.add(rp.name)
            if (rp / "pubspec.yaml").exists():
                t = "flutter"
            elif (rp / "package.json").exists():
                t = "nodejs"
            elif (rp / "Cargo.toml").exists():
                t = "rust"
            elif (rp / "setup.py").exists() or (rp / "pyproject.toml").exists():
                t = "python"
            else:
                t = "generic"
            repos.append({"name": rp.name, "path": str(rp), "type": t, "branch": "main"})
            dirs.clear()
    return sorted(repos, key=lambda x: x["name"])


def run_suite(repos):
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    results = []

    print(f"\n{'='*80}")
    print(f"  AUTOMATION SUITE — Test Run")
    print(f"{'='*80}")
    print(f"  {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"  Repos discovered: {len(repos)}\n")

    for repo in repos:
        rr = RepoResult(repo["name"], repo["path"], repo["branch"], repo["type"])
        print(f"  📦 {repo['name']} ({repo['type']})  →  {repo['path']}")
        cmds = test_commands(repo)
        for display, cmd, to in cmds:
            print(f"    ▶ {display:40s} ... ", end="", flush=True)
            tr = run_one(display, cmd, to, repo["path"])
            tr.repo_name = repo["name"]
            rr.add_test(tr)
            icon = {"pass": "✅", "fail": "❌", "error": "💥", "skip": "⏭️"}[tr.status]
            print(f"{icon} {tr.status:>5s}  ({format_duration(tr.duration)})")
        rr.finish()
        rr.save()
        results.append(rr)
        print()

    manifest = {
        "run_id": datetime.now().strftime("%Y%m%d_%H%M%S"),
        "run_at": datetime.now().isoformat(),
        "repos": [r.to_dict() for r in results],
        "summary": {
            "total_repos": len(results),
            "total_tests": sum(r.total for r in results),
            "total_passed": sum(r.passed for r in results),
            "total_failed": sum(r.failed for r in results),
            "total_errored": sum(r.errored for r in results),
            "total_skipped": sum(r.skipped for r in results),
            "success_rate": round(sum(r.success_rate for r in results) / len(results), 1) if results else 0,
        },
    }
    (REPORTS_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2))
    s = manifest["summary"]
    print(f"{'='*80}")
    print(f"  SUMMARY")
    print(f"{'='*80}")
    print(f"  Repos:        {s['total_repos']}")
    print(f"  Tests:        {s['total_tests']}")
    print(f"  ✅ Passed:    {s['total_passed']}")
    print(f"  ❌ Failed:    {s['total_failed']}")
    print(f"  💥 Errors:    {s['total_errored']}")
    print(f"  ⏭️ Skipped:   {s['total_skipped']}")
    print(f"  📊 Success:   {s['success_rate']}%")
    print(f"  📂 Results:   {RESULTS_DIR}")
    print(f"  📝 Logs:      {LOGS_DIR}")
    print(f"{'='*80}\n")
    return results


if __name__ == "__main__":
    repos = discover_repos(BASE_PATH)
    print(f"Discovered {len(repos)} repos\n")
    for r in repos:
        print(f"  - {r['name']} ({r['type']})  →  {r['path']}")
    print()
    run_suite(repos)
