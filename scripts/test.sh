#!/bin/bash
# Run all tests
set -eo pipefail

echo "==> Running IndexPilot test suite"
swift test --arch arm64 2>&1
echo "==> All tests complete"
