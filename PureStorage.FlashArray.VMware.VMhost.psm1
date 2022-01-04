$ErrorActionPreference = 'Stop'

Function Get-PureVmHostRecommendations
{
    <#
    .SYNOPSIS
        Return the Pure Storage FlashArray Recommendations for a vSphere Host
    .DESCRIPTION
        Query the ESXi Host and return the appropriate Recommendations

    .INPUTS
        (Required) A vSphere Host or Hosts Object returned from the Get-VMhost PowerCLI cmdlet
    .OUTPUTS
        Host, Host Version, Host Profile, SATP Rule Type Recommendation, and Disk.DiskMaxIOSize Recommendation
    .EXAMPLE
        PS C:\ Get-PureVmHostRecommendations -EsxiHost (Get-VMhost -Name "esxihost.fqdn") 
        
        Returns the Host info & recommendations for ESXi Host named 'esxihost.fqdn'
    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostRecommendations -EsxiHost $VMhosts
        
        VMHost           : esxi01.fqdn
        HostVersion      : 6.7.0
        HostProfile      : 20191204001      
        RuleType         : iops
        RuleOptions      : iops=1
        MaxIORecommended : 32767
        LimitType        : Default
        IOPLimit         : 1

        VMHost           : esxi02.fqdn
        HostVersion      : 6.7.0
        HostProfile      : 20191204001      
        RuleType         : iops
        RuleOptions      : iops=1
        MaxIORecommended : 32767
        LimitType        : Default
        IOPLimit         : 1


        Returns the Host info & recommendations for all ESXi hosts in the $VMhosts variable
    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostRecommendations -EsxiHost $VMhosts | Format-Table
        
        VMHost            HostVersion HostProfile RuleType RuleOptions MaxIORecommended
        ------            ----------- ----------- -------- ----------- ----------------
        esxi01.fqdn       6.7.0       20191204001 iops     iops=1      32767
        esxi02.fqdn       6.7.0       20191204001 iops     iops=1      32767

        Returns the Host info & recommendations for all ESXi hosts in the $VMhosts variable

    .NOTES
        Version:        1.0
        Author:         Jase McCarty https://jasemccarty.com
        Creation Date:  1/3/2022
    *******Disclaimer:******************************************************
    This script are offered "as is" with no warranty.  While this script is 
    tested and working in my environment, it is recommended that you test this 
    script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>

    [CmdletBinding()]
    Param
    (
        [Parameter(ValueFromPipeline,Mandatory)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl[]]$EsxiHost
    )

   BEGIN
    {
        $VMHostVersionInfo = @()
    }
    PROCESS
    {

            # Loop through the EsxiHosts passed
            Foreach ($VMhost in $EsxiHost) {

                # Create our EsxCli context for the current host
                $EsxCli = Get-EsxCli -VMHost $VMhost -V2

                # Retrieve the current vSphere Host Version/Release/Profile
                # This is neccessary because SATP rules & Disk MaxIO Size are different for different builds of vSphere 
                $HostVersionMajor = $VMhost.Version.Split(".")[0]
                $HostVersionMinor = $VMhost.Version.Split(".")[1]
                $HostProfileName  = $esxcli.software.profile.get.Invoke().name.Split("-")[2]

                # vSphere 6.x requires IOPS=1 & vSphere 7.0 uses the Latency policy
                # DiskMaxIO is 4MB for older versions of vSphere & the default of 32MB for more recent versions
                Switch ($HostVersionMajor) {
                    "7" { $MaxIORecommended = "32767";$PspOptions="policy=latency";$SatpType="latency";$LimitType="Latency";$IOPLimit="0"}
                    "5" { $MaxIORecommended = "4096";$PspOptions="iops=1";$SatpType="iops";$LimitType="Default";$IOPLimit="1"}
                    default {
                        Switch ($HostVersionMinor) {
                            "7" { If ($esxcli.system.version.get.invoke().update -ge "1") {$MaxIORecommended = "32767"};$PspOptions="iops=1";$SatpType="iops";$LimitType="Default";$IOPLimit="1"}
                            "5" { If ($HostProfileName -ge "201810002") { $MaxIORecommended = "32767"} else {$MaxIORecommended = "4096"};$PspOptions="iops=1";$SatpType="iops";$LimitType="Default";$IOPLimit="1"}
                            "0" { If ($HostProfileName -ge "201909001") { $MaxIORecommended = "32767"} else {$MaxIORecommended = "4096"};$PspOptions="iops=1";$SatpType="iops";$LimitType="Default";$IOPLimit="1"}
                        }
                    }
                }

                # Collect our per-Host Recommedations
                $VMHostVersion = New-Object PSObject -Property @{
                    VMHost            = $VMhost
                    HostVersion       = $VMhost.Version
                    HostsMajorVersion = $HostVersionMajor
                    HostProfile       = $HostProfileName
                    MaxIORecommended  = $MaxIORecommended
                    RuleOptions       = $PspOptions
                    RuleType          = $SatpType
                    LimitType         = $LimitType
                    IOPLimit          = $IOPLimit
                }
            
                # Add the per-Host Recommendations to the array
                $VMHostVersionInfo += $VMHostVersion
            }

            # Return the results for Host Recommendations
            $results = $VMHostVersionInfo | Sort-Object VMhost | Select-Object VMhost,HostVersion,HostProfile,RuleType,RuleOptions,MaxIORecommended,LimitType
            return $results
    }
    END
    {
    }
} #End Function Get-PureVmHostRecommendations

Function Get-PureVmHostMaxIOSize 
{
    <#
    .SYNOPSIS
        Return an ESXi Host's Disk.DiskMaxIOSize Value & Display whether it aligns with Pure Storage FlashArray Recommendations
    .DESCRIPTION
        Query the ESXi Host, return the Disk.DiskMaxIOSize value, and determine whether it matches the Pure Storage FlashArray Recommendation

    .INPUTS
        (Required) A vSphere Host or Hosts Object returned from the Get-VMhost PowerCLI cmdlet
        (Optional) The MaxIORecommended Value for a Host. If it is not passed, it will be determined using the Get-PureVmHostRecommendations Function
        (Optional) Show all or only the Hosts that do not align with Pure Storage FlashArray recommendations
    .OUTPUTS
        Host, if the returned Disk.DiskMaxIO Size passes, the returned Disk.DiskMaxIO Size, and the Recommended Disk.DiskMaxIOSize
    .EXAMPLE
        PS C:\ Get-PureVmHostMaxIOSize -EsxiHost (Get-VMhost -Name "esxihost.fqdn") 
        
        Returns the Host & MaxIO info & recommendations for ESXi Host named 'esxihost.fqdn'
    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostMaxIOSize -EsxiHost $VMhosts

        VMhost            MaxIOPass MaxIOValue MaxIORecommended
        ------            --------- ---------- ----------------
        esxi01.fqdn       PASS           32767 {32767}
        esxi02.fqdn       PASS           32767 {32767}
        esxi03.fqdn       PASS           32767 {32767}
        esxi04.fqdn       FAIL            4096 {32767}
        esxi05.fqdn       PASS           32767 {32767}
        esxi06.fqdn       PASS           32767 {32767}
        
        Returns the Host & MaxIO recommendations for all ESXi hosts in the $VMhosts variable
    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostMaxIOSize -EsxiHost $VMhosts -ShowFailuresOnly $true

        VMhost            MaxIOPass MaxIOValue MaxIORecommended
        ------            --------- ---------- ----------------
        esxi04.fqdn       FAIL            4096 {32767}
        
        Returns the Host & MaxIO recommendations for only the ESXi hosts in the $VMhosts variable that fail the recommendation
    .NOTES
        Version:        1.0
        Author:         Jase McCarty https://jasemccarty.com
        Creation Date:  1/3/2022

    *******Disclaimer:******************************************************
    This script are offered "as is" with no warranty.  While this script is 
    tested and working in my environment, it is recommended that you test this 
    script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(ValueFromPipeline,Mandatory)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl[]]$EsxiHost,
        [Parameter(Mandatory=$False)][int64[]]$MaxIORecommended,
        [Parameter(Mandatory=$False)][ValidateSet($false,$true)][Boolean]$ShowFailuresOnly
    )

   BEGIN
    {
        # Configure the MaxIOSettings Array
        $MaxIOSettings = @()
    }
    PROCESS
    {

        # Loop through each ESXi Host passed to the Function
        Foreach ($VMhost in $EsxiHost) {

            # Ensure the host is not offline
            if ((Get-VMhost $VMhost).ConnectionState -ne "NotResponding") {

                # If the MaxIORecommended Value was not specificed, look it up with the Get-PureVmHostRecommendations Function
                If (-Not $MaxIORecommended) {
                    $HostRecommendations = Get-PureVmHostRecommendations -EsxiHost $VMhost
                    $MaxIORecommended = $HostRecommendations.MaxIORecommended
                }

                # Get and check the Max Disk IO Size
                $maxiosize = $VMhost | Get-AdvancedSetting -Name Disk.DiskMaxIOSize

                # If the Host's Disk.DiskMaxIOSize is the recommended size, then pass
                if ($MaxIORecommended -eq $maxiosize.value) {
                    $MaxIOValue = $maxiosize.value
                    $MaxIOPass = "PASS"
                }
                # If the Host's Disk.DiskMaxIOSize does not match the recommended size, then fail
                else {
                    $MaxIOValue = $maxiosize.value
                    $MaxIOPass = "FAIL"
                }

                # Add the current hosts values to an object
                $MaxIOValues = New-Object psobject -Property @{
                    VMhost           = $VMhost
                    MaxIORecommended = $MaxIORecommended
                    MaxIOValue       = $MaxIOValue
                    MaxIOPass        = $MaxIOPass
                }
            }
            else {
                # Add the current hosts values to an object
                $MaxIOValues = New-Object psobject -Property @{
                    VMhost           = $VMhost
                    MaxIORecommended = $MaxIORecommended
                    MaxIOValue       = ""
                    MaxIOPass        = "FAIL"
                }
            }
            # Add each hosts' values to the array of hosts and their values
            $MaxIOSettings += $MaxIOValues

        }

        # If ShowFaluresOnly isn't specified as true, then return all hosts and their values returned
        if ($ShowFailuresOnly -ne $true) {
            return $MaxIOSettings | Sort-Object VMhost, MaxIORecommended, MaxIOValue, MaxIOPass | Select-Object VMhost, MaxIOPass, MaxIOValue, MaxIORecommended
        } 
        # If ShowFaluresOnly is specified as true, then return only the hosts that failed
        else {
            return $MaxIOSettings | Where-Object {$_.MaxIOPass -ne "PASS"} | Sort-Object VMhost, MaxIORecommended, MaxIOValue, MaxIOPass | Select-Object VMhost, MaxIOPass, MaxIOValue, MaxIORecommended
        }        
    }
    
    END
    {}
} #END Function Get-PureVmHostMaxIOSize

Function Get-PureVmHostVaai 
{
    <#
    .SYNOPSIS
        Return an ESXi Host's VAAI Values & Display whether they align with Pure Storage FlashArray Recommendations
    .DESCRIPTION
        Query the ESXi Host, return the VAAI Values, and determine whether they match the Pure Storage FlashArray Recommendation

    .INPUTS
        (Required) A vSphere Host or Hosts Object returned from the Get-VMhost PowerCLI cmdlet
        (Optional) Show all or only the Hosts that do not align with Pure Storage FlashArray recommendations
    .OUTPUTS
        The Host and the Pass/Fail of VAAI Settings based on Pure Storage FlashArray Recommendations
    .EXAMPLE
        PS C:\ Get-PureVmHostVaai -EsxiHost (Get-VMhost -Name "esxihost.fqdn") 

        VMhost       : esxi01.fqdn
        Xcopy        : PASS
        WriteSame    : PASS
        ATSLocking   : PASS
        ATSHeartBeat : PASS
        
        Returns the Host & VAAI info & recommendations for ESXi Host named 'esxihost.fqdn'
    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostVaai -EsxiHost $VMhosts

        VMhost       : esxi01.fqdn
        Xcopy        : PASS
        WriteSame    : PASS
        ATSLocking   : PASS
        ATSHeartBeat : PASS

        VMhost       : esxi02.fqdn
        Xcopy        : PASS
        WriteSame    : PASS
        ATSLocking   : PASS
        ATSHeartBeat : PASS        
        
        Returns the Host & VAAI recommendations for all ESXi hosts in the $VMhosts variable
    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostVaai -EsxiHost $VMhosts | Format-Table

        VMhost            Xcopy WriteSame ATSLocking ATSHeartBeat
        ------            ----- --------- ---------- ------------
        esxi01.fqdn       PASS  PASS      PASS       PASS
        esxi02.fqdn       PASS  PASS      PASS       PASS
        esxi03.fqdn       PASS  PASS      PASS       PASS
        esxi04.fqdn       FAIL  PASS      PASS       PASS
        esxi05.fqdn       PASS  PASS      PASS       PASS
        esxi06.fqdn       PASS  PASS      PASS       PASS

        Returns the Host & VAAI recommendations for all ESXi hosts in the $VMhosts variable

    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostVaai -EsxiHost $VMhosts -ShowFailuresOnly | Format-Table

        VMhost            Xcopy WriteSame ATSLocking ATSHeartBeat
        ------            ----- --------- ---------- ------------
        esxi04.fqdn       FAIL  PASS      PASS       PASS

        Returns the Host & VAAI recommendations for all ESXi hosts in the $VMhosts variable
    .NOTES
        Version:        1.0
        Author:         Jase McCarty https://jasemccarty.com
        Creation Date:  1/3/2022


    *******Disclaimer:******************************************************
    This script are offered "as is" with no warranty.  While this script is 
    tested and working in my environment, it is recommended that you test this 
    script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(ValueFromPipeline,Mandatory)]
        [VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl[]]$EsxiHost,
        [Parameter(Mandatory=$False)][ValidateSet($false,$true)][Boolean]$ShowFailuresOnly
    )

   BEGIN
    {
        # Preconfigure VaaiSettings Array & Pass Variable
        $VaaiSettings = @()
    }
    PROCESS
    {

        # Loop through the EsxiHosts passed
        Foreach ($VMhost in $EsxiHost) {

            # Ensure the host is not offline
            if ((Get-VMhost $VMhost).ConnectionState -ne "NotResponding") {

                # Perform one pull of Host Advanced Settings for better efficiency
                $VMhostVaai = $VMhost | Get-AdvancedSetting | Where-Object {$_.Name -Like "Datamover.*" -or $_.Name -Like "VMFS3*"}

                # Check Xcopy if DataMover.HardwareAcceleratedMove = 0 then fail, otherwise pass
                If ($VMhostVaai.Where{$_.Name -eq "DataMover.HardwareAcceleratedMove"} -eq 0) { 
                    $vaaiXcopy = "FAIL"
                } else {
                    $vaaiXcopy = "PASS"
                }

                # Check writesame if DataMover.HardwareAcceleratedInit = 0 then fail, otherwise pass
                If ($VMhostVaai.Where{$_.Name -eq "DataMover.HardwareAcceleratedInit"} -eq 0) { 
                    $vaaiWritesame = "FAIL"
                } else {
                    $vaaiWritesame = "PASS"
                }

                # check atslocking if VMFS3.HardwareAcceleratedLocking = 0 then fail, otherwise pass
                If ($VMhostVaai.Where{$_.Name -eq "VMFS3.HardwareAcceleratedLocking"} -eq 0) { 
                    $vaaiAtslocking = "FAIL"
                } else {
                    $vaaiAtslocking = "PASS"
                }            

                # Check Use of ATS for Heartbeat on VMFS5
                # Get any Pure Datastores
                $Datastore = $VMhost | Get-Datastore | Where-Object {$_.ExtensionData.Info.Vmfs.Extent.DiskName -like "naa.624a9370*"}

                # Get the Host Version
                $HostVersionMajor = $VMhost.Version.Split(".")[0]

                # If Host Major Version is 6.x or higher, and there are FlashArray Datastores present, then check if VMFS3.useATSForHBOnVMFS = 0
                if (($HostVersionMajor -ge "6") -and ($null -ne $Datastore)) {
                    if ($VMhostVaai.Where{$_.Name -eq "VMFS3.useATSForHBOnVMFS5"} -eq 0) {
                        $vaaiatsheartbeat = "FAIL"
                    } else {
                        $vaaiatsheartbeat = "PASS"
                    }
                }

                # Collect the Vaai Values for the current Host
                $VaaiValues = New-Object psobject -Property @{
                    VMhost       = $VMhost
                    Xcopy        = $vaaiXcopy
                    WriteSame    = $vaaiWritesame
                    ATSLocking   = $vaaiAtslocking
                    ATSHeartBeat = $vaaiatsheartbeat
                    HostState    = $VMhost.ConnectionState
                }
            } else {

                # Collect the Vaai Values for the current (Not Responding) Host
                $VaaiValues = New-Object psobject -Property @{
                    VMhost       = $VMhost
                    Xcopy        = "FAIL"
                    WriteSame    = "FAIL"
                    ATSLocking   = "FAIL"
                    ATSHeartBeat = "FAIL"
                }

            }

            # Add the current Host's values to the VaaiSettings Array
            $VaaiSettings += $VaaiValues

        }
        # If ShowFaluresOnly isn't specified as true, then return all Hosts and their values returned
        if ($ShowFailuresOnly -ne $true) {
            return $VaaiSettings | Sort-Object VMhost | Select-Object VMhost, Xcopy, WriteSame,ATSLocking,ATSHeartBeat
        } 
        # If ShowFaluresOnly is specified as true, then return only the Hosts with failures
        else {
            return $VaaiSettings | Where-Object {$_.Xcopy -ne "PASS" -or $_.WriteSame -ne "PASS" -or $_.ATSLocking -ne "PASS" -or $_.ATSHeartBeat -ne "PASS"} | Sort-Object VMhost | Select-Object VMhost, Xcopy, WriteSame,ATSLocking,ATSHeartBeat
        }

    }
    END
    {}
} #END Function Get-PureVmHostVaaiSettings

Function Get-PureVmHostUserRules
{
    <#
    .SYNOPSIS
        Return any Pure Storage User SATP Rules created on a host & make a recommendation as to what do do with them
    .DESCRIPTION
        Query the ESXi Host, any Pure Storage SATP User Rules, and determine whether they match the Pure Storage FlashArray Recommendation

    .INPUTS
        (Required) A vSphere Host or Hosts Object returned from the Get-VMhost PowerCLI cmdlet
        (Optional) Show all or only the Hosts that do not align with Pure Storage FlashArray recommendations
    .OUTPUTS
        The Host, any User Rule Group Rules for Pure Storage, the rule's properties, and any recommendations
    .EXAMPLE
        PS C:\ Get-PureVmHostUserRules -EsxiHost (Get-VMhost -Name "esxihost.fqdn") 

        VMhost         : esxihost.fqdn
        Name           : VMW_SATP_ALUA
        DefaultPSP     : VMW_PSP_RR
        Vendor         : PURE
        Model          : FlashArray
        RuleGroup      : user
        PSPOptions     : iops=1
        Recommendation : Remove
        
        Returns the Host, User Rules, and Recommendations for ESXi Host named 'esxihost.fqdn'
    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostUserRules -EsxiHost $VMhosts

        VMhost         : esxihost.fqdn
        Name           : VMW_SATP_ALUA
        DefaultPSP     : VMW_PSP_RR
        Vendor         : PURE
        Model          : FlashArray
        RuleGroup      : user
        PSPOptions     : iops=1
        Recommendation : Remove
        
        Returns the Host & VAAI recommendations ONLY for ESXi hosts in the $VMhosts variable that have a User Rule for Pure Storage

    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostUserRules -EsxiHost $VMhosts | Format-Table

        VMhost            Name          DefaultPSP Vendor Model      RuleGroup PSPOptions Recommendation
        ------            ----          ---------- ------ -----      --------- ---------- --------------
        esxi06.fqdn       VMW_SATP_ALUA VMW_PSP_RR PURE   FlashArray user      iops=1     Remove
        
        Returns the Host & VAAI recommendations ONLY for ESXi hosts in the $VMhosts variable that have a User Rule for Pure Storage

    .NOTES
        Version:        1.0
        Author:         Jase McCarty https://jasemccarty.com
        Creation Date:  1/3/2022

    *******Disclaimer:******************************************************
    This script are offered "as is" with no warranty.  While this script is 
    tested and working in my environment, it is recommended that you test this 
    script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(ValueFromPipeline,Mandatory)]
        [VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl[]]$EsxiHost
    )

   BEGIN
    {
        #Write-Host "Checking for User Pathing Rules"
        $UserRules = @()
    }
    PROCESS
    {

        # Loop through the EsxiHosts passed
        Foreach ($VMhost in $EsxiHost) {

            # Ensure the host is not offline
            if ((Get-VMhost $VMhost).ConnectionState -ne "NotResponding") {

                # Create our EsxCli context for the current host
                $EsxCli = Get-EsxCli -VMHost $VMhost -V2

                # Retrieve any User storage Rules for Pure Storage
                $SatpUserRules = $esxcli.storage.nmp.satp.rule.list.Invoke()| Where-Object {($_.RuleGroup -eq "user") -and ({$_.Model -Like "FlashArray"})}

                # If we have 1 or more rules, then proceed
                if ($SatpUserRules.Count -ge "1") {
                    
                    # Loop through each User rule found
                    Foreach ($SatpUserRule in $SatpUserRules) {

                        # Add the current User rule's values to an object
                        $UserRule = New-Object psobject -Property @{
                            VMhost         = $VMhost
                            Vendor         = $SatpUserRule.Vendor
                            Model          = $SatpUserRule.Model
                            DefaultPSP     = $SatpUserRule.DefaultPSP
                            Name           = $SatpUserRule.Name
                            PSPOptions     = $SatpUserRule.PSPOptions
                            Recommendation = "Remove"
                            RuleGroup      = $SatpUserRules.RuleGroup
                        }

                    }
                }

            } else {
                # Add the current User rule's values to an object
                $UserRule = New-Object psobject -Property @{
                    VMhost         = $VMhost
                    Vendor         = ""
                    Model          = ""
                    DefaultPSP     = ""
                    Name           = ""
                    PSPOptions     = ""
                    Recommendation = "Error"
                    RuleGroup      = ""
                }
            }

            # Add the current User rule object to the array of User Rules
            $UserRules += $UserRule

        }
            # Return the User Rules from the function
            return $UserRules | Sort-Object VMhost, Name, DefaultPSP, Vendor, Model, RuleGroup, PSPOptions, Recommendation | Select-Object VMhost, Name, DefaultPSP, Vendor, Model, RuleGroup, PSPOptions, Recommendation

    }
    END
    {}
} #END Function Get-PureVmHostUserRules

Function Get-PureVmHostIscsiTargets
{
    <#
    .SYNOPSIS
        Return an ESXi Host's VAAI Values & Display whether they align with Pure Storage FlashArray Recommendations
    .DESCRIPTION
        Query the ESXi Host, return the distinct iSCSI targets & addresses, and determine whether they match the Pure Storage FlashArray Recommendations
    .INPUTS
        (Required) A vSphere Host or Hosts Object returned from the Get-VMhost PowerCLI cmdlet
        (Optional) Show all or only the Hosts that do not align with Pure Storage FlashArray recommendations
        (Optional) only return a specific iSCSI target
    .OUTPUTS
        The Host, iSCSI target & address, and DelayedAck/LoginTimeout pass/fail based on Pure Storage FlashArray Recommendations
    .EXAMPLE
        PS C:\ Get-PureVmHostIscsiTargets -EsxiHost (Get-VMhost -Name "esxihost.fqdn") 

        VMhost                : esxihost.fqdn
        FlashArrayTarget      : iqn.2010-06.com.purestorage:flasharray.2e233218e7510e2d
        Address               : 10.21.200.182
        DelayedAckInherited   : True
        DelayedAck            : False
        DelayedAckPass        : PASS
        LogintimeoutInherited : True
        LoginTimeout          : 30
        LoginTimeoutPass      : PASS

        VMhost                : esxihost.fqdn
        FlashArrayTarget      : iqn.2010-06.com.purestorage:flasharray.2e233218e7510e2d
        Address               : 10.21.200.183
        DelayedAckInherited   : True
        DelayedAck            : False
        DelayedAckPass        : PASS
        LogintimeoutInherited : True
        LoginTimeout          : 30
        LoginTimeoutPass      : PASS
        
        Returns the Host, distinct iSCSI Target/Addresses, and DelayedACK/LoginTimeout settings/pass/fail for the ESXi Host named 'esxihost.fqdn'
    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostIscsiTargets -EsxiHost $VMhosts

        VMhost                : esxi02.fqdn
        FlashArrayTarget      : iqn.2010-06.com.purestorage:flasharray.2e233218e7510e2d
        Address               : 10.21.200.182
        DelayedAckInherited   : True
        DelayedAck            : False
        DelayedAckPass        : PASS
        LogintimeoutInherited : True
        LoginTimeout          : 30
        LoginTimeoutPass      : PASS

        VMhost                : esxi03.fqdn
        FlashArrayTarget      : iqn.2010-06.com.purestorage:flasharray.2e233218e7510e2d
        Address               : 10.21.200.182
        DelayedAckInherited   : True
        DelayedAck            : False
        DelayedAckPass        : PASS
        LogintimeoutInherited : True
        LoginTimeout          : 30
        LoginTimeoutPass      : PASS
        
        Returns the Host, distinct iSCSI Target/Addresses, and DelayedACK/LoginTimeout settings/pass/fail for all ESXi hosts in the $VMhosts variable
    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostIscsiTargets -EsxiHost (Get-VMhost -Name "esxihost.fqdn") | Format-Table

        VMhost            FlashArrayTarget                                        Address       DelayedAckInherited DelayedAck DelayedAckPass LogintimeoutInherited LoginTimeout LoginTimeoutPass
        ------            ----------------                                        -------       ------------------- ---------- -------------- --------------------- ------------ ----------------
        esxihost.fqdn     iqn.2010-06.com.purestorage:flasharray.def7d7133016eef  10.21.229.104               False       True FAIL                            True           30 PASS
        esxihost.fqdn     iqn.2010-06.com.purestorage:flasharray.def7d7133016eef  10.21.229.105                True      False PASS                            True           30 PASS
        esxihost.fqdn     iqn.2010-06.com.purestorage:flasharray.def7d7133016eef  10.21.229.106                True      False PASS                            True           30 PASS
        esxihost.fqdn     iqn.2010-06.com.purestorage:flasharray.def7d7133016eef  10.21.229.107                True      False PASS                            True           30 PASS

        Returns the Host, distinct iSCSI Target/Addresses, and DelayedACK/LoginTimeout settings/pass/fail for the ESXi Host named 'esxihost.fqdn'

    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostIscsiTargets -EsxiHost (Get-VMhost -Name "esxihost.fqdn") -ShowFailuresOnly $true | Format-Table

        VMhost            FlashArrayTarget                                        Address       DelayedAckInherited DelayedAck DelayedAckPass LogintimeoutInherited LoginTimeout LoginTimeoutPass
        ------            ----------------                                        -------       ------------------- ---------- -------------- --------------------- ------------ ----------------
        esxihost.fqdn     iqn.2010-06.com.purestorage:flasharray.def7d7133016eef  10.21.229.104               False       True FAIL                            True           30 PASS

        Returns the Host, distinct iSCSI Target/Addresses, and DelayedACK/LoginTimeout settings/pass/fail for the ESXi Host named 'esxihost.fqdn'

    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostIscsiTargets -EsxiHost (Get-VMhost) -FlashArrayTarget "iqn.2010-06.com.purestorage:flasharray.def7d7133016eef" | Format-Table

        VMhost            FlashArrayTarget                                       Address       DelayedAckInherited DelayedAck DelayedAckPass LogintimeoutInherited LoginTimeout LoginTimeoutPass
        ------            ----------------                                       -------       ------------------- ---------- -------------- --------------------- ------------ ----------------
        esxi01.fqdn       iqn.2010-06.com.purestorage:flasharray.def7d7133016eef 10.21.229.104                True      False PASS                            True           30 PASS
        esxi01.fqdn       iqn.2010-06.com.purestorage:flasharray.def7d7133016eef 10.21.229.105                True      False PASS                            True           30 PASS
        esxi01.fqdn       iqn.2010-06.com.purestorage:flasharray.def7d7133016eef 10.21.229.106                True      False PASS                            True           30 PASS
        esxi01.fqdn       iqn.2010-06.com.purestorage:flasharray.def7d7133016eef 10.21.229.107                True      False PASS                            True           30 PASS
        esxi02.fqdn       iqn.2010-06.com.purestorage:flasharray.def7d7133016eef 10.21.229.104               False       True FAIL                            True           30 PASS
        esxi02.fqdn       iqn.2010-06.com.purestorage:flasharray.def7d7133016eef 10.21.229.105                True      False PASS                            True           30 PASS
        esxi02.fqdn       iqn.2010-06.com.purestorage:flasharray.def7d7133016eef 10.21.229.106                True      False PASS                            True           30 PASS
        esxi02.fqdn       iqn.2010-06.com.purestorage:flasharray.def7d7133016eef 10.21.229.107                True      False PASS                            True           30 PASS
        
        Returns the Host, distinct iSCSI Target/Addresses, and DelayedACK/LoginTimeout settings/pass/fail for the ESXi Host named 'esxihost.fqdn'

    .NOTES
        Version:        1.0
        Author:         Jase McCarty https://jasemccarty.com
        Creation Date:  1/3/2022


    *******Disclaimer:******************************************************
    This script are offered "as is" with no warranty.  While this script is 
    tested and working in my environment, it is recommended that you test this 
    script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(ValueFromPipeline,Mandatory)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl[]]$EsxiHost,
        [Parameter(Mandatory=$False)][String]$FlashArrayTarget,
        [Parameter(Mandatory=$False)][ValidateSet($false,$true)][Boolean]$ShowFailuresOnly
    )

   BEGIN
    {
        $FlashArrayTargets = @()
        $StaticIscsiTargets = @()
    }
    PROCESS
    {

        # Loop through the EsxiHosts passed
        Foreach ($VMhost in $EsxiHost) {

            # Ensure the host is not offline
            if ((Get-VMhost $VMhost).ConnectionState -ne "NotResponding") {

                # Get the iSCSI Software Adapter if present
                $iscsihba = $VMhost | Get-VMHostHba |Where-Object{$_.Model -eq "iSCSI Software Adapter"}

                if ($iscsihba) {

                    # Create our EsxCli context for the current host
                    $EsxCli = Get-EsxCli -VMHost $VMhost -V2

                    # Get a list of all of the Pure Storage iSCSI Targets (if any)
                    $uniquetargets = $esxcli.iscsi.adapter.target.portal.list.Invoke().where{$_.Target -Like "*purestorage*"} | Select-Object Adapter,Id,Target 

                    # If a FlashArrayTarget is specified, filter out the other FlashArrayTargets
                    if ($FlashArrayTarget) {
                        # Select only the specified FlashArrayTarget
                        $uniquetargets = $uniquetargets | Where-Object {$_.Target -eq $FlashArrayTarget}
                    }

                    # Loop through each of the unique FlashArray iSCSI Targets
                    foreach ($uniquetarget in $uniquetargets) {

                        # Get the static targets for each unique target
                        $statictgts = $iscsihba | Get-IscsiHbaTarget -type "static" | Where-Object {$_.IscsiName -eq $uniquetarget.target} 

                        # Loop through each static target and return their values
                        foreach ($statictgt in $statictgts) {
                            $iscsioptions = $statictgt.ExtensionData.AdvancedOptions

                            # Return the iSCSI Options DelayedACK and LoginTimeout for the current Static Target
                            Foreach ($iscsioption in $iscsioptions) {
                                if ($iscsioption.key -eq "DelayedAck")    {
                                    $iscsiack = $iscsioption.value
                                    if ($iscsiack -eq $false) { $iscsiackpass = "PASS"} else { $iscsiackpass = "FAIL"}
                                    $delayedackinheretied=$iscsioption.IsInherited
                                }
                                if ($iscsioption.key -eq "LoginTimeout")  {
                                    $iscsitimeout = $iscsioption.value
                                    if ($iscsitimeout -eq "30") { $iscsitimeoutpass = "PASS"} else { $iscsitimeoutpass = "FAIL"}
                                    $logintimeoutinherited=$iscsioption.IsInherited
                                }
                            }

                            # Put the properties of the Static Target in an Object
                            $StaticTarget = New-Object psobject -Property @{
                                VMhost                 = $VMhost
                                FlashArrayTarget       = $uniquetarget.target
                                Address                = $statictgt.Address
                                DelayedAck             = $iscsiack
                                DelayedAckPass         = $iscsiackpass
                                DelayedAckInherited    = $delayedackinheretied
                                LoginTimeout           = $iscsitimeout
                                LoginTimeoutPass       = $iscsitimeoutpass
                                LogintimeoutInherited  = $logintimeoutinherited
                            }
                            # Add the Static Target Object to the Array for reporting
                            $StaticIscsiTargets += $StaticTarget

                        } 
                        # Add the Static Targets to the Larger List of Targets Across Hosts
                        $FlashArrayTargets += $StaticIscsiTargets
                        
                    } 

                } # End iSCSI Check
            }

        } # End Host Loop

        if ($ShowFailuresOnly -ne $true) {
            return $FlashArrayTargets | Sort-Object FlashArrayTarget, VMhost, Address, DelayedAckPass, LoginTimeoutPass -Unique | Select-Object VMhost,FlashArrayTarget,Address,DelayedAckInherited,DelayedAck,DelayedAckPass,LoginTimeoutInherited,LoginTimeout,LoginTimeoutPass
        } else {
            return $FlashArrayTargets | Sort-Object FlashArrayTarget, VMhost, Address, DelayedAckPass, LoginTimeoutPass -Unique | Select-Object VMhost,FlashArrayTarget,Address,DelayedAckInherited,DelayedAck,DelayedAckPass,LoginTimeoutInherited,LoginTimeout,LoginTimeoutPass | Where-Object {$_.DelayedAckPass -ne "PASS" -or $_.LoginTimeoutPass -ne "PASS"}
        }

    }
    END
    {
    }
} #End Function Get-PureHostIscsiTargets

Function Get-PureVmHostDeviceConfiguration 
{
        <#
    .SYNOPSIS
        Return an ESXi Host, the Pure Storage Block Devices presented, the Canonical Name, the Path Selection Policy, Lun Path Count,SATP Rule Type, and whether they align with Pure Storage FlashArray Best Practices
    .DESCRIPTION
        Query the ESXi Host, return the distinct Pure Storage Devices, and determine whether they match the Pure Storage FlashArray Recommendations
    .INPUTS
        (Required) A vSphere Host or Hosts Object returned from the Get-VMhost PowerCLI cmdlet
        (Optional) Show all or only the Hosts that do not align with Pure Storage FlashArray recommendations
        (Optional) only return a specific device (Must be a Get-ScsiLun returned Object)
    .OUTPUTS
        The Host, Devices (datastore or not), VMFS version for datastores, CanonicalName, Path Selection Policy, Lun Path Count, and whether these pass/fail based on Pure Storage FlashArray Recommendations
    .EXAMPLE
        PS C:\ Get-PureVmHostDeviceConfiguration -EsxiHost (Get-VMhost -Name "esxihost.fqdn") 

        VMhost                : esxihost.fqdn
        FlashArrayTarget      : iqn.2010-06.com.purestorage:flasharray.2e233218e7510e2d
        Address               : 10.21.200.182
        DelayedAckInherited   : True
        DelayedAck            : False
        DelayedAckPass        : PASS
        LogintimeoutInherited : True
        LoginTimeout          : 30
        LoginTimeoutPass      : PASS

        VMhost                : esxihost.fqdn
        FlashArrayTarget      : iqn.2010-06.com.purestorage:flasharray.2e233218e7510e2d
        Address               : 10.21.200.183
        DelayedAckInherited   : True
        DelayedAck            : False
        DelayedAckPass        : PASS
        LogintimeoutInherited : True
        LoginTimeout          : 30
        LoginTimeoutPass      : PASS
        
        Returns the Host, distinct iSCSI Target/Addresses, and DelayedACK/LoginTimeout settings/pass/fail for the ESXi Host named 'esxihost.fqdn'
    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostIscsiTargets -EsxiHost $VMhosts

        VMhost                : esxi02.fqdn
        FlashArrayTarget      : iqn.2010-06.com.purestorage:flasharray.2e233218e7510e2d
        Address               : 10.21.200.182
        DelayedAckInherited   : True
        DelayedAck            : False
        DelayedAckPass        : PASS
        LogintimeoutInherited : True
        LoginTimeout          : 30
        LoginTimeoutPass      : PASS

        VMhost                : esxi03.fqdn
        FlashArrayTarget      : iqn.2010-06.com.purestorage:flasharray.2e233218e7510e2d
        Address               : 10.21.200.182
        DelayedAckInherited   : True
        DelayedAck            : False
        DelayedAckPass        : PASS
        LogintimeoutInherited : True
        LoginTimeout          : 30
        LoginTimeoutPass      : PASS
        
        Returns the Host, distinct iSCSI Target/Addresses, and DelayedACK/LoginTimeout settings/pass/fail for all ESXi hosts in the $VMhosts variable
    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostIscsiTargets -EsxiHost (Get-VMhost -Name "esxihost.fqdn") | Format-Table

        VMhost            FlashArrayTarget                                        Address       DelayedAckInherited DelayedAck DelayedAckPass LogintimeoutInherited LoginTimeout LoginTimeoutPass
        ------            ----------------                                        -------       ------------------- ---------- -------------- --------------------- ------------ ----------------
        esxihost.fqdn     iqn.2010-06.com.purestorage:flasharray.def7d7133016eef  10.21.229.104               False       True FAIL                            True           30 PASS
        esxihost.fqdn     iqn.2010-06.com.purestorage:flasharray.def7d7133016eef  10.21.229.105                True      False PASS                            True           30 PASS
        esxihost.fqdn     iqn.2010-06.com.purestorage:flasharray.def7d7133016eef  10.21.229.106                True      False PASS                            True           30 PASS
        esxihost.fqdn     iqn.2010-06.com.purestorage:flasharray.def7d7133016eef  10.21.229.107                True      False PASS                            True           30 PASS

        Returns the Host, distinct iSCSI Target/Addresses, and DelayedACK/LoginTimeout settings/pass/fail for the ESXi Host named 'esxihost.fqdn'

    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostIscsiTargets -EsxiHost (Get-VMhost -Name "esxihost.fqdn") -ShowFailuresOnly $true | Format-Table

        VMhost            FlashArrayTarget                                        Address       DelayedAckInherited DelayedAck DelayedAckPass LogintimeoutInherited LoginTimeout LoginTimeoutPass
        ------            ----------------                                        -------       ------------------- ---------- -------------- --------------------- ------------ ----------------
        esxihost.fqdn     iqn.2010-06.com.purestorage:flasharray.def7d7133016eef  10.21.229.104               False       True FAIL                            True           30 PASS

        Returns the Host, distinct iSCSI Target/Addresses, and DelayedACK/LoginTimeout settings/pass/fail for the ESXi Host named 'esxihost.fqdn'

    .EXAMPLE
        PS C:\ $VMhosts = Get-VMhost
        PS C:\ Get-PureVmHostIscsiTargets -EsxiHost (Get-VMhost) -FlashArrayTarget "iqn.2010-06.com.purestorage:flasharray.def7d7133016eef" | Format-Table

        VMhost            FlashArrayTarget                                       Address       DelayedAckInherited DelayedAck DelayedAckPass LogintimeoutInherited LoginTimeout LoginTimeoutPass
        ------            ----------------                                       -------       ------------------- ---------- -------------- --------------------- ------------ ----------------
        esxi01.fqdn       iqn.2010-06.com.purestorage:flasharray.def7d7133016eef 10.21.229.104                True      False PASS                            True           30 PASS
        esxi01.fqdn       iqn.2010-06.com.purestorage:flasharray.def7d7133016eef 10.21.229.105                True      False PASS                            True           30 PASS
        esxi01.fqdn       iqn.2010-06.com.purestorage:flasharray.def7d7133016eef 10.21.229.106                True      False PASS                            True           30 PASS
        esxi01.fqdn       iqn.2010-06.com.purestorage:flasharray.def7d7133016eef 10.21.229.107                True      False PASS                            True           30 PASS
        esxi02.fqdn       iqn.2010-06.com.purestorage:flasharray.def7d7133016eef 10.21.229.104               False       True FAIL                            True           30 PASS
        esxi02.fqdn       iqn.2010-06.com.purestorage:flasharray.def7d7133016eef 10.21.229.105                True      False PASS                            True           30 PASS
        esxi02.fqdn       iqn.2010-06.com.purestorage:flasharray.def7d7133016eef 10.21.229.106                True      False PASS                            True           30 PASS
        esxi02.fqdn       iqn.2010-06.com.purestorage:flasharray.def7d7133016eef 10.21.229.107                True      False PASS                            True           30 PASS
        
        Returns the Host, distinct iSCSI Target/Addresses, and DelayedACK/LoginTimeout settings/pass/fail for the ESXi Host named 'esxihost.fqdn'

    .NOTES
        Version:        1.0
        Author:         Jase McCarty https://jasemccarty.com
        Creation Date:  1/3/2022


    *******Disclaimer:******************************************************
    This script are offered "as is" with no warranty.  While this script is 
    tested and working in my environment, it is recommended that you test this 
    script in a test lab before using in a production environment. Everyone can 
    use the scripts/commands provided here without any written permission but I
    will not be liable for any damage or loss to the system.
    ************************************************************************
    #>
    [CmdletBinding()]
    Param
    (
        [Parameter(ValueFromPipeline,Mandatory,Position=0)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl[]]$EsxiHost,
        [Parameter(ValueFromPipeline,Position=1)][String]$CanonicalName,
        [Parameter(Mandatory=$False)][ValidateSet($false,$true)][Boolean]$ShowFailuresOnly
    )

   BEGIN
    {
        $PureDevices = @()
        $VasaProviders = Get-VasaProvider | Where-Object {$_.Namespace -eq "com.purestorage"}
        
    }
    PROCESS
    {

        # Loop through the EsxiHosts passed
        Foreach ($VMhost in $EsxiHost) {

            # Ensure the host is not offline
            if ((Get-VMhost $VMhost).ConnectionState -ne "NotResponding") {

                # Get the Host Recommendations
                $HostRecommendations = Get-PureVmHostRecommendations -EsxiHost $VMhost

                # Enumerate all Pure Storage Devices on the Host
                if ($CanonicalName) {
                    $devices = $VMhost | Get-ScsiLun -CanonicalName $CanonicalName -ErrorAction SilentlyContinue
                    
                } else {
                    $devices = $VMhost | Get-ScsiLun -CanonicalName "naa.624a9370*"
                }

                # If we have at least 1 device proceed
                If ($devices.count -ge 1) {

                    # Create our EsxCli context for the current host
                    $EsxCli = Get-EsxCli -VMHost $VMhost -V2
                    
                    # Loop through each of our devices
                    Foreach ($device in $devices)
                    {

                        # Get any Protocol Endpoints for vVol Datastore info
                        $VmHostPEs = $Esxcli.storage.vvol.protocolendpoint.list.Invoke() 

                        # Null out the Datastore & VMFS Version
                        $datastore = $null;$DatastoreVersion = $null;$DatastoreType = $null;$SATPPass = $null;$DevicePSPPass = $null

                        # Get the Multipath Policy
                        $DevicePSP = $device.MultipathPolicy

                        # Get the Device Queue Depth
                        $DeviceQD = $device.ExtensionData.queuedepth

                        # Get the SATP Recommendations
                                                

                        # If Round Robin, pass. Otherwise fail
                        If ($DevicePSP -eq "RoundRobin") {
                            $DevicePSPPass = "PASS"

                            # Get the Device Configuration to check the rule being used
                            $deviceconfig = $esxcli.storage.nmp.psp.roundrobin.deviceconfig.get.Invoke(@{device="$($device.CanonicalName)"})

                            # Check for vSphere 7 or greater
                            If ($HostRecommendations.HostMajorVersion -ge "7") {
                                if (($deviceconfig.LimitType -eq $HostRecommendations.LimitType) -and ($deviceconfig.IOOperationLimit -eq 0)) {
                                    $DeviceSatpType = $deviceconfig.LimitType
                                    $SATPPass = "PASS" 
                                } else {
                                    $DeviceSatpType = $deviceconfig.LimitType
                                    $SATPPass = "FAIL"
                                }
                            }

                            If ($HostRecommendations.HostMajorVersion -lt "7") {
                                if (($deviceconfig.LimitType -ne "Latency") -and ($deviceconfig.IOOperationLimit -eq 1)) {
                                    $DeviceSatpType = "IOPS"
                                    $SATPPass = "PASS" 
                                } else {
                                    $DeviceSatpType = "IOPS"
                                    $SATPPass = "FAIL"
                                }
                            }

                        } else {
                            $DevicePSPPass = "FAIL"
                        }

                        # Lun Path Count
                        $LunPathCount = ($device | Get-ScsiLunPath).count
                        if ($LunPathCount -ge 4) {$LunPathCountPass = "PASS"}
                        else { $LunPathCountPass = "FAIL"}
        
                            # Check to see if this is a datastore
                            $datastore = $VMhost |Get-Datastore | Where-Object { $_.ExtensionData.Info.Vmfs.Extent.DiskName -eq $device.CanonicalName }

                            # If traditional datastores, get the version information
                            If ($datastore.Type -eq "VMFS") {
                                $DatastoreVersion = "Version $($Datastore.FilesystemVersion)"
                            }

                            if ($datastore) {
                                $DatastoreType = $datastore.Type
                            } else {
                                if ($device.ExtensionData.ProtocolEndpoint -eq $true) {
                                    $VmHostPe = $VmHostPEs | Where-Object {$_.LunId -eq $device.CanonicalName}
                                    $Datastore = Get-Datastore | Where-Object {$_.Type -eq "VVOL" -and $_.ExtensionData.Info.VvolDS.VasaProviderInfo.ArrayState.ArrayId -eq $VmHostPe.ArrayId}
                                    $VvolProvider = $Datastore.ExtensionData.Info.VvolDS.VasaProviderInfo.Provider.Url
                                    $VasaVersion = $VasaProviders | Where-Object {$_.Url -eq $VvolProvider}
                                    $DatastoreType = $Datastore.Type

                                    $DatastoreVersion = "VASA $($VASAVersion.VasaVersion)"
                                }
                            }


                        $PureDevice = New-Object PSObject -Property @{
                            VMHost              = $VMhost
                            CanonicalName       = $device.CanonicalName
                            PSP                 = $device.MultipathPolicy
                            PSPPass             = $DevicePSPPass
                            SATP                = $DeviceSatpType
                            SATPPass            = $SATPPass
                            PathCount           = $LunPathCount
                            PathCountPass       = $LunPathCountPass
                            Datastore           = $datastore
                            DatastoreType       = $DatastoreType
                            DSVersion           = $DatastoreVersion
                            QueueDepth          = $DeviceQD
                        }
                    
                        $PureDevices += $PureDevice
                    }
                }
            }
        } # End Host Loop

        if ($ShowFailuresOnly -ne $true) {
            return $PureDevices | Sort-Object VMhost,DatastoreType,Datastore | Select-Object -Property VMhost, Datastore, CanonicalName, DatastoreType, DSVersion, PSP, PSPPass, SATP, SATPPass, PathCount, PathCountPass
        } else {
            return $PureDevices | Sort-Object VMhost,DatastoreType,Datastore | Select-Object -Property VMhost, Datastore, CanonicalName, DatastoreType, DSVersion, PSP, PSPPass, SATP, SATPPass, PathCount, PathCountPass | Where-Object {$_.PSPPass -ne "PASS" -or $_.PathCountPass -ne "PASS" -or $_.SATPPass -ne "PASS"} 
        }


    } 
    END
    {}
} # End Function Get-PureVMhostDeviceConfiguration
