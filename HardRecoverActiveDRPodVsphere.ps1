#####
# Work in progress 
#####
$vcenter  = vcsa.domain.com
$vcuser   = "administrator@vsphere.local"
$vcpass   = "password"
$username = "pureuser"
$password = "password"
$endpoint = "10.10.12.34"
$podname  = "pod-dr"
$cluster  = "clustername"
$dsname   = "active-dr-ds1"

# Connect to vCenter
Connect-VIserver $vcenter -user $vcuser -password $vcpass

# Promote the DR Site Pod
$promote = "purepod promote $podname"
New-PfaCLICommand -EndPoint $endpoint -CommandText $promote -UserName $username -Password (ConvertTo-SecureString -AsPlainText $password -Force)

# Wait for the DR Site Pod to be promoted
$podstatus = "purepod list $podname"
do {
    Write-Host "Waiting for Pod Promotion"
    Start-Sleep -Milliseconds 500
    $test = New-PfaCLICommand -EndPoint $endpoint -CommandText $podstatus -UserName $username -Password (ConvertTo-SecureString -AsPlainText $pureuser -Force)   
} while ($test | select-string -pattern "promoting")

# Put the hosts in a Cluster variable
$VMHosts = Get-Cluster -Name $Cluster | Get-VMHost

Foreach($VMHost in $VMHosts){

    # Unbound volumes on the current host
    $ubvols = (Get-View (Get-VMhost -Name $VMhost | Get-View).ConfigManager.DatastoreSystem).QueryUnresolvedVmfsVolumes()

    foreach ($vol in $ubvols) {
        $vmpaths = @()
        $Extents = $vol.Extent;
        foreach ($Extent in $Extents) {
          $extPaths = $extPaths + $Extent.DevicePath
         }      
        $resolutionSpec = New-Object VMware.Vim.HostUnresolvedVmfsResolutionSpec[] (1)
        $resolutionSpec[0] = New-Object VMware.Vim.HostUnresolvedVmfsResolutionSpec
        $resolutionSpec[0].extentDevicePath = New-Object System.String[] (1)
        $resolutionSpec[0].extentDevicePath[0] = $extPaths
        $resolutionSpec[0].uuidResolution = "forceMount"

        $dsView = Get-View -Id (Get-View -Id (Get-VMhostStorage $VMhost).Id).MoRef
        $dsView.ResolveMultipleUnresolvedVmfsVolumes($resolutionSpec)
    }
}

$Datastore = Get-Datastore -Name $dsname
$VMhost    = Get-Cluster | Get-VMhost | Select-Object -First 1
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

