
#************* Settings *****************

class BackUpSetting {
    [string]$ClassCode
    [string]$TermCode
    [string]$StorageAccountName

    BackUpSetting(){
        $settings = Get-ConfigurationSettings

        $this.ClassCode = $settings.ClassCode
        $this.TermCode = $settings.TermCode
        $this.StorageAccountName = $settings.StorageAccountName

        if (-not $Settings.ClassCode){
            Write-Verbose "settings.json file didn't specify a ClassCode."
        }
        if (-not $Settings.TermCode){
            Write-Verbose "settings.json file didn't specify a TermCode"
        }
        if (-not $Settings.StorageAccountName){
            Write-Verbose "settings.json file didn't specify a StorageAccountName"
        }
    }
}

function Get-ConfigurationSettings() {
    $settingsFilePath = Join-Path $PSScriptRoot "settings.json"
    return Get-Content -Path $settingsFilePath -ErrorAction SilentlyContinue | ConvertFrom-Json  
}

function New-BackupSetting(){
    return [BackupSettings]::new()
}

#************* Email related ***************
function Get-CurrentUserEmail()
{
    $token = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com/" | Select-Object -ExpandProperty Token
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $token")

    $response = Invoke-RestMethod 'https://graph.microsoft.com/v1.0/me' -Method 'GET' -Headers $headers
    #$response | ConvertTo-Json
    return $response | Select-Object -ExpandProperty mail
}

#***************** Container related ********************

function Test-FileReady([string] $FilePath){
    $returnVal = $true
    $FilePath = Resolve-Path $FilePath -ErrorAction Continue
    if(-not $(Test-Path -Path $FilePath)){
        Write-Verbose "Couldn't find file $($FilePath)"
        $returnVal =  $false
    }else{
        try{
            $fs = [System.IO.File]::Open($FilePath,'Open','ReadWrite')
        }catch{
            Write-Verbose "$($FilePath) in use."
            $returnVal = $false
        }finally{
            $fs.Close()
            $fs.Dispose()
        }
    }
    return $returnVal
}

Get-BlobNameMapping([string] $Path, [string] $ClassCode){
    $blobNameMappings = New-Object "System.Collections.ArrayList"

    $Path = Resolve-Path $Path

    if(-not $(Test-Path -Path $Path)){
        Write-Warning "Couldn't find path $Path"
        return
    }

    $prefix = ""
    if(-not ([String]::IsNullOrWhiteSpace($ClassCode)) ){
        $prefix = "$($ClassCode)/"
    }

    if (Test-Path -Path $Path -PathType Leaf){
        $blobNameMappings.Add([PSCustomObject]@{"Name"=$Path.Name;"LocalFilePath"=$Path; "BlobName"="$(prefix)$($Path | Select-Object -Expand Name)"})
    }else{
        $files = Get-ChildItem $Path -Recurse -File
        foreach($file in $files){
            $fileFullName = $file | Select-Object -ExpandProperty FullPath
            $fileName = $file | Select-Object -ExpandProperty Name
            $fileRelativePath = $file.Replace($Path, $($Path | Select-Object -ExpandProperty FullPath),"").Replace("\", "/").Trim("/")
            $blobNameMappings.Add([PSCustomObject]@{"Name"=$fileName; "LocalFilePath"=$fileFullName; "BlobName"="$($prefix)$($fileRelativePath)"})
        }
    }

    return $blobNameMappings
}

function Get-ExpectedContainerName([string]$TermCode, [string]$Email){
    $containerName =  "$($Email.Replace('@', "-").Replace(".", "-"))".ToLower().Trim()
   if (-not [string]::IsNullOrEmpty($TermCode)){
       $containerName = "$($TermCode)-$($containerName)"
   }

   #container names must be 63 characters or less
   $containerName.Substring(0, [Math]::Min($containerName.Length, 63))

   return $containerName
}

Export-ModuleMember -Function New-BackupSetting
Export-ModuleMember -Function Get-CurrentUserEmail
Export-ModuleMember -Function Get-ExpectedContainerName
Export-ModuleMember -Function Get-BlobNameMapping