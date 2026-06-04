# dev-bootstrap

Eric N. Vander Weele's development environment bootstrapper.

Feel free to look around and take what inspires you!

## macOS / WSL

```sh
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ericvw/dev-bootstrap/main/bootstrap.sh)"
```

Git Credential Manager is installed automatically:

- **macOS** - installed as a Homebrew cask by the bootstrap script
- **WSL** - provided by Git for Windows (enabled via `git-install.inf` below)

## Windows (PowerShell)

```powershell
irm "https://raw.githubusercontent.com/ericvw/dev-bootstrap/main/git-install.inf" -OutFile "$env:TEMP\git-install.inf"
winget install Git.Git --override "/VERYSILENT /NORESTART /LOADINF=`"$env:TEMP\git-install.inf`""
winget install Microsoft.WindowsTerminal
```

Then install WSL: `wsl --install` (restart if prompted, create a Linux user, then run the macOS / WSL command above).

## License

Apache License, Version 2.0. See license text in [LICENSE](LICENSE).

<!--
vim: tw=100:spell
-->
