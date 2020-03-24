<#
The MIT License (MIT)
Copyright (c) Microsoft Corporation  
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.  
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. 
.SYNOPSIS
This script prepares the environment so 'stop-CurrentLabVm.ps1' can be successfully executed.
#>

Write-Host "Installing necessary modules."
Write-Verbose "Installing 'Az' module'."
Install-Module -Name Az -AllowClobber

Write-Verbose "Installing 'Az.Accounts' module'."
if(-not (Get-Module Az.Accounts)) {
    Import-Module Az.Accounts
}

Write-Host "Enable context to be saved and used for future calls to Az module."
Enable-AzContextAutosave | Out-Null

Write-Host "Login to Azure"
Login-AzAccount | Out-Null
