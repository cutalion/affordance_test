# Experiment Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an automated experiment framework that runs 7 experiments across 2 apps, 2 models, and 5 runs each, then analyzes results.

**Architecture:** Shell scripts orchestrate `claude -p --bare --dangerously-skip-permissions` invocations. Each experiment has a prompt, config, and runs directory. Code experiments use git branches. Analysis runs blind comparison via opus.

**Tech Stack:** Bash, claude CLI, git

**Spec:** `docs/superpowers/specs/2026-04-06-experiments-design.md`

---

## File Structure

```
experiments/
├── run.sh                                    # Main experiment runner
├── analyze.sh                                # Post-experiment analysis
├── 01-describe-system/
│   ├── prompt.md
│   ├── config.sh
│   └── runs/                                 # (created by run.sh)
├── 02-rebook-feature/
│   ├── prompt.md
│   ├── config.sh
│   └── runs/
├── 03-propose-different-time/
│   ├── prompt.md
│   ├── config.sh
│   └── runs/
├── 04-bulk-booking/
│   ├── prompt.md
│   ├── config.sh
│   └── runs/
├── 05-auto-assignment/
│   ├── prompt.md
│   ├── config.sh
│   └── runs/
├── 06-cancellation-fee/
│   ├── prompt.md
│   ├── config.sh
│   └── runs/
└── 07-happy-path/
    ├── prompt.md
    ├── config.sh
    └── runs/
```

---

### Task 1: Create experiment directories and prompts

**Files:**
- Create: `experiments/01-describe-system/prompt.md`
- Create: `experiments/01-describe-system/config.sh`
- Create: `experiments/02-rebook-feature/prompt.md`
- Create: `experiments/02-rebook-feature/config.sh`
- Create: `experiments/03-propose-different-time/prompt.md`
- Create: `experiments/03-propose-different-time/config.sh`
- Create: `experiments/04-bulk-booking/prompt.md`
- Create: `experiments/04-bulk-booking/config.sh`
- Create: `experiments/05-auto-assignment/prompt.md`
- Create: `experiments/05-auto-assignment/config.sh`
- Create: `experiments/06-cancellation-fee/prompt.md`
- Create: `experiments/06-cancellation-fee/config.sh`
- Create: `experiments/07-happy-path/prompt.md`
- Create: `experiments/07-happy-path/config.sh`

- [ ] **Step 1: Create 01-describe-system**

Create `experiments/01-describe-system/config.sh`:
```bash
TYPE=readonly
```

Create `experiments/01-describe-system/prompt.md`:
```
Describe what this system does. What is the domain, what are the main entities, and what is the typical workflow?
```

- [ ] **Step 2: Create 02-rebook-feature**

Create `experiments/02-rebook-feature/config.sh`:
```bash
TYPE=code
```

Create `experiments/02-rebook-feature/prompt.md`:
```
Add a feature that lets a client re-book with the same provider. The client should be able to create a new booking based on a previous one, reusing provider, location, and duration. Implement this and commit your changes.
```

- [ ] **Step 3: Create 03-propose-different-time**

Create `experiments/03-propose-different-time/config.sh`:
```bash
TYPE=code
```

Create `experiments/03-propose-different-time/prompt.md`:
```
Add a feature where the provider can propose a different time instead of just accepting or rejecting. The client can then accept or decline the counter-proposal. Implement this and commit your changes.
```

- [ ] **Step 4: Create 04-bulk-booking**

Create `experiments/04-bulk-booking/config.sh`:
```bash
TYPE=code
```

Create `experiments/04-bulk-booking/prompt.md`:
```
Add a feature where a client can book 5 sessions at once with the same provider (e.g., weekly recurring). All sessions should be created in a single API call. Implement this and commit your changes.
```

- [ ] **Step 5: Create 05-auto-assignment**

Create `experiments/05-auto-assignment/config.sh`:
```bash
TYPE=code
```

Create `experiments/05-auto-assignment/prompt.md`:
```
Add automatic provider assignment. When a client creates a booking without specifying a provider, the system should automatically assign the highest-rated available provider. Implement this and commit your changes.
```

- [ ] **Step 6: Create 06-cancellation-fee**

Create `experiments/06-cancellation-fee/config.sh`:
```bash
TYPE=code
```

Create `experiments/06-cancellation-fee/prompt.md`:
```
Add a cancellation fee. If the client cancels less than 24 hours before the scheduled time, charge 50% of the amount. Implement this in the cancel flow. Implement this and commit your changes.
```

- [ ] **Step 7: Create 07-happy-path**

Create `experiments/07-happy-path/config.sh`:
```bash
TYPE=readonly
```

Create `experiments/07-happy-path/prompt.md`:
```
What is the happy path for the main entity in this system? Walk through it step by step.
```

- [ ] **Step 8: Create runs directories**

```bash
for exp in 01-describe-system 02-rebook-feature 03-propose-different-time 04-bulk-booking 05-auto-assignment 06-cancellation-fee 07-happy-path; do
  mkdir -p experiments/$exp/runs
  touch experiments/$exp/runs/.gitkeep
done
```

- [ ] **Step 9: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add experiments
git commit -m "feat: add experiment prompts and configs for all 7 experiments"
```

---

### Task 2: Create the runner script (run.sh)

**Files:**
- Create: `experiments/run.sh`

- [ ] **Step 1: Create run.sh**

Create `experiments/run.sh`:
```bash
#!/bin/bash
set -euo pipefail

# Experiment runner for affordance test
# Usage: ./experiments/run.sh [experiment] [model] [app] [run]
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

          cd "$APP_DIR"
          git checkout main 2>/dev/null
          git branch -D "$BRANCH" 2>/dev/null || true
          git checkout -b "$BRANCH" 2>/dev/null

          # Run claude
          RESULT=$(echo "$PROMPT" | claude -p --bare --dangerously-skip-permissions --model "$model" 2>/dev/null) || true

          # Commit any uncommitted changes
          git add -A 2>/dev/null
          git diff --cached --quiet 2>/dev/null || git commit -m "experiment: $exp $app $model run-$run (auto-committed)" 2>/dev/null || true

          # Capture output + diff
          DIFF=$(git diff main..HEAD 2>/dev/null || echo "(no diff)")

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
          cd "$ROOT"

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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x experiments/run.sh
```

- [ ] **Step 3: Test with a single dry run**

Run a single invocation to verify it works:

```bash
cd /home/cutalion/code/affordance_test
./experiments/run.sh 01-describe-system sonnet order 1
```

Expected: Creates `experiments/01-describe-system/runs/order-sonnet-1.md` with claude's response. Re-running should show "SKIP".

- [ ] **Step 4: Verify skip logic**

```bash
./experiments/run.sh 01-describe-system sonnet order 1
```

Expected: Output shows "SKIP 01-describe-system/order/sonnet/run-1 (exists)"

- [ ] **Step 5: Test code experiment with a single run**

```bash
./experiments/run.sh 02-rebook-feature sonnet order 1
```

Expected: Creates branch `experiment/02-rebook-feature/order/sonnet/run-1`, runs claude, captures output + diff, returns to main.

Verify:
```bash
git branch | grep experiment
cat experiments/02-rebook-feature/runs/order-sonnet-1.md | head -20
```

- [ ] **Step 6: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add experiments/run.sh
git commit -m "feat: add experiment runner script"
```

---

### Task 3: Create the analysis script (analyze.sh)

**Files:**
- Create: `experiments/analyze.sh`

- [ ] **Step 1: Create analyze.sh**

Create `experiments/analyze.sh`:
```bash
#!/bin/bash
set -euo pipefail

# Post-experiment analysis — runs blind comparison via claude opus
# Usage: ./experiments/analyze.sh [experiment]
# Defaults to analyzing all experiments.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPERIMENTS="${1:-01-describe-system 02-rebook-feature 03-propose-different-time 04-bulk-booking 05-auto-assignment 06-cancellation-fee 07-happy-path}"

ANALYSIS_PROMPT='You are analyzing an experiment comparing AI responses to identical prompts given in two different codebases. The codebases are structurally identical except for naming conventions. You do not know what the naming difference is.

## Prompt Given

%PROMPT%

## App A Responses

%APP_A%

## App B Responses

%APP_B%

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
- **Raw tallies** where applicable (e.g., "App A added N new states on average, App B added M")
- A **bottom line**: one paragraph summarizing the most important finding'

for exp in $EXPERIMENTS; do
  ANALYSIS_FILE="$ROOT/experiments/$exp/analysis.md"
  PROMPT_FILE="$ROOT/experiments/$exp/prompt.md"

  # Check if runs exist
  RUN_COUNT=$(ls "$ROOT/experiments/$exp/runs/"*.md 2>/dev/null | wc -l)
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

  PROMPT_TEXT=$(cat "$PROMPT_FILE")

  # Collect App A (order) runs
  APP_A=""
  for f in "$ROOT/experiments/$exp/runs"/order-*.md; do
    [ -f "$f" ] || continue
    BASENAME=$(basename "$f" .md)
    APP_A="$APP_A

### $BASENAME

$(cat "$f")

---
"
  done

  # Collect App B (request) runs
  APP_B=""
  for f in "$ROOT/experiments/$exp/runs"/request-*.md; do
    [ -f "$f" ] || continue
    BASENAME=$(basename "$f" .md)
    APP_B="$APP_B

### $BASENAME

$(cat "$f")

---
"
  done

  # Build the full analysis prompt
  FULL_PROMPT=$(echo "$ANALYSIS_PROMPT" | sed "s|%PROMPT%|$PROMPT_TEXT|")
  # sed can't handle multi-line replacements well, use python
  FULL_PROMPT=$(python3 -c "
import sys
template = sys.stdin.read()
template = template.replace('%APP_A%', '''$APP_A''')
template = template.replace('%APP_B%', '''$APP_B''')
print(template)
" <<< "$FULL_PROMPT" 2>/dev/null) || true

  # If python approach fails due to quoting, fall back to temp files
  if [ -z "$FULL_PROMPT" ]; then
    TMPFILE=$(mktemp)
    {
      echo "$ANALYSIS_PROMPT" | head -1
      echo ""
      echo "## Prompt Given"
      echo ""
      cat "$PROMPT_FILE"
      echo ""
      echo "## App A Responses"
      echo ""
      for f in "$ROOT/experiments/$exp/runs"/order-*.md; do
        [ -f "$f" ] || continue
        echo "### $(basename "$f" .md)"
        echo ""
        cat "$f"
        echo ""
        echo "---"
        echo ""
      done
      echo "## App B Responses"
      echo ""
      for f in "$ROOT/experiments/$exp/runs"/request-*.md; do
        [ -f "$f" ] || continue
        echo "### $(basename "$f" .md)"
        echo ""
        cat "$f"
        echo ""
        echo "---"
        echo ""
      done
      echo ""
      # Append analysis instructions
      echo "Analyze across these dimensions:"
      echo ""
      echo "1. **Language/framing**: How does each set describe the domain? What words and metaphors are used?"
      echo "2. **Architectural choices**: What models, states, or abstractions were proposed or used?"
      echo "3. **Complexity**: Estimate lines of code, number of new files, new states/fields added (for code experiments). For text experiments, compare verbosity and detail level."
      echo "4. **Scope**: Did responses stay on-task or add unrequested features? Any scope creep?"
      echo "5. **Assumptions**: What did responses assume about the system purpose or user intent?"
      echo "6. **Model comparison**: Did Sonnet and Opus responses differ in their patterns within each app?"
      echo ""
      echo "Provide:"
      echo "- A **pattern summary** across all runs for each dimension"
      echo "- **Confidence level**: strong pattern / weak signal / no difference"
      echo "- **Notable outliers** (individual runs that broke the pattern)"
      echo "- **Raw tallies** where applicable"
      echo "- A **bottom line**: one paragraph summarizing the most important finding"
    } > "$TMPFILE"

    RESULT=$(cat "$TMPFILE" | claude -p --bare --dangerously-skip-permissions --model opus 2>/dev/null) || true
    rm -f "$TMPFILE"
  else
    RESULT=$(echo "$FULL_PROMPT" | claude -p --bare --dangerously-skip-permissions --model opus 2>/dev/null) || true
  fi

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

for exp in $EXPERIMENTS; do
  SUMMARY_FILE="$ROOT/experiments/$exp/summary.md"
  ANALYSIS_FILE="$ROOT/experiments/$exp/analysis.md"

  if [ ! -f "$ANALYSIS_FILE" ]; then
    echo "SKIP $exp summary (no analysis)"
    continue
  fi

  if [ -f "$SUMMARY_FILE" ]; then
    echo "SKIP $exp summary (exists)"
    continue
  fi

  echo -n "SUMMARY $exp ... "

  source "$ROOT/experiments/$exp/config.sh"

  # Build branch list for code experiments
  BRANCHES=""
  if [ "$TYPE" = "code" ]; then
    BRANCHES="
## Branches

### Order App
"
    for f in "$ROOT/experiments/$exp/runs"/order-*.md; do
      [ -f "$f" ] || continue
      BASENAME=$(basename "$f" .md)
      MODEL=$(echo "$BASENAME" | cut -d- -f2)
      RUN=$(echo "$BASENAME" | cut -d- -f3)
      BRANCHES="$BRANCHES
- \`experiment/${exp}/order/${MODEL}/run-${RUN}\`"
    done
    BRANCHES="$BRANCHES

### Request App
"
    for f in "$ROOT/experiments/$exp/runs"/request-*.md; do
      [ -f "$f" ] || continue
      BASENAME=$(basename "$f" .md)
      MODEL=$(echo "$BASENAME" | cut -d- -f2)
      RUN=$(echo "$BASENAME" | cut -d- -f3)
      BRANCHES="$BRANCHES
- \`experiment/${exp}/request/${MODEL}/run-${RUN}\`"
    done
  fi

  SUMMARY_PROMPT="You are writing a summary for an AI naming affordance experiment.

The experiment tested how AI agents respond differently to two identical codebases that differ only in naming:
- **App A = Order app** (affordance_order/) — central entity is 'Order' with clean states: pending, confirmed, in_progress, completed, canceled, rejected
- **App B = Request app** (affordance_request/) — central entity is 'Request' with legacy invitation-era states: created, created_accepted, accepted, started, fulfilled, declined, missed, canceled, rejected

The Request app evolved from an invitation system (invite sitter) but is functionally an order/booking system. Nobody refactored the naming.

## Blind Analysis (naming was hidden from analyzer)

$(cat "$ANALYSIS_FILE")

## Your Task

Write a concise summary (under 500 words) that:
1. Reveals the naming difference and connects it to the blind analysis findings
2. States the key conclusion: did naming affect AI reasoning? How?
3. Notes the confidence level
4. Highlights the most surprising or interesting finding"

  RESULT=$(echo "$SUMMARY_PROMPT" | claude -p --bare --dangerously-skip-permissions --model opus 2>/dev/null) || true

  if [ -n "$RESULT" ]; then
    {
      echo "# Summary: $exp"
      echo ""
      echo "**Prompt:** $(cat "$ROOT/experiments/$exp/prompt.md")"
      echo ""
      echo "**Type:** $TYPE"
      echo ""
      echo "**Naming key:** App A = Order (clean states) | App B = Request (legacy invitation-era states)"
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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x experiments/analyze.sh
```

- [ ] **Step 3: Commit**

```bash
cd /home/cutalion/code/affordance_test
git add experiments/analyze.sh
git commit -m "feat: add experiment analysis script"
```

---

### Task 4: End-to-end test with one experiment

**Files:** None (verification only)

- [ ] **Step 1: Run a single read-only experiment end-to-end**

```bash
cd /home/cutalion/code/affordance_test
./experiments/run.sh 01-describe-system sonnet order 1
./experiments/run.sh 01-describe-system sonnet request 1
```

Verify both output files exist and contain meaningful content:
```bash
wc -l experiments/01-describe-system/runs/order-sonnet-1.md
wc -l experiments/01-describe-system/runs/request-sonnet-1.md
```

Expected: Both files have 10+ lines of content.

- [ ] **Step 2: Run a single code experiment end-to-end**

```bash
./experiments/run.sh 02-rebook-feature sonnet order 1
```

Verify:
```bash
git branch | grep "experiment/02-rebook-feature/order/sonnet/run-1"
head -20 experiments/02-rebook-feature/runs/order-sonnet-1.md
grep -c "^+" experiments/02-rebook-feature/runs/order-sonnet-1.md || echo "diff lines present"
```

Expected: Branch exists, output file has claude response + git diff.

- [ ] **Step 3: Verify skip logic works**

```bash
./experiments/run.sh 01-describe-system sonnet order 1
```

Expected: Shows "SKIP" in output.

- [ ] **Step 4: Clean up test runs (optional — or keep as real data)**

If keeping as real data, no cleanup needed. If cleaning up:
```bash
rm -f experiments/01-describe-system/runs/order-sonnet-1.md
rm -f experiments/01-describe-system/runs/request-sonnet-1.md
rm -f experiments/02-rebook-feature/runs/order-sonnet-1.md
git branch -D experiment/02-rebook-feature/order/sonnet/run-1 2>/dev/null || true
```

- [ ] **Step 5: Commit scripts and any test run data**

```bash
cd /home/cutalion/code/affordance_test
git add experiments
git commit -m "feat: experiment framework complete — runner and analyzer scripts"
```
