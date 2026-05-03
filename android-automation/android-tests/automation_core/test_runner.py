#!/usr/bin/env python3
"""
Test Runner for media-rs Android Automation

Core orchestration framework that:
1. Manages test execution
2. Collects and analyzes logs
3. Handles errors and warnings
4. Generates test reports
5. Integrates with dashboard
"""

import os
import json
import logging
import sys
import time
from datetime import datetime
from pathlib import Path
import shutil
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Lock

# Import test cases
import thumbnail_generation
import transcoding

# Setup logging
logger = logging.getLogger(__name__)

class TestRunner:
    def __init__(self, config_path):
        self.config = self._load_config(config_path)
        self.test_videos_dir = Path(self.config.get('test_videos_dir', 
                '/home/kushal/Documents/Projects/media-rs/android-automation/android-tests/test_videos'))
        self.output_dir = Path(self.config.get('output_dir',
                '/home/kushal/Documents/Projects/media-rs/android-automation/android-tests/output'))
        self.logs_dir = Path(self.config.get('logs_dir',
                '/home/kushal/Documents/Projects/media-rs/android-automation/android-tests/logs'))
        self.dashboard_dir = Path(self.config.get('dashboard_dir',
                '/home/kushal/Documents/Projects/media-rs/android-automation/android-tests/dashboard'))
        
        # Ensure directories exist
        for directory in [self.output_dir, self.logs_dir, self.dashboard_dir]:
            directory.mkdir(parents=True, exist_ok=True)
        
        self.test_results = []
        self.lock = Lock()
        
    def _load_config(self, config_path):
        """Load configuration from file"""
        try:
            with open(config_path, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            # Default configuration
            return {
                'test_videos_dir': self.test_videos_dir,
                'output_dir': self.output_dir,
                'logs_dir': self.logs_dir,
                'dashboard_dir': self.dashboard_dir,
                'max_workers': 4,
                'log_level': 'INFO'
            }
    
    def run_all_tests(self):
        """Run all test suites"""
        logger.info("=" * 60)
        logger.info("Starting automated test run")
        logger.info("=" * 60)
        
        # Clean previous results
        cleanup_old_results()
        
        # Get available video files
        video_files = self._get_available_video_files()
        
        if not video_files:
            logger.warning("No video files found for testing")
            self._create_empty_results()
            return self._generate_summary()
        
        logger.info(f"Found {len(video_files)} video files for testing")
        
        # Initialize test cases
        thumbnail_tester = thumbnail_generation.ThumbnailGeneratorTest(
            str(self.test_videos_dir), str(self.output_dir)
        )
        
        transcoding_tester = transcoding.TranscodingTest(
            str(self.test_videos_dir), str(self.output_dir)
        )
        
        # Run thumbnail tests
        logger.info("Running thumbnail generation tests...")
        start_time = time.time()
        thumbnail_results = thumbnail_tester.run_all_thumbnail_tests()
        thumbnail_duration = time.time() - start_time
        
        with self.lock:
            self.test_results.extend(thumbnail_results)
        
        # Run transcoding tests
        logger.info("Running transcoding tests...")
        start_time = time.time()
        transcoding_results = transcoding_tester.run_all_transcoding_tests()
        transcoding_duration = time.time() - start_time
        
        with self.lock:
            self.test_results.extend(transcoding_results)
        
        # Collect and analyze logs
        logger.info("Collecting test logs...")
        self._collect_logs()
        
        # Analyze results
        logger.info("Analyzing test results...")
        self._analyze_results()
        
        # Generate summary
        summary = self._generate_summary()
        
        # Log performance
        total_duration = time.time() - start_time
        logger.info(f"Total test run duration: {total_duration:.2f} seconds")
        logger.info(f"Thumbnail tests: {len(thumbnail_results)} tests, {thumbnail_duration:.2f}s")
        logger.info(f"Transcoding tests: {len(transcoding_results)} tests, {transcoding_duration:.2f}s")
        
        # Save results
        self._save_results()
        
        return summary
    
    def _get_available_video_files(self):
        """Get available video files for testing"""
        video_extensions = ['.mp4', '.avi', '.mkv', '.webm', '.mov', '.3gp']
        video_files = []
        
        for ext in video_extensions:
            video_files.extend(self.test_videos_dir.glob(f"*{ext}"))
        
        # Also add any files without specific extension
        all_files = list(self.test_videos_dir.glob("*"))
        for file_path in all_files:
            if file_path not in video_files and file_path.is_file():
                video_files.append(file_path)
        
        return sorted(video_files, key=lambda p: p.stat().st_mtime, reverse=True)
    
    def _create_empty_results(self):
        """Create empty results when no videos are available"""
        with self.lock:
            self.test_results = []
            
            # Create summary
            summary = {
                'timestamp': datetime.now().isoformat(),
                'total_tests': 0,
                'passed': 0,
                'failed': 0,
                'skipped': 0,
                'duration_seconds': 0,
                'tests': []
            }
            
            # Save results
            with open(f"{self.output_dir}/test_results.json", 'w') as f:
                json.dump(summary, f, indent=2)
            
            return summary
    
    def _collect_logs(self):
        """Collect logs from all test executions"""
        log_files = [
            'thumbnail_test.log',
            'transcoding_test.log'
        ]
        
        for log_file in log_files:
            log_path = self.logs_dir / log_file
            if log_path.exists():
                # Read and analyze logs
                try:
                    with open(log_path, 'r') as f:
                        log_content = f.read()
                        
                    # Analyze for errors and warnings
                    error_count = log_content.count('ERROR')
                    warning_count = log_content.count('WARNING')
                    
                    # Log analysis
                    logger.info(f"Log file: {log_file}")
                    logger.info(f"Errors: {error_count}, Warnings: {warning_count}")
                    
                    # Save log analysis
                    analysis = {
                        'log_file': log_file,
                        'lines': len(log_content.split('\n')),
                        'errors': error_count,
                        'warnings': warning_count
                    }
                    
                    with open(self.logs_dir / f"{log_file.replace('.log', '_analysis.json')}", 'w') as f:
                        json.dump(analysis, f, indent=2)
                        
                except Exception as e:
                    logger.error(f"Failed to analyze log file {log_file}: {e}")
    
    def _analyze_results(self):
        """Analyze test results for errors and warnings"""
        total_tests = len(self.test_results)
        passed = sum(1 for r in self.test_results if r.get('status') == 'pass')
        failed = sum(1 for r in self.test_results if r.get('status') == 'fail')
        skipped = sum(1 for r in self.test_results if r.get('status') == 'skip')
        
        logger.info(f"Test analysis:")
        logger.info(f"  Total: {total_tests}, Passed: {passed}, Failed: {failed}, Skipped: {skipped}")
        
        # Create analysis file
        analysis = {
            'total_tests': total_tests,
            'passed': passed,
            'failed': failed,
            'skipped': skipped,
            'success_rate': (passed / total_tests * 100) if total_tests > 0 else 0
        }
        
        with open(self.logs_dir / 'test_analysis.json', 'w') as f:
            json.dump(analysis, f, indent=2)
        
        return analysis
    
    def _generate_summary(self):
        """Generate test run summary"""
        total_tests = len(self.test_results)
        passed = sum(1 for r in self.test_results if r.get('status') == 'pass')
        failed = sum(1 for r in self.test_results if r.get('status') == 'fail')
        skipped = sum(1 for r in self.test_results if r.get('status') == 'skip')
        
        summary = {
            'timestamp': datetime.now().isoformat(),
            'total_tests': total_tests,
            'passed': passed,
            'failed': failed,
            'skipped': skipped,
            'success_rate': (passed / total_tests * 100) if total_tests > 0 else 0,
            'tests': self.test_results
        }
        
        # Save summary to dashboard
        dashboard_file = self.dashboard_dir / f"summary_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
        with open(dashboard_file, 'w') as f:
            json.dump(summary, f, indent=2)
        
        # Create visual dashboard (HTML)
        self._create_html_dashboard(summary)
        
        logger.info(f"Summary saved to: {dashboard_file}")
        
        return summary
    
    def _create_html_dashboard(self, summary):
        """Create HTML dashboard with visual test results"""
        html_content = f"""<!DOCTYPE html>
<html>
<head>
    <title>media-rs Test Dashboard</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }}
        .container {{ max-width: 1200px; margin: 0 auto; }}
        h1 {{ color: #333; }}
        .stats {{ display: flex; gap: 20px; margin: 20px 0; }}
        .stat-card {{ background: white; padding: 20px; border-radius: 8px; flex: 1; text-align: center; }}
        .stat-value {{ font-size: 2em; font-weight: bold; }}
        .passed {{ color: #28a745; }}
        .failed {{ color: #dc3545; }}
        .skipped {{ color: #6c757d; }}
        .table {{ background: white; border-radius: 8px; overflow: hidden; }}
        .table th, .table td {{ padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }}
        .table th {{ background: #f8f9fa; font-weight: bold; }}
        .status {{ padding: 4px 8px; border-radius: 4px; font-size: 0.9em; }}
        .status.pass {{ background: #d4edda; color: #155724; }}
        .status.fail {{ background: #f8d7da; color: #721c24; }}
        .status.skip {{ background: #e2e3e5; color: #383d41; }}
        .timestamp {{ color: #666; font-size: 0.9em; }}
    </style>
</head>
<body>
    <div class="container">
        <h1>media-rs Test Dashboard</h1>
        <p class="timestamp">Generated: {summary['timestamp']}</p>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-value passed">{summary['passed']}</div>
                <div>Passed</div>
            </div>
            <div class="stat-card">
                <div class="stat-value failed">{summary['failed']}</div>
                <div>Failed</div>
            </div>
            <div class="stat-card">
                <div class="stat-value skipped">{summary['skipped']}</div>
                <div>Skipped</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">{summary['total_tests']}</div>
                <div>Total Tests</div>
            </div>
        </div>
        
        <h2>Test Results</h2>
        <div class="table">
            <table>
                <thead>
                    <tr>
                        <th>Test</th>
                        <th>Input Video</th>
                        <th>Format/Codec</th>
                        <th>Status</th>
                        <th>Message</th>
                    </tr>
                </thead>
                <tbody>
                    {self._generate_test_rows(summary['tests'])}
                </tbody>
            </table>
        </div>
    </div>
</body>
</html>"""
        
        dashboard_file = self.dashboard_dir / f"dashboard_{datetime.now().strftime('%Y%m%d_%H%M%S')}.html"
        with open(dashboard_file, 'w') as f:
            f.write(html_content)
        
        return dashboard_file
    
    def _generate_test_rows(self, tests):
        """Generate HTML table rows for tests"""
        rows = ""
        for test in tests:
            status_class = test.get('status', 'skip')
            status_display = test.get('status', 'skip').upper()
            message = test.get('message', '')
            
            rows += f"""
                <tr>
                    <td>{test.get('test', 'N/A')}</td>
                    <td>{test.get('input_video', test.get('video', 'N/A'))}</td>
                    <td>{test.get('output_format', test.get('expected_format', 'N/A'))} / {test.get('codec', 'N/A')}</td>
                    <td><span class="status {status_class}">{status_display}</span></td>
                    <td>{message}</td>
                </tr>
            """
        
        return rows
    
    def _save_results(self):
        """Save test results to JSON file"""
        summary = self._generate_summary()
        with open(f"{self.output_dir}/test_results.json", 'w') as f:
            json.dump(summary, f, indent=2)
        
        return summary

def cleanup_old_results():
    """Clean up old test results"""
    now = datetime.now()
    for directory in [Path('/home/kushal/Documents/Projects/media-rs/android-automation/android-tests/output'),
                      Path('/home/kushal/Documents/Projects/media-rs/android-automation/android-tests/logs')]:
        if directory.exists():
            for item in directory.iterdir():
                if item.is_file():
                    try:
                        mod_time = datetime.fromtimestamp(item.stat().st_mtime)
                        # Keep files from last 24 hours
                        if now - mod_time > timedelta(hours=24):
                            item.unlink()
                            print(f"Removed old file: {item}")
                    except Exception as e:
                        print(f"Error cleaning up {item}: {e}")

if __name__ == "__main__":
    # Run tests
    runner = TestRunner('/home/kushal/Documents/Projects/media-rs/android-automation/android-tests/config.json')
    summary = runner.run_all_tests()
    
    print(f"\n{'='*60}")
    print("Test Run Summary")
    print(f"{'='*60}")
    print(f"Total Tests: {summary['total_tests']}")
    print(f"Passed: {summary['passed']}")
    print(f"Failed: {summary['failed']}")
    print(f"Skipped: {summary['skipped']}")
    print(f"Success Rate: {summary['success_rate']:.2f}%")
    print(f"{'='*60}")
