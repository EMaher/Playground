  
[CmdletBinding()]
param ( )

# *** CHECK NORMAL USER SETTINGS ***

# Try to find other users on the machines, if there is one, then ask if they should be added to the "Hyper-V Administrators" Group

# Check permissions for VMs (maybe not necessary?)


# *** CHECK VM CONFIGURATION ***

# TODO: Take VM/OS list to verify against known minimum configurations.

$ErrorActionPreference = 'Stop' 

$vms = Get-VM

# Script that checks recommendations for each Hyper-V VM as described by https://learn.microsoft.com/azure/lab-services/concept-nested-virtualization-template-vm#recommendations

#For each VM
$vms | ForEach-Object{
    # TODO: Add check to see if VM is running. We won't be able to some change settings if it is.

    # Make sure automatic shutdown action is Shutdown

    # Verify disk is vhdx not vhd

    # CPUs is more than default 1 CPU

    # Memory is more than default 512
}