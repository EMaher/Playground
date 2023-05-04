# Backup System for Hyper-V Disks

## Infrastructure
1. Open PowerShell window with 'Az' module installed.  You can also use [Azure Cloud Shell](https://shell.azure.com).

2. Login

   ```powershell
   Login-AzAccount
   ```

3. Verify correct subscription is selected.  If not change context.

   ```powershell
   #Get current context.  All future commands will use this
   Get-AzContext
   ```
   
   If context is not as desired, switch subscriptions.

   ```powershell
   #List subscriptions
   Get-AzSubscriptions

   #Set current subscription
   Set-AzSubscription -Subscription 111111111111-1111-1111-11111111
   ```

4. Create  resource group, if not done already.

   ```powershell
    New-AzResourceGroup -Name "<ResourceGroupName>" -Location "<location>"
   ```

   To get a list of possible values for location of the resource group, run `Get-AzLocation | Join-String -Property Location  -Separator ", "`.

5. Run setup script

    ```powershell
    ./New-HyperVDiskStorage.ps1 -ResourceGroupName "<ResourceGroupName>" -StorageAccountName "<StorageAccountName>" -Location "<location>" -InstructorEmails @('email1@myschool.com', 'email2@myschool.com') -StudentEmails @('student1@myschool.com', 'student2@myschool.com')
    ```

6. Save storage account name

## Template VM

1. Save PowerShell file easy to find location (like the desktop) with configuration file.

    ```powershell
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/EMaher/Playground/main/LabServices-V2/hyperv-disk-backup/Backup-HyperVDisk.ps1" -OutFile $(Join-Path $env:USERPROFILE Desktop "SaveHypervDisk\Backup-HyperVDisk.ps1") -Force
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/EMaher/Playground/main/LabServices-V2/hyperv-disk-backup/settings.json" -OutFile $(Join-Path $env:USERPROFILE Desktop "SaveHypervDisk\settings.json")
    ```

2. Update configuration is settings.json.  
    
    - Storage account name will be one created in section above.  
    - ClassCode is prefix that will be used for backups in the case student has multiple classes that use nested virtualization. No invalid filename characters allowed.

    ```json
    {
        "ClassCode": "",
        "StorageAccount": ""
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

3. Upload disk to storage account.

   ```powershell
   ./Backup-HyperVDisk.ps1 -FilePath "<path to hyper-v disk>"
   ```