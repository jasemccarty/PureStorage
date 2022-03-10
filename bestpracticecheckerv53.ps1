<#
*******Disclaimer:**************************************************************
This scripts are offered "as is" with no warranty.  While this script is tested 
and working in my environment, it is recommended that you test this script in a 
test lab before using in a production environment. Everyone can use the scripts/
commands provided here without any written permission, I, Cody Hosterman, and  
Pure Storage, will not be liable for any damage or loss to the system. This 
is not an intrusive script, and wil make no changes to a vSphere environment
************************************************************************

This script will:
-Check for a SATP rule for Pure Storage FlashArrays
-Report correct and incorrect FlashArray rules
-Check for individual devices that are not configured properly

All information logged to a file by default

This can be run directly from PowerCLI or from a standard PowerShell prompt. PowerCLI must be installed on the local host regardless.

Supports:
-FlashArray 400 Series, //XL, //X, //M, & //C
-vCenter 6.5 and later
-PowerCLI 12 or later required. 
-PowerShell Core supported

Notes:
-iSCSI Configurations where Port Binding is not used will throw an error, but are still supported
 Please consult VMware KB article https://kb.vmware.com/s/article/2038869 

For info, refer to https://www.jasemccarty.com/blog/updated-purestorage-fa-bp-checker-for-vsphere/
#>

Param
(
    [Parameter(ValueFromPipeline,Mandatory=$false)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl[]]$EsxiHost,
    [Parameter(ValueFromPipeline,Mandatory=$false)][String]$CanonicalName,
    [Parameter(ValueFromPipeline,Mandatory=$false)][Boolean]$MaxIO=$true,
    [Parameter(ValueFromPipeline,Mandatory=$false)][Boolean]$VAAI=$true,
    [Parameter(ValueFromPipeline,Mandatory=$false)][Boolean]$IscsiTargets=$true,
    [Parameter(ValueFromPipeline,Mandatory=$false)][Boolean]$PortBinding=$true,
    [Parameter(ValueFromPipeline,Mandatory=$false)][Boolean]$NMP=$true,
    [Parameter(ValueFromPipeline,Mandatory=$false)][Boolean]$PureDevices=$true,
    [Parameter(ValueFromPipeline,Mandatory=$false)][ValidateSet("MaxIO","VAAI","IscsiTargets","PortBinding","NMP","PureDevices")][String]$OnlyRun,
    [Parameter(ValueFromPipeline,Mandatory=$false)][Boolean]$Log=$true
)

if ($OnlyRun) {
    Switch ($OnlyRun) {
        "MaxIO" {
            $MaxIO = $true;$VAAI = $false; $IscsiTargets = $false; $PortBinding = $false; $NMP = $false; $PureDevices = $false
        }
        "VAAI" {
            $MaxIO = $false;$VAAI = $true; $IscsiTargets = $false; $PortBinding = $false; $NMP = $false; $PureDevices = $false
        }
        "IscsiTargets" {
            $MaxIO = $false;$VAAI = $false; $IscsiTargets = $true; $PortBinding = $false; $NMP = $false; $PureDevices = $false
        }
        "PortBinding" {
            $MaxIO = $false;$VAAI = $false; $IscsiTargets = $false; $PortBinding = $true; $NMP = $false; $PureDevices = $false
        }
        "NMP" {
            $MaxIO = $false;$VAAI = $false; $IscsiTargets = $false; $PortBinding = $false; $NMP = $true; $PureDevices = $false
        } 
        "PureDevices" {
            $MaxIO = $false;$VAAI = $false; $IscsiTargets = $false; $PortBinding = $false; $NMP = $false; $PureDevices = $true
        }
    }
}

if ($CanonicalName) {
    $PureDevices = $true
}

$iopsvalue = 1
$minpaths = 4
$StartTime = (Get-Date)
if ($Log -eq $true) {
    #Create log if non-existent
    $Currentpath = split-path -parent $MyInvocation.MyCommand.Definition 
    $Logfile = $Currentpath + '\PureStorage-vSphere-' + (Get-Date -Format o |Foreach-Object {$_ -Replace ':', '.'}) + "-checkbestpractices.log"

    Add-Content $Logfile '             __________________________'
    Add-Content $Logfile '            /++++++++++++++++++++++++++\'           
    Add-Content $Logfile '           /++++++++++++++++++++++++++++\'           
    Add-Content $Logfile '          /++++++++++++++++++++++++++++++\'         
    Add-Content $Logfile '         /++++++++++++++++++++++++++++++++\'        
    Add-Content $Logfile '        /++++++++++++++++++++++++++++++++++\'       
    Add-Content $Logfile '       /++++++++++++/----------\++++++++++++\'     
    Add-Content $Logfile '      /++++++++++++/            \++++++++++++\'    
    Add-Content $Logfile '     /++++++++++++/              \++++++++++++\'   
    Add-Content $Logfile '    /++++++++++++/                \++++++++++++\'  
    Add-Content $Logfile '   /++++++++++++/                  \++++++++++++\' 
    Add-Content $Logfile '   \++++++++++++\                  /++++++++++++/' 
    Add-Content $Logfile '    \++++++++++++\                /++++++++++++/' 
    Add-Content $Logfile '     \++++++++++++\              /++++++++++++/'  
    Add-Content $Logfile '      \++++++++++++\            /++++++++++++/'    
    Add-Content $Logfile '       \++++++++++++\          /++++++++++++/'     
    Add-Content $Logfile '        \++++++++++++\'                   
    Add-Content $Logfile '         \++++++++++++\'                           
    Add-Content $Logfile '          \++++++++++++\'                          
    Add-Content $Logfile '           \++++++++++++\'                         
    Add-Content $Logfile '            \------------\'
    Add-Content $Logfile 'Pure Storage FlashArray VMware ESXi Best Practices Checker Script v5.0 (JANUARY-2022)'
    Add-Content $Logfile '----------------------------------------------------------------------------------------------------'
}

#########################################################
# Check PowerShell Version                              #
#########################################################
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

# Set the PowerCLI configuration to ignore incd /self-signed certificates
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$False | Out-Null 

#########################################################
# vCenter Server Selection                              #
#########################################################
# Check to see if a current vCenter Server session is in place
If ($Global:DefaultVIServer) {
    Write-Host "Connected to " -NoNewline 
    Write-Host $Global:DefaultVIServer -ForegroundColor Green
} else {
    # If not connected to vCenter Server make a connection
    Write-Host "Not connected to vCenter Server" -ForegroundColor Red
    $VIFQDN = Read-Host "Please enter the vCenter Server FQDN"  
    # Prompt for credentials using the native PowerShell Get-Credential cmdlet
    $VICredentials = Get-Credential -Message "Enter credentials for vCenter Server" 
    try {
        # Attempt to connect to the vCenter Server 
        Connect-VIServer -Server $VIFQDN -Credential $VICredentials -ErrorAction Stop | Out-Null
        Write-Host "Connected to $VIFQDN" -ForegroundColor Green 
        # Note that we connected to vCenter so we can disconnect upon termination
        $ConnectVc = $True
    }
    catch {
        # If we could not connect to vCenter report that and exit the script
        Write-Host "Failed to connect to $VIFQDN" -BackgroundColor Red
        Write-Host $Error
        Write-Host "Terminating the script " -BackgroundColor Red
        # Note that we did not connect to vCenter Server
        $ConnectVc = $False
        return
    }
}


if ($Log -eq $true) {
# Denote where the log is being written to
    Write-Host ""
    Write-Host "Script result log can be found at $Logfile" -ForegroundColor Green
    Write-Host ""
    Add-Content $Logfile "Connected to vCenter at $($Global:DefaultVIServer)"
    Add-Content $Logfile '----------------------------------------------------------------------------------------------------'
}

#########################################################
# Esxi Host Selection                                   #
#########################################################
# If an ESXi Object (1 or more hosts) is passed, do not prompt for which hosts or clusters.
if ($EsxiHost) {
    $Hosts = $EsxiHost
} else {
    # Choose to run the script against all hosts connected to a vCenter Server, or a single cluster
    Do{ $clusterChoice = Read-Host "Would you prefer to limit this to hosts in a specific cluster? (y/n)" }
    Until($clusterChoice -eq "Y" -or $clusterChoice -eq "N")

    # Choose a single cluster
        if ($clusterChoice -match "[yY]") {
            # Retrieve the clusters & sort them alphabetically 
            $clusters = Get-Cluster | Sort-Object Name

            # If no clusters are found, exit the script
            if ($clusters.count -lt 1)
            {
                if ($Log -eq $true) {Add-Content $Logfile "Terminating Script. No VMware cluster(s) found."} 
                Write-Host "No VMware cluster(s) found. Terminating Script" -BackgroundColor Red
                exit
            }

            # Select the Cluster
            Write-Host "1 or more clusters were found. Please choose a cluster:"
            Write-Host ""

            # Enumerate the cluster(s)
            1..$Clusters.Length | Foreach-Object { Write-Host $($_)":"$Clusters[$_-1]}

            # Wait until a valid cluster is picked
            Do
            {
                Write-Host # empty line
                $Global:ans = (Read-Host 'Please select a cluster') -as [int]
            
            } While ((-not $ans) -or (0 -gt $ans) -or ($Clusters.Length+1 -lt $ans))

            # Assign the $Cluster variable to the Cluster picked
            $Cluster = $clusters[($ans-1)]

            if ($Log -eq $true) {
                # Log/Enumerate which cluser was selected
                Add-Content $Logfile "Selected cluster is $($Cluster)"
                Add-Content $Logfile ""
            }
            Write-Host "Selected cluster is " -NoNewline 
            Write-Host $Cluster -ForegroundColor Green
            Write-Host ""

            # Assign all of the hosts in $Cluster to the $Hosts variable, and sort the list alphabetically
            $Hosts = $Cluster | Get-VMHost | Sort-Object Name 

        }  else {

            # Because individual clusters were not selected
            # Assign all of the hosts vCenter manages into the $Hosts variable & sort them alphabetically
            $Hosts = Get-VMHost | Sort-Object Name 
        }
    } 

# Begin the main execution of the script
$errorHosts = [System.Collections.ArrayList]@()

Write-Host "Executing..."

if ($Log -eq $true) { 
    Add-Content $Logfile "Iterating through all ESXi hosts..."
    $Hosts | Out-String | Add-Content $Logfile
    Add-Content $Logfile "***********************************************************************************************"
}

#Iterating through each host in the vCenter
#########################################################
# Loop through each Esxi Host                           #
#########################################################
$Hosts | Foreach-Object {

    $Esx = $_

    $HostDatastores = $_ | Get-Datastore 

    # Only perform these actions on hosts are available
    If ((Get-VMhost -Name $Esx.Name).ConnectionState -ne "NotResponding") {

        $EsxError = $false

        # Connect to the EsxCli instance for the current host
        $EsxCli = Get-EsxCli -VMHost $Esx -V2

        # Retrieve the current vSphere Host Version/Release/Profile
        # This is neccessary because SATP rules & Disk MaxIO Size 
        # are different for different builds of vSphere 
        $HostVersionMajor = $Esx.Version.Split(".")[0]
        $HostVersionMinor = $Esx.Version.Split(".")[1]
        $HostProfileName  = $EsxCli.software.profile.get.Invoke().name.Split("-")[2]

        # vSphere 6.x requires IOPS=1 & vSphere 7.0 uses the Latency policy
        # DiskMaxIO is 4MB for older versions of vSphere & the default of 32MB for more recent versions
        Switch ($HostVersionMajor) {
            "7" { $MaxIORecommended = "32767";$PspOptions="policy=latency";$SatpType="latency"}
            "5" { $MaxIORecommended = "4096";$PspOptions="iops=1";$SatpType="iops"}
            default {
                Switch ($HostVersionMinor) {
                    "7" { If ($esxcli.system.version.get.invoke().update -ge "1") {$MaxIORecommended = "32767"};$PspOptions="iops=1"}
                    "5" { If ($HostProfileName -ge "201810002") { $MaxIORecommended = "32767"} else {$MaxIORecommended = "4096"};$PspOptions="iops=1"}
                    "0" { If ($HostProfileName -ge "201909001") { $MaxIORecommended = "32767"} else {$MaxIORecommended = "4096"};$PspOptions="iops=1"}
                }
            }
        }
        Write-Host "Started check on ESXi host: " -NoNewLine
        Write-Host "$($Esx.NetworkInfo.hostname)" -ForegroundColor Yellow -NoNewLine
        Write-Host ", version $($Esx.Version)"
        if ($Log -eq $true) {
            Add-Content $Logfile "***********************************************************************************************"
            Add-Content $Logfile " Started check on ESXi host: $($Esx.NetworkInfo.hostname), version $($Esx.Version)"
            Add-Content $Logfile "-----------------------------------------------------------------------------------------------"
            Add-Content $Logfile "  Checking Disk.DiskMaxIoSize setting.    "
        }
        # MaxIO Check - Disk.DiskMaxIOSize 
        if ($MaxIO -eq $true) {
            $TestStart = (Get-Date)
            # Get and check the Max Disk IO Size
            Write-Host "     Checking Disk.DiskMaxIO Size                   " -NoNewLine
            $maxiosize = $Esx | Get-AdvancedSetting -Name Disk.DiskMaxIOSize
            if ($maxiosize.value -ne $MaxIORecommended) {
                $EsxError = $true
                $maxioerror = "(Disk.DiskMaxIOSize Recommended - $($MaxIORecommended))"
                if ($Log -eq $true) { Add-Content $Logfile "    FAIL - Disk.DiskMaxIOSize too high ($($maxiosize.value) KB) - Recommended $MaxIORecommended KB"}
                Write-Host "     MaxIO Done " -NoNewLine
                Write-Host "FAIL " -NoNewLine -ForegroundColor Red
                Write-Host "- $($maxioerror) " -NoNewLine
            }
            else {
                if ($Log -eq $true) { Add-Content $Logfile "    PASS - Disk.DiskMaxIOSize is set properly."}
                Write-Host "     MaxIO Done " -NoNewLine
                Write-Host "PASS " -ForegroundColor Green -NoNewLine
            }
            if ($Log -eq $true) { Add-Content $Logfile "  -------------------------------------------------------"}

            Write-Host "($((Get-Date) - $TestStart))"
        }

        # VAAI Check 
        if ($VAAI -eq $true) {

            $VaaiDetails = [System.Collections.ArrayList]@()

            Write-Host "     Checking VAAI                                  " -NoNewLine
            $TestStart = (Get-Date)
            # Check VAAI Settings
            if ($Log -eq $true) { Add-Content $Logfile "  Checking host-wide settings for VAAI.     " }
            $vaaiIssues = $false

            # Check Xcopy
            $Xcopy = $Esx | Get-AdvancedSetting -Name DataMover.HardwareAcceleratedMove
            if ($Xcopy.value -eq 0) {
                $EsxError = $true;$vaaiIssues = $true
                $XcopyErrorDetail = "(    XCOPY    ) DataMover.HardwareAcceleratedMove - Recommended 1"
                if ($Log -eq $true) { Add-Content $Logfile "    FAIL - $($XcopyErrorDetail)"}
                
                $VaaiDetail = [PSCustomObject][ordered]@{
                    Primitive    = "XCOPY"
                    Check        = "FAIL"
                    ErrorDetail  = $XcopyErrorDetail
                }                
                $null = $VaaiDetails.Add($VaaiDetail)
            } 

            # Check writesame
            $writesame = $Esx | Get-AdvancedSetting -Name DataMover.HardwareAcceleratedInit
            if ($writesame.value -eq 0)
            {
                $EsxError = $true;$vaaiIssues = $true
                $WriteSameErrorDetail = "(  Block Zero ) DataMover.HardwareAcceleratedInit - Recommended 1"
                if ($Log -eq $true) { Add-Content $Logfile "    FAIL - $($WriteSameErrorDetail)"}

                $VaaiDetail = [PSCustomObject][ordered]@{
                    Primitive    = "WriteSame"
                    Check        = "FAIL"
                    ErrorDetail  = $WriteSameErrorDetail
                }                
                $null = $VaaiDetails.Add($VaaiDetail)            
            }

            # Check atslocking
            $atslocking = $Esx | Get-AdvancedSetting -Name VMFS3.HardwareAcceleratedLocking
            if ($atslocking.value -eq 0)
            {
                $EsxError = $true;$vaaiIssues=$true
                $AtsLockingErrorDetail = "( ATS Locking ) VMFS3.HardwareAcceleratedLocking  - Recommended 1"
                if ($Log -eq $true) { Add-Content $Logfile "    FAIL - $($AtsLockingErrorDetail)"}
                
                $VaaiDetail = [PSCustomObject][ordered]@{
                    Primitive    = "ATS Locking"
                    Check        = "FAIL"
                    ErrorDetail  = $AtsLockingErrorDetail
                }                
                $null = $VaaiDetails.Add($VaaiDetail)
            } 

            # CHeck Use ATS for Heartbeat on VMFS5
            if (($null -ne $HostDatastores -ne $null) -and ($HostVersionMajor -ge "6")) { 
                $atsheartbeat = $Esx | Get-AdvancedSetting -Name "VMFS3.useATSForHBOnVMFS5"
                if ($atsheartbeat.value -eq 0)
                {
                    $EsxError = $true;$vaaiIssues=$true
                    $AtsHeartbeatErrorDetail = "(ATS Heartbeat) VMFS3.UseATSForHBOnVMFS5          - Recommended 1"
                    if ($Log -eq $true) { Add-Content $Logfile "    FAIL - $($AtsHeartbeatErrorDetail)"}

                    $VaaiDetail = [PSCustomObject][ordered]@{
                        Primitive    = "ATS Heartbeat"
                        Check        = "FAIL"
                        ErrorDetail  = $AtsHeartbeatErrorDetail
                    }                
                    $null = $VaaiDetails.Add($VaaiDetail)
                } 
            }
            if ($vaaiIssues -eq $false)
            {
                if ($Log -eq $true) { Add-Content $Logfile "    PASS - No issues with VAAI configuration found on this host" }
                Write-Host "     VAAI Done " -NoNewLine 
                Write-Host "PASS " -ForegroundColor Green -NoNewLine
                Write-Host "($((Get-Date) - $TestStart))"
            } else {
                Write-Host "     VAAI Done " -NoNewLine 
                Write-Host "FAIL " -ForegroundColor Red -NoNewLine
                Write-Host "($((Get-Date) - $TestStart))"
                $VaaiDetails | Foreach-Object {
 
                    Write-Host "                FAIL " -ForegroundColor Red -NoNewLine
                    Write-Host "- $($_.ErrorDetail)"
                }

            }
            
        }

        # Iscsi Targets Check
        if ($IscsiTargets -eq $true) {
            $testStart = (Get-Date)  

            # Get a list of all of the Pure Storage iSCSI Targets (if any)
            $targets = $esxcli.iscsi.adapter.target.portal.list.Invoke().where{$_.Target -Like "*purestorage*"}

            # if there are targets, proceed with the iSCSI Checks
            if ($targets.count -gt '0') {
                Write-Host "     Checking iSCSI Targets                         " -NoNewLine
                # Check for iSCSI targets 
                if ($Log -eq $true) {
                    Add-Content $Logfile "  -------------------------------------------------------------------------------------------------------------------------------------------"
                    Add-Content $Logfile "  Checking for FlashArray iSCSI targets and verify their configuration on the host. Only misconfigured iSCSI targets will be reported."
                }
                # Setup our iSCSI Variables
                $iscsitofix = [System.Collections.ArrayList]@()
                $flasharrayiSCSI = $false

                # Store the iSCSI Software Adaper in a variable
                $iscsihba = ($Esx | Get-VMHostHba).Where{$_.Model -eq "iSCSI Software Adapter"}

                # Store any Static targets 
                $statictgts = $iscsihba | Get-IScsiHbaTarget -type static

                # Enumerate through all iSCSI targets
                $targets | Foreach-Object {
                    $target = $_
                    $flasharrayiSCSI = $true

                    # Check for DelayedACK = False and LoginTimeout = 30 in each static target
                    ($statictgts).Where{$_.Address -eq $target.IP} | Foreach-Object {

                        $statictgt = $_

                        # Retrieve DelayedACK & LoginTimeout values
                        $iscsiack     = ($statictgt.ExtensionData.AdvancedOptions).Where{$_.Key -eq "DelayedAck"}
                        $iscsitimeout = ($statictgt.ExtensionData.AdvancedOptions).Where{$_.Key -eq "LoginTimeout"}

                        if ($iscsiack.value -eq $true) {
                                $DelayedAck = "Enabled"
                                if ($iscsiack.IsInherited -eq $true) {
                                    $Option = "DelayedAck (Inherited)"
                                } else {
                                    $Option = "DelayedAck"
                                }
                                # Create an object to better report iSCSI targets
                                $iscsitgttofix = [PSCustomObject][ordered]@{
                                    TargetIP = $target.IP
                                    TargetIQN = $target.Target
                                    Option    = $Option
                                    Value     = " Enabled - Recommended Disabled"
                                    }
                        $null = $iscsitofix.add($iscsitgttofix)
                        } 
                        if ($iscsitimeout.value -ne '30') {
                            if ($iscsitimeoutpass.IsInherited -eq $true) {
                                $iSCSIOption = "LoginTimeout (Inherited)"
                            } else {
                                $IscsiOption = "LoginTimeout"
                            }
                            # Create an object to better report iSCSI targets
                            $iscsitgttofix = [PSCustomObject][ordered]@{
                                TargetIP = $target.IP
                                TargetIQN = $target.Target
                                Option    = $IscsiOption
                                Value     = " $($iscsitimeout.value) - Recommended 30"
                                }
                        $null = $iscsitofix.add($iscsitgttofix)
                        }

                    }
                }

                # If there are any iSCSI targets with issues, report them here
                if ($iscsitofix.count -ge 1)
                {
                    Write-Host "     iSCSI Targets Done " -NoNewLine 
                    Write-Host "FAIL " -ForegroundColor Red -NoNewLine
                    Write-Host "($((Get-Date) - $TestStart))"

                    $EsxError = $true
                    $iscsitofix | Sort-Object -Property TargetIQN,TargetIP | Foreach-Object {
                        Write-Host "                FAIL " -NoNewLine -ForegroundColor Red
                        Write-Host "- IP: " -NoNewLine
                        Write-Host "$($_.TargetIP)" -NoNewLine -ForegroundColor Yellow
                        Write-Host " - IQN: " -NoNewLine
                        Write-Host "$($_.TargetIQN) " -NoNewLine -ForegroundColor Yellow
                        Write-Host "-Option: " -NoNewLine
                        Write-Host "$($_.Option)$($_.value)" -ForegroundColor Yellow
                    }
                    if ($Log -eq $true) {
                        Add-Content $Logfile ("    FAIL - A total of " + ($iscsitofix | select-object -unique).count + " FlashArray iSCSI targets have one or more errors.")
                        Add-Content $Logfile  "    Each target listed has an issue with at least one of the following configurations:"
                        Add-Content $Logfile ("    --The target does not have DelayedAck disabled")
                        Add-Content $Logfile ("    --The target does not have the iSCSI Login Timeout set to 30")
                    }
                    $tableofiscsi = @(
                                    'TargetIP'
                                        @{Label = '    TargetIQN'; Expression = {$_.TargetIQN}; Alignment = 'Left'} 
                                        @{Label = '    DelayedAck'; Expression = {$_.DelayedAck}; Alignment = 'Left'}
                                        @{Label = '    LoginTimeout'; Expression = {$_.LoginTimeout}; Alignment = 'Left'}
                                    )
                    $iscsitofix | Format-Table -Property $tableofiscsi -AutoSize| Out-String | Add-Content $Logfile
                } else {
                    Write-Host "     iSCSI Targets Done " -NoNewLine 
                    Write-Host "PASS " -ForegroundColor Green -NoNewLine
                    Write-Host "($((Get-Date) - $TestStart))"
    
                    if ($Log -eq $true) {
                        Add-Content $Logfile "  -------------------------------------------------------------------------------------------------------------------------------------------"
                        Add-Content $Logfile "  Checking for FlashArray iSCSI targets and verify their configuration on the host. Only misconfigured iSCSI targets will be reported."
                        Add-Content $Logfile "     PASS - No FlashArray iSCSI targets were found with configuration issues."
                    }
                }

            } else {

                Write-Host "     iSCSI Targets Done " -NoNewLine 
                Write-Host "PASS " -ForegroundColor Green -NoNewLine
                Write-Host "($((Get-Date) - $TestStart))"

                if ($Log -eq $true) {
                    Add-Content $Logfile "  -------------------------------------------------------------------------------------------------------------------------------------------"
                    Add-Content $Logfile "  Checking for FlashArray iSCSI targets and verify their configuration on the host. Only misconfigured iSCSI targets will be reported."
                    Add-Content $Logfile "     PASS - No FlashArray iSCSI targets were found with configuration issues."
                }
            }

        }

        # Iscsi Port Binding Check
        if ($PortBinding -eq $true) {

            If ($IscsiTargets -eq $false) {
                # Get a list of all of the Pure Storage iSCSI Targets (if any)
                # Specifying here because the iSCSI Targets Check was not performed
                Write-Host "Getting iSCSI Targets"
                $targets = $esxcli.iscsi.adapter.target.portal.list.Invoke().where{$_.Target -Like "*purestorage*"}
                if ($targets.count -ge '1') {
                    $flasharrayiSCSI = $true
                } else {
                    $flasharrayiSCSI = $false
                }
            }

            if ($targets.count -gt '0') {

                Write-Host "     Checking iSCSI Port Binding                    " -NoNewLine
                $TestStart = (Get-Date)

                # Check for network port binding configuration
                if ($flasharrayiSCSI -eq $true)
                {
                    $iSCSInics = $Esxcli.iscsi.networkportal.list.invoke()
                    $goodnics = [System.Collections.ArrayList]@()
                    $badnics = [System.Collections.ArrayList]@()

                    # Check to see if any iSCSI Nics are Bound
                    if ($iSCSInics.Count -gt 0) {
                        #Foreach ($iSCSInic in $iSCSInics) {
                        $iSCSInics | Foreach-Object {
                            $iSCSInic = $_
                            if (($iSCSInic.CompliantStatus -eq "compliant") -and (($iSCSInic.PathStatus -eq "active") -or ($iSCSInic.PathStatus -eq "unused")))
                            {
                                #$goodnics += $iSCSInic
                                $null = $goodnics.add($iSCSInic)
                            }
                            else
                            {
                                #$badnics += $iSCSInic
                                $null = $badnics.add($iSCSInic)
                            }
                        }
                    
                        if ($goodnics.Count -lt 2)
                        {
                            if ($Log -eq $true) { 
                                Add-Content $Logfile ("    Found " + $goodnics.Count + " COMPLIANT AND ACTIVE NICs out of a total of " + $iSCSInics.Count + "NICs bound to this adapter")
                                Add-Content $Logfile "      FAIL - There are less than two COMPLIANT and ACTIVE NICs bound to the iSCSI software adapter. It is recommended to have two or more."
                            }
                            $nicstofix = [System.Collections.ArrayList]@()
                            $EsxError = $true
                            
                            if ($badnics.count -ge 1)
                            {
                                #Foreach ($badnic in $badnics) {
                                $badnics | Foreach-Object {
                                    $badnic = $_
                                    $nictofix = [PSCustomObject][ordered]@{
                                                vmkName = $badnic.Vmknic
                                                CompliantStatus = $badnic.CompliantStatus
                                                PathStatus = $badnic.PathStatus 
                                                vSwitch  = $badnic.Vswitch
                                                }
                                    #$nicstofix += $nictofix
                                    $null = $nicstofix.add($nictofix)
                                }
                                $tableofbadnics = @(
                                                'vmkName'
                                                    @{Label = '    ComplianceStatus'; Expression = {$_.CompliantStatus}; Alignment = 'Left'} 
                                                    @{Label = '    PathStatus'; Expression = {$_.PathStatus}; Alignment = 'Left'}
                                                    @{Label = '    vSwitch'; Expression = {$_.vSwitch}; Alignment = 'Left'}
                                                )
                                if ($Log -eq $true) { 
                                    Add-Content $Logfile "      FAIL - There are less than two COMPLIANT and ACTIVE NICs bound to the iSCSI software adapter. It is recommended to have two or more."
                                    Add-Content $Logfile "    The following are NICs that are bound to the iSCSI Adapter but are either NON-COMPLIANT, INACTIVE or both. Or there is less than 2."
                                $nicstofix | Format-Table -property $tableofbadnics -autosize| out-string | Add-Content $Logfile 
                                }
                            }
                        }
                        else 
                        {
                            if ($Log -eq $true) { Add-Content $Logfile ("      Found " + $goodnics.Count + " NICs that are bound to the iSCSI Adapter and are COMPLIANT and ACTIVE. No action needed.")}
                        }
                        Write-Host "     Done " -NoNewLine 
                        Write-Host "PASS " -ForegroundColor Green -NoNewLine
                        Write-Host "($((Get-Date) - $TestStart))"
                    }
                    else
                    {
                        $EsxError = $true
                        if ($Log -eq $true) { Add-Content $Logfile "   FAIL - There are ZERO NICs bound to the software iSCSI adapter. This is strongly discouraged. Please bind two or more NICs"}
                        Write-Host "     Done " -NoNewLine 
                        Write-Host "FAIL " -ForegroundColor Yellow -NoNewLine
                        Write-Host "(0 NICs bound to the iSCSI Adapter) Pleave Review ($((Get-Date) - $TestStart))"
                    }
                } else {
                    #Write-Host "No iSCSI Targets"
                    if ($Log -eq $true) { Add-Content $Logfile "    No FlashArray iSCSI targets found on this host"}
                    Write-Host "     Done " -NoNewLine 
                    Write-Host " N/A " -ForegroundColor Yellow -NoNewLine
                    Write-Host "($((Get-Date) - $TestStart))"
        
                } # End $FlashArrayiSCSITRue
    
            }



        }

            # Check the NMP rules
        if ($NMP -eq $true) {

            $RuleDetails = [System.Collections.ArrayList]@()

            Write-Host "     Checking Native Multipathing Plugin            " -NoNewLine
            $TestStart = (Get-Date)
            if ($Log -eq $true) { 
                Add-Content $Logfile "  -------------------------------------------------------------------------------------------------------------------------------------------"
                Add-Content $Logfile "  Checking VMware NMP Multipathing configuration for FlashArray devices."
            }
            $correctrule = 0

            # Retrieve NMP Rules. Sort by RuleGroup to check for System Rules first
            $rules = ($Esxcli.storage.nmp.satp.rule.list.invoke()).Where{$_.Vendor -eq "PURE"} | Sort-Object RuleGroup
            $systemrulepresent = $false 

            If ($rules.count -lt '1') {
                #No rules
                
                $PspDetail = [PSCustomObject][ordered]@{
                    PSP   = ""
                    Pass  = $false 
                    }

                $SatpDetail = [PSCustomObject][ordered]@{
                    SATP  = ""
                    Pass  = $false 
                    }
                    
                $ModelDetail = [PSCustomObject][ordered]@{
                    Model = ""
                    Pass  = $false 
                    }

                $RuleDetail = [PSCustomObject][ordered]@{
                    RuleGroup    = ""
                    Vendor       = ""
                    Model        = ""
                    PSP          = $PspDetail
                    SATP         = $SatpDetail
                    Recommended  = $false
                    Reason       = "No FlashArray Rule Present"
                }

                $null = $RuleDetails.Add($RuleDetail)
 
            } else {
                #At least 1 rule

                # If vSphere 7, default to Latency, otherwise use IOPS=1
                Switch ($HostVersionMajor) {
                    "7" { $SatpOption = "policy";$SatpType="latency"}
                    default { $SatpOption = "iops";$SatpType="iops";$iopsoption="iops="+$iopsvalue}
                }

                $rules | Foreach-Object {
                    $rule = $_

                    if ($Log -eq $true) { 
                        Add-Content $Logfile "   -----------------------------------------------"
                        Add-Content $Logfile ""
                        Add-Content $Logfile "      Checking the following existing rule:"
                        ($rule | out-string).TrimEnd() | Add-Content $Logfile
                        Add-Content $Logfile ""
                    }
                    $issuecount = 0

                    # Is it a User Rule? It is required for vSphere 5.x, and might be ok for vSphere 6.0 if a system rule doesn't exist
                    Switch ($rule.RuleGroup) {
                        'user' {

                            # Check to see if the system rule exists. If a system rule exists, the user rule is not necessary
                            if ($systemrulepresent -eq $true) { $Recommended = $false;$Reason = "System Rule Present";$issuecount=1 } else { $Recommended = $true;$Reason = "System Rule Absent";$correctrule=$true }

                            # Path Selection Policy Check - This should be Round Robin for vSphere 6.5/6.7/7.0
                            if ($rule.DefaultPSP -ne "VMW_PSP_RR") {
                                $EsxError = $true
                                if ($Log -eq $true) { 
                                    Add-Content $Logfile "      FAIL - This Pure Storage FlashArray user rule is NOT configured with the correct Path Selection Policy: $($rule.DefaultPSP)"
                                    Add-Content $Logfile "      The rule should be configured to Round Robin (VMW_PSP_RR)"
                                }
                                $issuecount = $issuecount+1
                                $RulePspOk = $false 

                                $SatpDetail = [PSCustomObject][ordered]@{
                                    SATP  = ""
                                    Pass  = $false 
                                }

                            } else { 
                                $RulePspOk = $true
                            }
                            $PspDetail = [PSCustomObject][ordered]@{
                                PSP   = $rule.DefaultPSP
                                Pass  = $RulePspOk 
                                }

                            # SATP User Rule Check
                            if ($rule.PSPOptions -ne $iopsoption) 
                            {
                                $EsxError = $true
                                if ($Log -eq $true) { 
                                    Add-Content $Logfile "      FAIL - This Pure Storage FlashArray user rule is NOT configured with the correct IO Operations Limit: $($rule.PSPOptions)"
                                    Add-Content $Logfile "      The rule should be configured to an IO Operations Limit of $($iopsvalue)"
                                }
                                $issuecount  = $issuecount + 1
                                $RuleSatpOk  = $false
                                $Recommended = $false
                                $Reason      = "IOPS Recommended 1"  
                            } else { $RuleSatpOk = $true}
                            $SatpDetail = [PSCustomObject][ordered]@{
                                SATP  = $rule.PSPOptions
                                Pass  = $RuleSatpOk 
                                }

                            if ($rule.Model -ne "FlashArray") {
                                $EsxError = $true
                                if ($Log -eq $true) { 
                                    Add-Content $Logfile "      FAIL - This Pure Storage FlashArray rule is NOT configured with the correct model: $($rule.Model)"
                                    Add-Content $Logfile "      The rule should be configured with the model of FlashArray"
                                }
                                $issuecount = $issuecount + 1
                                $RuleModelOk = $false 
                            } else { $RuleModelOk = $true }
                            $ModelDetail = [PSCustomObject][ordered]@{
                                Model = $rule.Model
                                Pass  = $RuleModelOk 
                                }

                            $RuleDetail = [PSCustomObject][ordered]@{
                                RuleGroup    = $rule.RuleGroup
                                Vendor       = "PURE"
                                Model        = $ModelDetail
                                PSP          = $PspDetail
                                SATP         = $SatpDetail
                                Recommended  = $Recommended
                                Reason       = $Reason
                                }


                            $null = $RuleDetails.Add($RuleDetail)

                        }
                        default {

                            $systemrulepresent = $true

                            $PspDetail = [PSCustomObject][ordered]@{
                                PSP   = $rule.DefaultPSP
                                Pass  = $true 
                                }
    
                            $SatpDetail = [PSCustomObject][ordered]@{
                                SATP  = $rule.PSPOptions
                                Pass  = $true 
                                }
                                
                            $ModelDetail = [PSCustomObject][ordered]@{
                                Model = $rule.Model
                                Pass  = $true 
                                }
    
                            $RuleDetail = [PSCustomObject][ordered]@{
                                RuleGroup    = $rule.RuleGroup
                                Vendor       = "PURE"
                                Model        = $ModelDetail
                                PSP          = $PspDetail
                                SATP         = $SatpDetail
                                Recommended  = $true
                                Reason       = "System Rule"
                            }
                                $null = $RuleDetails.Add($RuleDetail)
                                $correctrule = $true
                        }
                    }

                } # End Rules Loop

                if ($Log -eq $true) { 
                    Add-Content $Logfile ("   Found " + $rules.Count + " existing Pure Storage SATP rule(s)")
                }
                if ($rules.count -gt 1) {
                    $EsxError = $true
                    if ($Log -eq $true) { 
                        Add-Content $Logfile "    CAUTION - There is more than one rule. User rules found will override any system rules. Ensure this is intentional."
                    }
                }
            } # End Rules Greater than 1

            #$RuleDetails |FT

            Write-Host "     Done " -NoNewLine 

            if ($issuecount -gt 0) {
                Write-Host "FAIL " -ForegroundColor Red -NoNewLine
                Write-Host "($((Get-Date) - $TestStart))"
                $RuleDetails.Where{$_.Recommended -eq $false} | Foreach-Object {
                    Write-Host "      FAIL " -ForegroundColor Red -NoNewLine
                    Write-Host "- User Rule - " -NoNewLine
                    Write-Host "Model: " -NoNewLine
                    Write-Host "$($_.Model.Model) " -NoNewLine -ForegroundColor Yellow
                    Write-Host "PSP: " -NoNewLine
                    Write-Host "$($_.PSP.PSP) " -NoNewLine -ForegroundColor Yellow
                    Write-Host "SATP: " -NoNewLine
                    Write-Host "$($_.SATP.SATP) " -NoNewLine -ForegroundColor Yellow
                    Write-Host "Reason: " -NoNewLine
                    Write-Host "$($_.Reason)" -ForegroundColor Red
                }
            } else {
                Write-Host "PASS " -ForegroundColor Green -NoNewLine
                Write-Host "($((Get-Date) - $TestStart))"
            }

        }

        $HostView = Get-View -ViewType HostSystem -Property Name,Config.StorageDevice,Config.MultipathState -Filter @{"Name"="$($esx.name)"}
        $devicemp = ($HostView.Config.StorageDevice.MultipathInfo.Lun)

        if ($CanonicalName) {
            $devices = ($HostView.Config.StorageDevice.ScsiLun).Where{$_.CanonicalName -Like $CanonicalName}
        } else {
            $devices = ($HostView.Config.StorageDevice.ScsiLun).Where{$_.CanonicalName -Like "naa.624a9370*"}
        }

        if ($PureDevices -eq $true) {
            if ($devices.count -ge 1) {
                $TestStart = (Get-Date)
                Write-Host "     Checking $($devices.count) Pure Storage Devices                 " -NoNewLine

                if ($Log -eq $true) { 
                    Add-Content $Logfile "   -------------------------------------------------------------------------------------------------------------------------------------------"
                    Add-Content $Logfile "   Checking for existing Pure Storage FlashArray devices and their multipathing configuration."
                    Add-Content $Logfile ("      Found " + $devices.count + " existing Pure Storage volumes on this host.")
                    Add-Content $Logfile "      Checking their configuration now. Only listing devices with issues."
                    Add-Content $Logfile "      Checking for Path Selection Policy, Path Count, Storage Array Type Plugin Rules, and AutoUnmap Settings"
                    Add-Content $Logfile ""
                }
                $devstofix = [System.Collections.ArrayList]@()

                $devices | Foreach-Object {

                    $device = $_;$devpsp = $false;$deviops = $false;$devpaths = $false;$devATS = $false;$datastore = $null;$autoUnmap = $false;
                    #Write-Host "Device: $($device.key)"
                    #Write-Host "DeviceMP: $($devicemp)"

                    $lunpathing = ($devicemp).where{$_.lun -eq $device.key}
 
                    #Write-Host "Lun Pathing: $($lunpathing.policy.policy)"
                    
                    #if ($device.MultipathPolicy -ne "RoundRobin")
                    if ($lunpathing.Policy.Policy -ne "VMW_PSP_RR")
                    {
                        $devpsp = $true
                        $psp = $lunpathing.Policy.Policy 
                        $psp = "$psp" + "*"

                        Switch ($HostVersionMajor) {
                            "7" {
                                if ($deviceconfig.LimitType -ne "Latency")
                                {
                                    $deviops = $true
                                    $iops = $deviceconfig.LimitType
                                    $iops = $iops + "*"
                                }
                                else
                                { $iops = $deviceconfig.LimitType }
                            }
                            default {
                                if ($deviceconfig.IOOperationLimit -ne $iopsvalue)
                                {
                                    $deviops = $true
                                    $iops = $deviceconfig.IOOperationLimit
                                    $iops = $iops + "*"
                                }
                                else
                                { $iops = $deviceconfig.IOOperationLimit }
                            }
                        }

                    }
                    else
                    {
                        $deviceargs = $Esxcli.storage.nmp.psp.roundrobin.deviceconfig.get.createargs()
                        $deviceargs.device = $device.CanonicalName
                        $deviceconfig = $Esxcli.storage.nmp.psp.roundrobin.deviceconfig.get.invoke($deviceargs)
                        $psp = $lunpathing.Policy.Policy 
                        $iops = "Not Available"
                    }

                    #$scsipathcount = ($device | Get-ScsiLunPath).count
                    $scsipathcount = $lunpathing.path.count

                    if ($scsipathcount -lt $minpaths)
                    {
                        $devpaths = $true
                        $paths = $scsipathcount
                        $paths = "$paths" + "*"
                    }
                    else
                    {
                        $paths = $scsipathcount
                    }

                    #Write-Host "CanonicalName: $($device.CanonicalName)"
                    $datastore = $HostDatastores.Where{$_.ExtensionData.Info.Vmfs.Extent.DiskName -eq $device.CanonicalName }
                    #Write-Host "Datastore: $($datastore)"
                    #exit
                    if (($datastore -ne $null) -and ($Esx.version -like ("6.*")))
                    {
                        $vmfsargs = $Esxcli.storage.vmfs.lockmode.list.CreateArgs()
                        $vmfsargs.volumelabel = $datastore.name
                        try {
                            $vmfsconfig = $Esxcli.storage.vmfs.lockmode.list.invoke($vmfsargs)
        
                            if ($vmfsconfig.LockingMode -ne "ATS")
                            {
                                $devATS = $true
                                $ATS = $vmfsconfig.LockingMode
                                $ATS = $ATS + "*" 
                            }
                            else
                            {
                                $ATS = $vmfsconfig.LockingMode
                            }
                        } 
                        catch {
                            $ATS = "Not Available"
                        }
        
        
                        if ($datastore.ExtensionData.info.vmfs.version -like "6.*")
                        {
                            $unmapargs = $Esxcli.storage.vmfs.reclaim.config.get.createargs()
                            $unmapargs.volumelabel = $datastore.name

                            try {
                                $unmapresult = $Esxcli.storage.vmfs.reclaim.config.get.invoke($unmapargs)
                                if ($unmapresult.ReclaimPriority -ne "low")
                                {
                                    $autoUnmap = $true
                                    $autoUnmapPriority = "$($unmapresult.ReclaimPriority)*"
                                }
                                elseif ($unmapresult.ReclaimPriority -eq "low")
                                {
                                    $autoUnmapPriority = "$($unmapresult.ReclaimPriority)"
                                }
        
                                $autoUnmap = $False
                                $autoUnmapPriority = "$($unmapresult)"
                            }
                            catch {
                                $autoUnmap = $False
                                $autoUnmapPriority = "Not Available"
                            }
                        }
                        else 
                        {
                            
                        }
                    }
                    if ($deviops -or $devpsp -or $devpaths -or $devATS -or $autoUnmap)
                    {
                        $devtofix = [PSCustomObject][ordered]@{
                            NAA = $device.CanonicalName
                            PSP = $psp 
                            SATP = $iops
                            PathCount  = $paths
                            DatastoreName = if ($datastore -ne $null) {$datastore.Name}else{"N/A"}
                            VMFSVersion = if ($datastore -ne $null) {$datastore.ExtensionData.info.vmfs.version}else{"N/A"}
                            ATSMode = if (($datastore -ne $null) -and ($Esx.version -like ("6.*"))) {$ATS}else{"N/A"}
                            AutoUNMAP = if (($datastore -ne $null) -and ($datastore.ExtensionData.info.vmfs.version -like "6.*")) {$autoUnmapPriority}else{"N/A"}
                        }

                        $null = $devstofix.Add($devtofix)
                    }
                }
                if ($devstofix.count -ge 1)
                {
                    $EsxError = $true
                    if ($Log -eq $true) { 
                        Add-Content $Logfile ("      FAIL - A total of " + $devstofix.count + " FlashArray devices have one or more errors.")
                        Add-Content $Logfile  ""
                        Add-Content $Logfile  "       Each device listed has an issue with at least one of the following configurations:"
                        Add-Content $Logfile  "       --Path Selection Policy is not set to Round Robin (VMW_PSP_RR)"
                        Add-Content $Logfile ("       --IO Operations Limit (IOPS) is not set to the recommended value (" + $iopsvalue + ")")
                        Add-Content $Logfile ("       --The device has less than the minimum recommended logical paths (" + $minpaths + ")")
                        Add-Content $Logfile ("       --The VMFS on this device does not have ATSonly mode enabled.")
                        Add-Content $Logfile ("       --The VMFS-6 datastore on this device does not have Automatic UNMAP enabled. It should be set to low.")
                        Add-Content $Logfile  ""
                        Add-Content $Logfile "        Settings that need to be fixed are marked with an asterisk (*)"
                }
        
                    $tableofdevs = @(
                                    'NAA' 
                                        @{Label = 'PSP'; Expression = {$_.PSP}; Alignment = 'Left'}
                                        @{Label = 'PathCount'; Expression = {$_.PathCount}; Alignment = 'Left'}
                                        @{Label = 'Storage Rule'; Expression = {$_.SATP}; Alignment = 'Left'}
                                        @{Label = 'DatastoreName'; Expression = {$_.DatastoreName}; Alignment = 'Left'}
                                        @{Label = 'VMFSVersion'; Expression = {$_.VMFSVersion}; Alignment = 'Left'}
                                        @{Label = 'ATSMode'; Expression = {$_.ATSMode}; Alignment = 'Left'}
                                        @{Label = 'AutoUNMAP'; Expression = {$_.AutoUNMAP}; Alignment = 'Left'}
                                    )
                    if ($Log -eq $true) {($devstofix | Format-Table -property $tableofdevs -autosize| out-string).TrimEnd() | Add-Content $Logfile}
                }
                else
                {
                    if ($Log -eq $true) { Add-Content $Logfile "      PASS - No devices were found with configuration issues."}
                }
                Write-Host "   Done ($((Get-Date) - $TestStart))"
            }
            else
            {
                if ($Log -eq $true) { Add-Content $Logfile "      No existing Pure Storage volumes found on this host."}
            }
        }
        Write-Host "     $($ESX) Done"
        Write-Host " "                              

        if ($Log -eq $true) { 
            Add-Content $Logfile ""
            Add-Content $Logfile " Completed check on ESXi host: $($Esx.NetworkInfo.hostname)"
            Add-Content $Logfile "***********************************************************************************************"
        }
        if ($EsxError -eq $true)
        {
            #$errorHosts += $Esx
            $null = $errorHosts.add($Esx)
        }

    } # End of Hosts that are online
    else {
        $EsxError = $true
        #$errorHosts += $Esx
        $null = $errorHosts.add($Esx)
    }
} # End of Enumerating $Hosts
if ($errorHosts.count -gt 0 -and $Log -eq $true)
{
    $tempText = Get-Content $Logfile
    "The following hosts have errors. Search for ****NEEDS ATTENTION**** for details" |Out-File $Logfile
    Add-Content $Logfile $errorHosts
    Add-Content $Logfile $tempText
    Add-Content $Logfile ""
    Add-Content $Logfile ""
}
    If ($ConnectVc -eq $true) {
        Disconnect-VIserver -Server $VIFQDN -confirm:$false
        Add-Content $Logfile "Disconnected vCenter connection"
    }

 Write-Host "Check complete."
 Write-Host ""
 if ($errorHosts.count -gt 0)
 {
    Write-Host "Errors on the following hosts were found:"
    Write-Host "==========================================="
    Write-Host $errorHosts
 }
 else 
 {
    Write-Host "No errors were found."    
 }
 Write-Host ""
 if ($Log -eq $true) {  Write-Host "Refer to log file for detailed results." -ForegroundColor Green }
 
 $EndTime = (Get-Date)
Write-Host "This script took $($EndTime - $StartTime) to run"
