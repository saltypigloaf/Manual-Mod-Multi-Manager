# Manual Mod Multi-Manager

A lightweight PowerShell script for manual Cyberpunk 2077 modders.  Create character-specific profiles, install or remove their mods with a single prompt, and keep your game folder clean without adopting a full mod manager.

## Features
- **Profile based installs.** Mods live under `MultiManage/<Profile>` and are copied into the game with a manifest so they can be removed later.
- **Backups and logs.** Files are backed up before overwrite or delete and all actions are logged.
- **Interactive menu.** Add, remove, switch, or dry-run operations from a simple prompt.
- **Status reporting.** Check whether a profile's files are present, missing, or modified.
- **Sandbox mode.** Run `MultiManage.ps1 -Sandbox` to exercise the workflow on dummy data.

## Requirements
- PowerShell 7 or newer.
- Cyberpunk 2077 on Windows, Linux, or macOS.

## Repository layout
```
Manual-Mod-Multi-Manager/
├── LICENSE
├── MultiManage/
│   ├── MultiManage.ps1
│   ├── Valerie/        # example profile (empty)
│   └── Vincent/        # example profile (empty)
└── README.md
```

Only the `MultiManage` folder needs to live in the game's root directory. The script and this README can stay with it.

## Creating profiles
1. Inside `MultiManage`, make a folder named after a character (e.g. `Valerie`).
2. Re-create the game's mod directories under that folder and drop the mods there:
   - `archive/pc/mod`
   - `r6/scripts`
   - `r6/tweaks`
3. Repeat for each character profile.

## Usage
Launch the script from the game's root directory:

```powershell
pwsh .\MultiManage\MultiManage.ps1
```

You will be presented with an interactive menu:

1. **Add character mods** – copy the selected profile's files into the game and record a manifest.
2. **Remove character mods** – delete files listed in the manifest, restoring backups if necessary.
3. **Show current status** – report whether each manifest's files match the game files.
4. **Dry-run (no changes)** – preview add/remove actions using PowerShell's `-WhatIf` mode.
5. **Switch character** – remove the active profile and install another in one step.
6. **Restore last backup** – recover files from the most recent backup set.
7. **Quit** – exit the script.

Logs are written to `MultiManage/logs/` and backups are stored under `MultiManage/.backup/<timestamp>/`.

## Sandbox
If you want to experiment without touching your real game install, run:

```powershell
pwsh .\MultiManage\MultiManage.ps1 -Sandbox
```

A dummy game directory and profile are created under `MultiManage/Sandbox`, the add/remove workflow is exercised, and a status report is printed.

## License
This project is licensed under the [MIT License](LICENSE).
