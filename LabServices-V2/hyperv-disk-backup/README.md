# Backup System for Hyper-V Disks

## Infrastructure

1. Open PowerShell window with 'Az' module installed.  You can also use [Azure Cloud Shell](https://shell.azure.com).

   ```powershell
   Install-Module Az
   ```

2. Login

   ```powershell
   Login-AzAccount
   ```

3. Verify correct subscription is the current context.  All future commands will use this.

   ```powershell
   Get-AzContext
   ```

   If context is not as desired, switch subscriptions.  Start by listing all available subscriptions, then update the context.

   ```powershel
   #List subscriptions
   Get-AzSubscription

   Set-AzContext -Subscription 11111111-1111-1111-1111-111111111111
   ```

4. Create  resource group, if not done already.

   ```powershell
    New-AzResourceGroup -Name "<ResourceGroupName>" -Location "<location>"
   ```

   To get a list of possible values for location of the resource group, run `Get-AzLocation | Join-String -Property Location  -Separator ", "`.

5. Download and run setup script

    ```powershell
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/EMaher/Playground/master/LabServices-V2/hyperv-disk-backup/HyperVBackup.psm1" -OutFile "HyperVBackup.psm1"
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/EMaher/Playground/master/LabServices-V2/hyperv-disk-backup/New-HyperVDiskStorage.ps1" -OutFile "New-HyperVDiskStorage.ps1"

    ./New-HyperVDiskStorage.ps1 -ResourceGroupName "<ResourceGroupName>" -StorageAccountName "<StorageAccountName>" -Location "<location>" -InstructorEmails @('email1@myschool.com', 'email2@myschool.com') -StudentEmails @('student1@myschool.com', 'student2@myschool.com') -TermCode "<TermCode>"
    ```

6. Save storage account name

## Template VM

1. Save PowerShell file easy to find location (like the desktop) with configuration file.

    ```powershell
    $directory = New-Item -Type Directory $(Join-Path $env:USERPROFILE Desktop | Join-Path -ChildPath "SaveHypervDisk") -Force
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/EMaher/Playground/master/LabServices-V2/hyperv-disk-backup/HyperVBackup.psm1" -OutFile $(Join-Path  $directory.FullName "HyperVBackup.psm1")
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/EMaher/Playground/master/LabServices-V2/hyperv-disk-backup/Backup-HyperVDisk.ps1" -OutFile $(Join-Path $directory.FullName "Backup-HyperVDisk.ps1")
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/EMaher/Playground/master/LabServices-V2/hyperv-disk-backup/Get-HyperVDiskBackup.ps1" -OutFile $(Join-Path  $directory.FullName "Get-HyperVDiskBackup.ps1")
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/EMaher/Playground/master/LabServices-V2/hyperv-disk-backup/settings.json" -OutFile $(Join-Path  $directory.FullName "settings.json")
    ```

2. Update configuration is settings.json.  

    - Storage account name will be one created in section above.  
    - ClassCode is prefix that will be used for backups in the case student has multiple classes that use nested virtualization. No invalid filename characters allowed.
    - SearchDirectories is a list of file paths and/or folder paths.  You can specify a specific file to backup or a directory in which to search for Hyper-V disk files.

    ```json
    {
        "ClassCode": "CS101",
        "StorageAccountName": "mystorageaccount",
        "TermCode": "Fall23",
        "SearchDirectories" : [ 
            "C:\\ProgramData\\Microsoft\\Windows\\Virtual Hard Disks", 
            "C:\\Users\\Public\\Documents"
        ]
    }
    ```

3. Install 'Az' module.  It is required by the scripts the students will use.

    ```powershell
    Install-Module 'Az' -Scope AllUsers 
    ```

## Student VM

1. Open PowerShell window.
2. Login

    ```powershell
    Login-AzAccount
    ```

3. Open PowerShell windows and navigate to script directory

```powershell
cd "$($env:USERPROFILE)\Desktop\SaveHypervDisk"
```

### Backup disks

To backup all disks to storage account, run the following command. Script will look for *.vhdx files in search folders specified settings.json

```powershell
./Backup-HyperVDisk.ps1
```

To backup a single file:

```powershell
./Backup-HyperVDisk.ps1 -Path "<path to file>"
```

To suppress confirmation prompts, use the `-Force` switch.

```powershell
./Backup-HyperVDisk.ps1 -Force
```

### Download backup disks

To download a backed up disk:

```powershell
./Get-HyperVDiskBackup.ps1 
```

To download a specific version of a backed up disk:

```powershell
./Get-HyperVDiskBackup.ps1 -IncludeVersion
```
