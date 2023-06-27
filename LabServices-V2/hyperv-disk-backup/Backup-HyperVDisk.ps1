[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$FilePath#,
    #[Parameter(Mandatory = $false)][string]$DestinationFileName
)

function Get-ExpectedContainerName(){
    #Alternatively, create container name based on the AAD ObjectId for the student
    $email = Get-AzContext | select -expand Account | select -expand Id
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
if (-not $Settings.ClassCode -or -not $Settings.StorageAccount){
    Write-Error "settings.json file must specify ClassCode and StorageAccount."
}

#Get Storage account name
$StorageAccountName = $Settings.StorageAccount
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
Write-Verbose "Destination blob name: $blobName"

Write-Host "Uploading file $([System.IO.Path]::GetFileName($FilePath)) to $ContainerName"
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
