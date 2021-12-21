<#==========================================================================
Script Name: RemovePre65PureUserRuleV2.ps1
Created on: 12/20/2021
Created by: Jase McCarty
Github: http://www.github.com/jasemccarty
Twitter: @jasemccarty
Website: http://www.jasemccarty.com
Updates: Added support for all vSphere Hosts managed by vCenter
===========================================================================
.DESCRIPTION
Remove any User PSP/SATP Rule for FlashArray
Powershell Core supported - Requires PowerCLI
.SYNTAX
RemovePre65PureUserRuleV2.ps1 -EsxiHost <EsxiHost/EsxiHost returned from Get-VMhost>
#>

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
    
############################################################
# Check to see if we're connected to the vCenter,          #
# if not, prompt for Credentials to connect to it.         #
############################################################

# Check to see if a current vCenter Server session is in place
If ($Global:DefaultVIServer.Name) {
    Write-Host "Connected to " -NoNewline 
    Write-Host $Global:DefaultVIServer.Name -ForegroundColor Green
} else {
    # If not connected to vCenter Server make a connection
    Write-Host "Not connected to vCenter Server" -ForegroundColor Red
    $Vcenter = Read-Host "Please enter the vCenter FQDN"
    # Prompt for credentials using the native PowerShell Get-Credential cmdlet
    $VICredentials = Get-Credential -Message "Enter credentials for vCenter Server: $($Vcenter)" 
    try {
        # Attempt to connect to the vCenter Server 
        Connect-VIServer -Server $Vcenter -Credential $VICredentials -ErrorAction Stop | Out-Null
        Write-Host "Connected to $Vcenter" -ForegroundColor Green 
        # Note that we connected to vCenter so we can disconnect upon termination
        $ConnectVc = $True
    }
    catch {
        # If we could not connect to vCenter report that and exit the script
        Write-Host "Failed to connect to $Vcenter" -BackgroundColor Red
        Write-Host $Error
        Write-Host "Terminating the script " -BackgroundColor Red
        # Note that we did not connect to vCenter Server
        $ConnectVc = $False
        return
    }
}


Function Remove-VmHostUserRule.ps1
{

    [CmdletBinding()]
    Param
    (
        [Parameter(ValueFromPipeline,Mandatory)]
        [VMware.VimAutomation.ViCore.Impl.V1.Inventory.InventoryItemImpl[]]$EsxiHost
    )

   BEGIN
    {}
    PROCESS
    {

        # Loop through the EsxiHosts passed
        Foreach ($VMhost in $EsxiHost) {

            # Create our EsxCli context for the current host
            $EsxCli = Get-EsxCli -VMHost $VMhost -V2

            Write-Host "Current VMhost is " -NoNewLine
            Write-Host "$($VMhost): " -ForegroundColor Green -NoNewline

            # Retrieve any User storage Rules for Pure Storage
            Write-Host "Retrieving any User Rules for Pure Storage. " -NoNewline
            $SatpUserRules = $esxcli.storage.nmp.satp.rule.list.Invoke()| Where-Object {($_.RuleGroup -eq "user") -and ({$_.Model -Like "FlashArray"})}

            # IF we have 1 or more rules, 
            if ($SatpUserRules.Count -ge "1") {
                Write-Host "Found " -NoNewLine 
                Write-Host "$($SatpUserRules.Count) " -ForegroundColor Green -NoNewline
                Write-Host "user rules. " -NoNewLine

                # Loop through each User rule and remove it.
                Foreach ($SatpUserRule in $SatpUserRules) {
                    # Create an object to assign our arguments to
                    $SatpArgs = $esxcli.storage.nmp.satp.rule.remove.CreateArgs()

                    # Populate the argument object with the current User rule's properties
                    $SatpArgs.model = $SatpUserRule.Model
                    $SatpArgs.pspoption = $SatpUserRule.PSPOptions
                    $SatpArgs.vendor = $SatpUserRule.Vendor
                    $SatpArgs.description = $SatpUserRule.Description
                    $SatpArgs.psp = $SatpUserRule.DefaultPSP
                    $SatpArgs.satp = $SatpUserRule.Name
                    
                    # Remove the User rule
                    Write-Host "Removing the current User rule for Pure Storage"
                    $RemoveSatpUserRules = $esxcli.storage.nmp.satp.rule.remove.invoke($SatpArgs)    
                }
            } else {
                Write-Host "No User rules were found for Pure Storage FlashArray on " -NoNewLine 
                Write-Host "$($VMhost)" -ForegroundColor Green
            }
        }
    }
    END
    {}
} #END Function Remove-VmHostUserRule.ps1

$VMhosts = Get-VMhost | Sort-Object Name 

Remove-VmHostUserRule.ps1 -EsxiHost $VMhosts
