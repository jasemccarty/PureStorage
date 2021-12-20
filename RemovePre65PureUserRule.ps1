<#==========================================================================
Script Name: RemovePre65PureUserRule.ps1
Created on: 12/20/2021
Created by: Jase McCarty
Github: http://www.github.com/jasemccarty
Twitter: @jasemccarty
Website: http://www.jasemccarty.com
===========================================================================
.DESCRIPTION
Remove any User PSP/SATP Rule for FlashArray
Powershell Core supported - Requires PowerCLI
.SYNTAX
RemovePre65PureUserRule.ps1 -EsxiHost <EsxiHost>
#>

# Set our Parameters
[CmdletBinding()]Param(
  [Parameter(Mandatory = $False)][string]$EsxiHost
)

# Check to see if a current ESXi Server session is in place
If ($Global:DefaultVIServer) {
    Write-Host "Connected to " -NoNewline 
    Write-Host $Global:DefaultVIServer -ForegroundColor Green
    If ($Global:DefaultVIServer.ProductLine -ne "embeddedEsx") {
        Write-Host "This is not an ESXi host. Please connect to an individual ESXi host"
        return
    } else {
        Write-Host "Connected to ESXi."
        If ($Global:DefaultVIServer.Name -eq $EsxiHost) {
            Write-Host "Already connected to $($Global:DefaultVIServer.Name)"
        } else {
            Write-Host "Not connected to $($EsxiHost), so disconnecting from $($Global:DefaultVIServer.Name)"
            Disconnect-Viserver * -Confirm:$false

            $VICredentials = Get-Credential -Message "Enter credentials for the ESXi host" 
            try {
                Connect-VIServer -Server $EsxiHost -Credential $VICredentials -ErrorAction Stop | Out-Null
                Write-Host "Connected to $EsxiHost" -ForegroundColor Green 
                If ($Global:DefaultVIServer.ProductLine -ne "embeddedEsx") {
                    Write-Host "This is not an ESXi host. Please connect to an individual ESXi host"
                    return
                } 
            }
            catch {
                Write-Host "Failed to connect to $EsxiHost" -BackgroundColor Red
                Write-Host $Error
                Write-Host "Terminating the script " -BackgroundColor Red
                return
            }

        }
    }
} else {
    Write-Host "Not connected to an ESXi host" -ForegroundColor Red
    $EsxiHost = Read-Host "Please enter the ESXi host FQDN"  
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
# Create our EsxCli context for the current host
$EsxCli = Get-EsxCli -VMHost (Get-VMhost) -V2

# Retrieve any User storage Rules for Pure Storage
Write-Host "Grabbing any User Rules for Pure Storage"
$SatpUserRules = $esxcli.storage.nmp.satp.rule.list.Invoke()| Where-Object {($_.RuleGroup -eq "user") -and ({$_.Model -Like "FlashArray"})}

# IF we have 1 or more rules, 
if ($SatpUserRules.Count -ge "1") {
    Write-Host "Found $($SatpUserRules.Count)"

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
    Write-Host "No User rules were found for Pure Storage FlashArray" -ForegroundColor Green
}

Write-Host "Disconnecting from $(Get-VMHost)"
Disconnect-VIServer * -Confirm:$false
