Function Add-CustomDomain {
Param (		
		[Parameter(Mandatory=$true, HelpMessage = "Please enter the Domain name you want to remove")]
        [String]$DomainName,
		[Parameter(Mandatory=$true, HelpMessage = "Please enter Office 365 Credential")]
        [PSCredential]$Credential,
		[Parameter(Mandatory=$true, HelpMessage = "Please enter the Azure Credential")]
        [PSCredential]$AzureCredential,
        [Parameter(Mandatory=$true, HelpMessage = "Please enter the Resource group Name which contains the zone")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory=$true, HelpMessage = "Please enter the Azure subscription Name of the resource")]
        [string]$subscriptionName
	    


       )


write "##################Connect to Office 365#########################"
Import-Module MSOnline
Connect-MsolService -Credential $Credential

write "##################Connect to Azure##############################"
Login-AzureRmAccount -Credential $AzureCredential
Select-AzureRmSubscription -SubscriptionName $subscriptionName


write "###############Add DomainName in Office 365#########################"
New-MsolDomain -Name $DomainName -ErrorAction Continue
Get-MsolDomain

write "###############Get DNS verification code############################"
$txt=Get-MsolDomainVerificationDns -DomainName $DomainName -Mode DnsTxtRecord
write $txt

write "###############create DNS record in Azure ##########################"
New-AzureRmDnsRecordSet -Name '@' -RecordType "TXT" -ZoneName $txt.Label -ResourceGroupName $ResourceGroupName -Ttl $txt.Ttl -DnsRecords (New-AzureRmDnsRecordConfig -Value $txt.Text) -Overwrite

Start-Sleep 10

write "############Confirm the DomainName is verified#############"
Confirm-MsolDomain -DomainName $DomainName -ErrorAction Continue


write "############create Exchange Office 365 DNS record in Azure##########"
#Exchange Records
$MX = $DomainName.replace('.','-') + '.mail.protection.outlook.com'
$SPF = "v=spf1 include:spf.protection.outlook.com -all"
$Auto = "autodiscover.outlook.com"
New-AzureRmDnsRecordSet -Name '@' -RecordType "MX" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -Exchange $MX -Preference 0) -Overwrite
New-AzureRmDnsRecordSet -Name '@' -RecordType "TXT" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -Value $SPF) -Overwrite
New-AzureRmDnsRecordSet -Name 'autodiscover' -RecordType "CName" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -Cname $Auto) -Overwrite

#write "########################################## Modified DNs Zone  #################################"
#Get-AzureRmDnsRecordSet -ZoneName $DomainName -ResourceGroupName $ResourceGroupName
write "########################################## Get-Office 365 Domain #################################"
Get-MsolDomain -DomainName $DomainName
}

Function Remove-CustomDomain {
Param (		
		[Parameter(Mandatory=$true, HelpMessage = "Please enter the Domain name you want to remove")]
        [String]$DomainName,
		[Parameter(Mandatory=$true, HelpMessage = "Please enter Office 365 Credential")]
        [PSCredential]$Credential

       )
	   
write "################# Connect to Office 365#########################"
Import-Module MSOnline
Connect-MsolService -Credential $Credential


write "################ Get all existing Domains........###############"
Get-MsolDomain

write "################ Disable directory synchronization #############"
#Disable directory synchronization
Set-MsolDirSyncEnabled –EnableDirSync $false -Force -Verbose

#Verifiy Enabled equal False
(Get-MSOLCompanyInformation).DirectorySynchronizationEnabled

write "############### Remove all objects from the domain #############"
write "Get existing Domain Users......."
Get-MsolUser -DomainName $DomainName
write "Remove Domain Users......."
Get-MsolUser -DomainName $DomainName | Remove-MsolUser -Force -Verbose
write "Confirm Domain Users are removed...."
Get-MsolUser -DomainName $DomainName

#Remove Domain
write "###############Remove $DomainName Domain...................................#######"
Remove-MsolDomain -DomainName $DomainName -Force -Verbose
write "###############Confirm $DomainName Domain is Removed.......................#######"
Get-MsolDomain

}

Function New-AzureDnsZone {

Param (		
		[Parameter(Mandatory=$true, HelpMessage = "Please enter the DNS Zone name you want to create")]
        [String]$DomainName,
		[Parameter(Mandatory=$true, HelpMessage = "Please enter the Azure Credential")]
        [PSCredential]$Credential,
        [Parameter(Mandatory=$true, HelpMessage = "Please enter the Resource group Name which will contain the zone")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory=$true, HelpMessage = "Please enter the Azure subscription Name to use")]
        [string]$subscriptionName,
        [Parameter(Mandatory=$False, HelpMessage = "Please enter the Azure Load Balencer DNS name for reverse proxy/skype Edge server")]
        [string]$LoadBalancerDNSName

       )
#Now you can login using that credential object:
Login-AzureRmAccount -Credential $Credential
Select-AzureRmSubscription -SubscriptionName $subscriptionName

#Create new Zone
New-AzureRmDnsZone -Name $DomainName -ResourceGroupName $ResourceGroupName -ErrorAction Continue

#Add skype and ADFS records
if ($LoadBalancerDNSName) {
    $sipurl = 'sip.'+$DomainName+'.'
    New-AzureRmDnsRecordSet -Name sip -RecordType "CName" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -CName $LoadBalancerDNSName) -ErrorAction Continue -Overwrite
    New-AzureRmDnsRecordSet -Name webext -RecordType "CName" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -CName $sipurl) -ErrorAction Continue -Overwrite
    New-AzureRmDnsRecordSet -Name meet -RecordType "CName" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -CName $sipurl) -ErrorAction Continue -Overwrite
    New-AzureRmDnsRecordSet -Name dialin -RecordType "CName" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -CName $sipurl) -ErrorAction Continue -Overwrite
    New-AzureRmDnsRecordSet -Name lyncdiscover -RecordType "CName" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -CName $sipurl) -ErrorAction Continue -Overwrite
    New-AzureRmDnsRecordSet -Name sts -RecordType "CName" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -CName $sipurl) -ErrorAction Continue -Overwrite
    New-AzureRmDnsRecordSet -Name _sipfederationtls._tcp -RecordType "SRV" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -Port 5061 -Priority 0 -Weight 10 -Target $sipurl) -ErrorAction Continue -Overwrite
    New-AzureRmDnsRecordSet -Name _sip._tls -RecordType "SRV" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -Port 5061 -Priority 0 -Weight 10 -Target $sipurl) -ErrorAction Continue -Overwrite
    }

}

Function Set-AzureDnsOnlineRecords {

Param (		
		[Parameter(Mandatory=$true, HelpMessage = "Please enter the DNS Zone name you want to create")]
        [String]$DomainName,
		[Parameter(Mandatory=$true, HelpMessage = "Please enter the Azure Credential")]
        [PSCredential]$Credential,
        [Parameter(Mandatory=$true, HelpMessage = "Please enter the Resource group Name which will contain the zone")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory=$true, HelpMessage = "Please enter the Azure subscription Name to use")]
        [string]$subscriptionName

       )
#Now you can login using that credential object:
Login-AzureRmAccount -Credential $Credential
Select-AzureRmSubscription -SubscriptionName $subscriptionName

#Create new Zone if it does not exist
New-AzureRmDnsZone -Name $DomainName -ResourceGroupName $ResourceGroupName -ErrorAction Continue

#Add skype online DNS records
New-AzureRmDnsRecordSet -Name sip -RecordType "CName" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -CName sipdir.online.lync.com) -ErrorAction Continue -Overwrite
New-AzureRmDnsRecordSet -Name lyncdiscover -RecordType "CName" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -CName webdir.online.lync.com) -ErrorAction Continue -Overwrite
New-AzureRmDnsRecordSet -Name _sipfederationtls._tcp -RecordType "SRV" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -Port 5061 -Priority 1 -Weight 10 -Target sipfed.online.lync.com) -ErrorAction Continue -Overwrite
New-AzureRmDnsRecordSet -Name _sip._tls -RecordType "SRV" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -Port 443 -Priority 1 -Weight 100 -Target sipdir.online.lync.com) -ErrorAction Continue -Overwrite

#Intune records
New-AzureRmDnsRecordSet -Name msoid -RecordType "CName" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -CName clientconfig.microsoftonline-p.net) -ErrorAction Continue -Overwrite
New-AzureRmDnsRecordSet -Name enterpriseregistration -RecordType "CName" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -CName enterpriseregistration.windows.net) -ErrorAction Continue -Overwrite
New-AzureRmDnsRecordSet -Name enterpriseenrollment -RecordType "CName" -ZoneName $DomainName -ResourceGroupName $ResourceGroupName -Ttl 3600 -DnsRecords (New-AzureRmDnsRecordConfig -CName enterpriseenrollment.manage.microsoft.com) -ErrorAction Continue -Overwrite

}

