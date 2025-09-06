
# Installs zsh, oh-my-zsh, and configures with Dracula theme only
[CmdletBinding()]
param(
    [ValidateSet("Ubuntu", "Ubuntu-22.04", "Ubuntu-20.04", "Debian", "kali-linux")]
    [string]$Distribution = "Ubuntu"
)

function Write-Status($Message) { Write-Host $Message -ForegroundColor Cyan }
function Write-Success($Message) { Write-Host $Message -ForegroundColor Green }
function Write-Error($Message) { Write-Host $Message -ForegroundColor Red }

$installedDistros = wsl --list --quiet 2>$null
$distroName = $Distribution.Replace("-", "")
if (-not ($installedDistros -contains $distroName)) {
    Write-Error "WSL distribution '$Distribution' not found. Run install-wsl.ps1 first."
    exit 1
}

Write-Status "Configuring zsh with Dracula theme for $Distribution..."

# Create zsh installation script
$zshScript = @'
#!/bin/bash

echo "=== Starting Zsh + Dracula Theme Installation ==="

echo "## updating package lists##"
sudo apt-get update

echo "## installing zsh and dependencies ##"
sudo apt-get install -y zsh curl

echo "## installing oh-my-zsh ##"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    export RUNZSH=no
    export CHSH=no
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    echo "oh-my-zsh installed successfully"
else
    echo "oh-my-zsh already installed"
fi

echo "## verify oh-my-zsh installation ##"
if [ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
    echo "ERROR: oh-my-zsh installation failed - missing oh-my-zsh.sh"
    exit 1
fi

echo "## installing Dracula theme ##"
if [ ! -d "$HOME/.oh-my-zsh/themes/dracula" ]; then
    git clone https://github.com/dracula/zsh.git "$HOME/.oh-my-zsh/themes/dracula"
    ln -sf "$HOME/.oh-my-zsh/themes/dracula/dracula.zsh-theme" "$HOME/.oh-my-zsh/themes/dracula.zsh-theme"
    echo "Dracula theme installed"
else
    echo "Dracula theme already exists"
fi

echo "## installing zsh plugins ##"
[ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ] && \
    git clone --quiet https://github.com/zsh-users/zsh-autosuggestions "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"

[ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ] && \
    git clone --quiet https://github.com/zsh-users/zsh-syntax-highlighting.git "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
 
echo "## add Dracula theme to .zshrc ##"
if grep -q '^ZSH_THEME=' "$HOME/.zshrc"; then
  sed -i 's|^ZSH_THEME=.*|ZSH_THEME="dracula"|' "$HOME/.zshrc"
else
  echo 'ZSH_THEME="dracula"' >> "$HOME/.zshrc"
fi

echo "## updating plugins ##"
# sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting sudo extract colored-man-pages)/' "$HOME/.zshrc"

echo "setting zsh as default shell..."
sudo chsh -s $(which zsh) $(whoami) >/dev/null 2>&1

echo "=== Configuration Summary ==="
echo "Theme: $(grep '^ZSH_THEME=' $HOME/.zshrc)"
echo "Plugins: $(grep '^plugins=' $HOME/.zshrc)"
echo "=== Installation Complete ==="
echo "Run 'exec zsh' or start a new terminal session to use Dracula theme"
'@

try {

    Write-Status "installing zsh with Dracula theme..."
    $scriptPath = "$env:TEMP\configure_zsh_dracula.sh"
    
    $zshScript = $zshScript -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($scriptPath, $zshScript, [System.Text.UTF8Encoding]::new($false))

    # convert Windows path to WSL path
    $wslScriptPath = $scriptPath.Replace('\', '/').Replace('C:', '/mnt/c')
    
    $result = wsl -d $distroName bash -c "bash '$wslScriptPath'"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Script execution failed with exit code $LASTEXITCODE"
        Write-Host "Output: $result" -ForegroundColor Red
        exit 1
    }
    
    Write-Success "Zsh with Dracula theme installation completed!"
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Restart WSL: wsl -d $distroName" -ForegroundColor White
    Write-Host "2. Or run 'exec zsh' in your current terminal" -ForegroundColor White
    Write-Host "3. The Dracula theme should now be active" -ForegroundColor White
}
catch {
    Write-Error "Configuration failed: $($_.Exception.Message)"
    exit 1
}
finally {
    # cleanup temp file
    if (Test-Path $scriptPath) {
        Remove-Item $scriptPath -Force
    }
}