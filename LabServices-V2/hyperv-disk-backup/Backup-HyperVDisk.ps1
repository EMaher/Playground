 
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $false)][string]$StorageAccountName
)
$ErrorActionPreference = 'Stop' 

Import-Module ./HyperVBackup.psm1

$Settings = New-BackupSetting


#TODO: Create collection for files to upload
#- if Path specified, use that.  Create list.
#- if Path not specified, Read search directories from settings and create list


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
 
#TODO: change blobNameMappies call to iterate over Path list created above

#Calculate blob name
$blobNameMappings = @(Get-BlobNameMapping -Path $Path)


foreach ($blobNameMapping in $blobNameMappings){

    Write-Host @"
Uploading file $($blobNameMapping.LocalFilePath.Name) 
    Origin: $($blobNameMapping.LocalFilePath)
    Destination: $($StorageAccountName)/$($containerName)/$($blobNameMapping.BlobName)
"@

    #Verify path exists and isn't in use
    if(Test-FileReady -FilePath $blobNameMapping.LocalFilePath){

        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        Set-AzStorageBlobContent -Container $containerName -File $blobNameMapping.LocalFilePath -Blob $blobNameMapping.BlobName -Context $storageContext -Force | Out-Null
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

