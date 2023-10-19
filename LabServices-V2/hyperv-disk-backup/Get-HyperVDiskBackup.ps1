[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)][string]$StorageAccountName,
    [Parameter(Mandatory = $false)][switch]$IncludeVersion
)
$ErrorActionPreference = 'Stop' 


Import-Module $(Join-Path $PSScriptRoot "HyperVBackup.psm1") -Force
$VerboseOutputInModuleFunctions = $PSBoundParameters.ContainsKey('Verbose')

$Settings = Get-ConfigurationSettings -Verbose:$VerboseOutputInModuleFunctions

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
$containerName = Get-ExpectedContainerName -Email $(Get-CurrentUserEmail) -TermCode $Settings.TermCode -Verbose:$VerboseOutputInModuleFunctions
Write-Verbose "ContainerName: '$($containerName)'"
$container =  Get-AzStorageContainer -Name $containerName -Context $storageContext -ErrorAction SilentlyContinue
if (-not $container){
     Write-Error "Couldn't find/access container '$($containerName)' in storage account '$($StorageAccountName)'"
}

#choose blobs to download
$blobs = Get-AzStorageBlob -Container $containerName -Context $storageContext -IncludeVersion:$IncludeVersion
$blobsToDownload = $blobs `
    | Sort-Object -Property @{Expression={$_.Name}; Descending=$false}, @{Expression={$_.LastModified} ;Descending=$true}    `
    | Out-GridView -Title "Select which backup files to download." -PassThru

#download blobs
foreach ($blob in $blobsToDownload){

    $fileDestination = Join-Path $env:USERPROFILE "Downloads"
    if($IncludeVersion){
        $fileDestination = Join-Path $fileDestination $($blob.VersionId.Split([IO.Path]::GetInvalidFileNameChars()) -join '_')
    }
    $fileDestination = Join-Path $fileDestination $blob.Name

    #Create destination folder if doesn't already exist
    New-Item -ItemType Directory -Path (Split-Path -Parent $fileDestination) -Force | Out-Null
    
    Write-Host @"
Downloading $($blob.Name)
`tVersion: $($blob.VersionId)
`tLast modified: $($blob.LastModified)
`tDestination: $($fileDestination)
"@

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $blob | Get-AzStorageBlobContent -Destination $fileDestination | Out-Null
    $timer.Stop()

    if(Test-Path $fileDestination){
        Write-Host "SUCCESS! Downloaded $($blob.name)`n`tVersion: $($blob.VersionId))`n`tDestination: $($fileDestination)" -ForegroundColor Green
    }
    Write-Verbose "Download operation took $([math]::Round($timer.Elapsed.TotalMinutes), 2) minutes."
}