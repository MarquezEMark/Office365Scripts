# Office365Scripts
Office 365 scripts

# Import the module
```PowerShell
Import-Module ".\Office365scripts.ps1"
```

To be able to use functions included in Office365scripts.ps1 you should first import the module using previous command in a powershell prompt or my lovely ISE.

# Create an Azure DNS zone
In here, I am automating domain registration using Azure DNS. You should fisrt create a DNS zone using the folling command.

```PowerShell
New-AzureDnsZone -DomainName "MyDomain.com" -Username "azureadmin@contoso.onmicrosoft.com" -Password "password" -ResourceGroupName "MyRG" -subscriptionName "MySub" -LoadBalancerDNSName "DNSName-of-LB-IPaddr"
```

This command is leveraging "New-AzureRmDnsZone" but it is not only creating a DNS zone but first it will connect to your Azure tenant then it will populate the zone with some entries.
The LoadBalancerDNSName is optional and will be used to reate CName records.

# DNS zone delegation
Azure DNS is not a name registrar service (Azure DNS does not support purchasing of domain names) but a service providing name resolution using Microsoft Azure infrastructure thus we could leverage automation.

Therefore, after creating the Azure DNS Zone you should delegate your domain in your registrar provider to use Azure DNS Name servers located in your zone. For more details arround zone delegation refer to following article :
https://docs.microsoft.com/en-us/azure/dns/dns-domain-delegation

# Add Office 365 custom domain and verify it

```PowerShell
Add-CustomDomain -DomainName "MyDomain.com" -Username "admin@contoso.onmicrosoft.com" -Password "password" -AzureUsername "azureadmin@contoso.onmicrosoft.com" -AzurePassword "password" -ResourceGroupName "MyRG" -subscriptionName "MySub"
```

This Function will add a custom domain to your office 365 tenant and automate it's verification by using your Azure DNS zone. Then it will create Exchange Online DNS entries in the Azure DNS zone 

# Remove Office 365 custom domain
```PowerShell
Remove-CustomDomain -DomainName "MyDomain.com" -Username "admin@contoso.onmicrosoft.com" -Password "password"
```

This function will remove the custom domain and reset your tenant by disabling directory syncronisation and deleting all users from that domain 
