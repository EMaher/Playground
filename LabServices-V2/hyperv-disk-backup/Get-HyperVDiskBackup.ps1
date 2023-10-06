[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)][string]$StorageAccountName,
    [switch]$IncludeVersion
)
$ErrorActionPreference = 'Stop' 

Import-Module $(Join-Path $PSScriptRoot "HyperVBackup.psm1")

$Settings = New-BackupSetting

#Get Storage account name
# Note, can't verify storage account existence because student's only have access to their containers.
if (-not $StorageAccountName){
    if (-not $Settings.StorageAccountName){
        Write-Error "Must specify 'StorageAccountName' parameter or have settings.json that specifies StorageAccountName."
    }else{
        $StorageAccountName = $Settings.StorageAccountName
    }
}
Write-Verbose "StorageAccountName: '$StorageAccountName'"

Resolve-AzContext
Export-AzContext -Force

#Set context to upload file
$storageContext = New-AzStorageContext -UseConnectedAccount -BlobEndpoint "https://$($StorageAccountName).blob.core.windows.net/"

#Verify container exists
$containerName = Get-ExpectedContainerName -Email $(Get-CurrentUserEmail) -TermCode $Settings.TermCode
Write-Verbose "ContainerName: '$($containerName)'"
$container =  Get-AzStorageContainer -Name $containerName -Context $storageContext -ErrorAction SilentlyContinue
if (-not $container){
     Write-Error "Couldn't find/access container '$($containerName)' in storage account '$($StorageAccountName)'"
}

#choose blobs to download
$blobs = Get-AzStorageBlob -Container $containerName -Context $storageContext -IncludeVersion:$IncludeVersion
$blobsToDownload = $blobs `
    | Sort-Object -Property @{Expression={$_.Name}; Descending=$false}, @{Expression={$_.LastModified} ;Descending=$true}    `
    | Out-GridView -Title "Select which backup files to download."  -Wait -PassThru

#download blobs
foreach ($blob in $blobsToDownload){

    $fileDestination = join-Path $env:TMPDIR $file.VersionId $file.Name
    $fileDestination = $fileDestination.Split([IO.Path]::GetInvalidFileNameChars()) -join '_'

    Write-Host @"
Downloading $($blob.Name)
    Version: $($blob.VersionId)
    Last modified: $($blob.LastModified)
    Destination: $($fileDestination)
"@

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $blob | Get-AzStorageContext -Destination $fileDestination
    $timer.Stop()

    Write-Host "Downloaded $($blob.name), version $($blob.VersionId)"
    Write-Verbose "Download operation took $([math]::Round($timer.Elapsed.TotalMinutes), 2) minutes."
}


