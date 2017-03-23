#
#To run in Skype for Business FE server
#

##################################function to Enable Oauth with Ex Online
Function Enable-ExOnlineOauth {
Param (		
		[Parameter(Mandatory=$true, HelpMessage = "Please enter the Domain name you want to remove")]
        [String]$DomainName,
		[Parameter(Mandatory=$true, HelpMessage = "Please enter the O365 Admin User Name")]
        [string]$Username,
	    [Parameter(Mandatory=$true, HelpMessage = "Please enter the O365 Admin Password")]
        [string]$Password 
       )

$SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
[PSCredential ]$cred = New-Object PSCredential ($Username, $SecurePassword)

#region###### create New online Oauth server and Exchangeonline partner Application
write "##################New csonline session to get tenant id#########################"
#Get the Lync Online TenantId
$session= New-CsOnlineSession -Credential $cred
Import-PSSession $session -AllowClobber
$TenantID = (Get-CsTenant ).TenantId

# verify if Oauth server is already existing if not create a new oAuth Server with identity "microsoft.sts"
$sts = Get-CsOAuthServer microsoft.sts -ErrorAction SilentlyContinue
        
   if ($sts -eq $null)
      {
         New-CsOAuthServer microsoft.sts -MetadataUrl "https://accounts.accesscontrol.windows.net/$TenantId/metadata/json/1"
      }
   else
      {
         if ($sts.MetadataUrl -ne  "https://accounts.accesscontrol.windows.net/$TenantId/metadata/json/1")
            {
               Remove-CsOAuthServer microsoft.sts
               New-CsOAuthServer microsoft.sts -MetadataUrl "https://accounts.accesscontrol.windows.net/$TenantId/metadata/json/1"
            }
        }
# verify if existing otherwise create a new Lync Partner Application for Exchange Online with identity "microsoft.exchange"
$exch = Get-CsPartnerApplication microsoft.exchange -ErrorAction SilentlyContinue
        
if ($exch -eq $null)
   {
      New-CsPartnerApplication -Identity microsoft.exchange -ApplicationIdentifier 00000002-0000-0ff1-ce00-000000000000 -ApplicationTrustLevel Full -UseOAuthServer
    }
else
    {
       if ($exch.ApplicationIdentifier -ne "00000002-0000-0ff1-ce00-000000000000")
          {
             Remove-CsPartnerApplication microsoft.exchange
             New-CsPartnerApplication -Identity microsoft.exchange -ApplicationIdentifier 00000002-0000-0ff1-ce00-000000000000 -ApplicationTrustLevel Full -UseOAuthServer 
          }
       else
          {
             Set-CsPartnerApplication -Identity microsoft.exchange -ApplicationTrustLevel Full -UseOAuthServer
          }
   }
#use the service name of "00000004-0000-0ff1-ce00-000000000000" which is actually the Application Identifier of Lync Server
Set-CsOAuthConfiguration -ServiceName 00000004-0000-0ff1-ce00-000000000000

#endregion

#Download and install MSOL
Invoke-WebRequest -Uri https://download.microsoft.com/download/5/0/1/5017D39B-8E29-48C8-91A8-8D0E4968E6D4/en/msoidcli_64.msi -OutFile c:\msoidcli_64.msi
Start-Process -FilePath msiexec -ArgumentList /i, c:\msoidcli_64.msi, /quiet -Wait
#Download and install MWindows Azure Active Directory Module for Windows PowerShell
Invoke-WebRequest -Uri https://go.microsoft.com/fwlink/p/?linkid=236297 -OutFile c:\AdministrationConfig-en.msi
Start-Process -FilePath msiexec -ArgumentList /i, c:\AdministrationConfig-en.msi, /quiet -Wait

write "##################Connect to Office 365#########################"
#Now you can login using that credential object:
Import-Module MSOnlineExtended
Connect-MsolService -Credential $cred

#Export Oauth certificate to a Base64 format
$cert = get-childitem Cert:\LocalMachine\My | where  {$_.FriendlyName -match 'OathCert'}
$DERCert    = 'C:\Cert_DER_Encoded.cer'
$Base64Cert = 'C:\Cert_Base64_Encoded.cer' 
Export-Certificate -Cert $cert -FilePath $DERCert
Start-Process -FilePath 'certutil.exe' -ArgumentList "-encode $DERCert $Base64Cert" -WindowStyle Hidden

#Import, encode, and assign the oAuth certificate that was exported earlier
$certificate = New-Object System.Security.Cryptography.X509Certificates.X509Certificate
$certificate.Import('C:\Cert_Base64_Encoded.cer')
$binaryValue = $certificate.GetRawCertData()
$credentialsValue = [System.Convert]::ToBase64String($binaryValue)

#Assign the certificate to the Office 365 service principals : skype the Exchange
New-MsolServicePrincipalCredential -AppPrincipalId 00000004-0000-0ff1-ce00-000000000000 -Type Asymmetric -Usage Verify -Value $credentialsValue 
New-MsolServicePrincipalCredential -AppPrincipalId 00000002-0000-0ff1-ce00-000000000000 -Type Asymmetric -Usage Verify -Value $credentialsValue 

#configure the Exchange Online Service Principal and on-prem Skype for Business Server 2015 external Web services URLs
# as an Office 365 service principal.
Set-MSOLServicePrincipal -AppPrincipalID 00000002-0000-0ff1-ce00-000000000000 -AccountEnabled $true

$SkypeSP = Get-MSOLServicePrincipal -AppPrincipalID 00000004-0000-0ff1-ce00-000000000000
$SkypeSP.ServicePrincipalNames.Add('00000004-0000-0ff1-ce00-000000000000/webext.'+$DomainName)
Set-MSOLServicePrincipal -AppPrincipalID 00000004-0000-0ff1-ce00-000000000000 -ServicePrincipalNames $SkypeSP.ServicePrincipalNames

}

##################################function to Disable Oauth with Ex Online
Function Disable-EXOnlineOauth {
Param (		
		[Parameter(Mandatory=$true, HelpMessage = "Please enter the Domain name you want to remove")]
        [String]$DomainName,
		[Parameter(Mandatory=$true, HelpMessage = "Please enter the O365 Admin User Name")]
        [string]$Username,
	    [Parameter(Mandatory=$true, HelpMessage = "Please enter the O365 Admin Password")]
        [string]$Password 
       )

#remove Microsoft Oauth server
Remove-CsOAuthServer microsoft.sts

#remove Microsoft Exchange Online partner application
Remove-CsPartnerApplication microsoft.exchange


write "##################Connect to Office 365#########################"
$SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
[PSCredential ]$cred = New-Object PSCredential ($Username, $SecurePassword)
#Now you can login using that credential object:
Import-Module MSOnlineExtended
Connect-MsolService -Credential $cred

#Delete Oauth Certificate
$keyId=(Get-MsolServicePrincipalCredential -AppPrincipalId 00000004-0000-0ff1-ce00-000000000000 -ReturnKeyValues 1).keyId.Guid
Remove-MsolServicePrincipalCredential -AppPrincipalId 00000004-0000-0ff1-ce00-000000000000 -KeyIds $keyId


#Disable Exchange Online Service Principal 
Set-MSOLServicePrincipal -AppPrincipalID 00000002-0000-0ff1-ce00-000000000000 -AccountEnabled $false

#remove on-prem Skype for Business Server 2015 external Web services URLs from the O365 service principal
$SkypeSP = Get-MSOLServicePrincipal -AppPrincipalID 00000004-0000-0ff1-ce00-000000000000
$SkypeSP.ServicePrincipalNames.Remove('00000004-0000-0ff1-ce00-000000000000/webext.'+$DomainName)
Set-MSOLServicePrincipal -AppPrincipalID 00000004-0000-0ff1-ce00-000000000000 -ServicePrincipalNames $SkypeSP.ServicePrincipalNames

}


##################################function to Deploy ExUM
function Deploy-ExUM {
Param (		
		[Parameter(Mandatory=$true, HelpMessage = "Please enter your O365 Domain")]
        [String]$DomainName,
        [Parameter(Mandatory=$true, HelpMessage = "Please enter the Default O365 Domain name *.onmicrosoft.com")]
        [String]$O365defaultDomain,
		[Parameter(Mandatory=$true, HelpMessage = "Please enter the O365 Admin User Name")]
        [string]$Username,
	    [Parameter(Mandatory=$true, HelpMessage = "Please enter the O365 Admin Password")]
        [string]$Password 
       )

#region Actions to perform on Exchange online
write "##################Connect to Exchange Online#########################"
$SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
[PSCredential ]$cred = New-Object PSCredential ($Username, $SecurePassword)
$O365sess = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://ps.outlook.com/powershell -Credential $cred -Authentication Basic -AllowRedirection
Import-PSSession $O365sess -AllowClobber

#Create UM Dialplan
New-UMDialPlan -Name MyUMDialPlan -CountryOrRegionCode 44 -NumberOfDigitsInExtension 4 -URIType SIPName -DefaultLanguage en-GB -GenerateUMMailboxPolicy $false
Set-UMDialPlan -Identity MyUMDialPlan -PilotIdentifierList +441180001100

#Create UM Mailbox policy
New-UMMailboxPolicy -Name MyUMDialPlanPolicy -UMDialPlan MyUMDialPlan 
Set-UMMailboxPolicy -Identity MyUMDialPlanPolicy -MinPINLength 4 -PINHistoryCount 1 -AllowCommonPatterns $true -PINLifetime Unlimited

sleep 15
#Enable Mailboxes for UM
Get-CsUser | ForEach-Object {
    $upn = $_.SamAccountName+'@'+$DomainName
    $lineURI =$_.LineURI
    $Ext = $lineURI.substring($lineURI.length - 4, 4)
    Enable-UMMailbox -Identity $upn -UMMailboxPolicy MyUMDialPlanPolicy  -Extensions $Ext -SIPResourceIdentifier $upn
}
#endregion


#region Actions to perfom on Skype on-prem
#if there is no Exchange online Hosting provider Create it
$ExHostingProvider= Get-CsHostingProvider | where {$_.ProxyFqdn -match 'exap.um.outlook.com' }
if(!$ExHostingProvider) {
Write "Create Exchange online Hosting Provider : exap.um.outlook.com"
New-CsHostingProvider -Identity "Exchange Online" -Enabled $True -EnabledSharedAddressSpace $True -HostsOCSUsers $False -ProxyFqdn "exap.um.outlook.com" -IsLocal $False -VerificationLevel UseSourceVerification
}
#Create a Hosted Voicemail policy
Set-CsHostedVoicemailPolicy -Destination Exap.um.outlook.com -Organization $O365defaultDomain

#Enable users for hosted voice mail
Get-CsUser | Set-CsUser -HostedVoiceMail $true

#Create a Subscriber Access number in Lync to access voicemail
$user = (Get-csuser)[0]
$EXUMOU=($user.Identity -split “,”, 2)[1]
New-CsExUmContact -SipAddress sip:exumsa1@$DomainName -RegistrarPool (Get-CsService -Registrar)[0].PoolFqdn -OU $ExUMOU -DisplayNumber "+441180001100“ -ErrorAction Continue
#endregion

Remove-PSSession $O365sess

}

##################################function to remove ExUM
function Remove-ExUM {
Param (		
		[Parameter(Mandatory=$true, HelpMessage = "Please enter your O365 Domain")]
        [String]$DomainName,
		[Parameter(Mandatory=$true, HelpMessage = "Please enter the O365 Admin User Name")]
        [string]$Username,
	    [Parameter(Mandatory=$true, HelpMessage = "Please enter the O365 Admin Password")]
        [string]$Password 
       )

#region Actions to perform on Exchange online
write "##################Connect to Exchange Online#########################"
$SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
[PSCredential ]$cred = New-Object PSCredential ($Username, $SecurePassword)
$O365sess = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://ps.outlook.com/powershell -Credential $cred -Authentication Basic -AllowRedirection
Import-PSSession $O365sess -AllowClobber

#Disable Mailboxes for UM
Get-CsUser | ForEach-Object {
    $upn = $_.SamAccountName+'@'+$DomainName
    Disable-UMMailbox -Identity $upn -ErrorAction Continue -Confirm:$false
    }

#Delete Mailbox policy
Get-UMMailboxPolicy -Identity MyUMDialPlanPolicy |Remove-UMMailboxPolicy -Confirm:$false

#DeleteDialplan
Get-UMDialPlan -Identity MyUMDialPlan | Remove-UMDialPlan -Confirm:$false

Get-CsExUmContact | Remove-CsExUmContact
Remove-PSSession $O365sess
}

