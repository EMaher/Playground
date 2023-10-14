  
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)][string]$Path,
    [Parameter(Mandatory = $false)][string]$StorageAccountName,
    [Parameter(Mandatory = $false)][switch]$Force
)
$ErrorActionPreference = 'Stop' 

Import-Module $(Join-Path $PSScriptRoot "HyperVBackup.psm1") -Force
$VerboseOutputInModuleFunctions = $PSBoundParameters.ContainsKey('Verbose')

# Configure variables for ShouldContinue prompts
$YesToAll = $Force
$NoToAll = $false

$Settings = Get-ConfigurationSettings -Verbose:$VerboseOutputInModuleFunctions

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
    Write-Verbose "Path(s) specified: $($PathList -join ';')"
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
$containerName = Get-ExpectedContainerName -Email $(Get-CurrentUserEmail) -TermCode $Settings.TermCode -Verbose:$VerboseOutputInModuleFunctions
Write-Verbose "ContainerName: '$($containerName)'"
$container =  Get-AzStorageContainer -Name $containerName -Context $storageContext -ErrorAction SilentlyContinue -Verbose:$VerboseOutputInModuleFunctions
if (-not $container){
     Write-Error "Couldn't find/access container '$($containerName)' in storage account '$($StorageAccountName)'"
}
 
#Calculate blob names
$blobNameMappings = New-Object "System.Collections.ArrayList"
foreach ($tempPath in $PathList){
    $tempMappings = Get-BlobNameMapping -Path $tempPath -ClassCode $Settings.ClassCode -Verbose:$VerboseOutputInModuleFunctions
    if ($tempMappings){
        $blobNameMappings.AddRange($tempMappings)
    }
}

#Upload files
foreach ($blobNameMapping in $blobNameMappings){

    if ($PSCmdlet.ShouldContinue("Backup file?`n`tOrigin: $($blobNameMapping.LocalFilePath)`n`tDestination: $($StorageAccountName)/$($containerName)/$($blobNameMapping.BlobName)", "Uploading file $($blobNameMapping.Name)", [ref] $YesToAll, [ref] $NoToAll )){

        Write-Host @"
Uploading file $($blobNameMapping.Name) 
    Origin: $($blobNameMapping.LocalFilePath)
    Destination: $($StorageAccountName)/$($containerName)/$($blobNameMapping.BlobName)
"@

        #Verify path exists and isn't in use
        if(Test-FileReady -FilePath $blobNameMapping.LocalFilePath -Verbose:$VerboseOutputInModuleFunctions){

            $timer = [System.Diagnostics.Stopwatch]::StartNew()
            Set-AzStorageBlobContent -Container $containerName `
                -File $blobNameMapping.LocalFilePath `
                -Blob $blobNameMapping.BlobName `
                -Context $storageContext -Force | Out-Null
            $timer.Stop()

            $blob = Get-AzStorageBlob -Container $containerName -Blob $blobNameMapping.BlobName -Context $storageContext

            if ($blob){
                Write-Host "SUCCESS! File '$($blobNameMapping.Name)' backed up. (Version:  $($blob.VersionId))." -ForegroundColor Green
                Write-Verbose "Upload operation took $([math]::Round($timer.Elapsed.TotalMinutes), 2) minutes."
            }else{
                Write-Warning "Unable to verify $($blobNameMapping.Name) backed up."
            }
        }else{
            Write-Error "Unable to upload $($blobNameMapping.Name).  File either doesn't exist or is locked." -ErrorAction Continue
        }
    }else{
        Write-Host "SKIPPED! File '$($blobNameMapping.Name)' NOT backed up." -ForegroundColor Yellow
    }

}