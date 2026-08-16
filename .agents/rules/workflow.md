# Workflow Rules

## Git Workflow & Autonomous Lifecycle
1. **Branching**: For every new prompt/task, checkout and pull latest `main`, then create a fresh descriptive branch off `main` (e.g., `feat/...`, `fix/...`, `chore/...`).
2. **Implementation**: Make all code/file changes directly without asking for user permission.
3. **Pull Requests**: For every prompt/task, push the branch and open a fresh Pull Request to `main`.
4. **GitHub Actions & Auto-Merge**:
   - Monitor GitHub Actions workflow runs for the PR until all checks complete.
   - Once all CI checks pass successfully, automatically merge the Pull Request into `main`.
   - After merging, pull the merged `main` locally and notify the user that the PR has merged.

## Autonomy
- Do not ask for permission to modify, create, or delete files, or to execute commands. Proceed autonomously from start to finish.
