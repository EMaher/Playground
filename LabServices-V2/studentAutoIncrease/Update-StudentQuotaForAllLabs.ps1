Param
(
    [Parameter (Mandatory = $true, HelpMessage = "Email address of student.")]
    [string] $UserEmail 
)

<#
    .DESCRIPTION
        A runbook that update's a student's quota

    .NOTES
        1. Create Automation Account.  Give system-assigned user identity 'Lab Services Contributor' access to all lab resources.
        2. Add the 'Az.Accounts', 'Az', and 'Az.LabServices' PowerShell modules for 7.2 runtime version.
        3. Create Runbook (with identity) for 7.2 runtime version.
        4. Add webhook so runbook can be called on demand.
#>

# @'
# IMPORTANT! Runbook will fail if the system-assigned identity of the Azure Automation Account isn't given sufficient privileges. (See comments for more info.)
# It should have 'Lab Serivces Contributor' or 'Contributor' access to 'Microsoft.LabServices/labs/*' resources. 
# For more information, see https://learn.microsoft.com/azure/automation/enable-managed-identity-for-automation#assign-role-to-a-system-assigned-managed-identity.
# '@

#Variables for quota updates
$maxHoursTimespan = [System.Timespan]::FromHours(50) # max including initial
$addHoursTimespan = [System.TimeSpan]::FromHours(10)
$preApprovalMaxAllowedHours = 5
$SubscriptionsToCheck = @("11111111-1111-1111-1111-111111111111", "11111111-1111-1111-1111-111111111111")

"Student will be given a maximum of  $($maxHoursTimespan.TotalHours) additional quota hours.  (Max hours for user doesn't include the number of quota hours set for the lab.)"
"Student will be given $($addHoursTimespan.TotalHours) additional quota hours for each lab where the have less than $preApprovalMaxAllowedHours hours left."

# Ensures you inherit azcontext in your Azure Automation runbook
Enable-AzContextAutosave -Scope Process

#Log in using system-assigned identity
"Logging in to Azure..."
try {
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

"Available Contexts:"
$(Get-AzContext -ListAvailable | Select-Object -ExpandProperty Name)

foreach ($subcriptionId in $SubscriptionsToCheck) {
    
    "********************************************************************************************"
    "Starting search for labs subscription id $subcriptionId."
    "********************************************************************************************"
    $subscriptionName = Get-AzContext -ListAvailable | Where-Object { $_.Name -match $subcriptionId } | Select-Object -ExpandProperty Name -First 1
    "For subscription $subcriptionId, name is: $subscriptionName"
    "Selecting context for $subcriptionId."
    Select-AzContext -Name $subscriptionName -Scope Process
    "Current context: $(Get-AzContext | Select-Object -ExpandProperty Name)"

    #Get user objects for each lab in subscription
    "Finding labs in subscription $subcriptionId."
    $labs =  Get-AzLabServicesLab
    "Found $($labs.count) labs in subscription."  
    if ($labs.Count -gt 0){
        "Labs found in subscription $subcriptionId are $( ($labs | Select-Object -ExpandProperty Name ) -join ", " )."

        "Finding labs to which user has been assigned."
        $infoList = @()
        foreach ($lab in $labs) {
            $tempUser = $lab | Get-AzLabServicesUser | where-object { $_.Email -eq $UserEmail}
            if ($tempUser) {
                $infoList += @{User = $tempUser; Lab = $lab }
            }
        }

        "Found $UserEmail in $($infoList.count) labs."
        if ($infoList.Count -gt 0) {
            "Current Additional Quota Usage for $($UserEmail): $( ($infoList | ForEach-Object { "$($_.Lab.Name) has quota of $($_.User.AdditionalUsageQuota)." }) -join " ") "
            
            "Updating quota for $UserEmail."
            foreach ($infoObj in $infoList) {
                $totalUsageTimespan = $infoObj.User.TotalUsage
                "Total quota used by $UserEmail in lab $($infoObj.Lab.Name) is $($totalUsageTimespan.TotalHours) hours."
 
                if (($null -ne $infoObj.Lab.VirtualMachineProfileUsageQuota ) -and ($infoObj.Lab.VirtualMachineProfileUsageQuota -ne ""))
                {
                    $labQuotaTimespan = $infoObj.Lab.VirtualMachineProfileUsageQuota
                } else {
                    $labQuotaTimespan = $(New-Timespan)
                }

                if (($null -ne $infoObj.User.AdditionalUsageQuota ) -and ($infoObj.User.AdditionalUsageQuota -ne ""))
                {
                    $userQuotaTimespan = $infoObj.User.AdditionalUsageQuota
                } else {
                    $userQuotaTimespan = $(New-Timespan)
                }
                $totalQuotaTimespan = $labQuotaTimespan.Add($userQuotaTimespan)
                "Total quota assigned to $UserEmail in lab $($infoObj.Lab.Name) is $($totalQuotaTimespan.TotalHours) hours."

                if ($totalQuotaTimespan.Subtract($totalUsageTimespan).TotalHours -le $preApprovalMaxAllowedHours) {
                    $newTimeSpan = $userQuotaTimespan.Add($addHoursTimespan)
                    if ([System.Timespan]::Compare($maxHoursTimespan, $newTimeSpan) -gt 0) { 
                        #Update Quota
                        "Setting quota for $UserEmail in $($infoObj.Lab.Name) to $($newTimeSpan.TotalHours) hours."   
                        Update-AzLabServicesUser -ResourceId $infoObj.User.Id -AdditionalUsageQuota $newTimeSpan
                    }  else { 
                        "NOT updating quota for $UserEmail in $($infoObj.Lab.Name) to $($newTimeSpan.TotalHours) hours. They have reach maximum allowed quota of $($maxHoursTimespan.TotalHours) hours."                    
                    }  
                }else{
                    "Not updating quota for $UserEmail in lab $($infoObj.Lab.Name). $UserEmail still has $($totalQuotaTimespan.Subtract($totalUsageTimespan).TotalHours) hours left.  Request will be approved when only $preApprovalMaxAllowedHours hours are left."
                }
            }
        }
    }
}

"Quota update completed."