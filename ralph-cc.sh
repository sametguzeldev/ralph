#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop (Claude Code edition)
# Uses claude -p with --append-system-prompt for proper skill/project integration
# Supports parallel execution: stories sharing the same priority run simultaneously
# in separate git worktrees via `claude --worktree`.
# Usage: ./ralph-cc.sh [max_iterations]

set -e

MAX_ITERATIONS=10

while [[ $# -gt 0 ]]; do
  case $1 in
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
SYSTEM_PROMPT="$(cat "$SCRIPT_DIR/CLAUDE.md")"

# ---------------------------------------------------------------------------
# jq helpers
# ---------------------------------------------------------------------------

# Lowest priority number that still has passes: false stories
get_lowest_priority() {
  jq -r '[.userStories[] | select(.passes == false) | .priority] | if length == 0 then empty else min end' "$PRD_FILE"
}

# JSON array of stories at a given priority with passes: false
get_stories_at_priority() {
  local priority="$1"
  jq -c "[.userStories[] | select(.passes == false and .priority == $priority)]" "$PRD_FILE"
}

# Mark a story as passing in prd.json (in-place)
mark_story_done() {
  local story_id="$1"
  local tmp
  tmp=$(mktemp)
  jq "(.userStories[] | select(.id == \"$story_id\") | .passes) |= true" "$PRD_FILE" > "$tmp"
  mv "$tmp" "$PRD_FILE"
}

# True if all stories have passes: true
all_stories_done() {
  local remaining
  remaining=$(jq '[.userStories[] | select(.passes == false)] | length' "$PRD_FILE")
  [ "$remaining" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Worktree helpers
# ---------------------------------------------------------------------------

# Return the current branch of a worktree directory
worktree_branch_for() {
  local wt_dir="$1"
  git -C "$wt_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

# Remove a worktree and its branch (force-delete branch so it works for
# both merged and unmerged/failed branches)
cleanup_worktree() {
  local wt_name="$1"
  local branch="$2"
  local wt_dir="$GIT_ROOT/.claude/worktrees/$wt_name"
  git -C "$GIT_ROOT" worktree remove --force "$wt_dir" 2>/dev/null || true
  if [ -n "$branch" ]; then
    git -C "$GIT_ROOT" branch -D "$branch" 2>/dev/null || true
  fi
}

# ---------------------------------------------------------------------------
# Archive previous run if branch changed
# ---------------------------------------------------------------------------
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    DATE=$(date +%Y-%m-%d)
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"

    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

echo "Starting Ralph (Claude Code) - Max iterations: $MAX_ITERATIONS"

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS (Claude Code)"
  echo "==============================================================="

  # Find the current wave (lowest priority with unfinished stories)
  WAVE_PRIORITY=$(get_lowest_priority)

  if [ -z "$WAVE_PRIORITY" ]; then
    echo "All stories complete!"
    echo "<promise>COMPLETE</promise>"
    exit 0
  fi

  WAVE_STORIES=$(get_stories_at_priority "$WAVE_PRIORITY")
  WAVE_COUNT=$(echo "$WAVE_STORIES" | jq 'length')

  echo "  Wave priority: $WAVE_PRIORITY | Stories: $WAVE_COUNT"

  # -------------------------------------------------------------------------
  # SEQUENTIAL MODE — single story, agent manages prd.json + progress.txt
  # -------------------------------------------------------------------------
  if [ "$WAVE_COUNT" -eq 1 ]; then
    echo "  Mode: sequential"
    OUTPUT=$(claude -p "Read CLAUDE.md and begin the next Ralph iteration" \
      --append-system-prompt "$SYSTEM_PROMPT" \
      --dangerously-skip-permissions 2>&1 | tee /dev/stderr) || true

    if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
      echo ""
      echo "Ralph completed all tasks!"
      echo "Completed at iteration $i of $MAX_ITERATIONS"
      exit 0
    fi

  # -------------------------------------------------------------------------
  # PARALLEL MODE — multiple stories, each in its own worktree
  # -------------------------------------------------------------------------
  else
    echo "  Mode: parallel (${WAVE_COUNT} concurrent worktrees)"

    declare -A PIDS
    declare -A STORY_IDS_MAP

    # Launch all stories in parallel
    while IFS= read -r story; do
      STORY_ID=$(echo "$story" | jq -r '.id')
      STORY_TITLE=$(echo "$story" | jq -r '.title')
      STORY_DESC=$(echo "$story" | jq -r '.description')
      STORY_AC=$(echo "$story" | jq -r '.acceptanceCriteria | join("; ")')

      WORKTREE_NAME="ralph-${STORY_ID,,}"
      OUT_FILE="/tmp/ralph-${STORY_ID}.out"

      PROMPT="Parallel mode: implement story ${STORY_ID}: ${STORY_TITLE}.
Description: ${STORY_DESC}
Acceptance criteria: ${STORY_AC}"

      echo "  Launching ${STORY_ID}: ${STORY_TITLE} (worktree: ${WORKTREE_NAME})"

      (
        cd "$GIT_ROOT"
        claude --worktree "$WORKTREE_NAME" \
          -p "$PROMPT" \
          --append-system-prompt "$SYSTEM_PROMPT" \
          --dangerously-skip-permissions \
          > "$OUT_FILE" 2>&1
      ) &

      PIDS["$STORY_ID"]=$!
      STORY_IDS_MAP["$STORY_ID"]="$STORY_TITLE"
    done < <(echo "$WAVE_STORIES" | jq -c '.[]')

    echo "  Waiting for ${WAVE_COUNT} parallel agents..."

    # Collect results and merge worktrees
    MERGED_STORIES=()
    FAILED_STORIES=()

    for STORY_ID in "${!PIDS[@]}"; do
      PID="${PIDS[$STORY_ID]}"
      STORY_TITLE="${STORY_IDS_MAP[$STORY_ID]}"
      WORKTREE_NAME="ralph-${STORY_ID,,}"
      WORKTREE_DIR="$GIT_ROOT/.claude/worktrees/$WORKTREE_NAME"
      OUT_FILE="/tmp/ralph-${STORY_ID}.out"

      # Wait for this agent
      wait "$PID" || true

      OUTPUT=""
      [ -f "$OUT_FILE" ] && OUTPUT=$(cat "$OUT_FILE")

      # Check completion signal
      if ! echo "$OUTPUT" | grep -q "<story-done>${STORY_ID}</story-done>"; then
        echo "  ✗ ${STORY_ID}: no completion signal — skipping merge"
        FAILED_STORIES+=("$STORY_ID")
        BRANCH=$(worktree_branch_for "$WORKTREE_DIR")
        cleanup_worktree "$WORKTREE_NAME" "$BRANCH"
        continue
      fi

      # Get the worktree branch
      BRANCH=$(worktree_branch_for "$WORKTREE_DIR")
      if [ -z "$BRANCH" ]; then
        echo "  ✗ ${STORY_ID}: could not determine worktree branch — skipping"
        FAILED_STORIES+=("$STORY_ID")
        cleanup_worktree "$WORKTREE_NAME" ""
        continue
      fi

      # Attempt merge into current branch
      echo "  Merging ${STORY_ID} (branch: ${BRANCH})..."
      if git -C "$GIT_ROOT" merge --no-ff "$BRANCH" -m "merge: ${STORY_ID} - ${STORY_TITLE}" 2>/dev/null; then
        mark_story_done "$STORY_ID"
        MERGED_STORIES+=("$STORY_ID")
        echo "  ✓ ${STORY_ID} merged and marked done"
      else
        git -C "$GIT_ROOT" merge --abort 2>/dev/null || true
        echo "  ✗ ${STORY_ID}: merge conflict — will retry next iteration"
        FAILED_STORIES+=("$STORY_ID")
      fi

      cleanup_worktree "$WORKTREE_NAME" "$BRANCH"
    done

    unset PIDS
    unset STORY_IDS_MAP

    # Append combined progress entry
    if [ ${#MERGED_STORIES[@]} -gt 0 ]; then
      STORY_LIST=$(IFS=', '; echo "${MERGED_STORIES[*]}")
      {
        echo ""
        echo "## $(date '+%Y-%m-%d %H:%M') - Parallel wave: ${STORY_LIST}"
        echo "- Stories ran in parallel worktrees via \`claude --worktree\`"
        if [ ${#FAILED_STORIES[@]} -gt 0 ]; then
          FAILED_LIST=$(IFS=', '; echo "${FAILED_STORIES[*]}")
          echo "- Failed to merge (will retry): ${FAILED_LIST}"
        fi
        echo "---"
      } >> "$PROGRESS_FILE"
    fi

    # Check if all done after this wave
    if all_stories_done; then
      echo ""
      echo "Ralph completed all tasks!"
      echo "Completed at iteration $i of $MAX_ITERATIONS"
      echo "<promise>COMPLETE</promise>"
      exit 0
    fi
  fi

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
