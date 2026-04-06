# Affordance Experiment Framework Design

## Purpose

Automated experiment framework to measure how entity naming (Order vs Request) affects AI agent reasoning when working with structurally identical codebases.

## Parameters

- **Models under test**: Sonnet, Opus
- **Runs per experiment**: 5 per model per app
- **Total invocations**: 7 experiments x 2 apps x 2 models x 5 runs = 140
- **Mode**: `--bare --dangerously-skip-permissions` (no CLAUDE.md, no skills, no hooks)
- **Prompt style**: Bare task, no persona
- **Analysis**: Blind comparison (App A vs App B, naming revealed only in summary)

## Directory Structure

```
experiments/
├── run.sh                          # Main runner script
├── analyze.sh                      # Post-experiment analysis script
├── 01-describe-system/
│   ├── prompt.md                   # Prompt sent to claude
│   ├── config.sh                   # type=readonly or type=code
│   ├── runs/                       # Raw outputs
│   │   ├── order-sonnet-1.md
│   │   ├── order-sonnet-2.md
│   │   ├── ...
│   │   ├── request-opus-5.md
│   ├── analysis.md                 # AI-generated blind comparison
│   └── summary.md                  # Conclusions with naming revealed
├── 02-rebook-feature/
│   └── ...
├── 03-propose-different-time/
│   └── ...
├── 04-bulk-booking/
│   └── ...
├── 05-auto-assignment/
│   └── ...
├── 06-cancellation-fee/
│   └── ...
└── 07-happy-path/
    └── ...
```

## Experiments

### Read-only (text comparison)

**01-describe-system**
- Prompt: "Describe what this system does. What is the domain, what are the main entities, and what is the typical workflow?"
- Hypothesis: "Order" → transactional framing. "Request" → negotiation/invitation framing.
- Signal: Language used, how the AI characterizes relationships between Client and Provider.

**07-happy-path**
- Prompt: "What is the happy path for the main entity in this system? Walk through it step by step."
- Hypothesis: Order gives clean linear path. Request may describe dual paths (created→accepted vs created_accepted) or get confused by legacy states.
- Signal: Number of paths described, clarity, whether legacy states are questioned.

### Code-writing (branch + diff comparison)

**02-rebook-feature**
- Prompt: "Add a feature that lets a client re-book with the same provider. The client should be able to create a new booking based on a previous one, reusing provider, location, and duration. Implement this and commit your changes."
- Hypothesis: "Request" leads to reuse/reopen patterns. "Order" leads to clean new-record creation.
- Signal: Whether AI creates new records vs modifies existing, number of states added, overall approach.

**03-propose-different-time**
- Prompt: "Add a feature where the provider can propose a different time instead of just accepting or rejecting. The client can then accept or decline the counter-proposal. Implement this and commit your changes."
- Hypothesis: "Request" leads to state machine bloat. "Order" leads to a separate counter-proposal model.
- Signal: New states vs new models, state machine complexity delta.

**04-bulk-booking**
- Prompt: "Add a feature where a client can book 5 sessions at once with the same provider (e.g., weekly recurring). All sessions should be created in a single API call. Implement this and commit your changes."
- Hypothesis: "Request" triggers throttling/spam-prevention. "Order" treats it as batch creation.
- Signal: Presence of rate limiting, confirmation steps, or intermediate models.

**05-auto-assignment**
- Prompt: "Add automatic provider assignment. When a client creates a booking without specifying a provider, the system should automatically assign the highest-rated available provider. Implement this and commit your changes."
- Hypothesis: "Request" preserves accept/decline ceremony for auto-assigned bookings. "Order" skips to confirmed.
- Signal: Initial state of auto-assigned entity, whether acceptance flow is preserved.

**06-cancellation-fee**
- Prompt: "Add a cancellation fee. If the client cancels less than 24 hours before the scheduled time, charge 50% of the amount. Implement this in the cancel flow. Implement this and commit your changes."
- Hypothesis: "Request" with extra terminal states (declined, missed) causes over-scoping.
- Signal: Which states get fee logic, scope of changes, number of files touched.

## Runner Script (run.sh)

```bash
#!/bin/bash
# Runs all experiments sequentially
# Skips completed runs (checks if output file exists)
# For code experiments: creates branch, runs claude, commits, captures diff, resets

EXPERIMENTS="01-describe-system 02-rebook-feature 03-propose-different-time 04-bulk-booking 05-auto-assignment 06-cancellation-fee 07-happy-path"
APPS="order request"
MODELS="sonnet opus"
RUNS=5
ROOT=$(cd "$(dirname "$0")/.." && pwd)

for exp in $EXPERIMENTS; do
  source "$ROOT/experiments/$exp/config.sh"  # sets TYPE (readonly|code)
  PROMPT=$(cat "$ROOT/experiments/$exp/prompt.md")

  for model in $MODELS; do
    for app in $APPS; do
      APP_DIR="$ROOT/affordance_$app"

      for run in $(seq 1 $RUNS); do
        OUTPUT_FILE="$ROOT/experiments/$exp/runs/${app}-${model}-${run}.md"
        
        # Skip if already done
        if [ -f "$OUTPUT_FILE" ]; then
          echo "SKIP $exp $app $model run$run (exists)"
          continue
        fi

        echo "RUN  $exp $app $model run$run ..."

        if [ "$TYPE" = "code" ]; then
          BRANCH="experiment/${exp}/${app}/${model}/run-${run}"
          cd "$APP_DIR"
          git checkout main 2>/dev/null
          git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH" 2>/dev/null

          RESULT=$(echo "$PROMPT" | claude -p --bare --dangerously-skip-permissions --model "$model" 2>/dev/null)

          # Commit any uncommitted changes claude left behind
          git add -A 2>/dev/null
          git diff --cached --quiet || git commit -m "experiment: $exp $app $model run-$run (uncommitted)" 2>/dev/null

          # Capture output + diff
          {
            echo "# Experiment: $exp"
            echo "# App: $app | Model: $model | Run: $run"
            echo "---"
            echo "$RESULT"
            echo ""
            echo "---"
            echo "## Git Diff (committed changes)"
            echo '```diff'
            git diff main..HEAD
            echo '```'
            echo ""
            echo "## Branch"
            echo "$BRANCH"
          } > "$OUTPUT_FILE"

          # Return to main
          cd "$ROOT"
          cd "$APP_DIR"
          git checkout main 2>/dev/null
        else
          # Read-only
          cd "$APP_DIR"
          RESULT=$(echo "$PROMPT" | claude -p --bare --dangerously-skip-permissions --model "$model" 2>/dev/null)

          {
            echo "# Experiment: $exp"
            echo "# App: $app | Model: $model | Run: $run"
            echo "---"
            echo "$RESULT"
          } > "$OUTPUT_FILE"
        fi

        cd "$ROOT"
        echo "DONE $exp $app $model run$run"
      done
    done
  done
done

echo "All experiments complete."
```

## Analysis Script (analyze.sh)

For each experiment:
1. Collects all output files
2. Sends to claude (opus) with blind comparison prompt (App A = order, App B = request, but not revealed)
3. Writes `analysis.md`
4. Generates `summary.md` draft with naming revealed + branch links

Analysis prompt template:
```
You are analyzing an experiment comparing AI responses to identical prompts
given in two different codebases. The codebases are structurally identical
except for naming conventions. You do not know what the naming difference is.

## Prompt Given
[prompt.md content]

## App A Responses (5 Sonnet + 5 Opus)
[concatenated outputs]

## App B Responses (5 Sonnet + 5 Opus)
[concatenated outputs]

Analyze across these dimensions:
1. Language/framing: How does each set describe the domain?
2. Architectural choices: What models, states, or abstractions were proposed?
3. Complexity: Lines of code, number of new files, new states added
4. Scope: Did responses stay on-task or add unrequested features?
5. Assumptions: What did responses assume about the system's purpose?
6. Model comparison: Did Sonnet and Opus differ in their patterns?

Provide:
- A pattern summary across all runs
- Confidence level: strong pattern / weak signal / no difference
- Notable outliers
- Raw tallies where applicable (e.g., "App A added N new states on average, App B added M")
```

## Code Experiment Branch Management

For code-writing experiments:
- Each run gets its own branch: `experiment/<name>/<app>/<model>/run-<N>`
- Branch created from `main` before each run
- Claude runs, makes changes, commits within the branch
- Diff captured to output file
- Script returns to `main` after each run
- Branches are preserved (not deleted) for later inspection
- `summary.md` lists all branches for each experiment

## Resumability

The runner skips any run where the output file already exists. If the session limit hits mid-run:
1. The current run's output file won't be written (incomplete)
2. Re-running the script after limit resets will retry that run and continue
3. No manual cleanup needed

## Cost Estimate

- Read-only experiments (2): ~20 runs x ~$0.05 = ~$1
- Code-writing experiments (5): ~100 runs x ~$0.30 = ~$30
- Analysis (7 experiments): ~7 x ~$0.50 = ~$3.50
- **Total estimate: ~$35**
