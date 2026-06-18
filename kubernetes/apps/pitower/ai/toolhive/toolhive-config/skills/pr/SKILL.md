---
name: pr
description: |
  Create a branch, commit changes, push, and open a pull request.
  Use when asked to "open a PR", "create a PR", "branch and push",
  or "submit this for review".
allowed-tools:
  - Bash
  - Read
  - Grep
  - AskUserQuestion
---

# Pull Request Workflow

Complete flow: branch, commit, push, open PR.

## Branch Naming

Use the format `<type>/<ticket-id>/<short-description>`:

- `feat/DND-123/add-auth-flow`
- `fix/DND-456/null-pointer-crash`
- `chore/DND-789/update-deps`

If no ticket ID is provided, ask the user. Types: `feat`, `fix`, `chore`, `refactor`, `docs`, `test`, `ci`.

## Steps

1. **Check state**: Run `git status` and `git diff --stat` to understand what's changed.

2. **Create branch**: Ask for ticket ID and description if not provided. Create and switch:
   ```
   git checkout -b <type>/<ticket-id>/<description>
   ```

3. **Stage changes**: Stage relevant files. Never stage `.env`, credentials, or secrets. Prefer specific file names over `git add .`.

4. **Commit**: Write a concise commit message following conventional commits:
   ```
   <type>(<scope>): <description>
   ```
   Use a HEREDOC for multi-line messages.

5. **Push**: Push with upstream tracking:
   ```
   git push -u origin <branch>
   ```

6. **Open PR**: Create the PR with `gh pr create`:
   ```
   gh pr create --title "<type>(<scope>): <description>" --body "$(cat <<'EOF'
   ## Summary
   <bullet points>

   ## Test plan
   - [ ] <checklist>
   EOF
   )"
   ```

7. **Return the PR URL** to the user.

## Rules

- Keep PR titles under 70 chars
- Never force push
- Never push to main/master directly
- If there are no changes, tell the user — don't create an empty commit
