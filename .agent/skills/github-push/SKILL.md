---
name: github-push
description: Git synchronization, commit formatting, rebase handling, and pushing to remote using git or GitHub CLI.
---

# GitHub Push Skill

## Workflow
1. Verify working directory:
   ```bash
   cd C:/dev/namaz-app
   git status
   ```
2. Stage and commit changes:
   ```bash
   git add .
   git commit -m "feat: <descriptive message>"
   ```
3. Pull with rebase to ensure clean linear history:
   ```bash
   git pull --rebase origin main
   ```
4. Push to origin:
   ```bash
   git push origin main
   ```
5. Deploy configuration on GitHub Pages:
   - Repository -> Settings -> Pages -> Build and deployment -> Branch: `main` / `/ (root)`.
