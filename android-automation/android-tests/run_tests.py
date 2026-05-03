#!/usr/bin/env python3
"""
Simple test runner for media-rs Android Automation
"""

import sys
import os

# Add current directory to path
sys.path.insert(0, '/home/kushal/Documents/Projects/media-rs/android-automation/android-tests')

from automation_core.test_runner import TestRunner

if __name__ == "__main__":
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
    
    # Save summary
    with open('/home/kushal/Documents/Projects/media-rs/android-automation/android-tests/output/summary.json', 'w') as f:
        import json
        json.dump(summary, f, indent=2)
    
    print(f"\nSummary saved to: output/summary.json")
    print(f"Dashboard available at: dashboard/")
