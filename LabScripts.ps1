#
# To Run On Skype For Business Front End server
#

#region###########################     Block 1                ####### PARAMETERS     
$DomainName = "LabXXXXX.o365ready.com"
$subDomainName = "corp."+$DomainName
$O365defaultDomain = "xxxxxxxx.onmicrosoft.com"
$ResourceGroupName = "labXXXXX"
$subscriptionName = "Free Trial"
#$LBDNSName = "labxxxxxdmz.westeurope.cloudapp.azure.com." -- Not used

#O365 credential
$Username= "admin@xxxxxxx.onmicrosoft.com"
#$Password = "pass@word"
#$SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
#[PSCredential ]$O365Cred = New-Object PSCredential ($Username, $SecurePassword)
$O365Cred = Get-credential -UserName $Username -message "Office365 Online credential"

#Azure credential
$AzureUsername = "admin@labXXXXX.onmicrosoft.com"
#$AzurePassword = "pass@word"
#$SecurePassword = ConvertTo-SecureString -String $AzurePassword -AsPlainText -Force
#[PSCredential ]$AzureCred = New-Object PSCredential (AzureUsername, $SecurePassword)
$AzureCred = Get-credential -UserName $AzureUsername -message "Azure credential"
#endregion#############################################################



#region###########################     Block 2                ####### Install MSOL and WAAD and Azure RM
#Download and install MSOL
Invoke-WebRequest -Uri https://download.microsoft.com/download/5/0/1/5017D39B-8E29-48C8-91A8-8D0E4968E6D4/en/msoidcli_64.msi -OutFile c:\msoidcli_64.msi
Start-Process -FilePath msiexec -ArgumentList /i, c:\msoidcli_64.msi, /quiet -Wait
#Download and install MWindows Azure Active Directory Module for Windows PowerShell
#Invoke-WebRequest -Uri https://go.microsoft.com/fwlink/p/?linkid=236297 -OutFile c:\AdministrationConfig-en.msi
Invoke-WebRequest -Uri "http://download.connect.microsoft.com/pr/AdministrationConfig_3.msi?t=81017406-00d3-47f5-acc6-cfcad5aa3869&e=1496264044&h=0c61bb8c735b47302a24133aecd216a6" -OutFile c:\AdministrationConfig-en.msi
Start-Process -FilePath msiexec -ArgumentList /i, c:\AdministrationConfig-en.msi, /quiet -Wait
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Install-Module AzureRM.Dns -Confirm:$false -Force
#endregion#############################################################



#region###########################     Block 3                ####### CUSTOM DOMAIN
Import-Module $env:USERPROFILE\Desktop\Scripts\Office365scripts.ps1

Add-CustomDomain -DomainName $DomainName -Credential $O365Cred -AzureCredential $AzureCred -ResourceGroupName $ResourceGroupName -subscriptionName $subscriptionName

#Remove-CustomDomain -DomainName $DomainName -Username $Username -Password $Password
#New-AzureDnsZone -DomainName $DomainName -Username "" -Password "" -ResourceGroupName "" -subscriptionName "" -LoadBalancerDNSName ""
Remove-Module Office365scripts
#endregion#############################################################



#region###########################     Block 4                ####### LICENSE SYNCED USERS
Import-module $env:USERPROFILE\Desktop\Scripts\EnableUserLicenses.ps1

Enable-UserLicence -DomainName $DomainName -Credential $O365Cred 

Remove-Module EnableUserLicenses
#endregion#############################################################



#region###########################     Block 5                ####### ENABLE IM&P FOR OWA
New-CsHostingProvider -Identity "Exchange Online" -Enabled $True -EnabledSharedAddressSpace $True -HostsOCSUsers $False -ProxyFqdn "exap.um.outlook.com" -IsLocal $False -VerificationLevel UseSourceVerification
#endregion#############################################################



#region###########################     Block 6                ####### ENABLE OAUTH WITH EX ONLINE (for skype meeting)
Import-module $env:USERPROFILE\Desktop\Scripts\ExchangeOnlineScripts.ps1

Enable-ExOnlineOauth -DomainName $DomainName -Credential $O365Cred 
#Disable-EXOnlineOauth -DomainName $DomainName -Username $Username -Password $Password

Remove-Module ExchangeOnlineScripts
#endregion#############################################################



#region###########################     Block 7                ####### ENABLE UM
Import-module $env:USERPROFILE\Desktop\Scripts\ExchangeOnlineScripts.ps1

#Deploy ExUM
Deploy-ExUM -DomainName $DomainName -O365defaultDomain $O365defaultDomain -Credential $O365Cred 
#Remove ExUM
#Remove-UMDP -DomainName $DomainName -Username $Username -Password $Password

Remove-Module ExchangeOnlineScripts
#endregion#############################################################



#region###########################     Block 8                ####### ENABLE SHARED SIP
#configure onprem
Remove-CsHostingProvider -Identity 'Skype For Business Online'
New-CSHostingProvider -Identity 'Skype For Business Online' -ProxyFqdn "sipfed.online.lync.com" -Enabled $true -EnabledSharedAddressSpace $true -HostsOCSUsers $true -VerificationLevel UseSourceVerification -IsLocal $false -AutodiscoverUrl https://webdir.online.lync.com/Autodiscover/AutodiscoverService.svc/root

#configure online
$session= New-CsOnlineSession -Credential $O365Cred 
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
$session= New-CsOnlineSession -Credential $O365Cred 
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