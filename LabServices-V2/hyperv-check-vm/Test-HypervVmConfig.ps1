  
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


function Stop-HypervVm {
    param (
        [Parameter(ValueFromPipeline)]
        [Microsoft.HyperV.PowerShell.VirtualMachine]
        $vm
    )

    if (($vm | Select-Object -ExpandProperty State) -eq [Microsoft.HyperV.PowerShell.VMState]::Off) {
        return
    }

    $vm | Stop-VM -Force -WarningAction Continue
}

function Set-HypervVmProperty {
    param (
        [Parameter(ValueFromPipeline)]
        [Microsoft.HyperV.PowerShell.VirtualMachine]
        $vm,
        [Parameter(Mandatory = $true)][scriptblock]$GetCurrentValueScriptBlock,
        [Parameter(Mandatory = $false)][scriptblock]$GetDesiredValueScriptBlock,
        [Parameter(Mandatory = $false)][scriptblock]$IsCurrentValueAcceptableScriptBlock,
        [Parameter(Mandatory = $true)][scriptblock]$SetValueScriptBlock,
        [string]$PropertyName,
        [bool]$RequiresVmStopped
    )

#todo: make sure desired value of iscurrentvalue acceptable is specified

    $isAcceptableValue = $false
    if (-not $IsCurrentValueAcceptableScriptBlock) {
        $isAcceptableValue = $currentValue -eq $desiredValue
    }
    else {
        $isAcceptableValue = & $IsCurrentValueAcceptableScriptBlock
    }



    if (-not $isAcceptableValue) {
         
        if ($RequiresVmStopped -and $(($vm | Select-Object -ExpandProperty State) -ne [Microsoft.HyperV.PowerShell.VMState]::Off)) {
            if (-not $PSCmdlet.ShouldContinue("Stop VM?  It is required to change $($PropertyName). ", "Stop $($vm.VMName)", [ref] $YesToAll, [ref] $NoToAll )) {
                Write-Host "Did not change $($PropertyName) from $($currentValue) to $($desiredValue).  VM must be stopped first."
                return
            }

            $vm | Stop-VM -Force -WarningAction Continue          
        }

        $currentValue = & $GetCurrentValueScriptBlock
        #todo: handle case when desired value is asked in set value script block
        $desiredValue = & $GetDesiredValueScriptBlock

        $prompt = "Change value of?"
        if ($desiredValue){
            "Change $($PropertyName) from '$($currentValue)' to '$($desiredValue)' ", "$($vm.VMName).$($PropertyName)"
        }

        if ($PSCmdlet.ShouldContinue($prompt, [ref] $YesToAll, [ref] $NoToAll )) {     
            & $SetValueScriptBlock
        }
    }
}

$vms = Get-VM

# Script that checks recommendations for each Hyper-V VM as described by https://learn.microsoft.com/azure/lab-services/concept-nested-virtualization-template-vm#recommendations

# Warn if any VMs are in saved state
$savedStateVMs = @($vms | Where-Object { $_.State -eq "Saved" })
if ($savedStateVMs) {
    Write-Warning "Found VM(s) that are in a saved state. VM may fail to start if processor of the Azure VM changes.`n`t$($savedStateVMs -join '`n`t')"
}

#For each VM
foreach ($vm in $vms) {
    Write-Host "*** Testing $($vm.VMName) ***"

    # TODO: Add check to see if VM is running. We won't be able to some change settings if it is.

    # Set automatic shutdown action is Shutdown
    $vm | Set-HypervVmProperty -PropertyName "AutomaticStopAction" `
        -GetCurrentValueScriptBlock { $vm | Select-Object -ExpandProperty AutomaticStopAction } `
        -GetDesiredValueScriptBlock { [Microsoft.HyperV.PowerShell.StopAction]::ShutDown } `
        -SetValueScriptBlock { $vm | Set-VM -AutomaticStopAction ShutDown }

    # Verify disk is vhdx not vhd

    # Verify CPUs is more than default 1 CPU
    $vm | Set-HypervVmProperty -PropertyName "ProcessorCount" `
        -GetCurrentValueScriptBlock { $vm | Select-Object -ExpandProperty ProcessorCount } `
        -GetDesiredValueScriptBlock { $number_of_vCPUs } `
        -IsCurrentValueAcceptableScriptBlock { $vm.ProcessorCount -gt 1 } `
        -SetValueScriptBlock { 
        if (!($number_of_vCPUs = `
                    Read-Host "VM $( to $($vm.VMName)) has only has 1 virtual processor assigned to it. Many modern OSes require more. How many cores/virtual processors should be assigned? [max $($env:NUMBER_OF_PROCESSORS), default 1]")) {
            $number_of_vCPUs = $default 
        }
        $number_of_vCPUs = [math]::Max(1, $number_of_vCPUs)
        $number_of_vCPUs = [math]::Min($number_of_vCPUs, $env:NUMBER_OF_PROCESSORS)
        $vm | Set-VM -ProcessorCount $number_of_vCPUs } `
        -RequiresVmStopped $true
   

    # Verify Memory is more than default 512
    $assignedMemory = $vm | Get-VMMemory
    $vm | Set-HypervVmProperty -PropertyName "ProcessorCount" `
        -GetCurrentValueScriptBlock { $assignedMemory | Select-Object -ExpandProperty Startup } `
        -IsCurrentValueAcceptableScriptBlock { $assignedMemory.Startup -ge 6 * [math]::Pow(10, 8) } `
        -SetValueScriptBlock { $vm | Set-VMMemory -Startup 2GB } `
        -RequiresVmStopped $true

    #TODO: Check variable memory

}