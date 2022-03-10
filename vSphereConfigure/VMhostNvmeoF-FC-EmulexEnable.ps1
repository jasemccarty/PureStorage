Get-Cluster -Name "clustername" | Get-VMHost | Get-EsxCli  -v2 | Foreach-Object { $_.system.module.parameters.set.Invoke(@{module='lpfc';parameterstring='lpfc_enable_fc4_type=3'})}
