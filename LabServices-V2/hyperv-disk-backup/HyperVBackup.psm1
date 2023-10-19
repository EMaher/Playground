 
#************* Settings *****************

function Get-ConfigurationSettings {
    [CmdletBinding()]
    param(
        [string]$SettingsFilePath
    )

    if (-not $SettingsFilePath){
        $SettingsFilePath = $(Join-Path $PSScriptRoot "settings.json") 
    }

    $settings =   return Get-Content -Path $SettingsFilePath -ErrorAction SilentlyContinue | ConvertFrom-Json 
    return $settings
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
        if ($Force -or $($PSCmdlet.ShouldContinue("Do you want program to remember login information?", "Save context"))) {
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
    return $response | Select-Object -ExpandProperty mail
}

function Get-AzADUserIdByEmail {
    [CmdletBinding()]param([string] $userEmail)

    $userAdObject = $null
    $userAdObject = Get-AzADUser -UserPrincipalName $userEmail.ToString().Trim() -ErrorAction SilentlyContinue
    if (-not $userAdObject) {
        $userAdObject = Get-AzADUser -Mail $userEmail.ToString().Trim() -ErrorAction SilentlyContinue
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
        $containerName = "$($TermCode)-$($containerName)".ToLower().Trim()
    }

    #container names must be 63 characters or less
    $containerName = $containerName.Substring(0, [Math]::Min($containerName.Length, 63))

    Write-Verbose "Expected container name is $($containerName) for term '$($TermCode)' for email '$($Email)'"

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

function Get-BlobNameMapping {
    [CmdletBinding()]param([string] $Path, [string] $ClassCode)

    $blobNameMappings = New-Object "System.Collections.ArrayList"

    $Path = Resolve-Path $Path -ErrorAction SilentlyContinue

    if (-not $(Test-Path -Path $Path)) {
        Write-Warning "Couldn't find path $Path"
        return
    }

    $prefix = ""
    if (-not ([String]::IsNullOrWhiteSpace($ClassCode)) ) {
        $prefix = "$($ClassCode)/"
    }

    if (Test-Path -Path $Path -PathType Leaf) {
        $fileName = $(Split-Path $Path -Leaf)
        $blobNameMappings.Add([PSCustomObject]@{"Name" = $fileName; "LocalFilePath" = $Path; "BlobName" = "$($prefix)$($fileName)" }) | Out-Null
    }
    else {
        $files = Get-ChildItem $Path -Recurse -File
        foreach ($file in $files) {
            $fileFullName = $file | Select-Object -ExpandProperty FullName
            $fileName = $file | Select-Object -ExpandProperty Name
            $fileRelativePath = $fileFullName.Replace($Path, "").Replace("\", "/").Trim("/")
            $blobNameMappings.Add([PSCustomObject]@{"Name" = $fileName; "LocalFilePath" = $fileFullName; "BlobName" = "$($prefix)$($fileRelativePath)" }) | Out-Null
        }
    }

    return $blobNameMappings
}

Export-ModuleMember -Function Get-ConfigurationSettings
Export-ModuleMember -Function Resolve-AzContext
Export-ModuleMember -Function Export-AzContext
Export-ModuleMember -Function Remove-ExportedAzContext
Export-ModuleMember -Function Get-CurrentUserEmail
Export-ModuleMember -Function Get-AzADUserIdByEmail
Export-ModuleMember -Function Get-ExpectedContainerName
Export-ModuleMember -Function Get-BlobNameMapping
Export-ModuleMember -Function Test-FileReady 