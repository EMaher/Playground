<#
The MIT License (MIT)
Copyright (c) Microsoft Corporation  
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.  
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 
.SYNOPSIS
This script shuts down student's current lab vm.
.PARAMETER labName
Name of the lab for which the virtual machine needs to be shutdown.  This parameter is only required in when a school uses multiple subscriptions in Azure.  See notes for further details.
.NOTES 
This script is intended to be run on a student virtual machine.

The script attempts to determine which virtual machine the student is logged into ask Lab Services to shut it down.  It looks for all running machines for a student that have the same private IP address as the current virtual machine.  In the rare occasion that a school uses different subscriptions for different labs, this may not be enough information to find the correct virtual machine.  If this is a possibility for a student, specify the lab name in the labName parameter to help the script to determine the correct virtual machine to be found.
#>

[CmdletBinding()]
param(
    [Parameter(HelpMessage="Name of the lab for which the virtual machine needs to be shutdown. ")]
    [string] $labName = $null
)

#get local ip addresses. 
$ipAddresses = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | Select-Object -ExpandProperty Addresses | Select-Object -ExpandProperty IpAddressToString 
Write-Verbose "Ip address(es) for the current machines: $($ipAddresses -join ', ')"

$currentAzureContext = Get-AzContext
if ($null -eq $currentAzureContext){
    Write-Error "Must run 'Enable-AzContextAutosave' and 'Login-AzAccount' before running this script."
}

#get bearer token 
$profileClient = New-Object Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient([Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile)
$token = $profileClient.AcquireAccessToken($currentAzureContext.Tenant.TenantId).AccessToken
if ($null -eq $token)
{
    Write-Error "Unable to get authorization information."
}
$headers = @{
    'Authorization' = "Bearer $token"
}

#get all running lab vms for a student
Write-Verbose "Finding running lab virtual machines"
$uri = "https://management.azure.com/providers/Microsoft.LabServices/users/NoUsername/listAllEnvironments?api-version=2019-01-01-preview"
$output = Invoke-RestMethod -Uri $uri -Method 'Post' -Headers $headers
$studentLabVms = $output | Select-Object -expand 'environments' | Where-Object lastKnownPowerState -eq 'Running'
Write-Verbose "Found running lab virtual machines for the following classes: $($($studentLabVms | Select-Object -ExpandProperty name) -join ', ')"

#further filter out lab vms, based on private IP address
Write-Verbose "Filtering lab virtual machines based on IP address"
$studentLabVms = $studentLabVms | Where-Object { $ipAddresses.Contains($_.virtualMachineDetails.privateIpAddress) }
Write-Verbose "Found lab virtual machines that also match local ip address for classes: $($($studentLabVms | Select-Object -ExpandProperty name) -join ', ')"

#further filter on class name, if specified
if (-not [string]::IsNullOrEmpty($labName)){
    Write-Verbose "Filtering lab virtual machines based on lab name '$labName'"
    $studentLabVms = $studentLabVms | Where-Object name -eq $labName
    Write-Verbose "Found lab virtual machines that also lab name '$labName': $($($studentLabVms | Select-Object -ExpandProperty name) -join ', ')"
}

#stop virtual machine
if (0 -eq $studentLabVms.Count){
    Write-Host "Unable to find any running virtual machines that need to be stopped." -ForegroundColor 'Yellow'
}elseif (1 -eq $studentLabVms.Count){
      
    $uri = "https://management.azure.com/providers/Microsoft.LabServices/users/NoUsername/stopEnvironment?api-version=2019-01-01-preview"
    $body = @{
        'environmentId' = $studentLabVms[0].id
    } | ConvertTo-Json

    Write-Host "Stopping virtual machine for '$($studentLabVms[0].name)' lab."
    Invoke-RestMethod -Method 'Post' -Uri $uri  -Body $body -Headers $headers -ContentType 'application/json'
}else{
    Write-Error "Unable to find which lab VM needs to be stopped. Please specify labName parameter.  Virtual machines found for the following labs: $($($studentLabVms | Select-Object -ExpandProperty name) -join ', ')"
}