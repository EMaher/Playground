<#
The MIT License (MIT)
Copyright (c) Microsoft Corporation  
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.  
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 
.SYNOPSIS
This script prepares computer for class by aiding in the deletion of unneeded Microsoft Store applications.  Remaining Microsoft Store applications are updated.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)][switch]$Force,
    [Parameter(Mandatory = $false)][string]$ConfigFilePath
)
Set-StrictMode -Version Latest

# Script that checks recommendations for each Hyper-V VM as described by https://learn.microsoft.com/azure/lab-services/concept-nested-virtualization-template-vm#recommendations

$ErrorActionPreference = 'Stop' 

# Configure variables for ShouldContinue prompts
$YesToAll = $Force
$NoToAll = $false

# ##### CLASSES ####

class ConfigurationInfo {
    [VmConfiguration[]] $VMConfigurations
    ConfigurationInfo() {
        $this.VMConfigurations = @()
    }
}

class VmConfiguration {
    [string] $Name
    [VmConfigurationProperties] $Properties

}

class VmConfigurationProperties {
    [int]$ProcessorCount
    [VMConfigurationMemoryProperties] $Memory


}

class VMConfigurationMemoryProperties {
    [string] $Startup
    [bool] $DynamicMemoryEnabled
    [string] $Minimum
    [string] $Maximum
}


# ### FUNCTIONS ####

function Get-ConfigurationSettings {
    [CmdletBinding()]
    
    param(
        [string]$SettingsFilePath
    )
    $settings = $null
    if (Test-Path $SettingsFilePath) {
        $settings = return Get-Content -Path $SettingsFilePath -ErrorAction SilentlyContinue | ConvertFrom-Json 
    }
    return [ConfigurationInfo] $settings
}


function Get-DefaultConfigurationSettings {
    [CmdletBinding()]
    [OutputType('VmConfiguration')]
    param(
        [string]$SettingsFilePath
    )

    $defaultConfigString = @"
{
    "Name": "",
    "Properties": {
        "ProcessorCount": 2,
        "Memory": {
            "Startup": "2GB",
            "DynamicMemoryEnabled": true,
            "Minimum": "2GB",
            "Maximum": "4GB"
        }
    }
}
"@

    Write-Verbose "Default configuration: `n$($defaultConfigString)"

    return [VmConfiguration] $($defaultConfigString | ConvertFrom-Json)

}
function Get-RunningAsAdministrator {
    [CmdletBinding()]
    param()
    
    $isAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    Write-Verbose "Running with Administrator privileges (t/f): $isAdministrator"
    return $isAdministrator
}

function Set-HypervVmProperty {
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [Microsoft.HyperV.PowerShell.VirtualMachine]
        $vm,
        [scriptblock]$GetCurrentValueScriptBlock,
        [scriptblock]$GetDesiredValueScriptBlock,
        [Parameter(Mandatory = $true)][scriptblock]$IsCurrentValueAcceptableScriptBlock,
        [Parameter(Mandatory = $true)][scriptblock]$SetValueScriptBlock,
        [Parameter(Mandatory = $true)][string]$PropertyName,
        [bool]$RequiresVmStopped = $true
    )

    $isAcceptableValue = $false
    if (-not $IsCurrentValueAcceptableScriptBlock) {
        $currentValue = & $GetCurrentValueScriptBlock
        $desiredValue = & $GetDesiredValueScriptBlock
        $isAcceptableValue = $currentValue -eq $desiredValue
    }
    else {
        $isAcceptableValue = & $IsCurrentValueAcceptableScriptBlock
    }

    if (-not $isAcceptableValue) {
         
        #Stop VM
        if ($RequiresVmStopped -and $(($vm | Select-Object -ExpandProperty State) -ne [Microsoft.HyperV.PowerShell.VMState]::Off)) {
            if (-not $PSCmdlet.ShouldContinue("Stop VM?  It is required to change $($PropertyName). ", "Stop $($vm.VMName)", [ref] $YesToAll, [ref] $NoToAll )) {
                Write-Host "Did not change $($PropertyName).  VM must be stopped first."
                return
            }

            $vm | Stop-VM -Force -WarningAction Continue          
        }

        #Change value
        $prompt = ""
        if ($GetCurrentValueScriptBlock) {
            $prompt += " Current value is '$(& $GetCurrentValueScriptBlock)'."
        }
        if ($GetDesiredValueScriptBlock) {
            $prompt += " New value will be '$(& $GetDesiredValueScriptBlock)'."
        }

        if ($PSCmdlet.ShouldContinue($prompt, "Change value of $($PropertyName)?", [ref] $YesToAll, [ref] $NoToAll )) {     
            & $SetValueScriptBlock
        }
    }
}

<#
.SYNOPSIS
Returns true is current machine is a Windows Server machine and false otherwise.
#>
function Get-RunningServerOperatingSystem {
    [CmdletBinding()]
    param()

    return ($null -ne $(Get-Module -ListAvailable -Name 'servermanager') )
}


function Get-DhcpInstalled {
    if ($(Get-RunningServerOperatingSystem) -and $(Get-WindowsFeature -Name 'DHCP')) {
        return   $($(Get-WindowsFeature -Name 'DHCP') | Select-Object -ExpandProperty Installed)
    }
    else {
        return $false
    }
}

####### Main Execution ##################################################################

if ($ConfigFilePath) {
    $configs = Get-ConfigurationSettings -SettingsFilePath $ConfigFilePath
}
else {
    $configs = New-Object ConfigurationInfo
}

Write-Host "Verify running as administrator.`n"
if (-not (Get-RunningAsAdministrator)) { Write-Error "Please re-run this script as Administrator." }

# *** CHECK NORMAL USER SETTINGS ***
Write-Host "******************************"
Write-Host "* Checking User Permissions  *"
Write-Host "******************************"

# Try to find other users on the machines, if there is one, then ask if they should be added to the "Hyper-V Administrators" Group
$addedLocalUsers = @(Get-LocalUser | Where-Object { [int]$($_.SID -split '-' | Select-Object -Last 1) -ge '1000' })
if ($addedLocalUsers.Count -gt 0) {
    $hyperVAdminGroup = Get-LocalGroup | Where-Object { $_.SID -eq "S-1-5-32-578" }
    #$adminGroup =  Get-LocalGroup | Where-Object {$_.SID -eq "S-1-5-32-544" }

    foreach ($localUser in $addedLocalUsers) {
        $localUserName = $localUser | Select-Object -ExpandProperty Name
        $isAdmin = $null -ne $(Get-WmiObject win32_groupuser |  Where-Object { $_.groupcomponent -like '*"Administrators"' } | Where-Object { $_.PartComponent -like $($localUser | Select-Object -ExpandProperty Name) }) #work-around for powershell bug
        Write-Verbose "$($localUserName) part of Administrators group? $($isAdmin)"
        $isHypervAdmin = @(Get-LocalGroupMember -Group $hyperVAdminGroup | Select-Object -Expand Name) -contains "$($env:COMPUTERNAME)\$($localUser | Select-Object -ExpandProperty Name)"
        Write-Verbose "$($localUserName) part of Hyper-V Administrators group? $($isHypervAdmin)"

        if ($isAdmin -or $isHypervAdmin) {
            Write-Host "Verified user '$($localUserName)' has permissions to use Hyper-V."
        }
        else {
            if ($PSCmdlet.ShouldContinue("User '$($localUserName)' can not use Hyper-V.  Add user to Hyper-V Administrators Group?", "Add user to Hyper-V Administrators Group?", [ref] $YesToAll, [ref] $NoToAll )) {          
                Add-LocalGroupMember -Group $hyperVAdminGroup -Member $localUser
                Write-Host "$($localUserName) added to Hyper-V Administrators group."   
            }  
        }
    }
}

Write-Host "Permission check completed.`n"

if (Get-RunningServerOperatingSystem) {

    # *** CHECK VM CONFIGURATIONS  ***

    Write-Host "*************************************"
    Write-Host "*        Testing Network Settings   *"
    Write-Host "*************************************"

    if (Get-DhcpInstalled) {
        $warningText = 
        @"
Installing DHCP role on an Azure VM is not a supported scenario.
See https://learn.microsoft.com/azure/virtual-network/virtual-networks-faq#can-i-deploy-a-dhcp-server-in-a-vnet

It is recommended to unistall the DHCP role and modify network adapter settings for Hyper-V VMs for internet connectivity.
"@
            
    }
    Write-Warning $warningText

}
Write-Host "Network check completed.`n"

# *** CHECK VM CONFIGURATIONS  ***
$vms = @(Get-VM)

if ($vms.Count -gt 0) {

    Write-Host "******************************"
    Write-Host "*        Testing VMs         *"
    Write-Host "******************************"

    # Warn if any VMs are in saved state
    $savedStateVMs = @($vms | Where-Object { $_.State -eq "Saved" })
    if ($savedStateVMs) {
        Write-Warning "Found VM(s) that are in a saved state. VM may fail to start if processor of the Azure VM changes.`n`t$($savedStateVMs -join '`n`t')"
        if ($PSCmdlet.ShouldContinue("Found VM(s) that are in a saved state. VM may fail to start if processor of the Azure VM changes.`n`t$($savedStateVMs -join '`n`t')?", "Start and ShutDown Hyper-V VMs)?", [ref] $YesToAll, [ref] $NoToAll )) {
            foreach ($vm in $savedStateVMs) {
                $vm | Start-VM -WarningAction Continue
                $vm | Stop-VM -Force -WarningAction Continue
            }
        }
    }

    #For each VM
    foreach ($vm in $vms) {
        $vmName = $vm.VMName
        Write-Host "============================="
        Write-Host "`t$($vmName)"
        Write-Host "============================="

        #Config settings for VM
        $currentConfig = $configs.VMConfigurations | Where-Object { $_.Name -eq $vmName }
        if (-not $currentConfig) {
            $currentConfig = Get-DefaultConfigurationSettings
            $currentConfig.Name = $vmName
        }
        Write-Debug $currentConfig | Format-Custom
    

        Write-Verbose "Verifying: AutomaticStopAction==ShutDown"
        $vm | Set-HypervVmProperty -PropertyName "AutomaticStopAction" `
            -GetCurrentValueScriptBlock { $vm | Select-Object -ExpandProperty AutomaticStopAction } `
            -GetDesiredValueScriptBlock { [Microsoft.HyperV.PowerShell.StopAction]::ShutDown } `
            -IsCurrentValueAcceptableScriptBlock { $($vm | Select-Object -ExpandProperty AutomaticStopAction ) -eq [Microsoft.HyperV.PowerShell.StopAction]::ShutDown } `
            -SetValueScriptBlock { $vm | Set-VM -AutomaticStopAction ShutDown } `
            -RequiresVmStopped $true


        Write-Verbose "Verifying: ProcessorCount >= $($currentConfig.Properties.ProcessorCount)"
        $vm | Set-HypervVmProperty -PropertyName "ProcessorCount" `
            -GetCurrentValueScriptBlock { $vm | Select-Object -ExpandProperty ProcessorCount } `
            -GetDesiredValueScriptBlock { $currentConfig.Properties.ProcessorCount } `
            -IsCurrentValueAcceptableScriptBlock { $vm.ProcessorCount -ge $currentConfig.Properties.ProcessorCount } `
            -SetValueScriptBlock { 
            # if (!($number_of_vCPUs = `
            #             Read-Host "VM '$($vm.VMName)' has $($vm.ProcessorCount) virtual processor assigned to it.  [max $($env:NUMBER_OF_PROCESSORS), default $($currentConfig.Properties.ProcessorCount)]")) {
            #     $number_of_vCPUs = $currentConfig.Properties.ProcessorCount 
            # }
            $number_of_vCPUs = $currentConfig.Properties.ProcessorCount
            $number_of_vCPUs = [math]::Max(1, $number_of_vCPUs)
            $number_of_vCPUs = [math]::Min($number_of_vCPUs, $env:NUMBER_OF_PROCESSORS)
            $vm | Set-VM -ProcessorCount $number_of_vCPUs 
        } `
            -RequiresVmStopped $true
   

        $assignedMemory = $vm | Get-VMMemory
        $desiredStartupMemory = Invoke-Expression($currentConfig.Properties.Memory.Startup)
        Write-Verbose "Verifying: Memory.Startup > $($desiredStartupMemory)"
        $vm | Set-HypervVmProperty -PropertyName "Memory - Startup" `
            -GetCurrentValueScriptBlock { "$($($assignedMemory | Select-Object -ExpandProperty Startup) / 1GB) GB" } `
            -GetDesiredValueScriptBlock { "$($desiredStartupMemory / 1GB) GB" } `
            -IsCurrentValueAcceptableScriptBlock { $assignedMemory.Startup -ge $desiredStartupMemory } `
            -SetValueScriptBlock { $vm | Set-VMMemory -Startup  $desiredStartupMemory } `
            -RequiresVmStopped $true

        Write-Verbose "Verifying: Memory.DynamicMemoryEnabled == $($currentConfig.Properties.Memory.DynamicMemoryEnabled)"
        $vm | Set-HypervVmProperty -PropertyName "Memory - Dynamic Memory Enabled" `
            -GetCurrentValueScriptBlock { $assignedMemory | Select-Object -ExpandProperty DynamicMemoryEnabled } `
            -GetDesiredValueScriptBlock { $true } `
            -IsCurrentValueAcceptableScriptBlock { $assignedMemory.DynamicMemoryEnabled -eq $($($currentConfig.Properties.Memory.DynamicMemoryEnabled)) } `
            -SetValueScriptBlock { $vm | Set-VMMemory -DynamicMemoryEnabled $($($currentConfig.Properties.Memory.DynamicMemoryEnabled)) } `
            -RequiresVmStopped $true

        if ($assignedMemory | Select-Object -ExpandProperty DynamicMemoryEnabled) {
            $desiredMinimumMemory = Invoke-Expression($currentConfig.Properties.Memory.Minimum)
            Write-Verbose "Verifying: Memory.Minimum >= $desiredMinimumMemory"
            $vm | Set-HypervVmProperty -PropertyName "Memory - Minimum" `
                -GetCurrentValueScriptBlock { "$($($assignedMemory | Select-Object -ExpandProperty Minimum) / 1GB) GB" } `
                -GetDesiredValueScriptBlock { "$($desiredMinimumMemory / 1GB) GB" } `
                -IsCurrentValueAcceptableScriptBlock { $($assignedMemory | Select-Object -ExpandProperty Minimum ) -ge $desiredMinimumMemory } `
                -SetValueScriptBlock { $vm | Set-VMMemory -Minimum $desiredMinimumMemory } `
                -RequiresVmStopped $true 

            $desiredMaximumMemory = Invoke-Expression($currentConfig.Properties.Memory.Maximum)
            Write-Verbose "Verifying: Memory.Maximum >= $desiredMaximumMemory"
            $vm | Set-HypervVmProperty -PropertyName "Memory - Maximum" `
                -GetCurrentValueScriptBlock { $assignedMemory | Select-Object -ExpandProperty Maximum } `
                -GetDesiredValueScriptBlock { "$($desiredMaximumMemory / 1GB) GB" } `
                -IsCurrentValueAcceptableScriptBlock { $($assignedMemory | Select-Object -ExpandProperty Maximum ) -ge $desiredMaximumMemory } `
                -SetValueScriptBlock { $vm | Set-VMMemory -Maximum $desiredMaximumMemory } `
                -RequiresVmStopped $true 
        }

        # Verify disk is vhdx not vhd

        $hardDriveDisks = @($vm | Get-VMHardDiskDrive)
        foreach ($hardDriveDisk in $hardDriveDisks) {
            $diskPath = $hardDriveDisk | Select-Object -ExpandProperty Path
            $diskName = [System.IO.Path]::GetFileNameWithoutExtension($diskPath)
            Write-Verbose "Verifying: HardDriveDisks.$diskName.VMType == Dynamic"

            $vm | Set-HypervVmProperty -PropertyName "Disk '$diskName' - VhdType" `
                -GetCurrentValueScriptBlock { Get-VHD $diskPath | Select-Object -ExpandProperty VhdFormat } `
                -GetDesiredValueScriptBlock { "VHDX" } `
                -IsCurrentValueAcceptableScriptBlock { $(Get-VHD $diskPath | Select-Object -ExpandProperty VhdFormat) -eq "VHDX" } `
                -SetValueScriptBlock { 
                $newDiskPath = Join-Path $([System.IO.Path]::GetDirectoryName($diskPath)) "$($diskName).vhdx"
                if (Test-Path $newDiskPath) {
                    Write-Error "Unable to convert '$($diskPath)' to '$($newDiskPath). '$($newDiskPath) exists." -ErrorAction Continue
                }
                else {
                    $controllerLocation = $hardDriveDisk | Select-Object -ExpandProperty ControllerLocation
                    $controllerNumber = $hardDriveDisk | Select-Object -ExpandProperty ControllerNumber
                    $controllerType = $hardDriveDisk | Select-Object -ExpandProperty ControllerType
                    

                    $hardDriveDisk | Remove-VMHardDiskDrive
                    Convert-VHD -Path $diskPath -DestinationPath $newDiskPath -VHDType Dynamic 

                    Add-VMHardDiskDrive -VMName $vm.VMName -Path $newDiskPath -ControllerLocation $controllerLocation -ControllerType $controllerType -ControllerNumber $controllerNumber                    
                }

            } `
                -RequiresVmStopped $true 
        }

        Write-Host "Testing Hyper-V VMs completed.`n"
    }


    Write-Host "******************************"
    Write-Host "*           RESULTS          *"
    Write-Host "******************************"

    # List current status
    foreach ($vm in $vms) {
        Write-Host "============================="
        Write-Host "`t$($vm.VMName)"
        Write-Host "============================="
        Write-Host "`tState: $($vm | Select-Object -ExpandProperty State)"
        Write-Host "`tAutomaticStopAction: $($vm | Select-Object -ExpandProperty AutomaticStopAction)"
        Write-Host "`tvCPU(s): $($vm | Select-Object -ExpandProperty ProcessorCount)"
        Write-Host "`tMemory - Startup: $($vm | Get-VMMemory | Select-Object -ExpandProperty Startup)"
        Write-Host "`tMemory - Dynamic Memory Enabled: $($vm | Get-VMMemory | Select-Object -ExpandProperty DynamicMemoryEnabled)"
        Write-Host "`tMemory - Minimum: $($vm | Get-VMMemory | Select-Object -ExpandProperty Minimum)"
        Write-Host "`tMemory - Maximum: $($vm | Get-VMMemory | Select-Object -ExpandProperty Maximum)"
        $hardDriveDisks = @($vm | Get-VMHardDiskDrive)
        foreach ($hardDriveDisk in $hardDriveDisks) {
            $diskPath = $hardDriveDisk | Select-Object -ExpandProperty Path
            Write-Host "`tDisk - $([System.IO.Path]::GetFileNameWithoutExtension($diskPath)): $(Get-VHD $diskPath | Select-Object -ExpandProperty VhdFormat)"
        }

    }
    Write-Host ""

    Write-Host "******************************"
    if ($PSCmdlet.ShouldContinue("Restart all Hyper-V VMs to ensure all updated settings are in effect?", "Restart Hyper-V VMs?", [ref] $YesToAll, [ref] $NoToAll )) {
        foreach ($vm in $vms) {
            $vm | Stop-VM -Force -WarningAction SilentlyContinue
            $vm | Start-VM -WarningAction Continue
            Write-Verbose "Restarted $($vm.VMName)."
        }
    }
} 
