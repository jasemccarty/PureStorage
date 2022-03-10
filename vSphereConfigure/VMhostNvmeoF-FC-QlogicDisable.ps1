(Get-VMHostModule -VMhost (Get-Cluster -name "clustername" | Get-VMhost )).Where{$_.Name -eq "qlnativefc"} | Set-VMHostModule -Options "ql2xnvmesupport=0"
