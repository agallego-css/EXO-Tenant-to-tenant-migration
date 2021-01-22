
<#
	Title: Cross-Tenant-Migration-AttributeSync.ps1
	Version: 0.1
	Date: 2021.01.22
	Authors: Denis Vilaca Signorelli (denis.signorelli@microsoft.com)

    .REQUIREMENTS: 
    
    1 - ExchangeOnlineManagement module (EXO v2) is required to run this script. 
        You can install manually using: Install-Module -Name ExchangeOnlineManagement. 
        If you don't install EXO v2 manually, the will install it automatically for you.

    2 - To make things easier, run this script from Exchange On-Premises machine powershell, 
        the script will automatically import the Exchange On-Prem module. If you don't want 
        to run the script from an Exchange machine, use the switch -LocalMachineIsNotExchange 
        and enter the FQDN of an Exchange Server. You will be prompted to sign-in, use the same 
        credential that you are already logged in your domain machine

	.PARAMETES: 

    -AdminUPN 
        Mandatory parameter used to connec to to Exchange Online. Only the UPN is 
        stored to avoid token expiration during the session, no password is stored.

    -CustomAttributeNumber 
        Mandatory parameter used to inform the code which custom attributes will 
        be used to scope the search

    -CustomAttributeValue 
        Mandatory parameter used to inform the code which value will be used to 
        scope the search

    -SourceDomain 
        Mandatory parameter used to replace the source SMTP domain to the target SMTP 
        domain in the CSV. These values are not replaced on the object itself, only in the CSV. 

    -TargetDomain 
        Mandatory parameter used to replace the source SMTP domain to the target SMTP domain 
        in the CSV. These values are not replaced in the object itself, only in the CSV.  

    -Path
        Optional parameter used to inform which path will be used to save the CSV. 
        If no path is chosen, the script will save on desktop path. 

    -LocalMachineIsNotExchange
        Optional parameter used to inform that you are running the script from 
        a non-Exchange Server machine. This parameter will require the -ExchangeHostname. 

    -ExchangeHostname
        Mandatory parameter if the switch -LocalMachineIsNotExchange was used. 
        Used to inform the Exchange Server FQDN that the script will connect.


	.DESCRIPTION: 

    This script will dump all necessary attributes that cross-tenant RMS migration requires. 
    No changes will be performed this code.

    ##############################################################################################
    #This sample script is not supported under any Microsoft standard support program or service.
    #This sample script is provided AS IS without warranty of any kind.
    #Microsoft further disclaims all implied warranties including, without limitation, any implied
    #warranties of merchantability or of fitness for a particular purpose. The entire risk arising
    #out of the use or performance of the sample script and documentation remains with you. In no
    #event shall Microsoft, its authors, or anyone else involved in the creation, production, or
    #delivery of the scripts be liable for any damages whatsoever (including, without limitation,
    #damages for loss of business profits, business interruption, loss of business information,
    #or other pecuniary loss) arising out of the use of or inability to use the sample script or
    #documentation, even if Microsoft has been advised of the possibility of such damages.
    ##############################################################################################

#>


# Define Parameters
[CmdletBinding(DefaultParameterSetName="Default")]
Param(
    [Parameter(Mandatory=$true,
    HelpMessage="Enter an EXO administrator UPN")]
    [string]$AdminUPN,
    
    [Parameter(Mandatory=$true,
    HelpMessage="Enter the custom attribute number. Valid range: 1-15")]
    [ValidateRange(1,15)]
    [Int]$CustomAttributeNumber,
    
    [Parameter(Mandatory=$true,
    HelpMessage="Enter the custom attribute value that will be used")]
    [string]$CustomAttributeValue,
    
    [Parameter(Mandatory=$true,
    HelpMessage="Enter the SOURCE domain. E.g. contoso.com")]
    [string]$SourceDomain,
    
    [Parameter(Mandatory=$true,
    HelpMessage="Enter the TARGET domain. E.g. fabrikam.com")]
    [string]$TargetDomain,
    
    [Parameter(Mandatory=$false,
    HelpMessage="Enter a custom output path for the csv. if no value is defined it will save on Desktop")]
    [string]$Path,
    
    [Parameter(ParameterSetName="RemoteExchange",Mandatory=$false)]
    [switch]$LocalMachineIsNotExchange,
    
    [Parameter(ParameterSetName="RemoteExchange",Mandatory=$true,
    HelpMessage="Enter the remote exchange hostname")]
    [string]$ExchangeHostname
    )


if ( $Path -ne '' ) 
{ 

$outFile = "$path\UserListToImport.csv" 

} else {

$outFile = "$home\desktop\UserListToImport.csv"

}

$outArray = @() 
$CustomAttribute = "CustomAttribute$CustomAttributeNumber"
$SourceDomain = "@$SourceDomain"
$TargetDomain = "@$TargetDomain"

# Check if EXO v2 is installed, if not check if the powershell is RunAs admin
if (Get-Module -ListAvailable -Name ExchangeOnlineManagement) {
    
    Write-Host "Exchange Online Module v2 already exists"

} else {

    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $RunAs = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if ($RunAs -like 'False') {

        Write-Host 'Administrator rights are required to install modules. RunAs Administrator and then run the script'
        Exit

    } else {

        #User consent to install EXO v2 Module, if not stop the script
        $title    = 'Exchange Online Module v2 Installation'
        $question = 'Do you want to proceed with the module installation?'
        $choices  = '&Yes', '&No'
        $decision = $Host.UI.PromptForChoice($title, $question, $choices, 1)

        if ($decision -eq 0) {
        
            Write-Host 'Installing...'
            Install-Module ExchangeOnlineManagement -AllowClobber -Confirm:$False -Force

        } else {
        
            Write-Host 'We cannot proceed without EXO v2 module'
            Exit

        }

    }

}



# Connecto to Exchange and AD
if ( $LocalMachineIsNotExchange.IsPresent )
{
    $Credentials = Get-Credential -Message "Enter your Exchange admin credentials"
    $ExOPSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://$ExchangeHostname/PowerShell/ -Authentication Kerberos -Credential $Credentials
    Import-PSSession $ExOPSession -AllowClobber

    #Load remote AD module from the DC where the local PC is authenticated
    function Get-ModuleAD() {
    If ((Get-Module -Name RemAD | Measure-Object).Count -lt 1) {
        # Adding Active Directory connection and remap all commands to "RemAD": E.g.: Get-RemADUser
        If ((Get-Module -ListAvailable -Name RemAD | Measure-Object).Count -lt 1) {
            $sessionAD = New-PSSession -ComputerName $env:LogOnServer.Replace("\\","")
            Invoke-Command { Import-Module ActiveDirectory } -Session $sessionAD
            Export-PSSession -Session $sessionAD -CommandName *-AD* -OutputModule RemAD -AllowClobber -Force | Out-Null
            Remove-PSSession -Session $sessionAD
        } Else { Write-Output "Active Directory Module was exported" }
 
        #Create copy of the module on the local computer
        Import-Module RemAD -Prefix Rem -DisableNameChecking
    }
}

} else {

    Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn; 
}


# Save all properties from MEU object to variable
$RemoteMailboxes = Get-RemoteMailbox -resultsize unlimited | Where-Object {$_.$CustomAttribute -like $CustomAttributeValue}

# Remove Exchange On-Prem PSSession in order to connect later to EXO PSSession
$ClearSession = Get-PSSession | Remove-PSSession

# Connect specifying username, if you already have authenticated 
# to another moduel, you actually do not have to authenticate
Connect-ExchangeOnline -UserPrincipalName $AdminUPN -ShowProgress $true

# This will make sure when you need to reauthenticate after 1 hour 
# that it uses existing token and you don't have to write password
$global:UserPrincipalName=$AdminUPN

Foreach ($i in $RemoteMailboxes)  
{ 
 	$user = get-Recipient $i.alias 
 	$object = New-Object System.Object 
 	$object | Add-Member -type NoteProperty -name primarysmtpaddress -value $i.PrimarySMTPAddress 
 	$object | Add-Member -type NoteProperty -name alias -value $i.alias 
 	$object | Add-Member -type NoteProperty -name FirstName -value $User.FirstName 
 	$object | Add-Member -type NoteProperty -name LastName -value $User.LastName 
 	$object | Add-Member -type NoteProperty -name DisplayName -value $User.DisplayName 
 	$object | Add-Member -type NoteProperty -name Name -value $i.Name 
 	$object | Add-Member -type NoteProperty -name SamAccountName -value $i.SamAccountName 
 	$object | Add-Member -type NoteProperty -name legacyExchangeDN -value $i.legacyExchangeDN 
 	$object | Add-Member -type NoteProperty -name CustomAttribute -value $CustomAttribute    
 	$object | Add-Member -type NoteProperty -name CustomAttributeValue -value $CustomAttributeValue
    

    # Save all properties from EXO object to variable
    $EXOMailbox = Get-EXOMailbox -Identity $i.Alias -PropertySets Retention,Hold,Archive,StatisticsSeed

    # Get mailbox guid from EXO because if the mailbox was created from scratch 
    # on EXO, the ExchangeGuid would not write-back to On-Premises this value
    $object | Add-Member -type NoteProperty -name ExchangeGuid -value $EXOMailbox.ExchangeGuid
    
    # Get mailbox ECL value
    $ELCValue = 0 
    if ($EXOMailbox.LitigationHoldEnabled) {$ELCValue = $ELCValue + 8} 
    if ($EXOMailbox.SingleItemRecoveryEnabled) {$ELCValue = $ELCValue + 16} 
    if ($ELCValue -gt 0) { $object | Add-Member -type NoteProperty -name ELCValue -value $ELCValue}
    
    # Get the ArchiveGuid from EXO if it exist. The reason that we don't rely on
    # "-ArchiveStatus" parameter is that may not be trustable in certain scenarios 
    # https://docs.microsoft.com/en-us/office365/troubleshoot/archive-mailboxes/archivestatus-set-none
    if ( $EXOMailbox.ArchiveDatabase -ne '' -and 
         $EXOMailbox.ArchiveGuid -ne "00000000-0000-0000-0000-000000000000" )    
    {
        
        $object | Add-Member -type NoteProperty -name ArchiveGuid -value $EXOMailbox.ArchiveGuid
    
    }

    # Get any SMTP alias avoiding *.onmicrosoft
    $ProxyArray = @()
    $TargetArray = @()
    $Proxy = $i.EmailAddresses
	foreach ($email in $Proxy)
    {
        if ($email -notlike '*.onmicrosoft.com')
        {

            $ProxyArray = $ProxyArray += $email

        }

        if ($email -like '*.onmicrosoft.com')
        {

            $TargetArray = $TargetArray += $email

        }

    }
         
    # Join it using ";" and replace the old domain (source) to the new one (target)
    $ProxyToString = [system.String]::Join(";",$ProxyArray)
    $object | Add-Member -type NoteProperty -name EmailAddresses -value $ProxyToString.Replace($SourceDomain,$TargetDomain) 
    #TO DO: Provide input for more source and target domains and probably mapping them bases on CSV.

    # Get ProxyAddress only for *.mail.onmicrosoft to define in the target AD the targetAddress value
    $TargetToString = [system.String]::Join(";",$TargetArray)
    $object | Add-Member -type NoteProperty -name ExternalEmailAddress -value $TargetToString.Replace("smtp:","")


    if ( $LocalMachineIsNotExchange.IsPresent )
    {

        # Connect to AD exported module only if this machine isn't an Exchange   
        Get-ModuleAD
        $Junk = Get-RemADUser -Identity $i.SamAccountName -Properties *
    
    } else {

        $Junk = Get-ADUser -Identity $i.SamAccountName -Properties *

    }

        # Get Junk hashes, these are SHA-265 write-backed from EXO. Check if the user 
        # has any hash, if yes we convert the HEX to String removing the "-"
    if ( $null -ne $junk.msExchSafeSendersHash -and
         $junk.msExchSafeSendersHash -ne '' )
    {
        $SafeSender = [System.BitConverter]::ToString($junk.msExchSafeSendersHash)
        $Safesender = $SafeSender.Replace("-","")
        $object | Add-Member -type NoteProperty -name SafeSender -value $SafeSender
    }
    
    if ( $null -ne $junk.msExchSafeRecipientsHash -and
         $junk.msExchSafeRecipientsHash -ne '' )
    {
        $SafeRecipient = [System.BitConverter]::ToString($junk.msExchSafeRecipientsHash)
        $SafeRecipient = $SafeRecipient.Replace("-","")
        $object | Add-Member -type NoteProperty -name SafeRecipient -value $SafeRecipient 

    }

    if ( $null -ne $junk.msExchBlockedSendersHash -and
         $junk.msExchBlockedSendersHash -ne '' )
    {
        $BlockedSender = [System.BitConverter]::ToString($junk.msExchBlockedSendersHash)
        $BlockedSender = $BlockedSender.Replace("-","")
        $object | Add-Member -type NoteProperty -name BlockedSender -value $BlockedSender
    }


 	$outArray += $object 
} 

# Export to a CSV and clear up variables and sessions
$outArray | Export-CSV $outfile -notypeinformation
Remove-Variable * -ErrorAction SilentlyContinue
$ClearSession

