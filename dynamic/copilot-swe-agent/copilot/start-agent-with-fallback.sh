#!/usr/bin/env bash
set -euo pipefail

PRIMARY="${1:-gpt-5.3}"
FALLBACK="${2:-gpt-4o}"
LOG="${RUNNER_TEMP:-/tmp}/copilot-agent.log"

echo "Starting Copilot agent with model: $PRIMARY"

# List of possible agent entrypoint candidates in order of likelihood.
CANDIDATES=(
  "./copilot"
  "./run"
  "./start"
  "./bin/copilot-agent"
  "./dist/entrypoint"
  "./entrypoint"
)

FOUND_CMD=""
for cmd in "${CANDIDATES[@]}"; do
  if [ -x "${cmd}" ]; then
    FOUND_CMD="$cmd"
    break
  fi
done

if [ -z "$FOUND_CMD" ]; then
  echo "No obvious copilot agent entrypoint found in the action directory."
  echo "Looking for a package.json script or node entrypoint as a last resort."
  if [ -f package.json ] && command -v node >/dev/null 2>&1; then
    if jq -r '.bin // empty' package.json 2>/dev/null | grep -q .; then
      # If package.json declares a bin entry, try `node .` as fallback
      FOUND_CMD="node ."
    fi
  fi
fi

if [ -z "$FOUND_CMD" ]; then
  echo "Could not find an agent entrypoint to run. Please update this action to call the real agent binary or adjust the wrapper script." | tee "$LOG"
  exit 1
fi

# Function to run the agent with a model and return the exit code
run_agent() {
  MODEL="$1"
  # Support both direct executable invocations and node commands like 'node .'
  if [[ "$FOUND_CMD" == node* ]]; then
    # run node . with environment variable or an argument if supported
    NODE_CMD=(node . "--model" "$MODEL")
    "${NODE_CMD[@]}" 2>&1 | tee "$LOG"
    return ${PIPESTATUS[0]:-0}
  else
    "${FOUND_CMD}" --model "$MODEL" 2>&1 | tee "$LOG"
    return ${PIPESTATUS[0]:-0}
  fi
}

# Try primary
if run_agent "$PRIMARY"; then
  echo "Agent started with $PRIMARY"
  exit 0
fi

# Check log for the specific model-unavailable error
if grep -q -E "Model .* is not available" "$LOG"; then
  echo "Primary model $PRIMARY unavailable — retrying with fallback $FALLBACK"
  if run_agent "$FALLBACK"; then
    echo "Agent started with fallback $FALLBACK"
    exit 0
  else
    echo "Agent failed with fallback model as well; see $LOG"
    cat "$LOG"
    exit 1
  fi
else
  echo "Agent failed for another reason; see $LOG"
  cat "$LOG"
  exit 1
fi
