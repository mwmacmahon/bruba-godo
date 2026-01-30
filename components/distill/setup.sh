#!/bin/bash
# Distill component setup
#
# Sets up the conversation processing pipeline.
#
# Usage: ./components/distill/setup.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Distill Component Setup ==="
echo ""

# Check Python version
echo "Checking Python..."
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is required but not installed."
    echo "Install with: brew install python3"
    exit 1
fi

PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
echo "  Python $PYTHON_VERSION found"

# Check if version is 3.8+
if python3 -c 'import sys; exit(0 if sys.version_info >= (3, 8) else 1)'; then
    echo "  ✓ Version OK (3.8+ required)"
else
    echo "  ✗ Python 3.8+ required, found $PYTHON_VERSION"
    exit 1
fi

# Create output directories
echo ""
echo "Creating directories..."
mkdir -p "$ROOT_DIR/sessions/converted"
mkdir -p "$ROOT_DIR/reference/transcripts"
echo "  ✓ Created sessions/converted/"
echo "  ✓ Created reference/transcripts/"

# Check for dependencies
echo ""
echo "Checking dependencies..."

MISSING_DEPS=()

# Check PyYAML
if ! python3 -c "import yaml" 2>/dev/null; then
    MISSING_DEPS+=("pyyaml")
fi

# Check anthropic (for summary generation)
if ! python3 -c "import anthropic" 2>/dev/null; then
    echo "  Note: anthropic package not installed (optional, for AI summaries)"
fi

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo ""
    echo "Installing missing dependencies: ${MISSING_DEPS[*]}"
    pip3 install "${MISSING_DEPS[@]}"
fi

echo "  ✓ Dependencies OK"

# Check for API key (optional)
echo ""
echo "Checking configuration..."

if [[ -f "$ROOT_DIR/.env" ]] && grep -q "ANTHROPIC_API_KEY" "$ROOT_DIR/.env"; then
    echo "  ✓ ANTHROPIC_API_KEY found in .env"
else
    echo "  Note: No ANTHROPIC_API_KEY in .env"
    echo "        AI summaries will be disabled. Add key to .env to enable."
fi

# Verify config file
if [[ -f "$SCRIPT_DIR/config.yaml" ]]; then
    echo "  ✓ config.yaml exists"
else
    echo "  ✗ config.yaml missing"
    exit 1
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Review config: components/distill/config.yaml"
echo "  2. Add name mappings for redaction (if desired)"
echo "  3. Pull sessions: /pull"
echo "  4. Process: python -m components.distill.lib.cli process sessions/*.jsonl"
echo ""
