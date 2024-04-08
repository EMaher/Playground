# Lets stop the script for any errors
$ErrorActionPreference = "Stop"

# Path to Az.LabServices.psm1 for lab accounts:
# https://github.com/Azure/azure-devtestlab/blob/master/samples/ClassroomLabs/Modules/Library/Az.LabServices.psm1

# ************************************************
# ************ FIELDS TO UPDATE ******************
# ************************************************

# List of Lab IDs where we want to start the VMs
$labs = @(
    '/subscriptions/{subscription-id}/resourcegroups/{resource-group-name}/providers/microsoft.labservices/labaccounts/{lab-account-name}/labs/{lab-name}'
     )

# ************************************************


# Make sure we have the modules already imported via the automation account
if (-not (Get-Command -Name "Get-AzLabAccount" -ErrorAction SilentlyContinue)) {
    Write-Error "Unable to find the Az.LabServices.psm1 module, please add to the Azure Automation account"
}

# Log Into Azure with Managed Identity
try
{
    # Ensures you inherit azcontext in your Azure Automation runbook
    Enable-AzContextAutosave -Scope Process
    Write-Output "Logging in to Azure..."
    Connect-AzAccount -Identity
}
catch {
    Write-Error -Message $_.Exception
    throw $_.Exception
}

# Copy of some library functions that we need
function GetHeaderWithAuthToken {

    Write-Verbose "Creating header with Auth Token..."
    $authToken = Get-AzAccessToken

    $header = @{
        'Content-Type'  = 'application/json'
        "Authorization" = "Bearer " + $authToken.Token
        "Accept"        = "application/json;odata=fullmetadata"
    }

    return $header
}

$ApiVersion = 'api-version=2019-01-01-preview'

function ConvertToUri($resource) {
    "https://management.azure.com" + $resource.Id
}

function InvokeRest($Uri, $Method, $Body, $params) {
    #Variables for retry logic
    $maxCallCount = 3 #Max number of calls to attempt
    $retryIntervalInSeconds = 5 
    $shouldRetry = $false
    $currentCallCount = 0

    $authHeaders = GetHeaderWithAuthToken

    $fullUri = $Uri + '?' + $ApiVersion
    
    if ($params) { $fullUri += '&' + $params }

    if ($body) { Write-Verbose $body }

    do{
        try{
            $currentCallCount += 1
            $shouldRetry = $false
            $result = Invoke-WebRequest -Uri $FullUri -Method $Method -Headers $authHeaders -Body $Body -UseBasicParsing 
        }catch{
            #if we have reach max number of calls, rethrow error no matter what it is
            if($currentCallCount -eq $maxCallCount){
                throw
            }

            #retry if Rest method is GET
            if ($Method -eq 'Get'){
                $shouldRetry = $true
            }

            $StatusCode = $null
            if ($_.PSObject.Properties.Item('Exception') -and `
                $_.Exception.PSObject.Properties.Item('Response') -and `
                $_.Exception.Response.PSObject.Properties.Item('StatusCode') -and `
                $_.Exception.Response.StatusCode.PSObject.Properties.Item('value__')){
                $StatusCode = $_.Exception.Response.StatusCode.value__
            }
            Write-Verbose "Response status code for '$Uri' is '$StatusCode'"
            switch($StatusCode){
                401 { $shouldRetry = $false } #Don't retry on Unauthorized error, regardless of what kind of call
                404 { $shouldRetry = $false } #Don't retry on NotFound error, even if it is a GET call
                503 { $shouldRetry = $true} #Always safe to retry on ServerUnavailable
            }

            if ($shouldRetry){
                 #Sleep before retrying call
                Write-Verbose "Retrying after interval of $retryIntervalInSeconds seconds. Status code for previous attempt: $StatusCode"
                Start-Sleep -Seconds $retryIntervalInSeconds
            }else{
                #propogate error if not retrying
                throw
            }
        }
    }while($shouldRetry -and ($currentCallCount -lt $maxCallCount))
    $resObj = $result.Content | ConvertFrom-Json
    
    # Happens with Post commands ...
    if (-not $resObj) { return $resObj }

    Write-Verbose "ResObj: $resObj"

    # Need to make it unique because the rest call returns duplicate ones (bug)
    if (Get-Member -inputobject $resObj -name "Value" -Membertype Properties) {
        return $resObj.Value | Sort-Object -Property id -Unique | Enrich
    }
    else {
        return $resObj | Sort-Object -Property id -Unique | Enrich
    }
}

function Start-AzLabVmNoWait {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Vm to start.", ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        $Vm

    )

    foreach ($v in $vm) {
        $baseUri = (ConvertToUri -resource $v)
        $uri = $baseUri + '/start'
        InvokeRest -Uri $uri -Method 'Post' | Out-Null
    }
}

Write-Output "Logged into Azure - proceeding to check for labs!"

foreach ($labId in $labs) {
    $labArray = $labId -split '/'
    $resourceGroupName = $labArray[4]
    $labAccountName = $labArray[8]
    $labName = $labArray[10]

    Write-Output "Checking for Lab '$labName' in Resource Group '$resourceGroupName'"

    if (-not $resourceGroupName -or -not $labAccountName -or -not $labName) {
        Write-Error "Lab resource ID not formatted correctly: '$lab'"
    }

    $labAccount = Get-AzLabAccount -ResourceGroupName $resourceGroupName -LabAccountName $labAccountName
    if (-not $labAccount) {
        Write-Error "Lab Account doesn't exist, can't continue: '$labAccountName'"
    }

    $lab = Get-AzLab -LabAccount $labAccount -LabName $labName
    if (-not $lab) {
        Write-Error "Lab doesn't exist, can't continue: '$labName'"
    }

    # We got to the lab, now we need to send start requests for all the VMs
    $vms = $lab | Get-AzLabVm

    if (-not $vms -or ($vms | Measure-Object).Count -eq 0) {
        Write-Output "No student VMs in lab '$labName' to start..."
    }
    else {
        $vms | ForEach-Object {
            if ($_.Status -ieq "Stopped") {
            
            Write-Output "    sending start request to Lab '$($lab.name)', VM '$($_.name)'"
            try
            {
                $_ | Start-AzLabVmNoWait
            }
            catch {
                # Ignoring errors
            }
            }
            else {
                Write-Output "    lab '$($lab.name)', VM '$($_.name)' state is '$($_.Status)', skipping..."
            }
        }
    }
}

Write-Output "Completed sending 'start' operations to VMs!"

