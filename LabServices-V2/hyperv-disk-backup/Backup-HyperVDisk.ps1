[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $false)][string]$StorageAccountName
)
$ErrorActionPreference = 'Stop' 


function Get-ExpectedContainerName(){
    $email = Get-AzContext | Select-Object -expand Account | Select-Object -expand Id
    return "$($email.Replace('@', "-").Replace(".", "-"))".ToLower()
}
function Get-ConfigurationSettings() {
    $settingsFilePath = Join-Path $PSScriptRoot "settings.json"
    return Get-Content -Path $settingsFilePath | ConvertFrom-Json  
}

#Verify files exists and isn't in use
$FilePath = Resolve-Path $FilePath
if(-not $(Test-Path -Path $FilePath)){
    Write-Error "Couldn't find file $FilePath"
}
try{
    $fs = [System.IO.File]::Open($FilePath,'Open','ReadWrite')
}catch{
    Write-Error "Can't upload file.  $FilePath in use.  "
}finally{
    $fs.Close()
    $fs.Dispose()
}

$Settings = Get-ConfigurationSettings
if (-not $Settings.ClassCode){
    Write-Verbose "settings.json file didn't specify a ClassCode."
}

#Get Storage account name
if (-not $StorageAccountName){
    if (-not $Settings.StorageAccountName){
        Write-Error "Must specify 'StroageAccountName' paramter or have settings.json that specifies StorageAccountName."
    }else{
        $StorageAccountName = $Settings.StorageAccountName
    }
}
#Note, can't verify existence because student's only have access to their containers.

#Set context to upload file
$storageContext = New-AzStorageContext -UseConnectedAccount -BlobEndpoint "https://$StorageAccountName.blob.core.windows.net/"

#Verify container exists
$ContainerName = Get-ExpectedContainerName
$container =  Get-AzStorageContainer -Name $ContainerName -Context $storageContext 
if (-not $container){
    Write-Error "Couldn't find/access container '$ContainerName' in storage account '$StorageAccountName'"
}

#Calculate blob name
$blobName = "$($Settings.ClassCode)-$([System.IO.Path]::GetFileName($FilePath))"
if(-not ([String]::IsNullOrWhiteSpace($Settings.ClassCode)) ){
    $blobName = "$($Settings.ClassCode)-$($blobName)"
}
Write-Verbose "Destination blob name: $blobName"

Write-Host "Uploading file $([System.IO.Path]::GetFileName($FilePath)) to $StorageAccount/$ContainerName"
$timer = [System.Diagnostics.Stopwatch]::StartNew()
Set-AzStorageBlobContent -Container $ContainerName -File $FilePath -Blob $blobName -Context $storageContext -Force
$timer.Stop()

$blob = Get-AzStorageBlob -Container $ContainerName -Blob $blobName -Context $storageContext
if ($blob){
    Write-Host "Success! '$FilePath' backed up as '$blobname' (version  $($blob.VersionId))."
    Write-Host "Upload operation took $($timer.Elapsed.TotalMinutes) minutes."
}else{
    Write-Warning "Unable to verify disk back up."
} 
