# Setup the script's parameters
[CmdletBinding()]Param(
[Parameter(Mandatory=$True)][string]$VM,
[Parameter(Mandatory=$True)][string]$GuestUser,
[Parameter(Mandatory=$True)][string]$GuestPassword,
[Parameter(Mandatory=$False)][boolean]$Table
)

# Retrieve all datastores that are vVols
$VvolDstore = Get-Datastore | Where-Object {$_.Type -eq "VVOL"}

# Retrieve ALL disks, regardless of VM that reside on those datastores
$Disks = Get-HardDisk -Datastore $VvolDstore

# Configure the output fields for the hard disks
$vmname = @{N='VM';E={$_.Parent.Name}}
$scsiid = @{label="ScsiId";expression={$hd = $_;$ctrl = $hd.Parent.Extensiondata.Config.Hardware.Device | where{$_.Key -eq $hd.ExtensionData.ControllerKey}"$($ctrl.BusNumber):$($_.ExtensionData.UnitNumber)"}}
$vvolid = @{label="vVolUuid";expression={$_ | Get-VvolUuidFromHardDisk}}
$favolume = @{label="FaVolume";expression={get-faVolumeNameFromVvolUuid -vvolUUID ($_ | Get-VvolUuidFromHardDisk)}}

# Return all of the disks that are attached to the VM, and then format the output.
$VvolDisks = Get-VM $VM | Get-HardDisk | Where-Object {$_.Filename -in $Disks.Filename} |
Select $vmname, Name, CapacityGB,
@{N='SCSIid';E={
$hd = $_
$ctrl = $hd.Parent.Extensiondata.Config.Hardware.Device | where{$_.Key -eq $hd.ExtensionData.ControllerKey}
"$($ctrl.BusNumber):$($_.ExtensionData.UnitNumber)"
}}, Filename, $vvolid,$favolume,
@{N='DeviceInfo';E={
$hd = $_
$ctrl = $hd.Parent.Extensiondata.Config.Hardware.Device | where{$_.Key -eq $hd.ExtensionData.ControllerKey}
# Using lsscsi to determine the SCSI ID in CentOS - This may be different for different versions of Linux
$GuestScript = "lsscsi -b -s 0:"+$ctrl.BusNumber+":"+$_.ExtensionData.UnitNumber+":0"
$GuestDevice = Invoke-VMScript -ScriptText $GuestScript -Guestuser $GuestUser -GuestPassword $GuestPassword -ScriptType "bash" -VM $_.Parent | Select -ExpandProperty scriptoutput
"$($GuestDevice)"
}}

# If Table is $true, then output as a table.
If ($Table -eq $true) {
$VvolDisks | FT
} else {
$VvolDisks
}
