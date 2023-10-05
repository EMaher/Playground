
#************* Settings *****************

class BackUpSetting {
    [string]$ClassCode
    [string]$TermCode
    [string]$StorageAccountName
    [string[]]$SearchDirectories

    BackUpSetting() {
        $settingFilePath = $(Join-Path $PSScriptRoot "settings.json")
        $settings = Get-ConfigurationSettings -SettingsFilePath $settingFilePath

        $this.ClassCode = $settings.ClassCode
        $this.TermCode = $settings.TermCode
        $this.StorageAccountName = $settings.StorageAccountName
        $this.SearchDirectories = $settings.SearchDirectories


        if (-not $Settings.ClassCode) {
            Write-Verbose "settings.json file didn't specify a ClassCode."
        }
        if (-not $Settings.TermCode) {
            Write-Verbose "settings.json file didn't specify a TermCode"
        }
        if (-not $Settings.StorageAccountName) {
            Write-Verbose "settings.json file didn't specify a StorageAccountName"
        }
        if (-no $Settings.SearchDirectories) {
            Write-Verbose "settings.json file didn't specify a StorageAccountName"
        }
    }
}

function Get-ConfigurationSettings($SettingsFilePath) {
    return Get-Content -Path $SettingsFilePath -ErrorAction SilentlyContinue | ConvertFrom-Json  
}

func

function New-BackupSetting {
    [CmdletBinding()]param()
    return [BackupSettings]::new()
}

#************* AD and email related ***************

$AZ_CONTEXT_PATH = $(Join-Path $PSScriptRoot "context.json")
function Resolve-AzContext {
    [CmdletBinding()]param()

    $azContext = Get-AzContext 
    if (-not $azContext) {
        $azContext = Import-AzContext -Path $AZ_CONTEXT_PATH -ErrorAction SilentlyContinue
        if (-not $azContext) {
            $azContext = Connect-AzAccount
        }
    }
    return $azContext
}
function Export-AzContext() {
    [CmdletBinding()]param([switch]$Force, [switch]$Overwrite)

    $contextFileExists = (Test-Path $AZ_CONTEXT_PATH)

    if ($(-not $contextFileExists) -or $($contextFileExists -and $Overwrite)) {
        if (-not $Force -and $($PSCmdlet.ShouldContinue("Do you want program to remember login information?", "Save context"))) {
             Save-AzContext -Path $AZ_CONTEXT_PATH
        }
    }
}

function Remove-ExportedAzContext {
    [CmdletBinding()]param()

    Remove-Item $AZ_CONTEXT_PATH
}


function Get-CurrentUserEmail {
    [CmdletBinding()]param()

    $token = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com/" | Select-Object -ExpandProperty Token
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $token")

    $response = Invoke-RestMethod 'https://graph.microsoft.com/v1.0/me' -Method 'GET' -Headers $headers
    #$response | ConvertTo-Json
    return $response | Select-Object -ExpandProperty mail
}

function Get-AzADUserIdByEmail {
    [CmdletBinding()]param([string] $userEmail)

    $userAdObject = $null
    $userAdObject = Get-AzADUser -UserPrincipalName $email.ToString().Trim() -ErrorAction SilentlyContinue
    if (-not $userAdObject) {
        $userAdObject = Get-AzADUser -Mail $email.ToString().Trim() -ErrorAction SilentlyContinue
    }

    if (-not $userAdObject) {
        Write-Error "Unable to find object for user with email $userEmail"
    }
    else {
        Write-Verbose "Found id $($UserAdObject.Id) for email $userEmail"
        return $userAdObject.Id
    }
}

#***************** Container related ********************

function Get-ExpectedContainerName {
    [CmdletBinding()]param([string]$TermCode, [string]$Email)

    $containerName = "$($Email.Replace('@', "-").Replace(".", "-"))".ToLower().Trim()
    if (-not [string]::IsNullOrEmpty($TermCode)) {
        $containerName = "$($TermCode)-$($containerName)"
    }

    #container names must be 63 characters or less
    $containerName.Substring(0, [Math]::Min($containerName.Length, 63))

    return $containerName
}

function Test-FileReady {
    [CmdletBinding()]param([string] $FilePath)

    $returnVal = $true
    $FilePath = Resolve-Path $FilePath -ErrorAction Continue
    if (-not $(Test-Path -Path $FilePath)) {
        Write-Verbose "Couldn't find file $($FilePath)"
        $returnVal = $false
    }
    else {
        try {
            $fs = [System.IO.File]::Open($FilePath, 'Open', 'ReadWrite')
        }
        catch {
            Write-Verbose "$($FilePath) in use."
            $returnVal = $false
        }
        finally {
            $fs.Close()
            $fs.Dispose()
        }
    }
    return $returnVal
}

Get-BlobNameMapping {
    [CmdletBinding()]param([string] $Path, [string] $ClassCode)

    $blobNameMappings = New-Object "System.Collections.ArrayList"

    $Path = Resolve-Path $Path

    if (-not $(Test-Path -Path $Path)) {
        Write-Warning "Couldn't find path $Path"
        return
    }

    $prefix = ""
    if (-not ([String]::IsNullOrWhiteSpace($ClassCode)) ) {
        $prefix = "$($ClassCode)/"
    }

    if (Test-Path -Path $Path -PathType Leaf) {
        $blobNameMappings.Add([PSCustomObject]@{"Name" = $Path.Name; "LocalFilePath" = $Path; "BlobName" = "$(prefix)$($Path | Select-Object -Expand Name)" })
    }
    else {
        $files = Get-ChildItem $Path -Recurse -File
        foreach ($file in $files) {
            $fileFullName = $file | Select-Object -ExpandProperty FullPath
            $fileName = $file | Select-Object -ExpandProperty Name
            $fileRelativePath = $file.Replace($Path, $($Path | Select-Object -ExpandProperty FullPath), "").Replace("\", "/").Trim("/")
            $blobNameMappings.Add([PSCustomObject]@{"Name" = $fileName; "LocalFilePath" = $fileFullName; "BlobName" = "$($prefix)$($fileRelativePath)" })
        }
    }

    return $blobNameMappings
}



Export-ModuleMember -Function New-BackupSetting
Export-ModuleMember -Function Resolve-AzContext
Export-ModuleMember -Function Export-AzContext
Export-ModuleMember -Function Remove-ExportedAzContext
Export-ModuleMember -Function Get-CurrentUserEmail
Export-ModuleMember -Function Get-AzADUserIdByEmail
Export-ModuleMember -Function Get-ExpectedContainerName
Export-ModuleMember -Function Get-BlobNameMapping