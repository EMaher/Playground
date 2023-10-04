 
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $false)][string]$StorageAccountName
)
$ErrorActionPreference = 'Stop' 

Import-Module ./HyperVBackup.psm1

#Verify files exists and isn't in use
Test-FileReady -FilePath $FilePath

$Settings = New-BackupSetting


#Get Storage account name
if (-not $StorageAccountName){
    if (-not $Settings.StorageAccountName){
        Write-Error "Must specify 'StorageAccountName' parameter or have settings.json that specifies StorageAccountName."
    }else{
        $StorageAccountName = $Settings.StorageAccountName
    }
}
Write-Verbose "StorageAccountName: '$StorageAccountName'"
#Note, can't verify storage account existence because student's only have access to their containers.

$azContext = Get-AzContext
$azSavedContextPath = Join-Path $PSScriptRoot "context.json"
if (-not $azContext){
    $azContext = Import-AzContext -Path $azSavedContextPath -ErrorAction SilentlyContinue
    if (-not $azContext){
        Connect-AzAccount
    }
}
if (-not $(Test-Path $azSavedContextPath)){
    Save-AzContext -Path $azSavedContextPath
}

#Set context to upload file
$storageContext = New-AzStorageContext -UseConnectedAccount -BlobEndpoint "https://$($StorageAccountName).blob.core.windows.net/"

#Verify container exists
$containerName = Get-ExpectedContainerName -Email $(Get-CurrentUserEmail) -TermCode $Settings.TermCode
Write-Verbose "ContainerName: '$($containerName)'"
$container =  Get-AzStorageContainer -Name $containerName -Context $storageContext -ErrorAction SilentlyContinue
if (-not $container){
     Write-Error "Couldn't find/access container '$($containerName)' in storage account '$($StorageAccountName)'"
}
 
#TODO: Change Get-BlobName to return tuples of FileNames and Target Names
#TODO: Add search directories to settings.

#Calculate blob name
$blobNames = @(Get-BlobName)
Write-Verbose "Destination blob name: $blobName"

foreach ($blobName in $blobNames){

    Write-Host "Uploading file $([System.IO.Path]::GetFileName($FilePath)) to $($StorageAccountName)/$($containerName)"
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    Set-AzStorageBlobContent -Container $containerName -File $FilePath -Blob $blobName -Context $storageContext -Force | Out-Null
    $timer.Stop()
    $blob = Get-AzStorageBlob -Container $containerName -Blob $blobName -Context $storageContext
    if ($blob){
        Write-Host "Success! '$blobName' backed up as '$blobname' (version  $($blob.VersionId))."
        Write-Verbose "Upload operation took $($timer.Elapsed.TotalMinutes) minutes."
    }else{
        Write-Warning "Unable to verify disk backed up."
    }

}

