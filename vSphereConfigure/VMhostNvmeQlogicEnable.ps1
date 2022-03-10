(Get-VMHostModule -VMhost (Get-Cluster -name "cluster-jase" | Get-VMhost )).Where{$_.Name -eq "qlnativefc"} | Set-VMHostModule -Options "ql2xnvmesupport=1"
