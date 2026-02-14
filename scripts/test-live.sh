#!/usr/bin/env bash
# Run live provider integration tests with API keys from .env
#
# Usage:
#   ./scripts/test-live.sh          # Load .env and run all live tests
#   ./scripts/test-live.sh path/to/.env  # Use a custom .env file

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ENV_FILE="${1:-$PROJECT_ROOT/.env}"

if [ ! -f "$ENV_FILE" ]; then
    echo "Error: .env file not found at $ENV_FILE"
    echo "Copy .env.example to .env and fill in your API keys:"
    echo "  cp .env.example .env"
    exit 1
fi

# Export variables from .env (skip comments and blank lines)
set -a
while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and blank lines
    [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
    # Only export lines that look like KEY=VALUE
    [[ "$line" =~ ^[A-Z_]+= ]] && eval "$line"
done < "$ENV_FILE"
set +a

# Show which providers have keys configured
echo "Provider status:"
echo "  OpenAI:    $([ -n "${OPENAI_API_KEY:-}" ] && echo 'configured' || echo 'skipped (no OPENAI_API_KEY)')"
echo "  Anthropic: $([ -n "${ANTHROPIC_API_KEY:-}" ] && echo 'configured' || echo 'skipped (no ANTHROPIC_API_KEY)')"
echo "  Google:    $([ -n "${GOOGLE_GENERATIVE_AI_API_KEY:-}" ] && echo 'configured' || echo 'skipped (no GOOGLE_GENERATIVE_AI_API_KEY)')"
echo "  xAI:       $([ -n "${XAI_API_KEY:-}" ] && echo 'configured' || echo 'skipped (no XAI_API_KEY)')"
echo "  Azure:     $([ -n "${AZURE_API_KEY:-}" ] && echo 'configured' || echo 'skipped (no AZURE_API_KEY)')"
echo ""

cd "$PROJECT_ROOT"
echo "Running live tests..."
echo ""
zig build test-live
