#
# To Run On Skype For Business Front End server
#

#region###########################     Block 1                ####### PARAMETERS     
$DomainName = "LabXXXXX.o365ready.com"
$O365defaultDomain = "xxxxxxxx.onmicrosoft.com"
$Username= "admin@xxxxxxx.onmicrosoft.com"
$Password = "pass@word"
$AzureUsername = "admin@labXXXXX.onmicrosoft.com"
$AzurePassword = "pass@word"
$ResourceGroupName = "labXXXXX"
$subscriptionName = "Free Trial"
#$LBDNSName = "labxxxxxdmz.westeurope.cloudapp.azure.com." -- Not used
#endregion#############################################################



#region###########################     Block 2                ####### Install MSOL and WAAD and Azure RM
#Download and install MSOL
Invoke-WebRequest -Uri https://download.microsoft.com/download/5/0/1/5017D39B-8E29-48C8-91A8-8D0E4968E6D4/en/msoidcli_64.msi -OutFile c:\msoidcli_64.msi
Start-Process -FilePath msiexec -ArgumentList /i, c:\msoidcli_64.msi, /quiet -Wait
#Download and install MWindows Azure Active Directory Module for Windows PowerShell
Invoke-WebRequest -Uri https://go.microsoft.com/fwlink/p/?linkid=236297 -OutFile c:\AdministrationConfig-en.msi
Start-Process -FilePath msiexec -ArgumentList /i, c:\AdministrationConfig-en.msi, /quiet -Wait
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module AzureRM.Dns -Confirm:$false -Force
#endregion#############################################################



#region###########################     Block 3                ####### CuSTOM DOMAIN
Import-Module $env:USERPROFILE\Desktop\Scripts\Office365scripts.ps1

Add-CustomDomain -DomainName $DomainName -Username $Username -Password $Password `
                 -AzureUsername $AzureUsername -AzurePassword $AzurePassword -ResourceGroupName $ResourceGroupName -subscriptionName $subscriptionName

#Remove-CustomDomain -DomainName $DomainName -Username $Username -Password $Password
#New-AzureDnsZone -DomainName $DomainName -Username "" -Password "" -ResourceGroupName "" -subscriptionName "" -LoadBalancerDNSName ""
Remove-Module Office365scripts
#endregion#############################################################



#region###########################     Block 4                ####### LICENSE SYNCED USERS
Import-module $env:USERPROFILE\Desktop\Scripts\EnableUserLicenses.ps1

Enable-UserLicence -DomainName $DomainName -Username $Username -Password $Password 

Remove-Module EnableUserLicenses
#endregion#############################################################



#region###########################     Block 5                ####### ENABLE IM&P FOR OWA
New-CsHostingProvider -Identity "Exchange Online" -Enabled $True -EnabledSharedAddressSpace $True -HostsOCSUsers $False -ProxyFqdn "exap.um.outlook.com" -IsLocal $False -VerificationLevel UseSourceVerification
#endregion#############################################################



#region###########################     Block 6                ####### ENABLE OAUTH WITH EX ONLINE (for skype meeting)
Import-module $env:USERPROFILE\Desktop\Scripts\ExchangeOnlineScripts.ps1

Enable-ExOnlineOauth -DomainName $DomainName -Username $Username -Password $Password
#Disable-EXOnlineOauth -DomainName $DomainName -Username $Username -Password $Password

Remove-Module ExchangeOnlineScripts
#endregion#############################################################



#region###########################     Block 7                ####### ENABLE UM
Import-module $env:USERPROFILE\Desktop\Scripts\ExchangeOnlineScripts.ps1

#Deploy ExUM
Deploy-ExUM -DomainName $DomainName -O365defaultDomain $O365defaultDomain -Username $Username -Password $Password
#Remove ExUM
#Remove-UMDP -DomainName $DomainName -Username $Username -Password $Password

Remove-Module ExchangeOnlineScripts
#endregion#############################################################



#region###########################     Block 8                ####### ENABLE SHARED SIP
#configure onprem
Remove-CsHostingProvider -Identity 'Skype For Business Online'
New-CSHostingProvider -Identity 'Skype For Business Online' -ProxyFqdn "sipfed.online.lync.com" -Enabled $true -EnabledSharedAddressSpace $true -HostsOCSUsers $true -VerificationLevel UseSourceVerification -IsLocal $false -AutodiscoverUrl https://webdir.online.lync.com/Autodiscover/AutodiscoverService.svc/root

#configure online
$SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
[PSCredential ]$cred = New-Object PSCredential ($Username, $SecurePassword)
$session= New-CsOnlineSession -Credential $cred
Import-PSSession $session -AllowClobber
Set-CsTenantFederationConfiguration -SharedSipAddressSpace $true
Get-CsTenantFederationConfiguration
Remove-PSSession $session
#endregion#############################################################



#region###########################     Block 9                ####### MOVE USERS TO SKYPE ONLINE
$users= @('pgas','dend','dgate','tbag')

#Create and Grant a Voice routing policy to users that will be moved online
New-CsVoiceRoutingPolicy -Identity Tag:CloudPBXOnPremRouting –Name CloudPBXOnPremRouting -PSTNUsages (Get-CsPstnUsage).Usage
$users | ForEach-Object {
    $upn = $_+'@'+$DomainName
    write $upn
    Grant-CsVoiceRoutingPolicy -Identity $upn -PolicyName Tag:CloudPBXOnPremRouting
    }

#Connect CS online
$SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
[PSCredential ]$cred = New-Object PSCredential ($Username, $SecurePassword)
$session= New-CsOnlineSession -Credential $cred
Import-PSSession $session -AllowClobber
$HostedMigrationurl = 'https://'+$session.ComputerName+'/HostedMigration/hostedmigrationservice.svc'
write $HostedMigrationurl

#move users and Grant Enterprise voice and Hosted Voicemail capabilities
$users | ForEach-Object {
   $upn = $_+'@'+$DomainName
   write $upn
   Move-CsUser -Identity $upn -Target sipfed.online.lync.com -Credential $cred -HostedMigrationOverrideUrl $HostedMigrationurl -Confirm:$false
   Set-CsUser –Identity $upn –EnterpriseVoiceEnabled $true –HostedVoicemail $true
   Get-CsOnlineUser -Identity $upn | FL *voice*,*dial*,*Line*
}
Remove-PSSession $session
#endregion#############################################################


#region###########################     Block 10                ####### Dial plan for CloudPBX users
#Configure Dial plans and normalization rules
$CloudPBXDP= "CloudPBX_DialPlan"
New-CsDialPlan -Identity $CloudPBXDP -SimpleName $CloudPBXDP
Remove-CsVoiceNormalizationRule -Identity $CloudPBXDP'/Keep All'
New-CsVoiceNormalizationRule -Identity $CloudPBXDP'/ToSkypeUKUsers' -Pattern "^(1\d{3})$" -Translation '+44118000$1'
New-CsVoiceNormalizationRule -Identity $CloudPBXDP'/ToFreeSwitchUsers' -Pattern "^(2\d{3})$" -Translation '+44118000$1'
New-CsVoiceNormalizationRule -Identity $CloudPBXDP'/ToInternationalE164' -Pattern "^(\+|00)(\d{10}\d+)$" -Translation '+$2'
New-CsVoiceNormalizationRule -Identity $CloudPBXDP'/ToUKE164' -Pattern "^0(\d{10})$" -Translation '+44$1'

#
$users= @('pgas','dend','dgate','tbag')
$users | ForEach-Object {
   $upn = $_+'@'+$DomainName
   write $upn
   Grant-CsDialPlan -Identity $upn -PolicyName $CloudPBXDP

}
#endregion#############################################################