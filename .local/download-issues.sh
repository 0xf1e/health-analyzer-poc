#!/usr/bin/env bash

# ==============================================================================
# Script: download_github_issues.sh
# Description: Downloads all issues and their discussions (comments) from the
#              current GitHub repository using the GitHub CLI ('gh').
# Output (stdout): Formatted issues and comments.
# Logging (stderr): Detailed progress and error messages.
# Requirements:
#   - git: To determine the current repository.
#   - gh: GitHub CLI installed and authenticated (run 'gh auth login').
# ==============================================================================

# --- Configuration ---
ISSUE_LIMIT=5000

# --- Helper Functions ---

log() {
  echo "[LOG] $(date +'%Y-%m-%d %H:%M:%S') - $*" >&2
}

error_exit() {
  echo "[ERROR] $(date +'%Y-%m-%d %H:%M:%S') - $*" >&2
  exit 1
}

# --- Pre-flight Checks ---

log "Starting script: Download GitHub Issues"

if ! command -v gh &> /dev/null; then
  error_exit "GitHub CLI ('gh') could not be found. Please install it (https://cli.github.com/) and authenticate ('gh auth login')."
fi
log "GitHub CLI found."

if ! gh auth status &> /dev/null; then
 error_exit "GitHub CLI is not authenticated. Please run 'gh auth login'."
fi
log "GitHub CLI is authenticated."

# --- Main Logic ---

log "Detecting current GitHub repository..."
REPO_INFO=$(gh repo view --json owner,name --jq '.owner.login + "/" + .name' 2> >(sed 's/^/[ERROR] /' >&2))
if [[ $? -ne 0 || -z "$REPO_INFO" ]]; then
  error_exit "Failed to detect GitHub repository information. Make sure you are in a git repository with a remote pointing to GitHub."
fi
log "Detected repository: $REPO_INFO"

log "Fetching list of all issue numbers (limit: $ISSUE_LIMIT)..."
ISSUE_NUMBERS=$(gh issue list --repo "$REPO_INFO" --state all --limit "$ISSUE_LIMIT" --json number --jq '.[].number' 2> >(sed 's/^/[ERROR] /' >&2))
if [[ $? -ne 0 ]]; then
  error_exit "Failed to list issues for repository '$REPO_INFO'."
fi

if [[ -z "$ISSUE_NUMBERS" ]]; then
  log "No issues found for repository '$REPO_INFO'."
  log "Script finished successfully."
  exit 0
fi

ISSUE_COUNT=$(echo "$ISSUE_NUMBERS" | wc -l | xargs)
log "Found $ISSUE_COUNT issues. Processing each one..."

IFS=$'\n' # Process one line (issue number) at a time
for number in $ISSUE_NUMBERS; do
  log "Processing Issue #$number..."

  log "Fetching details for Issue #$number..."
  ISSUE_DETAILS_JSON=$(gh issue view "$number" --repo "$REPO_INFO" --json number,title,state,author,body,createdAt,url 2> >(sed 's/^/[ERROR] /' >&2))
  if [[ $? -ne 0 ]]; then
    log "Skipping Issue #$number: Failed to fetch main details."
    continue
  fi

  log "Fetching comments for Issue #$number..."
  ISSUE_COMMENTS_JSON=$(gh issue view "$number" --repo "$REPO_INFO" --comments --json comments 2> >(sed 's/^/[ERROR] /' >&2))
   if [[ $? -ne 0 ]]; then
    log "Warning for Issue #$number: Failed to fetch comments, but proceeding with issue details."
    ISSUE_COMMENTS_JSON='{"comments":[]}'
  fi

  # --- Output to stdout ---

  ISSUE_TITLE=$(echo "$ISSUE_DETAILS_JSON" | jq -r '.title')
  ISSUE_STATE=$(echo "$ISSUE_DETAILS_JSON" | jq -r '.state')
  ISSUE_AUTHOR=$(echo "$ISSUE_DETAILS_JSON" | jq -r '.author.login // "ghost"') # Handle null author
  ISSUE_CREATED_AT=$(echo "$ISSUE_DETAILS_JSON" | jq -r '.createdAt')
  ISSUE_URL=$(echo "$ISSUE_DETAILS_JSON" | jq -r '.url')
  ISSUE_BODY=$(echo "$ISSUE_DETAILS_JSON" | jq -r '.body')

  # Use echo for separators to avoid potential printf issues
  echo "============================================================"
  # Use printf only for formatting known-safe variables
  printf "Issue #%s: %s\n" "$number" "$ISSUE_TITLE"
  echo "------------------------------------------------------------"
  printf "State: %s\n" "$ISSUE_STATE"
  printf "Author: %s\n" "$ISSUE_AUTHOR"
  printf "Created At: %s\n" "$ISSUE_CREATED_AT"
  printf "URL: %s\n" "$ISSUE_URL"
  echo "------------------------------------------------------------"
  echo # Print a blank line
  echo "### Issue Body ###"
  echo # Print a blank line
  # Use echo to print the body safely, handling empty body
  echo "${ISSUE_BODY:-*(No body)*}"
  echo # Print a blank line

  # Prepare comments count
  COMMENT_COUNT=$(echo "$ISSUE_COMMENTS_JSON" | jq '.comments | length')
  printf "### Discussion (%s comments) ###\n" "$COMMENT_COUNT"

  echo "$ISSUE_COMMENTS_JSON" | jq -c '.comments[]' | while IFS= read -r comment; do
      COMMENT_AUTHOR=$(echo "$comment" | jq -r '.author.login // "ghost"')
      COMMENT_CREATED_AT=$(echo "$comment" | jq -r '.createdAt')
      COMMENT_BODY=$(echo "$comment" | jq -r '.body')

      echo # Blank line before comment separator
      echo "--------------------"
      # Use printf for metadata
      printf "Comment by %s at %s:\n" "$COMMENT_AUTHOR" "$COMMENT_CREATED_AT"
      echo # Blank line before comment body
      # Use echo to print comment body safely, handling empty body
      echo "${COMMENT_BODY:-*(No body)*}"
  done

  echo # Blank line after last comment (or discussion header if no comments)
  echo "============================================================"
  echo # Blank line between issues
  echo # Another blank line for better separation

  log "Finished processing Issue #$number."

done

log "Script finished successfully."
exit 0
