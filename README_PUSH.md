Pushing this backend to GitHub (safe workflow)

This guide helps you push the repository in `C:\backend` to the GitHub repo:
https://github.com/carlosmontesdeocae321-oss/taller-motos-backend.git

Important: This will NOT replace or touch other GitHub repositories you have. The included PowerShell script adds a new remote under the name `taller-motos-remote` (customizable) and pushes the `main` branch there.

Quick run (PowerShell):
```powershell
cd C:\backend
# Run the helper script (will prompt if user interaction required)
.\push_to_github.ps1 -remoteUrl "https://github.com/carlosmontesdeocae321-oss/taller-motos-backend.git"
```

If authentication is required, use one of these methods:
- Recommended: install GitHub CLI and login: `gh auth login` (choose HTTPS or SSH and follow prompts).
- Or configure the Git Credential Manager for Windows so `git push` prompts a credential dialog.

Manual commands (if you prefer not to use the script):
```powershell
cd C:\backend
# initialize git if needed
git init
# create a commit if none exists
git add .
git commit -m "Initial commit - backend for Taller de Motos"
# add a safe remote name (do not overwrite 'origin')
git remote add taller-motos-remote https://github.com/carlosmontesdeocae321-oss/taller-motos-backend.git
# push main
git branch -M main
git push -u taller-motos-remote main
```

Notes & troubleshooting
- If you already have a remote pointing to the same URL, `push_to_github.ps1` will detect it and will not add another remote; it will list the existing remote name for your convenience.
- If push fails due to authentication, run `gh auth login` or set up credentials in Windows Credential Manager and try again.
- If your default branch is `master` instead of `main`, either rename locally with `git branch -M main` or change the `-branch` parameter of the script.

After push
- In GitHub, verify the repository shows files and commits.
- Connect this GitHub repo to Render (or let Render import using `render.yaml`).
- Add environment variables on Render dashboard: `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, `PORT`, `BASE_URL`.

If you want, puedo intentar crear un workflow GitHub Actions para CI/CD o un paso automatizado que dispare el deploy en Render; dime si lo deseas.
