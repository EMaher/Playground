# Instructions

## Script Setup

1. [Install PowerShell Core for Ubuntu-1804](https://docs.microsoft.com/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-7#ubuntu-1804)

```
# Download the Microsoft repository GPG keys
wget -q https://packages.microsoft.com/config/ubuntu/18.04/packages-microsoft-prod.deb

# Register the Microsoft repository GPG keys
sudo dpkg -i packages-microsoft-prod.deb

# Update the list of products
sudo apt-get update

# Enable the "universe" repositories
sudo add-apt-repository universe

# Install PowerShell
sudo apt-get install -y powershell

```

## Run before job

```
pwsh ./prepare-CurrentLabVmStop.ps1

```

## Run after job

```
pwsh ./stop-CurrentLabVm.ps1

```
