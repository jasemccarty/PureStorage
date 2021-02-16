
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
