  
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)][switch]$Force
)

$ErrorActionPreference = 'Stop' 

# Configure variables for ShouldContinue prompts
$YesToAll = $Force
$NoToAll = $false

# ### FUNCTIONS ###

# *** CHECK NORMAL USER SETTINGS ***

# Try to find other users on the machines, if there is one, then ask if they should be added to the "Hyper-V Administrators" Group

# Check permissions for VMs (maybe not necessary?)


# *** CHECK VM CONFIGURATION ***

# TODO: Take VM/OS list to verify against known minimum configurations.


function Stop-HypervVm{
    param (
        [Parameter(ValueFromPipeline)]
        [Microsoft.HyperV.PowerShell.VirtualMachine]
        $vm
    )

    if (($vm | Select-Object -ExpandProperty State) -eq [Microsoft.HyperV.PowerShell.VMState]::Off){
        return
    }

    $vm | Stop-VM -Force -WarningAction Continue
}

function Set-HypervVmProperty{
    param (
        [Parameter(ValueFromPipeline)]
        [Microsoft.HyperV.PowerShell.VirtualMachine]
        $vm,
        [Parameter(Mandatory = $true)][scriptblock]$GetCurrentValueScriptBlock,
        [Parameter(Mandatory = $true)][scriptblock]$GetDesiredValueScriptBlock,
        [Parameter(Mandatory = $true)][scriptblock]$SetValueScriptBlock,
         [string]$PropertyName,
        [bool]$RequiresVmStopped
    )

    $currentValue = & $GetCurrentValueScriptBlock
    $desiredValue = & $GetDesiredValueScriptBlock

    if ($currentValue -ne $desiredValue){
        if ($RequiresVmStopped -and $(($vm | Select-Object -ExpandProperty State) -ne [Microsoft.HyperV.PowerShell.VMState]::Off)){
            if (-not $PSCmdlet.ShouldContinue("Stop VM?  It is required to change $($PropertyName) from $($currentValue) to $($desiredValue)? ", "$($PropertyName) for $($vm.VMName)", [ref] $YesToAll, [ref] $NoToAll )){
                Write-Warning "Did not change $($PropertyName) from $($currentValue) to $($desiredValue).  VM must be stopped first."
                return
            }

            $vm | Stop-VM -Force -WarningAction Continue
        }

        & $SetValueScriptBlock
    }
}

$vms = Get-VM

# Script that checks recommendations for each Hyper-V VM as described by https://learn.microsoft.com/azure/lab-services/concept-nested-virtualization-template-vm#recommendations

# Warn if any VMs are in saved state
$savedStateVMs =  @($vms | Where-Object { $_.State -eq "Saved" })
if ($savedStateVMs){
    Write-Warning "Found VM(s) that are in a saved state. VM may fail to start if processor of the Azure VM changes.`n`t$($savedStateVMs -join '`n`t')"
}

#For each VM
foreach ($vm in $vms){
    Write-Host "*** Testing $($vm.VMName) ***"

    # TODO: Add check to see if VM is running. We won't be able to some change settings if it is.

    # Set automatic shutdown action is Shutdown
    $vm | Set-HypervVmProperty -PropertyName "AutomaticStopAction" `
        -GetCurrentValueScriptBlock {$vm | Select-Object -ExpandProperty AutomaticStopAction} `
        -GetDesiredValueScriptBlock { [Microsoft.HyperV.PowerShell.StopAction]::ShutDown} `
        -SetValueScriptBlock {$vm | Set-VM -AutomaticStopAction ShutDown}

    # Verify disk is vhdx not vhd

    # Verify CPUs is more than default 1 CPU
    if ($vm.ProcessorCount -eq 1){
        if ($PSCmdlet.ShouldContinue("VM has only has 1 virtual processor assigned to it. Many modern OSes require more.  Increase number of virtual processors for VM? This will require stopping the VM, if it is running.", "Virtual Processor(s) for $($vm.VMName)", [ref] $YesToAll, [ref] $NoToAll )){
            $number_of_vCPUs = Read-Host "How many cores/virtual processors (max $($env:NUMBER_OF_PROCESSORS))?"
            $number_of_vCPUs = [math]::Min($number_of_vCPUs, $env:NUMBER_OF_PROCESSORS)
            $vm | Stop-VM -Force -WarningAction SilentlyContinue
            $vm | Set-VM -ProcessorCount $number_of_vCPUs
        }
    }

    # Verify Memory is more than default 512
    $assignedMemory = $vm | Get-VMMemory
    if ($assignedMemory.Startup -lt 6 * [math]::Pow(10,8)){
        if ($PSCmdlet.ShouldContinue("VM has only has $($assignedMemory.Startup) MB memory assigned to it assigned to it. Many modern OSes require more. Increase assigned memory to 2GB?`n`nWARNING: This will require stopping the VM, if it is running.", "Assigned Memory for $($vm.VMName)", [ref] $YesToAll, [ref] $NoToAll )){
            #$input = [int]$(Read-Host "How much memory?")
            $vm | Stop-VM -Force -WarningAction SilentlyContinue
            $vm | Set-VMMemory -Startup 2GB
        }
    }


    #TODO: Check variable memory

}