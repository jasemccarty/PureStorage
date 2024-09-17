<#
*******Disclaimer:**********************************************************************************
This scripts are offered "as is" with no warranty.  
It is recommended that you test this script in a test lab before using in a production environment. 
vSphere Cluster name must be the same as FlashArray HostGroup name
ESXi host names must be the same as the FlashArray Host names
16 SEPT 2024 - Jase McCarty - Pure Storage
*******Disclaimer:**********************************************************************************
SYNTAX: Chap-Iscsi.ps1 -FaEndpoint flasharray.testdrive.local -vcenter vcsa.testdrive.local
#>

Param
(
    [Parameter(ValueFromPipeline,Mandatory=$true)][String]$FaEndpoint,
    [Parameter(ValueFromPipeline,Mandatory=$true)][String]$vcenter
)

#########################################################
# Set our ChapHostPassword & ChapTargetPassword         #
#########################################################
$chaphostpassword = "asdfghjklpoiuytrewq"
$chaptargetpassword = "asdfghjklpoiuytrewq1"

#########################################################
# Check PowerCLI Version                                #
#########################################################
# Get the PowerCLI Version
$PowerCLIVersion = Get-Module -Name VMware.PowerCLI -ListAvailable | Select-Object -Property Version

# If the PowerCLI Version is not v13 or higher, recommend that the user install PowerCLI 13 or higher
If ($PowerCLIVersion.Version.Major -ge "13") {
    Write-Host "PowerCLI version 13 or higher present, " -NoNewLine
    Write-Host "proceeding" -ForegroundColor Green 
} else {
    Write-Host "PowerCLI version could not be determined or is less than version 13" -Foregroundcolor Red
    Write-Host "Please install PowerCLI 13 or higher and rerun this script" -Foregroundcolor Yellow
    Write-Host " "
    exit
}

# Set the PowerCLI configuration to ignore/self-signed certificates
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$False | Out-Null 

#########################################################
# Check PureStoragePowerShellSDK2 Version               #
#########################################################
# Get the PureStoragePowerShellSDK2 Version
$PSPSDKVersion = Get-Module -Name PureStoragePowerShellSDK2 -ListAvailable | Select-Object -Property Version

# If the PureStoragePowerShellSDK2 Version is not v2.26.70 or higher, recommend that the user install PureStoragePowerShellSDK2 2.26.70 or higher
If ($PSPSDKVersion.Version.Major -ge "2") {
    Switch ($PSPSDKVersion.Version.Minor) {
        {$_ -lt 26} { 
            Write-Host "PureStoragePowerShellSDK2 version could not be determined or is less than version 2.26.70" -Foregroundcolor Red
            Write-Host "Please install PureStoragePowerShellSDK2 2.26.70 or higher and rerun this script" -Foregroundcolor Yellow
            Write-Host " "
            exit
        }
        {$_ -gt 26} { 
            Write-Host "PureStoragePowerShellSDK2 version $($PSPSDKVersion.Version) is acceptable," -NoNewline
            Write-Host "proceeding" -ForegroundColor Green 
        }
        {$_ -eq 26} { 
            If ($PSPSDKVersion.Version.Build -ge "70") {
                Write-Host "PureStoragePowerShellSDK2 version $($PSPSDKVersion.Version) is acceptable," -NoNewline
                Write-Host "proceeding" -ForegroundColor Green
            } else {
                Write-Host "PureStoragePowerShellSDK2 version could not be determined or is less than version 2.26.70" -Foregroundcolor Red
                Write-Host "Please install PureStoragePowerShellSDK2 2.26.70 or higher and rerun this script" -Foregroundcolor Yellow
                Write-Host " "
                exit
            }
        }
    }
}

#########################################################
# Connect to FlashArray                                 #
#########################################################
# Check to see if a current FlashArray session is in place
If ($PURE_AUTH_2_X.ArrayName -ne $FaEndpoint) {
    # Disconnect from the currently connected FlashArray if the name doesn't match
    try {Disconnect-Pfa2Array}  catch { Write-Host $Error }

    # Null out the Default FlashArray Global Variable
    $PURE_AUTH_2_X = $null

    # If no FlashArray Endpoint was passed, prompt for it
    if ($null -eq $FaEndpoint) {
        $FaEndpoint = Read-Host "Please enter the FlashArray FQDN"  
    }

    # Prompt for credentials using the native PowerShell Get-Credential cmdlet
    $FaCredentials = Get-Credential -Message "Enter credentials for $($FaEndpoint)" 
    try {
        # Attempt to connect to the vCenter Server 
        $FlashArray = Connect-Pfa2Array -Endpoint $FaEndpoint -Credential $FaCredentials -IgnoreCertificateError
        Write-Host "Connected to $($FlashArray.Name)" -ForegroundColor Green 
    }
    catch {
        # If we could not connect to FlashArray report that and exit the script
        Write-Host "Failed to connect to $FlashArray" -BackgroundColor Red
        Write-Host $Error
        Write-Host "Terminating the script " -BackgroundColor Red
        return
    }
} else {
    Write-Host "Already connected to " -NoNewline 
    Write-Host $PURE_AUTH_2_X.ArrayName -ForegroundColor Green
    $FaEndpoint = $PURE_AUTH_2_X.ArrayName     
}

#########################################################
# Retrieve the IQN from FlashArray                      #
#########################################################
$FlashArrayIqn = (Get-Pfa2Port | Select-Object -unique IQN | Where-Object {$_.Iqn -like "iqn*"}).Iqn
$FlashArrayIscsiIp = (Get-Pfa2Port | Where-Object {$_.Iqn -like "iqn*"} | Select-Object Portal).Portal

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
    if ($null -eq $vcenter) {
        $vCenter = Read-Host "Please enter the vCenter Server FQDN"  
    }
    # Prompt for credentials using the native PowerShell Get-Credential cmdlet
    $VICredentials = Get-Credential -Message "Enter credentials for vCenter Server $($vcenter)" 
    try {
        # Attempt to connect to the vCenter Server 
        Connect-VIServer -Server $vCenter -Credential $VICredentials -ErrorAction Stop | Out-Null
        Write-Host "Connected to $vCenter" -ForegroundColor Green 
    }
    catch {
        # If we could not connect to vCenter report that and exit the script
        Write-Host "Failed to connect to $VIFQDN" -BackgroundColor Red
        Write-Host $Error
        Write-Host "Terminating the script " -BackgroundColor Red
        return
    }
}

#########################################################
# Choose to run the script against a specific cluster   #
#########################################################

# Retrieve the clusters & sort them alphabetically 
$Clusters = Get-Cluster | Sort-Object Name

# If no clusters are found, exit the script
if ($Clusters.count -lt 1)
{
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

# Log/Enumerate which cluser was selected
Write-Host "Selected cluster is " -NoNewline 
Write-Host $Cluster -ForegroundColor Green
Write-Host ""

#########################################################
# Update the iSCSI Send Targets on all Hosts Selected   #
#########################################################
$Cluster | Get-VMhost | Sort-Object Name | Foreach-Object {
    $EsxiHost = $_

    #########################################################
    # Ensure the iSCSI Static Target Exists                 #
    #########################################################
    $HostHba = $EsxiHost | Get-VMHostHba -Type IScsi | Where-Object {$_.Model -eq "iSCSI Software Adapter"}
    foreach ($HostStaticTarget in $FlashArrayIscsiIp) {

        # Remove the port from the Static Target
        $HostStaticTargetAddress = $HostStaticTarget.Split(":")[0] 

        if (Get-IScsiHbaTarget -IScsiHba $HostHba -Type Static | Where-Object {$_.Address -cmatch $HostStaticTargetAddress}) {
            Write-Host "The Static target $HostStaticTargetAddress " -NoNewLine 
            Write-Host "already exists on $EsxiHost" -ForegroundColor Green
            Write-Host " "
        }
        else {
            Write-Host "The target $HostStaticTargetAddress " -NoNewLine 
            Write-Host "doesn't exist on $EsxiHost" -ForegroundColor Red
            Write-Host "Creating $HostStaticTargetAddress on $host ..."
            Try {
                New-IScsiHbaTarget -IScsiHba $HostHba -Address $HostStaticTargetAddress -Port 3260 -IScsiName $FlashArrayIqn -Type Static
            } Catch {
                Write-Host "Could not create Static Target $($HostStaticTargetAddress) on $($EsxiHost.Name)" -NoNewline Red
                Write-Host $Error
            }
            Write-Host " "
        }
        Get-VMHostStorage -VMHost $EsxiHost -RescanAllHba -RescanVmfs  | Out-Null
    }
}

#########################################################
# Update FlashArray Host Entries to Match               #
#########################################################
Write-Host "Updating FlashArray Host Chap Credentials"
$PureHosts = Get-Pfa2Host | Where-Object {$_.HostGroup.Name -eq $Cluster.Name}

$PureHosts | Foreach-Object {
    $PureHost = $_

    if ($PureHost.Chap.HostUser -ne $null) {
        Write-Host "Chap is already configured for FlashArray Host $($PureHost.Name)" -NoNewLine
        Write-Host " "
    }
    else {
        Write-Host "Updating the ChapHostPassword and ChapTarget Password for FlashArray Host $($PureHost.Name)"
        Try {
            Update-Pfa2Host -Array $PURE_AUTH_2_X -Name $PureHost.Name -ChapHostPassword $chaphostpassword -ChapHostUser $($PureHost.Iqns).ToString() -ChapTargetPassword $chaptargetpassword -ChapTargetUser $($PureHost.Iqns).ToString() | Out-Null
            Write-Host "Successfully updated the ChapHostPassword and/or ChapTargetPassword for FlashArray Host $($_.Name)" -ForegroundColor Green
            Write-Host " "
        } Catch {
            Write-Host "Could not update the ChapHostPassword and/or ChapTargetPassword for FlashArray Host $($_.Name)" -ForegroundColor Red
            Write-Host $Error
            Write-Host " "
        }
    }
}
