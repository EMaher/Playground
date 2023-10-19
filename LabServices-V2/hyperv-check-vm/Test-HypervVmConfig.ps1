  
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)][switch]$Force
)

$ErrorActionPreference = 'Stop' 

# Configure variables for ShouldContinue prompts
$YesToAll = $Force
$NoToAll = $false

# *** CHECK NORMAL USER SETTINGS ***

# Try to find other users on the machines, if there is one, then ask if they should be added to the "Hyper-V Administrators" Group

# Check permissions for VMs (maybe not necessary?)


# *** CHECK VM CONFIGURATION ***

# TODO: Take VM/OS list to verify against known minimum configurations.



$vms = Get-VM

# Script that checks recommendations for each Hyper-V VM as described by https://learn.microsoft.com/azure/lab-services/concept-nested-virtualization-template-vm#recommendations

# Warn if any VMs are in saved state
$savedStateVMs =  @($vms | Where-Object { $_.State -eq "Saved" })
if ($savedStateVMs){
    Write-Warning "Found VM(s) that are in a saved state. VM may fail to start if processor of the Azure VM changes.`n`t$($savedStateVMs -join '`n`t')"
}

#For each VM
$vms | ForEach-Object{

    Write-Host "Testing $_.VMName"

    # TODO: Add check to see if VM is running. We won't be able to some change settings if it is.

    # Set automatic shutdown action is Shutdown
    if ($_.AutomaticStopAction -ne "ShutDown"){
        if ($PSCmdlet.ShouldContinue("Change AutomaticStopOption to ShutDown?  This will require stopping the VM, if it is running.", "AutomaticStopOption for $_.VMName", [ref] $YesToAll, [ref] $NoToAll )){
            $_ | Stop-VM
            $_ | Set-VM -AutomaticStopAction ShutDown
        }

    }

    # Verify disk is vhdx not vhd

    # CPUs is more than default 1 CPU

    # Memory is more than default 512
}