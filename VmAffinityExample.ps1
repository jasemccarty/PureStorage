<#==========================================================================
Created on: 14 DEC 2021
Created by: Jase McCarty
Github: http://www.github.com/jasemccarty
Twitter: @jasemccarty
===========================================================================
VM Affinity Set/Get Examples for vMSC
Requirements - 
  1) PowerCLI 12.3 or higher (may work with older releases)
  2) Cluster Host Groups Created - Names MUST match a Tag
  3) Tags Created - Names MUST match Cluster Host Groups
  4) Datastores MUST be tagged with Tag specific to which Host Group they align with
  5) Category Tags are member of must be included

#>
function Get-VmHostGroupAffinityByStorageTag {
    <#
    .SYNOPSIS
      Updates the DRS VM Group a VM is assigned to, based on a Site Affinity Category & Host Group Tag
    .DESCRIPTION
      Takes a VM and vCenter Connection. A VM's VM Group assignment will be checked against the Host Group assignment it's datastore Host Group tag.
    .INPUTS
      vCenter Server, VM or VMs, and Tag Category
    .OUTPUTS
      Returns the operation of assigning, reassigning, or leaving the VM's assignment alone
    .NOTES
      Version:        1.0
      Author:         Jase McCarty https://www.jasemccarty.com/blog/
      Creation Date:  13 DEC 2021
      Purpose/Change: Meet a specific Site assignment based on a datastore's affinity assignment
    .EXAMPLE
      PS C:\  Get-VmHostGroupAffinityByStorageTag -vm 
      PS C:\  Update-PfaVvolVmVolumeGroup -vm (get-vm myVM)
      
      Updated the volume group for a virtual machine on the default FlashArray
    .EXAMPLE
      PS C:\ Get-VmHostGroupAffinityByStorageTag -vm "SQLVM" -tagcategory "SiteAffinity"
    #>
    [CmdletBinding()]
    Param(
            [Parameter(Mandatory=$false)][String]$vm,
            [Parameter(Mandatory=$true)][String]$tagcategory
    )

    # Get VM's matching the search criteria and place them in an array
    $VmList = Get-VM | Where-Object {$_.Name -Like $vm}

    # Create our VM Affinity List Array
    $VmAffinity = @()

    Foreach ($WorkingVM in $VmList) {

        # Get the datastore the current VM is on
        $Datastore = $WorkingVM | Get-Datastore

        # Get the current cluster the VM resides in
        $Cluster = $WorkingVM | Get-Cluster

        # Get the VM group assignment of the VM if any
        $CurrentVMGroup = Get-DrsClusterGroup -Cluster ($WorkingVM | Get-Cluster) -Type VMGroup | Where-Object {$_.Member -Like $WorkingVM} -ErrorAction SilentlyContinue

        # Get the tags for the specified affinity category for the VM's datastore
        $DatastoreTags = Get-TagAssignment -Entity $Datastore -Category $tagcategory

        # Get the Host Group assignment (tag) from the affinity category
        $DatastoreHostGroup = $DatastoreTags.Tag.Name
        if ($null -eq $DatastoreHostGroup) { $DatastoreHostGroup = 'no Host Group assigned'}

        # Get the Host Group for the Datastore for the VM's datastore
        $DrsClusterGroup = Get-DrsClusterGroup -Cluster $Cluster -Type VMHostGroup -Name $DatastoreHostGroup -ErrorAction SilentlyContinue

        # Get the VM Group that the VM should reside in
        
        $DrsVMGroup = (Get-DrsVMHostRule -Cluster $Cluster -VMHostGroup $DrsClusterGroup).VMGroup 
    
        if ($CurrentVMGroup.Name -eq $DrsVMGroup.Name) { $AssignedCorrectly=$true} else { $AssignedCorrectly=$false}
        if ($DrsVMgroup.Count -gt 1) {$DrsVMGroup='no VM Group assigned';$AssignedCorrectly=$false}

        $VmAffinity += [PsCustomObject]@{
            Cluster            = $Cluster;
            VM                 = $WorkingVM;
            CurrentVMGroup     = $CurrentVMGroup;
            ExpectedVMGroup    = $DrsVMGroup;
            Datastore          = $Datastore;
            DatastoreHostGroup = $DatastoreHostGroup;
            AssignedCorrectly  = $AssignedCorrectly

        }
    }
        return $VmAffinity | Format-Table
    
# End of Function
}

function Set-VmHostGroupAffinityByStorageTag {
    <#
    .SYNOPSIS
      Updates the DRS VM Group a VM is assigned to, based on a Site Affinity Category & Host Group Tag
    .DESCRIPTION
      Takes a VM and vCenter Connection. A VM's VM Group assignment will be checked against the Host Group assignment it's datastore Host Group tag.
    .INPUTS
      vCenter Server, VM or VMs, and Tag Category
    .OUTPUTS
      Returns the operation of assigning, reassigning, or leaving the VM's assignment alone
    .NOTES
      Version:        1.0
      Author:         Jase McCarty https://www.jasemccarty.com/blog/
      Creation Date:  13 DEC 2021
      Purpose/Change: Meet a specific Site assignment based on a datastore's affinity assignment
    .EXAMPLE
      PS C:\ Set-VmHostGroupAffinityByStorageTag -vm "SQLVM" -tagcategory "SiteAffinity" -Confirm $True 

      Removing VM: nsqltest from VM Group DC2VMs
      Perform operation?
      Should perform operation 'Update DRS cluster group' on 'DC2VMs'?
      [Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Yes"): y
      Adding VM: nsqltest to VM Group DC1VMs
      Perform operation?
      Should perform operation 'Update DRS cluster group' on 'DC1VMs'?
      [Y] Yes [A] Yes to All [N] No [L] No to All [S] Suspend [?] Help (default is "Yes"): y

      Cluster  VM       CurrentVMGroup ExpectedVMGroup Datastore             DatastoreHostGroup AssignedCorrectly
      -------  --       -------------- --------------- ---------             ------------------ -----------------
      Cluster1 nsqltest DC1VMs         DC1VMs          m70-x70-activecluster DC1Hosts                        True
      Cluster1 nsqlprod                                sn1-m70-f06-33-vmfs                                   True


    .EXAMPLE
      PS C:\ Set-VmHostGroupAffinityByStorageTag -vm "SQLVM" -tagcategory "SiteAffinity" -Confirm $False

      Cluster  VM       CurrentVMGroup ExpectedVMGroup Datastore             DatastoreHostGroup AssignedCorrectly
      -------  --       -------------- --------------- ---------             ------------------ -----------------
      Cluster1 nsqltest DC1VMs         DC1VMs          m70-x70-activecluster DC1Hosts                        True
      Cluster1 nsqlprod                                sn1-m70-f06-33-vmfs                                   True
    #>
    [CmdletBinding()]
    Param(
      [Parameter(Mandatory=$false)][String]$vm,
            [Parameter(Mandatory=$true)][String]$tagcategory,
            [Parameter(Mandatory=$false)][Boolean]$confirm
    )

    # Get VM's matching the search criteria and place them in an array
    $VmList = Get-VM -Name $vm

    # Create our VM Affinity List Array
    $VmAffinity = @()

    Foreach ($WorkingVM in $VmList) {

        # Get the datastore the current VM is on
        $Datastore = $WorkingVM | Get-Datastore

        # Get the current cluster the VM resides in
        $Cluster = $WorkingVM | Get-Cluster

        # Get the VM group assignment of the VM if any
        $CurrentVMGroup = Get-DrsClusterGroup -Cluster $Cluster -Type VMGroup | Where-Object {$_.Member -Like $WorkingVM} -ErrorAction SilentlyContinue

        # Get the tags for the specified affinity category for the VM's datastore
        $DatastoreTags = Get-TagAssignment -Entity $Datastore -Category $tagcategory

        # Get the Host Group assignment (tag) from the affinity category
        $DatastoreHostGroup = $DatastoreTags.Tag.Name

        if ($null -eq $DatastoreHostGroup) { 
            # If there is no Host Group assignment for the datastore, do not make any changes
            $DatastoreHostGroup = ' '
            $DrsClusterGroup = $null
            $DrsVMGroup = $null
        } else {
            # Get the Host Group for the Datastore for the VM's datastore
            $DrsClusterGroup = Get-DrsClusterGroup -Cluster $Cluster -Type VMHostGroup -Name $DatastoreHostGroup -ErrorAction SilentlyContinue

            # Get the VM Group that the VM should reside in    
            $DrsVMGroup = (Get-DrsVMHostRule -Cluster $Cluster -VMHostGroup $DrsClusterGroup).VMGroup 

            # If the datastore has a Host Group assignment, let's check to ensure the VM has the proper VM Group assignment
            if ($CurrentVMGroup.Name -eq $DrsVMGroup.Name) { 
                $AssignedCorrectly=$true
            } else {
                # Make changes based on the VM Group assignment
                if ($null -ne $CurrentVMGroup) {
                    Write-Host "Removing VM: $($WorkingVM) from VM Group $($CurrentVMGroup)"
                    Set-DrsClusterGroup -DrsClusterGroup $CurrentVMGroup -VM $WorkingVM -Remove -Confirm:$confirm | Out-Null
                }
                Write-Host "Adding VM: $($WorkingVM) to VM Group $($DrsVMGroup)"
                Set-DrsClusterGroup -DrsClusterGroup $DrsVMGroup -VM $WorkingVM -Add -Confirm:$confirm | Out-Null
                $CurrentVMGroup = Get-DrsClusterGroup -Cluster $Cluster -Type VMGroup | Where-Object {$_.Member -Like $WorkingVM} -ErrorAction SilentlyContinue
                $AssignedCorrectly = $True
            }
        }

        $VmAffinity += [PsCustomObject]@{
            Cluster            = $Cluster;
            VM                 = $WorkingVM;
            CurrentVMGroup     = $CurrentVMGroup;
            ExpectedVMGroup    = $DrsVMGroup;
            Datastore          = $Datastore;
            DatastoreHostGroup = $DatastoreHostGroup;
            AssignedCorrectly  = $AssignedCorrectly

        }
    }   $DrsVMGroup = $null
        return $VmAffinity | Format-Table
    
# End of Function
}

#Set-VmHostGroupAffinityByStorageTag -vm "n*" -tagcategory "SiteAffinity" -Confirm $True
#Get-VmHostGroupAffinityByStorageTag -vm "n*" -tagcategory "SiteAffinity"
