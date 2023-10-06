 
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $false)][string]$StorageAccountName
)
$ErrorActionPreference = 'Stop' 

Import-Module $(Join-Path $PSScriptRoot "HyperVBackup.psm1")

$Settings = New-BackupSetting

# Get file(s) to upload
$PathList = $null
if ($Path){
    $PathList = @($Path)
}else{
    $PathList = $Settings.SearchDirectories
}
if(-not $PathList){
    Write-Error "Must specify 'Path' parameter or have settings.json that specifies SearchDirectories."
}else{
    Write-Verbose "Path(s) specified: $($PathList)"
}


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

#Get Az Context
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
 
#Calculate blob names
$blobNameMappings = New-Object "System.Collections.ArrayList"
foreach ($tempPath in $PathList){
    $blobNameMappings.AddRange(($(Get-BlobNameMapping -Path $tempPath -ClassCode $Settings.ClassCode)))
}

#Upload files
foreach ($blobNameMapping in $blobNameMappings){

    Write-Host @"
Uploading file $($blobNameMapping.Name) 
    Origin: $($blobNameMapping.LocalFilePath)
    Destination: $($StorageAccountName)/$($containerName)/$($blobNameMapping.BlobName)
"@

    #Verify path exists and isn't in use
    if(Test-FileReady -FilePath $blobNameMapping.LocalFilePath){

        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        Set-AzStorageBlobContent -Container $containerName `
            -File $blobNameMapping.LocalFilePath `
            -Blob $blobNameMapping.BlobName `
            -Context $storageContext -Force | Out-Null
        $timer.Stop()

        $blob = Get-AzStorageBlob -Container $containerName -Blob $blobName -Context $storageContext

        if ($blob){
            Write-Host "'$($blobNameMapping.Name) backed up.' \n\t Version:  $($blob.VersionId))." -ForegroundColor Green
            Write-Verbose "Upload operation took $([math]::Round($timer.Elapsed.TotalMinutes), 2) minutes."
        }else{
            Write-Warning "Unable to verify $($blobNameMapping.Name) backed up."
        }
    }else{
        Write-Error "Unable to upload $($blobNameMapping.Name).  File either doesn't exist or is locked." -ErrorAction Continue
    }

}

