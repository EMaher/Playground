# README

This sample has script to help shutdown a student's Lab Services virtual machine so that Lab Services is notified and billing stops.  This solution is expected to be execute by the student on the student's virtual machine.

There are two parts.  The first setups up prerequisites and caches authorization information.  The second script calls Lab Services and asks it to stop the virtual machine.  

**These scripts are intended to be run on the student virtual machine.**  There is logic in the scripts to find the correct virtual machine.  See 'stop-CurrentlabVm.ps1' notes for further details.

## Setup

Both scripts use PowerShell Core to execute commands.  [Install PowerShell Core](https://docs.microsoft.com/powershell/scripting/install/installing-powershell?view=powershell-7), if you have not already done so.

For Ubuntu-1804, follow the instructions in [Install PowerShell Core for Ubuntu-1804](https://docs.microsoft.com/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-7#ubuntu-1804).  Commands included below for convenience.  

```bash
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
The following command should be run at the start of the task.  It will install some prequisites, if needed and cache credentials for later use.

Bash:
```bash
pwsh ./prepare-CurrentLabVmStop.ps1
```

PowerShell:
```PowerShell
Prepare-CurrentLabVmStop.ps1
```

## Run after job
Once your task is complete, call the following script and the virtual machine will be shutdown and student quota will no longer be used.

Bash:
```bash
pwsh ./stop-CurrentLabVm.ps1
```

PowerShell:
```PowerShell
Stop-CurrentLabVm.ps1
```
