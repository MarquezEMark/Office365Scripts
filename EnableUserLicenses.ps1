
Function Enable-UserLicence {
Param (		
		[Parameter(Mandatory=$true, HelpMessage = "Please enter the Domain name you want to remove")]
        [String]$DomainName,
		[Parameter(Mandatory=$true, HelpMessage = "Please enter the O365 Admin User Name")]
        [string]$Username,
	    [Parameter(Mandatory=$true, HelpMessage = "Please enter the O365 Admin Password")]
        [string]$Password


       )

write "##################Connect to Office 365#########################"
$SecurePassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
[PSCredential ]$cred = New-Object PSCredential ($Username, $SecurePassword)
#Now you can login using that credential object:
Import-Module MSOnline
Connect-MsolService -Credential $cred

#Delete existing Office365 Licenced demo users exept administrator
get-msoluser |  where {($_.lastName -notmatch 'Administrator') -and ($_.IsLicensed -eq $true) -and ($_.UserPrincipalName-like '*onmicrosoft.com') } | Remove-MsolUser -Force

#Set usagelocage for synced user
Get-MsolUser | where {$_.UserPrincipalName -like '*'+$DomainName } | Set-MsolUser -UsageLocation GB

#Set Licence for synced user (except for Wfindit user) 
$AccountskuId = (Get-MsolAccountSku).AccountskuId
Get-MsolUser | where {($_.UserPrincipalName -like '*'+$DomainName) -and ($_.UserPrincipalName -notlike 'wfindit*')} | Set-MsolUserLicense -AddLicenses $AccountskuId

#print all Domain user
Get-MsolUser | where {$_.UserPrincipalName -like '*'+$DomainName }
}