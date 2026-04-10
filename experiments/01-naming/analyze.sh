#!/bin/bash
set -euo pipefail

# Post-experiment analysis — runs blind comparison via claude opus
# Usage: ./experiments/01-naming/analyze.sh [experiment]
# Defaults to analyzing all experiments.

# Ensure claude -p uses subscription auth, not API key
unset ANTHROPIC_API_KEY

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EXPERIMENTS="${1:-01-describe-system 02-rebook-feature 03-propose-different-time 04-bulk-booking 05-auto-assignment 06-cancellation-fee 07-happy-path}"

# Hide CLAUDE.md and project memory to prevent experiment contamination
MEMORY_DIR="$HOME/.claude/projects/-home-cutalion-code-affordance-test/memory"
restore_hidden() {
  mv "$ROOT/.CLAUDE.md.hidden" "$ROOT/CLAUDE.md" 2>/dev/null || true
  mv "$MEMORY_DIR.hidden" "$MEMORY_DIR" 2>/dev/null || true
}
trap restore_hidden EXIT

if [ -f "$ROOT/CLAUDE.md" ]; then
  mv "$ROOT/CLAUDE.md" "$ROOT/.CLAUDE.md.hidden"
fi
if [ -d "$MEMORY_DIR" ]; then
  mv "$MEMORY_DIR" "$MEMORY_DIR.hidden"
fi

echo "=== Naming Affordance Experiment Analyzer ==="
echo ""

for exp in $EXPERIMENTS; do
  ANALYSIS_FILE="$SCRIPT_DIR/$exp/analysis.md"
  PROMPT_FILE="$SCRIPT_DIR/$exp/prompt.md"
  RUNS_DIR="$SCRIPT_DIR/$exp/runs"

  # Check if runs exist
  RUN_COUNT=$(find "$RUNS_DIR" -name "*.md" 2>/dev/null | wc -l)
  if [ "$RUN_COUNT" -eq 0 ]; then
    echo "SKIP $exp (no runs found)"
    continue
  fi

  # Skip if analysis already exists
  if [ -f "$ANALYSIS_FILE" ]; then
    echo "SKIP $exp (analysis exists)"
    continue
  fi

  echo -n "ANALYZE $exp ($RUN_COUNT runs) ... "

  # Build analysis prompt in a temp file
  TMPFILE=$(mktemp)

  cat >> "$TMPFILE" << 'INSTRUCTIONS'
You are analyzing an experiment comparing AI responses to identical prompts given in three different codebases. The codebases differ in naming conventions and/or structural complexity. You do not know what the differences are.

INSTRUCTIONS

  echo "## Prompt Given" >> "$TMPFILE"
  echo "" >> "$TMPFILE"
  cat "$PROMPT_FILE" >> "$TMPFILE"
  echo "" >> "$TMPFILE"

  echo "## App A Responses" >> "$TMPFILE"
  echo "" >> "$TMPFILE"
  for f in "$RUNS_DIR"/order-*.md; do
    [ -f "$f" ] || continue
    echo "### $(basename "$f" .md)" >> "$TMPFILE"
    echo "" >> "$TMPFILE"
    cat "$f" >> "$TMPFILE"
    echo "" >> "$TMPFILE"
    echo "---" >> "$TMPFILE"
    echo "" >> "$TMPFILE"
  done

  echo "## App B Responses" >> "$TMPFILE"
  echo "" >> "$TMPFILE"
  for f in "$RUNS_DIR"/request-*.md; do
    [ -f "$f" ] || continue
    # Skip request_clean files (they go under App C)
    case "$(basename "$f")" in request_clean-*) continue ;; esac
    echo "### $(basename "$f" .md)" >> "$TMPFILE"
    echo "" >> "$TMPFILE"
    cat "$f" >> "$TMPFILE"
    echo "" >> "$TMPFILE"
    echo "---" >> "$TMPFILE"
    echo "" >> "$TMPFILE"
  done

  echo "## App C Responses" >> "$TMPFILE"
  echo "" >> "$TMPFILE"
  for f in "$RUNS_DIR"/request_clean-*.md; do
    [ -f "$f" ] || continue
    echo "### $(basename "$f" .md)" >> "$TMPFILE"
    echo "" >> "$TMPFILE"
    cat "$f" >> "$TMPFILE"
    echo "" >> "$TMPFILE"
    echo "---" >> "$TMPFILE"
    echo "" >> "$TMPFILE"
  done

  cat >> "$TMPFILE" << 'ANALYSIS_INSTRUCTIONS'

Analyze across these dimensions:

1. **Language/framing**: How does each set describe the domain? What words and metaphors are used?
2. **Architectural choices**: What models, states, or abstractions were proposed or used?
3. **Complexity**: Estimate lines of code, number of new files, new states/fields added (for code experiments). For text experiments, compare verbosity and detail level.
4. **Scope**: Did responses stay on-task or add unrequested features? Any scope creep?
5. **Assumptions**: What did responses assume about the system purpose or user intent?
6. **Model comparison**: Did Sonnet and Opus responses differ in their patterns within each app?

Provide:
- A **pattern summary** across all runs for each dimension
- **Confidence level**: strong pattern / weak signal / no difference
- **Notable outliers** (individual runs that broke the pattern)
- **Raw tallies** where applicable (e.g., "App A added N new states on average, App B added M, App C added P")
- **Pairwise comparisons**: A vs B, A vs C, B vs C — which pairs are most similar? Most different?
- A **bottom line**: one paragraph summarizing the most important finding
ANALYSIS_INSTRUCTIONS

  RESULT=$(cat "$TMPFILE" | claude -p --dangerously-skip-permissions --disable-slash-commands --model opus 2>/dev/null) || true
  rm -f "$TMPFILE"

  if [ -n "$RESULT" ]; then
    {
      echo "# Analysis: $exp"
      echo ""
      echo "> Blind comparison — App A and App B naming not revealed to analyzer."
      echo ""
      echo "$RESULT"
    } > "$ANALYSIS_FILE"
    echo "done"
  else
    echo "FAILED"
  fi
done

echo ""
echo "=== Generating summaries ==="
echo ""

for exp in $EXPERIMENTS; do
  SUMMARY_FILE="$SCRIPT_DIR/$exp/summary.md"
  ANALYSIS_FILE="$SCRIPT_DIR/$exp/analysis.md"

  if [ ! -f "$ANALYSIS_FILE" ]; then
    echo "SKIP $exp summary (no analysis)"
    continue
  fi

  if [ -f "$SUMMARY_FILE" ]; then
    echo "SKIP $exp summary (exists)"
    continue
  fi

  echo -n "SUMMARY $exp ... "

  source "$SCRIPT_DIR/$exp/config.sh"

  # Build summary prompt in temp file
  TMPFILE=$(mktemp)

  cat >> "$TMPFILE" << 'SUMMARY_INTRO'
You are writing a summary for an AI naming affordance experiment.

The experiment tested how AI agents respond differently to three related codebases:
- **App A = Order app** (apps/order/) — central entity is 'Order' with clean states: pending, confirmed, in_progress, completed, canceled, rejected
- **App B = Request app** (apps/request/) — central entity is 'Request' with legacy invitation-era states: created, created_accepted, accepted, started, fulfilled, declined, missed, canceled, rejected. Has extra services (CreateAcceptedService, DeclineService) and extra API endpoint.
- **App C = Request Clean app** (apps/request_clean/) — central entity is 'Request' but with the SAME clean states as Order: pending, confirmed, in_progress, completed, canceled, rejected. Same service structure as Order. This isolates naming from structural complexity.

The Request app evolved from an invitation system (invite sitter) but is functionally an order/booking system. Nobody refactored the naming. The Request Clean app tests whether the name "Request" alone (without legacy structural complexity) produces different AI behavior than "Order".

## Blind Analysis (naming was hidden from analyzer)

SUMMARY_INTRO

  cat "$ANALYSIS_FILE" >> "$TMPFILE"

  cat >> "$TMPFILE" << 'SUMMARY_TASK'

## Your Task

Write a concise summary (under 700 words) that:
1. Reveals the naming/structural differences and connects them to the blind analysis findings
2. States the key conclusion: did naming alone affect AI reasoning? Did structural complexity matter independently?
3. Compares App C (Request naming + clean states) to both App A and App B — does it behave like A (same structure) or B (same name)?
4. Notes the confidence level
5. Highlights the most surprising or interesting finding
SUMMARY_TASK

  RESULT=$(cat "$TMPFILE" | claude -p --dangerously-skip-permissions --disable-slash-commands --model opus 2>/dev/null) || true
  rm -f "$TMPFILE"

  # Build branch list for code experiments
  BRANCHES=""
  if [ "$TYPE" = "code" ]; then
    BRANCHES="

## Branches

### Order App
"
    for f in "$SCRIPT_DIR/$exp/runs"/order-*.md; do
      [ -f "$f" ] || continue
      BASENAME=$(basename "$f" .md)
      # Parse: order-sonnet-1 -> model=sonnet, run=1
      MODEL=$(echo "$BASENAME" | sed 's/order-//' | sed 's/-[0-9]*$//')
      RUN_NUM=$(echo "$BASENAME" | grep -o '[0-9]*$')
      BRANCHES="$BRANCHES
- \`experiment/${exp}/order/${MODEL}/run-${RUN_NUM}\`"
    done
    BRANCHES="$BRANCHES

### Request App
"
    for f in "$SCRIPT_DIR/$exp/runs"/request-*.md; do
      [ -f "$f" ] || continue
      # Skip request_clean files
      case "$(basename "$f")" in request_clean-*) continue ;; esac
      BASENAME=$(basename "$f" .md)
      MODEL=$(echo "$BASENAME" | sed 's/request-//' | sed 's/-[0-9]*$//')
      RUN_NUM=$(echo "$BASENAME" | grep -o '[0-9]*$')
      BRANCHES="$BRANCHES
- \`experiment/${exp}/request/${MODEL}/run-${RUN_NUM}\`"
    done
    BRANCHES="$BRANCHES

### Request Clean App
"
    for f in "$SCRIPT_DIR/$exp/runs"/request_clean-*.md; do
      [ -f "$f" ] || continue
      BASENAME=$(basename "$f" .md)
      MODEL=$(echo "$BASENAME" | sed 's/request_clean-//' | sed 's/-[0-9]*$//')
      RUN_NUM=$(echo "$BASENAME" | grep -o '[0-9]*$')
      BRANCHES="$BRANCHES
- \`experiment/${exp}/request_clean/${MODEL}/run-${RUN_NUM}\`"
    done
  fi

  if [ -n "$RESULT" ]; then
    {
      echo "# Summary: $exp"
      echo ""
      echo "**Prompt:** $(cat "$SCRIPT_DIR/$exp/prompt.md")"
      echo ""
      echo "**Type:** $TYPE"
      echo ""
      echo "**Naming key:** App A = Order (clean name + clean states) | App B = Request (legacy name + legacy states) | App C = Request Clean (legacy name + clean states)"
      echo ""
      echo "---"
      echo ""
      echo "$RESULT"
      echo "$BRANCHES"
    } > "$SUMMARY_FILE"
    echo "done"
  else
    echo "FAILED"
  fi
done

echo ""
echo "=== Analysis complete ==="
