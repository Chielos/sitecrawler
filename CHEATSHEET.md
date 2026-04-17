Git Workflow Cheatsheet for sitecrawler

📁 Navigate to Project

cd /Users/chielos/Documents/GitHub/sitecrawler

⸻

🔍 Basic Checks

pwd
git rev-parse --show-toplevel
git branch --show-current
git status
git remote -v

⸻

🚀 Daily Start

git checkout main
git pull --rebase origin main
git status

⸻

🌿 Create Branch

Feature

git checkout -b feature/your-feature-name

Bugfix

git checkout -b fix/your-bug-name

⸻

🔄 Switch Branch

git checkout main
git checkout your-branch-name
git branch
git branch -a

⸻

✏️ During Work

git status
git diff
git diff --name-only

⸻

💾 Commit Changes

git add .
git commit -m "Clear message"

⸻

📤 Push Changes

git push origin HEAD

⸻

📥 Pull Updates

git pull --rebase origin main

⸻

🧪 Open Editors

VS Code

code .

Xcode

xed .
# or
open -a Xcode .

⸻

⚠️ Conflict Resolution

git status
# fix files manually
git add <file>
git rebase --continue

Find conflict markers:

grep -nE '<<<<<<<|=======|>>>>>>>' <file>

⸻

📜 Logs

git log --oneline -10
git log --oneline --graph --decorate --all -20

⸻

🧹 Cleanup

git clean -fdXn   # preview
git clean -fdX    # remove ignored files

Manual cleanup:

rm -f .DS_Store
rm -rf .build
rm -rf .vscode
rm -rf .swiftpm/xcode/package.xcworkspace/xcuserdata

⸻

🔄 Restore

git restore <file>
git restore .
git restore --staged <file>

⸻

⚡ Standard Workflow

git checkout main
git pull --rebase origin main
git checkout -b feature/or-fix-name
code .
xed .
git add .
git commit -m "What you did"
git push origin HEAD

⸻

🚨 Safety Rules

* Do NOT use git push --force
* Do NOT work directly on main
* Always commit before switching tasks
* Ignore build/editor files via .gitignore

⸻

🧠 Quick Sanity Check

pwd
git rev-parse --show-toplevel
git branch --show-current
git status

⸻

🧩 Your Workflow

* VS Code → writing & features
* Xcode → run & debug
* Git → source of truth

⸻

✅ Done Criteria

* Code builds in Xcode
* No errors
* Changes committed
* Branch pushed to GitHub