# Configure our Parameters
[CmdletBinding()]Param(
[Parameter(Mandatory=$True)][string]$VM,
[Parameter(Mandatory=$False)][string]$GuestUser,
[Parameter(Mandatory=$False)][string]$GuestPassword,
[Parameter(Mandatory=$False)][boolean]$Table
)

# If a username/password have not been provided, prompt for them
If ((-Not $GuestUser) -or (-Not $GuestPassword)) {
$VMCred = Get-Credential -Message "Enter credentials for $VM"
} else {
$password = (ConvertTo-SecureString $GuestPassword -AsPlainText -Force)
$VMCred = New-Object System.Management.Automation.PSCredential -ArgumentList ($GuestUser, (ConvertTo-SecureString $GuestPassword -AsPlainText -Force))
}

# Setup the array for the custom data collection 
$DiskOutput = @()

# Return the disks that are attached to the VM
$VMHDS = Get-HardDisk -VM $VM

# Enumerate each of the vmdks that are attached to the VM
Foreach ($VMHD in $VMHDS) {

# Get the current datastore
$Datastore = Get-Datastore -Id $VMHD.ExtensionData.Backing.Datastore

# If the datastore that backs the current vmdk is of type VVOL, then let's do our work
If ($Datastore.Type -eq "VVOL") {

# Get the Pure Array from the vVol Datastore if possible
$FaName = Get-PfaConnectionOfDatastore -Datastore (Get-Datastore -Id $VMHD.ExtensionData.Backing.Datastore)

# Get the controller for the current disk
$CTRL = $VMHD.Parent.ExtensionData.Config.Hardware.Device | Where {$_.Key -eq $VMHD.ExtensionData.ControllerKey}

# Setup the script that is used to pull guest os information for the current disk
# This example executes 'lsscsi' to return CentOS guest information. 
# Adjust as necessary for different flavors of Linux 
$GuestScript = "lsscsi -b -s 0:"+$CTRL.BusNumber+":"+$VMHD.ExtensionData.UnitNumber+":0"

# Execute the script in the guest and store the results in $GuestDevice
$GuestDevice = Invoke-VMScript -ScriptText $GuestScript -GuestCredential $VMCred -ScriptType "bash" -VM $VMHD.Parent | Select -ExpandProperty scriptoutput

# Create the custom object to store our data
$PSObject = New-Object PSObject -Property @{
  VMName = $VMHD.Parent.Name
  HDName = $VMHD.Name
  CapacityGB = $VMHD.CapacityGB
  ScsiId = "$($CTRL.BusNumber):$($VMHD.ExtensionData.UnitNumber)"
  VvolId = $VMHD | Get-VvolUuidFromHardDisk
  FaVolume = Get-faVolumeNameFromVvolUuid -vvolUUID ($VMHD | Get-VvolUuidFromHardDisk) -flasharray $FaName
  DeviceInfo = $GuestDevice
  }

# Add the current record to the DiskOutput array
$DiskOutput += $PSObject

  }
}

# Display as a Table if desire
If ($Table -eq $true) {
$DiskOutput | FT
} else {
$DiskOutput
}
