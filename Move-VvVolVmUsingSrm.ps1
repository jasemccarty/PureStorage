
# Get the PowerCLI Version
$PowerCLIVersion = Get-Module -Name VMware.PowerCLI -ListAvailable | Select-Object -Property Version

# If the PowerCLI Version is not v12 or higher, recommend that the user install PowerCLI 12 or higher
If ($PowerCLIVersion.Version.Major -ge "12") {
    Write-Host "PowerCLI version 12 or higher present, " -NoNewLine
    Write-Host "proceeding" -ForegroundColor Green 
} else {
    Write-Host "PowerCLI version could not be determined or is less than version 12" -Foregroundcolor Red
    Write-Host "Please install PowerCLI 12 or higher and rerun this script" -Foregroundcolor Yellow
    Write-Host " "
    exit
}

# Meadowcroft SRM is required (https://github.com/benmeadowcroft/SRM-Cmdlets)
# Ensure that Meadowcroft.Srm is loaded
if (-Not (Get-module).Where({$_.Name -eq "Meadowcroft.Srm"})) {
    import-module 'C:\Program Files\WindowsPowerShell\Modules\SRM-Cmdlets-0.2\Meadowcroft.Srm.psd1'
}


# Get Credentials for use with vCenter and SRM
$Creds = Get-Credential

# Connect to the Source vCenter
$Vcenter1 = Connect-VIServer "vcenter1.domain" -Credential $Creds

# Connect to the Target vCenter
$Vcenter2 = Connect-VIServer "vcenter2.domain" -Credential $Creds

# Connect to the Source SRM Server
$SrmServer1 = Connect-SrmServer -SrmServerAddress "srm1.domain" -Credential $Creds -RemoteCredential $Creds

# Connect to the Target SRM Server
$SrmServer2 = Connect-SrmServer -SrmServerAddress "srm2.domain" -Credential $Creds -RemoteCredential $Creds

# Get the Source VM
$VM1 = Get-VM -Name "TESTVVOL" -Server $Vcenter1

# Gather the SPBM Policy so it can be assigned to the VM and it's disks
$Policy1 = Get-SpbmStoragePolicy -Server $Vcenter1 -Name "1hr-Repl-M70"

# vVols based VM's with replication require the Replication Policy when assigning policies, so gather the policy
$RGroup1 = Get-SpbmReplicationGroup -Server $Vcenter1 -FaultDomain "array1" -Name "*:1hr-replication"

# Get the Protection Group so we can add the VM to it
$PGroup1 = Get-SrmProtectionGroup -Name "VVOLPG"

# Get the Recovery Plan on the TARGET SRM Server
$Rplan1 = Get-SrmRecoveryPlan -Name "VVOLRP" -SrmServer $SrmServer2 

# Get the current SPBM configuration for the VM & replace the policy assigned
Set-SpbmEntityConfiguration -Configuration (Get-SpbmEntityConfiguration $VM1) -StoragePolicy $Policy1 -ReplicationGroup $RGroup1
# Get the current SPBM configuration for each hard disk & replace the policy assigned
Set-SpbmEntityConfiguration -Configuration (Get-SpbmEntityConfiguration -HardDisk (Get-HardDisk -VM $VM1)) -StoragePolicy $Policy1 -ReplicationGroup $RGroup1

# Discover the devices on the Source SRM Server
# This will discover the newly assigned vVols VM
Start-SrmDiscoverDevice -SrmServer $SrmServer1

# Let's give SRM 30 seconds to discover devices
Start-Sleep 30 

# Invoke the Recovery Plan to move the VM from the Source to Target Site
Start-SrmRecoveryPlan -RecoveryPlan $Rplan1 -RecoveryMode "Migrate" -Confirm:$False

# Wait 30 seconds before checking the status of the VM Recovery Plan being implemented
Start-Sleep 30 

# While the Recovery Plan is executing, check the Recovery Plan's state and wait until it isn't Running anymore
Do {
    $RplanState = (Get-SrmRecoveryPlan -Name "VVOLRP").GetInfo().State
} While (-not $RplanState -ne "Running")


# Perform a reportection to be able to reverse the Failover if desired
Start-SrmRecoveryPlan -RecoveryPlan $Rplan1 -RecoveryMode "Reprotect" -Confirm:$False

# While the Recovery Plan is executing, check the Recovery Plan's state and wait until it isn't Running anymore
Do {
    $RplanState = (Get-SrmRecoveryPlan -Name "VVOLRP").GetInfo().State
} While (-not $RplanState -ne "Running")

# Perform a Test and then Test Cleanup to remove any residual vVols on the Source
Start-SrmRecoveryPlan -RecoveryPlan $Rplan1 -RecoveryMode "Test" -Confirm:$False

# While the Recovery Plan is executing, check the Recovery Plan's state and wait until it isn't Running anymore
Do {
    $RplanState = (Get-SrmRecoveryPlan -Name "VVOLRP").GetInfo().State
} While (-not $RplanState -ne "Running")

# Perform a Test and then Test Cleanup to remove any residual vVols on the Source
Start-SrmRecoveryPlan -RecoveryPlan $Rplan1 -RecoveryMode "CleanupTest" -Confirm:$False

# Gather the VM Object on the Target vCenter because it has moved over
$VM2 = Get-VM -Name "TESTVVOL" -Server $Vcenter2

# Gather the SPBM Policy so it can be assigned to the VM and it's disks
$Policy2 = Get-SpbmStoragePolicy -Server $Vcenter2 -Name "1hr-Replication"

# vVols based VM's with replication require the Replication Policy when assigning policies, so gather the policy
$RGroup2 = Get-SpbmReplicationGroup -Server $Vcenter2 -Name "*:1hr-replication" -FaultDomain "array2"

# Get the current SPBM configuration for the VM & replace the policy assigned so it isn't part of an SRM Replication Group any longer
Set-SpbmEntityConfiguration -Configuration (Get-SpbmEntityConfiguration $VM2) -StoragePolicy $Policy1 -ReplicationGroup $RGroup2

# Get the current SPBM configuration for each hard disk & replace the policy assigned so it isn't part of an SRM Replication Group any longer
Set-SpbmEntityConfiguration -Configuration (Get-SpbmEntityConfiguration -HardDisk (Get-HardDisk -VM $VM2)) -StoragePolicy $Policy2 -ReplicationGroup $RGroup1
