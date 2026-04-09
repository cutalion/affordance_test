#!/bin/bash
set -euo pipefail

unset ANTHROPIC_API_KEY

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENTS="${1:-e01-describe-system e02-happy-path e03-counter-proposal e04-cancellation-fee e05-recurring-bookings e06-withdraw-response}"

APP_LABELS=("app_alpha:A" "app_bravo:B" "app_charlie:C" "app_delta:D" "app_echo:E")

echo "=== Debt Threshold Experiment Analyzer ==="
echo ""

for exp in $EXPERIMENTS; do
  ANALYSIS_FILE="$ROOT/experiments_phase3b/$exp/analysis.md"
  PROMPT_FILE="$ROOT/experiments_phase3b/$exp/prompt.md"
  RUNS_DIR="$ROOT/experiments_phase3b/$exp/runs"

  RUN_COUNT=$(find "$RUNS_DIR" -name "*.md" 2>/dev/null | wc -l)
  if [ "$RUN_COUNT" -eq 0 ]; then
    echo "SKIP $exp (no runs found)"
    continue
  fi

  if [ -f "$ANALYSIS_FILE" ]; then
    echo "SKIP $exp (analysis exists)"
    continue
  fi

  echo -n "ANALYZE $exp ($RUN_COUNT runs) ... "

  TMPFILE=$(mktemp)

  cat >> "$TMPFILE" << 'INSTRUCTIONS'
You are analyzing an experiment comparing AI responses to identical prompts given in up to 5 different codebases. The codebases represent different stages of a domain evolution and different levels of technical debt. You do not know which app has more or less debt.

INSTRUCTIONS

  echo "## Prompt Given" >> "$TMPFILE"
  echo "" >> "$TMPFILE"
  cat "$PROMPT_FILE" >> "$TMPFILE"
  echo "" >> "$TMPFILE"

  for label_pair in "${APP_LABELS[@]}"; do
    APP_NAME="${label_pair%%:*}"
    LABEL="${label_pair##*:}"

    FILES=$(find "$RUNS_DIR" -name "${APP_NAME}-*.md" 2>/dev/null | sort)
    [ -z "$FILES" ] && continue

    echo "## App $LABEL Responses" >> "$TMPFILE"
    echo "" >> "$TMPFILE"
    RUN_NUM=0
    for f in $FILES; do
      RUN_NUM=$((RUN_NUM + 1))
      echo "### App $LABEL — Run $RUN_NUM" >> "$TMPFILE"
      echo "" >> "$TMPFILE"
      # Strip header lines that contain app/model names to prevent identity leaks
      tail -n +5 "$f" >> "$TMPFILE"
      echo "" >> "$TMPFILE"
      echo "---" >> "$TMPFILE"
      echo "" >> "$TMPFILE"
    done
  done

  cat >> "$TMPFILE" << 'ANALYSIS_INSTRUCTIONS'

Analyze across these dimensions:

1. **Language/framing**: How does each app's AI describe the domain?
2. **Architectural choices**: What models, states, or abstractions were proposed?
3. **Model placement**: For code experiments, did the AI put new features on the correct model?
4. **State reuse vs invention**: Did the AI reuse existing states or create new ones?
5. **Correctness**: Any logical errors, bugs, or state transition mistakes?
6. **Scope**: Did responses stay on-task or add unrequested features?

Provide:
- Pattern summary per dimension
- Pairwise comparisons between all apps present
- Confidence levels
- Notable outliers
- Bottom line: one paragraph on the most important finding
ANALYSIS_INSTRUCTIONS

  RESULT=$(cat "$TMPFILE" | claude -p --dangerously-skip-permissions --disable-slash-commands --model opus 2>/dev/null) || true
  rm -f "$TMPFILE"

  if [ -n "$RESULT" ]; then
    {
      echo "# Analysis: $exp"
      echo ""
      echo "> Blind comparison — app identities not revealed to analyzer."
      echo ""
      echo "$RESULT"
    } > "$ANALYSIS_FILE"
    echo "done"
  else
    echo "FAILED"
  fi
done

echo ""
echo "=== Analysis complete ==="
