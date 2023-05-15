[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $false)][string]$DestinationFileName
)

function Get-ExpectedContainerName([string] $classCode){
    #Alternatively, create container name based on the AAD ObjectId for the student
    $email = Get-AzContext | select -expand Account | select -expand Id
    return "$classCode-$($email.Replace('@', "-").Replace(".", "-"))".ToLower()
}

function Get-ConfigurationSettings() {
    $settingsFilePath = Join-Path $PSScriptRoot "settings.json"
    return Get-Content -Path $settingsFilePath | ConvertFrom-Json  
}

$Settings = Get-ConfigurationSettings
if (-not $Settings.ClassCode -or -not $Settings.StorageAccount){
    Write-Error "settings.json file must specify ClassCode and StorageAccount."
}

$ContainerName = Get-ExpectedContainerName -classCode $Settings.ClassCode
$StorageAccountName = $Settings.StorageAccount

$ClassCode = $Settings.ClassCode
if (-not $DestinationFileName)
{
    $DestinationFileName = [System.IO.Path]::GetFileName($FilePath)
}
Write-Verbose "Destination FileName $DestinationFileName"

#Set context to upload file
$storageContext = New-AzStorageContext -UseConnectedAccount -BlobEndpoint "https://$StorageAccountName.blob.core.windows.net/"
$blobName = "$ClassCode-$DestinationFileName"

Set-AzStorageBlobContent -Container $ContainerName -File $FilePath -Blob $blobName -Context $storageContext

Get-AzStorageBlob -Container $ContainerName -Blob $blobName -Context $storageContext
Write-Host "'$FilePath' saved as '$blobname' in backup."

