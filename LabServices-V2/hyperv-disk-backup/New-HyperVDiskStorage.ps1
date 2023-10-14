[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)][String]$ResourceGroupName,
    [Parameter(Mandatory = $true)][String]$StorageAccountName,
    [Parameter(Mandatory = $false)][String]$Location,
    [Parameter(Mandatory = $false)][String[]]$InstructorEmails,
    [Parameter(Mandatory = $false)][String[]]$StudentEmails,
    [Parameter(Mandatory = $false)][String]$TermCode
    )

$ErrorActionPreference = 'Stop' 

Import-Module $(Join-Path $PSScriptRoot "HyperVBackup.psm1") -Force
$VerboseOutputInModuleFunctions = $PSBoundParameters.ContainsKey('Verbose')

$InstructorRbacRoleName = "Storage Blob Data Reader"
$StudentRbacRoleName = "Storage Blob Data Contributor" 

function Update-BlobRole(
    [Parameter(Mandatory=$true)][guid] $UserAdObjectId, 
    [ValidateSet("Storage Blob Data Contributor", "Storage Blob Data Reader")][Parameter(Mandatory=$true)][string] $RoleName, 
    [Parameter(Mandatory=$true)][string] $scope){

    $roleAssignment =  Get-AzRoleAssignment -ObjectId $UserAdObjectId -RoleDefinitionName $RoleName -Scope $scope -ErrorAction SilentlyContinue   
    if (-not  $roleAssignment)
    {
        $roleAssignment = New-AzRoleAssignment -ObjectId $UserAdObjectId -RoleDefinitionName $RoleName -Scope $scope               
    }
    Write-Verbose "Role assignment $($roleAssignment.RoleAssignmentId) for $($roleAssignment.SignInName)."
}

$StorageAccountName = [Regex]::Replace($StorageAccountName, "[^a-zA-Z0-9]", "").ToLower()
Write-Verbose "Storage Account Name: $StorageAccountName"

#Determine resource group name
if ([String]::IsNullOrWhiteSpace($ResourceGroupName)) {
    $ResourceGroupName = $StorageAccountName + "RG"
    Write-Verbose "No resource group specified.  Using default resource group name: $ResourceGroupName"
}
Write-Verbose "Resource Group Name: $ResourceGroupName"

#Get current subscription
if (Get-AzContext) {
    $SubscriptionId = Get-AzContext | Select-Object -ExpandProperty Subscription | Select-Object -ExpandProperty Id
}
else {
    Write-Error "Must login to Azure first.  Use Login-AzAccount cmdlet."
}
Write-Verbose "Subscription Id: $SubscriptionId"

#Verify resource group exists
if(-not $(Get-AzResourceGroup -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue)){
    if (-not [String]::IsNullOrWhiteSpace($Location)){
        New-AzResourceGroup -ResourceGroupName $ResourceGroupName -Location $Location
    }else{
        Write-Error "Couldn't create resource group '$ResourceGroupName'.  Must specify 'Location' paramter."
    }
}

#Create storage account
$storageContext = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName -ErrorAction SilentlyContinue
if ($storageContext){
    Write-Verbose "Using existing storage account with the name '$StorageAccountName'."

}else{
    Write-Host "Creating storage account '$StorageAccountName' in $ResourceGroupName"
    if (-not [String]::IsNullOrWhiteSpace($Location)){
        $storageContext = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -AccountName $StorageAccountName -Location $Location -SkuName Standard_GRS
        Write-Verbose "Created storage account with the name '$StorageAccountName' in $ResourceGroupName."
    }else{
        Write-Error "Could not create storage account $StorageAccountName in $ResourceGroupName.  Missing required parameter Location"
    }
}

# Change the storage account tier to cool
#   See https://learn.microsoft.com/azure/storage/blobs/storage-blob-storage-tiers
#   for more information about storage tiers.
Write-Host "Enabling access tier to Cool for storage account '$StorageAccountName' in $ResourceGroupName"
Set-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -AccessTier Cool -Force | Out-Null

# Enable versioning.
Write-Host "Enabling version for storage account '$StorageAccountName' in $ResourceGroupName"
Update-AzStorageBlobServiceProperty -ResourceGroupName $ResourceGroupName   -StorageAccountName $StorageAccountName  -IsVersioningEnabled $true | Out-Null

#Set read permissions on acct for instructors
foreach ($email in $InstructorEmails){
    $adObjectId = Get-AzADUserIdByEmail -userEmail $email -Verbose:$VerboseOutputInModuleFunctions
    Update-BlobRole -UserAdObject $adObjectId -RoleName $InstructorRbacRoleName -Scope $storageContext.Id -ErrorAction Continue
    Write-Host "$email given $InstructorRbacRoleName on $($storageContext.Name) storage account."
}
$storageContext | Set-AzCurrentStorageAccount | Out-Null

#Create container for each student
#Set r/w permissions for each student on their container
foreach ($email in $StudentEmails){
    Write-Host "Verifying container status for $($email) (Term: '$($TermCode)')."

    $adObjectId = Get-AzADUserIdByEmail -userEmail $email -Verbose:$VerboseOutputInModuleFunctions

    $studentContainerName = Get-ExpectedContainerName -Email $email -TermCode $TermCode -Verbose:$VerboseOutputInModuleFunctions
    $storageContainer = Get-AzStorageContainer  -Name $studentContainerName -ErrorAction SilentlyContinue 
    if (-not $storageContainer){
        $storageContainer = New-AzStorageContainer -Name $studentContainerName -Permission Off
        Write-Host "Created container $($storageContainer.Name) for $email."
    }else{
        Write-Host "Found container $($storageContainer.Name) for $email"
    }
    
    Write-Host "Updating permissions for student's container."
    Update-BlobRole -UserAdObject $adObjectId -RoleName $StudentRbacRoleName -Scope "$($storageContext.id)/blobServices/default/containers/$studentContainerName" -ErrorAction Continue | Out-Null
    Write-Host "Using container $($storageContainer.Name) for $email.  User has '$StudentRbacRoleName' access on the container only."
}