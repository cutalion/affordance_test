#!/bin/bash
set -euo pipefail

# Experiment runner for affordance test
# Usage: ./experiments/run.sh [experiment] [model] [app] [max_run]
# All arguments optional — defaults to running everything.
# Skips completed runs (output file already exists).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENTS="${1:-01-describe-system 02-rebook-feature 03-propose-different-time 04-bulk-booking 05-auto-assignment 06-cancellation-fee 07-happy-path}"
MODELS="${2:-sonnet opus}"
APPS="${3:-order request}"
MAX_RUN="${4:-5}"

TOTAL=0
DONE=0
SKIPPED=0
FAILED=0

# Count total runs
for exp in $EXPERIMENTS; do
  for model in $MODELS; do
    for app in $APPS; do
      for run in $(seq 1 "$MAX_RUN"); do
        TOTAL=$((TOTAL + 1))
      done
    done
  done
done

echo "=== Affordance Experiment Runner ==="
echo "Experiments: $EXPERIMENTS"
echo "Models: $MODELS"
echo "Apps: $APPS"
echo "Runs per combo: $MAX_RUN"
echo "Total invocations: $TOTAL"
echo "==================================="
echo ""

for exp in $EXPERIMENTS; do
  # Load config
  source "$ROOT/experiments/$exp/config.sh"
  PROMPT=$(cat "$ROOT/experiments/$exp/prompt.md")

  echo "--- Experiment: $exp (type=$TYPE) ---"

  for model in $MODELS; do
    for app in $APPS; do
      APP_DIR="$ROOT/affordance_$app"

      for run in $(seq 1 "$MAX_RUN"); do
        OUTPUT_FILE="$ROOT/experiments/$exp/runs/${app}-${model}-${run}.md"
        RUN_LABEL="$exp/$app/$model/run-$run"

        # Skip if already done
        if [ -f "$OUTPUT_FILE" ]; then
          SKIPPED=$((SKIPPED + 1))
          echo "  SKIP $RUN_LABEL (exists)"
          continue
        fi

        echo -n "  RUN  $RUN_LABEL ... "
        START_TIME=$(date +%s)

        if [ "$TYPE" = "code" ]; then
          BRANCH="experiment/${exp}/${app}/${model}/run-${run}"

          # Create branch from main (at repo root)
          cd "$ROOT"
          git checkout main 2>/dev/null
          git branch -D "$BRANCH" 2>/dev/null || true
          git checkout -b "$BRANCH" 2>/dev/null

          # Run claude from the app directory
          cd "$APP_DIR"
          RESULT=$(echo "$PROMPT" | claude -p --bare --dangerously-skip-permissions --model "$model" 2>/dev/null) || true

          # Commit any uncommitted changes (only app directory)
          cd "$ROOT"
          git add "affordance_$app/" 2>/dev/null || true
          git diff --cached --quiet 2>/dev/null || git commit -m "experiment: $exp $app $model run-$run (auto-committed)" 2>/dev/null || true

          # Capture diff (only app directory changes)
          DIFF=$(git diff main..HEAD -- "affordance_$app/" 2>/dev/null) || DIFF="(no diff)"

          {
            echo "# Experiment: $exp"
            echo "# App: $app | Model: $model | Run: $run"
            echo "# Branch: $BRANCH"
            echo ""
            echo "---"
            echo ""
            echo "## Claude Output"
            echo ""
            echo "$RESULT"
            echo ""
            echo "---"
            echo ""
            echo "## Git Diff"
            echo ""
            echo '```diff'
            echo "$DIFF"
            echo '```'
          } > "$OUTPUT_FILE"

          # Return to main
          git checkout main 2>/dev/null

        else
          # Read-only experiment
          cd "$APP_DIR"
          RESULT=$(echo "$PROMPT" | claude -p --bare --dangerously-skip-permissions --model "$model" 2>/dev/null) || true
          cd "$ROOT"

          {
            echo "# Experiment: $exp"
            echo "# App: $app | Model: $model | Run: $run"
            echo ""
            echo "---"
            echo ""
            echo "$RESULT"
          } > "$OUTPUT_FILE"
        fi

        END_TIME=$(date +%s)
        ELAPSED=$((END_TIME - START_TIME))

        if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
          DONE=$((DONE + 1))
          echo "done (${ELAPSED}s)"
        else
          FAILED=$((FAILED + 1))
          echo "FAILED (${ELAPSED}s)"
        fi
      done
    done
  done
  echo ""
done

echo "==================================="
echo "Complete: $DONE | Skipped: $SKIPPED | Failed: $FAILED | Total: $TOTAL"
echo "==================================="
