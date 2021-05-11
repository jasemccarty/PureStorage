# Check to see if a current ESXi Server session is in place
If ($Global:DefaultVIServer) {
    Write-Host "Connected to " -NoNewline 
    Write-Host $Global:DefaultVIServer -ForegroundColor Green
    If ($Global:DefaultVIServer.ProductLine -ne "embeddedEsx") {
        Write-Host "This is not an ESXi host. Please connect to an individual ESXi host"
        return
    }
} else {
    Write-Host "Not connected to an ESXi host" -ForegroundColor Red
    $VIFQDN = Read-Host "Please enter the ESXi host FQDN"  
    $VICredentials = Get-Credential -Message "Enter credentials for the ESXi host" 
    try {
        Connect-VIServer -Server $VIFQDN -Credential $VICredentials -ErrorAction Stop | Out-Null
        Write-Host "Connected to $VIFQDN" -ForegroundColor Green 
        If ($Global:DefaultVIServer.ProductLine -ne "embeddedEsx") {
            Write-Host "This is not an ESXi host. Please connect to an individual ESXi host"
            return
        } 
    }
    catch {
        Write-Host "Failed to connect to $VIFQDN" -BackgroundColor Red
        Write-Host $Error
        Write-Host "Terminating the script " -BackgroundColor Red
        return
    }
}


$EsxCli = Get-EsxCli -VMHost (Get-VMhost) -V2

$Snaps = $esxcli.storage.vmfs.snapshot.list.invoke()

if ($Snaps.Count -gt 0) {
    Foreach ($Snap in $Snaps) {
        Write-Host "Snapshot Found: $($Snap.VolumeName)"
        $esxcli.storage.vmfs.snapshot.resignature.invoke(@{volumelabel=$($Snap.VolumeName)})
    }
} else {
    Write-Host "No Snapshot volumes found"
}
