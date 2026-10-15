"""Run macOS package tests with bounded execution and useful hang diagnostics."""

import os
import signal
import subprocess
import sys


process = subprocess.Popen(["swift", "test", "--disable-xctest"], start_new_session=True)
try:
    sys.exit(process.wait(timeout=120))
except subprocess.TimeoutExpired:
    print("Swift tests exceeded 120 seconds. Capturing test runner stacks.", flush=True)
    runners = subprocess.run(["pgrep", "-f", "swiftpm-testing"], capture_output=True, text=True)
    for value in runners.stdout.split():
        subprocess.run(["sample", value, "3", "1", "-file", f"/tmp/swift-tests-{value}.sample"], check=False)
        subprocess.run(["cat", f"/tmp/swift-tests-{value}.sample"], check=False)
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    sys.exit(1)
