#####
# Work in progress
#####
$vcenter  = vcsa.domain.com
$vcuser   = "administrator@vsphere.local"
$vcpass   = "password"
$username = "pureuser"
$password = "pureuser"
$endpoint = "flasharray.testdrive.local"
$podname  = "ADRPOD"
$cluster  = "cluster"
$dsname   = "Pure-iSCSI-Datastore2-ADR"

# Import the Pure Storage PowerShellSDK2
Import-Module PureStoragePowerShellSDK2

# Get Credentials for FlashArray
$cred = Get-Credential -Message "Enter credentials for Pure Array"

# Connect to the FlashArray with the Pure Storage PowerShell SDK2
Connect-Pfa2Array -IgnoreCertificateError -Endpoint $endpoint -Credential $cred

# Connect to vCenter
Connect-VIserver $vcenter -user $vcuser -password $vcpass

# Get the ActiveDR Pod object using the PSPSSDK2
$ADRPOD = Get-Pfa2Pod -Name $podname 


# Promote the Pod in the DR Site
Update-Pfa2Pod -Name $ADRPOD.Name -RequestedPromotionState "promoted"

# Wait for the DR Site Pod to be promoted
$podstatus = "purepod list $podname"
Get-Pfa2Pod -Name $ADRPOD.Name
do {
    Write-Host "Waiting for Pod Promotion"
    Start-Sleep -Milliseconds 500
    $test = Get-Pfa2Pod -Name $ADRPOD.Name
} while ($test.PromotionStatus -ne "promoted")

# Connect to the first VMware host
$VMHost = Get-VMhost | Select-Object -First 1
$EsxCli = Get-EsxCli -VMHost $VMhost -V2

# Look for snapshots
$Snaps = $esxcli.storage.vmfs.snapshot.list.invoke()
if ($Snaps.Count -gt 0) {
    Foreach ($Snap in $Snaps) {
        Write-Host "Snapshot Found: $($Snap.VolumeName)"
        $esxcli.storage.vmfs.snapshot.resignature.invoke(@{volumelabel=$($Snap.VolumeName)})
    }
} else {
    Write-Host "No Snapshot volumes found"
}

$Datastore = Get-Datastore -Name $dsname
$VMFolder  = Get-Folder -Type VM -Name "Discovered virtual machine"

foreach($Datastore in $Datastore) {
    # Searches for .VMX Files in datastore variable
    $ds = Get-Datastore -Name $Datastore | %{Get-View $_.Id}
    $SearchSpec = New-Object VMware.Vim.HostDatastoreBrowserSearchSpec
    $SearchSpec.matchpattern = "*.vmx"
    $dsBrowser = Get-View $ds.browser
    $DatastorePath = "[" + $ds.Summary.Name + "]"
    # Find all .VMX file paths in Datastore variable and filters out .snapshot
    $SearchResults = $dsBrowser.SearchDatastoreSubFolders($DatastorePath,$SearchSpec) | Where-Object {$_.FolderPath -notmatch ".snapshot"} | %{$_.FolderPath + $_.File.Path}
    # Register all .VMX files with vCenter
    foreach($SearchResult in $SearchResults) {
    New-VM -VMFilePath $SearchResult -VMHost $VMHost -Location $VMFolder -RunAsync -ErrorAction SilentlyContinue
   }
}
