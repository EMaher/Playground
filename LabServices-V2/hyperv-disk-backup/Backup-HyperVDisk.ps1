 
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $false)][string]$StorageAccountName
)
$ErrorActionPreference = 'Stop' 


function Get-ConfigurationSettings() {
    $settingsFilePath = Join-Path $PSScriptRoot "settings.json"
    return Get-Content -Path $settingsFilePath -ErrorAction SilentlyContinue| ConvertFrom-Json  
}

function Get-CurrentUserEmail()
{
    $token = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com/" | Select-Object -ExpandProperty Token
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $token")

    $response = Invoke-RestMethod 'https://graph.microsoft.com/v1.0/me' -Method 'GET' -Headers $headers
    #$response | ConvertTo-Json
    return $response | Select-Object -ExpandProperty mail
}

function Get-ExpectedContainerName([string]$TermCode, [string]$Email){
    $containerName =  "$($Email.Replace('@', "-").Replace(".", "-"))".ToLower().Trim()
   if (-not [sting]::IsNullOrEmpty($TermCode)){
       $containerName = "$($TermCode)-$($containerName)"
   }

   #container names must be 63 characters or less
   $containerName.Substring(0, [Math]::Min($containerName.Length, 63))

   return $containerName
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
if (-not $Settings.TermCode){
    Write-Verbose "settings.json file didn't specify a TermCode"
}

#Get Storage account name
if (-not $StorageAccountName){
    if (-not $Settings.StorageAccountName){
        Write-Error "Must specify 'StorageAccountName' parameter or have settings.json that specifies StorageAccountName."
    }else{
        $StorageAccountName = $Settings.StorageAccountName
    }
}
Write-Verbose "StorageAccountName: '$StorageAccountName'"
#Note, can't verify existence because student's only have access to their containers.

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
$storageContext = New-AzStorageContext -UseConnectedAccount -BlobEndpoint "https://$StorageAccountName.blob.core.windows.net/"
#$storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName

#Verify container exists
$containerName = Get-ExpectedContainerName -Email $(Get-CurrentUserEmail) -TermCode $Settings.TermCode
Write-Verbose "ContainerName: '$containerName'"
$container =  Get-AzStorageContainer -Name $containerName -Context $storageContext -ErrorAction SilentlyContinue
if (-not $container){
     Write-Error "Couldn't find/access container '$containerName' in storage account '$StorageAccountName'"
}
 
#Calculate blob name
$blobName = [System.IO.Path]::GetFileName($FilePath)
if(-not ([String]::IsNullOrWhiteSpace($Settings.ClassCode)) ){
    $blobName = "$($Settings.ClassCode)/$($blobName)"
}
Write-Verbose "Destination blob name: $blobName"

Write-Host "Uploading file $([System.IO.Path]::GetFileName($FilePath)) to $StorageAccountName/$containerName"
$timer = [System.Diagnostics.Stopwatch]::StartNew()
Set-AzStorageBlobContent -Container $containerName -File $FilePath -Blob $blobName -Context $storageContext -Force | Out-Null
$timer.Stop()
$blob = Get-AzStorageBlob -Container $containerName -Blob $blobName -Context $storageContext
if ($blob){
    Write-Host "Success! '$FilePath' backed up as '$blobname' (version  $($blob.VersionId))."
    Write-Host "Upload operation took $($timer.Elapsed.TotalMinutes) minutes."
}else{
    Write-Warning "Unable to verify disk back up."
}
