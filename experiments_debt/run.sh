#!/bin/bash
set -euo pipefail

# Experiment runner for debt threshold test
# Usage: ./experiments_debt/run.sh [experiment] [app] [max_run]
# Opus only. All arguments optional.

unset ANTHROPIC_API_KEY

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENTS="${1:-e01-describe-system e02-happy-path e03-counter-proposal e04-cancellation-fee e05-recurring-bookings e06-withdraw-response}"
MODEL="opus"
APPS="${2:-app_alpha app_bravo app_charlie app_delta app_echo}"
MAX_RUN="${3:-3}"

# Define which experiments run on which apps
can_run() {
  local exp="$1" app="$2"
  case "$exp" in
    e01-describe-system|e02-happy-path)
      return 0 ;; # All apps
    e03-counter-proposal|e04-cancellation-fee|e05-recurring-bookings)
      case "$app" in
        app_alpha) return 1 ;; # Skip MVP for these
        *) return 0 ;;
      esac ;;
    e06-withdraw-response)
      case "$app" in
        app_delta|app_echo) return 0 ;;
        *) return 1 ;; # Only stage 2 apps
      esac ;;
  esac
}

TOTAL=0
CURRENT=0
DONE=0
SKIPPED=0
FAILED=0
WALL_START=$(date +%s)

# Check if Claude output indicates an error (rate limit, auth failure, etc.)
is_error_output() {
  local output="$1"
  if [ -z "$output" ]; then return 0; fi
  if echo "$output" | grep -qiE "hit your limit|rate limit|resets [0-9]|unauthorized|authentication failed|API error|Could not connect"; then
    return 0
  fi
  return 1
}

for exp in $EXPERIMENTS; do
  for app in $APPS; do
    can_run "$exp" "$app" || continue
    for run in $(seq 1 "$MAX_RUN"); do
      TOTAL=$((TOTAL + 1))
    done
  done
done

# Hide CLAUDE.md
if [ -f "$ROOT/CLAUDE.md" ]; then
  mv "$ROOT/CLAUDE.md" "$ROOT/.CLAUDE.md.hidden"
  trap 'mv "$ROOT/.CLAUDE.md.hidden" "$ROOT/CLAUDE.md" 2>/dev/null || true' EXIT
fi

echo "=== Debt Threshold Experiment Runner ==="
echo "Experiments: $EXPERIMENTS"
echo "Model: $MODEL"
echo "Apps: $APPS"
echo "Runs per combo: $MAX_RUN"
echo "Total invocations: $TOTAL"
echo "========================================"
echo ""

for exp in $EXPERIMENTS; do
  source "$ROOT/experiments_debt/$exp/config.sh"
  PROMPT=$(cat "$ROOT/experiments_debt/$exp/prompt.md")

  echo "--- Experiment: $exp (type=$TYPE) ---"

  for app in $APPS; do
    can_run "$exp" "$app" || continue

    APP_DIR="$ROOT/$app"

    for run in $(seq 1 "$MAX_RUN"); do
      OUTPUT_FILE="$ROOT/experiments_debt/$exp/runs/${app}-${MODEL}-${run}.md"
      RUN_LABEL="$exp/$app/$MODEL/run-$run"

      CURRENT=$((CURRENT + 1))

      if [ -f "$OUTPUT_FILE" ]; then
        SKIPPED=$((SKIPPED + 1))
        echo "  [$CURRENT/$TOTAL] SKIP $RUN_LABEL (exists)"
        continue
      fi

      echo -n "  [$CURRENT/$TOTAL] RUN  $RUN_LABEL ... "
      START_TIME=$(date +%s)

      if [ "$TYPE" = "code" ]; then
        BRANCH="debt_experiment/${exp}/${app}/${MODEL}/run-${run}"

        cd "$ROOT"
        git checkout main 2>/dev/null
        git branch -D "$BRANCH" 2>/dev/null || true
        git checkout -b "$BRANCH" 2>/dev/null

        cd "$APP_DIR"
        RESULT=$(echo "$PROMPT" | claude -p --dangerously-skip-permissions --disable-slash-commands --model "$MODEL" 2>&1) || true

        if is_error_output "$RESULT"; then
          cd "$ROOT"
          git checkout main 2>/dev/null
          git branch -D "$BRANCH" 2>/dev/null || true
          END_TIME=$(date +%s)
          ELAPSED=$((END_TIME - START_TIME))
          echo "ERROR (${ELAPSED}s): $RESULT"
          echo ""
          echo "Aborting — Claude returned an error. Fix the issue and re-run."
          exit 1
        fi

        cd "$ROOT"
        git add "$app/" 2>/dev/null || true
        git diff --cached --quiet 2>/dev/null || git commit -m "experiment: $exp $app $MODEL run-$run (auto-committed)" 2>/dev/null || true

        DIFF=$(git diff main..HEAD -- "$app/" 2>/dev/null) || DIFF="(no diff)"

        {
          echo "# Experiment: $exp"
          echo "# App: $app | Model: $MODEL | Run: $run"
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

        git checkout main 2>/dev/null

      else
        cd "$APP_DIR"
        RESULT=$(echo "$PROMPT" | claude -p --dangerously-skip-permissions --disable-slash-commands --model "$MODEL" 2>&1) || true
        cd "$ROOT"

        if is_error_output "$RESULT"; then
          END_TIME=$(date +%s)
          ELAPSED=$((END_TIME - START_TIME))
          echo "ERROR (${ELAPSED}s): $RESULT"
          echo ""
          echo "Aborting — Claude returned an error. Fix the issue and re-run."
          exit 1
        fi

        {
          echo "# Experiment: $exp"
          echo "# App: $app | Model: $MODEL | Run: $run"
          echo ""
          echo "---"
          echo ""
          echo "$RESULT"
        } > "$OUTPUT_FILE"
      fi

      END_TIME=$(date +%s)
      ELAPSED=$((END_TIME - START_TIME))
      DONE=$((DONE + 1))
      echo "done (${ELAPSED}s)"
    done
  done
  echo ""
done

WALL_END=$(date +%s)
WALL_ELAPSED=$(( WALL_END - WALL_START ))
WALL_MIN=$(( WALL_ELAPSED / 60 ))
WALL_SEC=$(( WALL_ELAPSED % 60 ))

echo "========================================"
echo "Complete: $DONE | Skipped: $SKIPPED | Failed: $FAILED | Total: $TOTAL"
echo "Wall time: ${WALL_MIN}m ${WALL_SEC}s"
echo "========================================"
