---
name: ship
description: Stage, commit, push changes and create PR if on feature branch
disable-model-invocation: true
allowed-tools: Bash(git:*, gh:*), Read, Grep, Glob
argument-hint: [optional commit message override]
---

# Automated Git Ship Workflow

Execute this workflow step by step. Stop immediately if any step fails.

## Step 1: Check Repository Status

Run these commands to understand the current state:
```bash
git status
git branch --show-current
```

Verify:
- We are in a git repository
- Note the current branch name

## Step 2: Stage All Changes

Stage all modified, added, and deleted files:
```bash
git add -A
```

## Step 3: Analyze Changes and Generate Commit Message

Run to see what will be committed:
```bash
git diff --cached --stat
git diff --cached
```

**If the user provided $ARGUMENTS**, use that as the commit message.

**Otherwise**, analyze the staged changes and generate a single-line commit message that:
- Starts with a lowercase verb (add, fix, update, remove, refactor, etc.)
- Summarizes the main change in under 72 characters
- Is specific but concise
- Does NOT use conventional commit prefixes like "feat:" or "fix:"

Examples of good commit messages:
- "add user authentication with JWT tokens"
- "fix race condition in websocket handler"
- "update dependencies and remove unused packages"
- "refactor database queries for better performance"

## Step 4: Create the Commit

Create the commit with the generated or provided message:
```bash
git commit -m "YOUR_MESSAGE"
```

## Step 5: Push to Remote

Push the changes to the remote repository:
```bash
git push origin HEAD
```

If the branch doesn't exist on remote yet, use:
```bash
git push -u origin HEAD
```

## Step 6: Create Pull Request (Feature Branches Only)

Check if we're on a feature branch (not main or master):
```bash
git branch --show-current
```

**If the branch is NOT main or master:**

Check if a PR already exists:
```bash
gh pr view --json state 2>/dev/null || echo "NO_PR"
```

If no PR exists, create one:
```bash
gh pr create --fill
```

The `--fill` flag uses the commit message as the PR title and body.

**If on main or master:** Skip PR creation and inform the user that changes were pushed directly to the main branch.

## Step 7: Report Results

Provide a summary:
- What was committed (brief description)
- The commit hash (short form)
- Whether a PR was created and include the URL if so
- Or note that changes were pushed directly to main
