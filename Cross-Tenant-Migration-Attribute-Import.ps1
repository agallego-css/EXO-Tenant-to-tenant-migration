<#
	Title: Cross-Tenant-Migration-Attribute-Import.ps1
	Version: 0.1
	Date: 2021.01.03
	Authors: Denis Vilaca Signorelli (denis.signorelli@microsoft.com)

    .REQUIREMENTS: 
    
    1 - To make things easier, run this script from Exchange On-Premises machine powershell, 
        the script will automatically import the Exchange On-Prem module. If you don't want 
        to run the script from an Exchange machine, use the switch -LocalMachineIsNotExchange 
        and enter the FQDN of an Exchange Server. You will be prompted to sign-in, use the same 
        credential that you are already logged in your domain machine

	.PARAMETERS: 

    -UPNSuffix

    -Password

    -ResetPassword

    OrganizationalInit

    -Path
        Optional parameter used to inform which path will be used import the CSV. 
        If no path is chosen, the script will searching for UserListToImport.csv file on desktop path. 

    -LocalMachineIsNotExchange
        Optional parameter used to inform that you are running the script from 
        a non-Exchange Server machine. This parameter will require the -ExchangeHostname. 

    -ExchangeHostname
        Mandatory parameter if the switch -LocalMachineIsNotExchange was used. 
        Used to inform the Exchange Server FQDN that the script will connect.


	.DESCRIPTION: 

    This script will dump all necessary attributes that cross-tenant RMS migration requires. No changes are performed by the code

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
    HelpMessage="Enter UPN suffix of your domain E.g. contoso.com")]
    [string]$UPNSuffix,
    
    [Parameter(Mandatory=$false,
    HelpMessage="Enter the password for the new MEU objects. If no password is chosen, 
    the script will define '?r4mdon-_p@ss0rd!' as password")]
    [string]$Password,
    
    [Parameter(Mandatory=$false,
    HelpMessage="Require password change on first user access")]
    [switch]$ResetPassword,
    
    [Parameter(Mandatory=$false,
    HelpMessage="Enter the organization unit that MEU objects will be created. 
    The input is accepted as Name, Canonical name, Distinguished name (DN) or GUID")]
    [string]$OrganizationalInit,
    
    [Parameter(Mandatory=$false,
    HelpMessage="Enter a custom import path for the csv. if no value is defined 
    the script will search on Desktop path for the UserListToImport.csv")]
    [string]$Path,

    [Parameter(ParameterSetName="RemoteExchange",Mandatory=$false)]
    [switch]$LocalMachineIsNotExchange,
    
    [Parameter(ParameterSetName="RemoteExchange",Mandatory=$true,
    HelpMessage="Enter the remote exchange hostname")]
    [string]$ExchangeHostname
    )


$title    = Write-Host "$(Get-Date) - AD Sync status" -ForegroundColor Green
$question = Write-Host "Did you stopped the Azure AD Connect sync cycle?" -ForegroundColor Green
$choices  = '&Yes', '&No'
$decision = $Host.UI.PromptForChoice($title, $question, $choices, 1)

    if ($decision -eq 0) {
        
        Write-Host "$(Get-Date) - Loading parameters..." -ForegroundColor Green

    } else {
        
        Write-Host "$(Get-Date) - AD sync cycle should be stopped before moving forward" -ForegroundColor Green
        
        $title1    = Write-Host ""
        $question1 = Write-Host "Type Yes if you want that we automatically stop AD Sync cycle or type No if you want to stop yourself" -ForegroundColor Green
        $choices1  = '&Yes', '&No'
        $decision1 = $Host.UI.PromptForChoice($title1, $question1, $choices1, 1)

            if ($decision1 -eq 0) {
        
                $AADC = Read-Host "$(Get-Date) - Please enter the Azure AD Connect server FQDN"

                    Write-Host "$(Get-Date) - Disabling AD Sync cycle..." -ForegroundColor Green
                    $sessionAADC = New-PSSession -ComputerName $AADC
                    Invoke-Command { 
    
                        Import-Module ADSync 
                        Set-ADSyncScheduler -SyncCycleEnabled $false
    
                         } -Session $sessionAADC

                    $SynccycleStatus = Invoke-Command { 
    
                        Import-Module ADSync 
                        Get-ADSyncScheduler | Select-Object SyncCycleEnabled
    
                         } -Session $sessionAADC

                         if ($SynccycleStatus.SyncCycleEnabled -eq $false) {
    
                        Write-Host "$(Get-Date) - Azure AD sync cycle succesfully disabled" -ForegroundColor Green

                        } else {

                            Write-Host "$(Get-Date) - Azure AD sync cycle could not be stopped, please stop it manually with the following cmdlet: Set-ADSyncScheduler -SyncCycleEnabled $False" -ForegroundColor Green
                            Exit

                        }
                    
            } else {
                
                Write-Host "$(Get-Date) - Please stop the AD sync cycle and run the script again" -ForegroundColor Green
                Exit
                
                }
        }
                    

    if ( $Password -ne '' ) {
        
        $pwstr = $Password

    } else {

        $pwstr = "?r4mdon-_p@ss0rd!"

    }

    if ( $Path -ne '' ) { 
        
        $ImportUserList = Import-CSV "$Path"

    } else {

        $ImportUserList = Import-CSV "$home\desktop\UserListToImport.csv" 

    }

    if ( $ResetPassword.IsPresent ) {

        [bool]$resetpwrd = $True

    } else {

        [bool]$resetpwrd = $False

    }


$UPNSuffix = "@$UPNSuffix"
$pw = new-object "System.Security.SecureString"; 
$CustomAttribute = "CustomAttribute$CustomAttributeNumber"

# Connecto to Exchange and AD
if ( $LocalMachineIsNotExchange.IsPresent ) {

    # Connect to Exchange
    Write-Host "$(Get-Date) - Loading AD Module and Exchange Server Module" -ForegroundColor Green
    $Credentials = Get-Credential -Message "Enter your Exchange admin credentials. It should be the same that you are logged in the current machine"
    $ExOPSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://$ExchangeHostname/PowerShell/ -Authentication Kerberos -Credential $Credentials
    Import-PSSession $ExOPSession -AllowClobber -DisableNameChecking | Out-Null

    # Connect to AD
    $sessionAD = New-PSSession -ComputerName $env:LogOnServer.Replace("\\","")
    Invoke-Command { Import-Module ActiveDirectory } -Session $sessionAD
    Export-PSSession -Session $sessionAD -CommandName *-AD* -OutputModule RemoteAD -AllowClobber -Force | Out-Null
    Remove-PSSession -Session $sessionAD
            
    try {
        
        # Create copy of the module on the local computer
        Import-Module RemoteAD -Prefix Remote -DisableNameChecking -ErrorAction Stop 
        
    } catch { 
        
        # Sometimes the following path is not registered as system variable for PS modules path, thus we catch explicitly the .psm1
        Import-Module "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\RemoteAD\RemoteAD.psm1" -Prefix Remote -DisableNameChecking
              
    } finally {

        If (Get-Module -Name RemoteAD) {

            Write-Host "$(Get-Date) - AD Module was succesfully installed." -ForegroundColor Green
                
        } else {
                
            Write-Host "$(Get-Date) - AD module failed to load. Please run the script from an Exchange Server." -ForegroundColor Green 
            Exit

        }

    }

} else {

    Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn; 

}

for ($i=0; $i -lt $pwstr.Length; $i++) {$pw.AppendChar($pwstr[$i])} 

foreach ($user in $ImportUserList) 
{ 
    
    #Write-Progress -Activity "Creating MEU objects and importing attributes from CSV" -Status "Working on $($user.DisplayName)" -PercentComplete ($i/$ImportUserList.Count*100)
    
    $tmpUser = $null
     	
    $UPN = $user.Alias+$UPNSuffix
 	
    # If OU was passed through param, honor it. 
    # Otherwise create the MEU without OU specification   
    if ( $OrganizationalInit -ne '' -or $OrganizationalInit -ne $Null) 
    {
        $tmpUser = New-MailUser -UserPrincipalName $upn -ExternalEmailAddress $user.ExternalEmailAddress -FirstName $user.FirstName -LastName $user.LastName -SamAccountName $user.SamAccountName -Alias $user.alias -PrimarySmtpAddress $UPN -Name $User.Name -DisplayName $user.DisplayName -Password $pw -ResetPasswordOnNextLogon $resetpwrd

    } else {

        $tmpUser = New-MailUser -UserPrincipalName $upn -ExternalEmailAddress $user.ExternalEmailAddress -FirstName $user.FirstName -LastName $user.LastName -SamAccountName $user.SamAccountName -Alias $user.alias -PrimarySmtpAddress $UPN -Name $User.Name -DisplayName $user.DisplayName -Password $pw -ResetPasswordOnNextLogon $resetpwrd -OrganizationalUnit $OrganizationalInit 

    }

    # Convert legacyDN to X500. As we used ";" as delimiter within EmailAddress 
    # to avoid conflict, now we need to and replace to ","  
    $x500 = "x500:" + $user.legacyExchangeDN 
    $proxy = $user.EmailAddresses.Replace(";",",") 
    
    #Add CustomAtrribute parameter as hashtable to match the variable to parameter's name
    $CustomAttributeParam = @{ $User.CustomAttribute = $user.CustomAttributeValue }
    
    # Set ExchangeGuid, all previous ProxyAddress values and CustomAttribute
    $tmpUser | Set-MailUser -ExchangeGuid $user.ExchangeGuid -EmailAddresses @{Add=$x500} @CustomAttributeParam
    
    if ( $LocalMachineIsNotExchange.IsPresent )
    {
        
        # Used later because the "-Instance" parameter requires an explicit 
        # search and cannot accept the samAccountName from the CSV 
        $UserInstance = Get-RemoteADUser -Identity $user.SamAccountName

        # Add all proxyAddresses and ELC value 
        $ProxyArray = @()
        $ProxyArray = $Proxy -split ","
        Set-RemoteADUser -Identity $user.SamAccountName -add @{proxyAddresses=$proxy} -Replace @{msExchELCMailboxFlags=$user.ELCValue}

    } else {

        # Used later because the "-Instance" parameter requires an explicit 
        # search and cannot accept the samAccountName from the CSV 
        $UserInstance = Get-ADUser -Identity $user.SamAccountName
        
        #Add alll proxyaddresses and ECP value
        Set-ADUser -Identity $user.SamAccountName -add @{ProxyAddresses=$proxy -split ","} -Replace @{msExchELCMailboxFlags=$user.ELCValue}

    }    
    
    # Set ArchiveGuid if user has source cloud archive. We don't really care if the 
    # archive will be moved, it's up to the batch to decide, we just sync the attribute
    if ( $null -ne $user.ArchiveGuid -and $user.ArchiveGuid -ne '' ) 
    {
        
        $tmpUser | Set-MailUser -ArchiveGuid $user.ArchiveGuid
    
    }

    # If the user has Junk hash, convert the HEX string
    # to byte array and set it using instance variable
    if ( $null -ne $user.SafeSender -and $user.SafeSender -ne '' ) 
    {
    
        $BytelistSafeSender = New-Object -TypeName System.Collections.Generic.List[System.Byte]
        $HexStringSafeSender = $user.SafeSender
            for ($i = 0; $i -lt $HexStringSafeSender.Length; $i += 2)
            {
                $HexByteSafeSender = [System.Convert]::ToByte($HexStringsafeSender.Substring($i, 2), 16)
                $BytelistSafeSender.Add($HexByteSafeSender)
            }
        
        $UserInstance.msExchSafeSendersHash = $BytelistSafeSender.ToArray()
        
            if ( $LocalMachineIsNotExchange.IsPresent )
            {
                
            Set-RemoteADUser -instance $UserInstance

            } else {

                Set-ADUser -instance $UserInstance

            }   
          
    }

    if ( $null -ne $user.SafeRecipient -and $user.SafeRecipient -ne '' )
    {
    
        $BytelistSafeRecipient = New-Object -TypeName System.Collections.Generic.List[System.Byte]
        $HexStringSafeRecipient = $user.SafeRecipient
            for ($i = 0; $i -lt $HexStringSafeRecipient.Length; $i += 2)
            {
                $HexByteSafeRecipient = [System.Convert]::ToByte($HexStringSafeRecipient.Substring($i, 2), 16)
                $BytelistSafeRecipient.Add($HexByteSafeRecipient)
            }
        
        $UserInstance.msExchSafeRecipientsHash = $BytelistSafeRecipient.ToArray()
        
            if ( $LocalMachineIsNotExchange.IsPresent )
            {
                
                Set-RemoteADUser -instance $UserInstance

            } else {

                Set-ADUser -instance $UserInstance

            }  
       
    }

    if ( $null -ne $user.BlockedSender -and $user.BlockedSender -ne '' )
    {
    
        $BytelistBlockedSender = New-Object -TypeName System.Collections.Generic.List[System.Byte]
        $HexStringBlockedSender = $user.BlockedSender
            for ($i = 0; $i -lt $HexStringBlockedSender.Length; $i += 2)
            {
                $HexByteBlockedSender = [System.Convert]::ToByte($HexStringBlockedSender.Substring($i, 2), 16)
                $BytelistBlockedSender.Add($HexByteBlockedSender)
            }
        
        $UserInstance.msExchBlockedSendersHash = $BytelistBlockedSender.ToArray()
        
            if ( $LocalMachineIsNotExchange.IsPresent )
            {
                
                Set-RemoteADUser -instance $UserInstance

            } else {

                Set-ADUser -instance $UserInstance

            }  
       
        }

}

Write-Host "$(Get-Date) - The import was finished. Please confirm that all users are correctly created before start the Azure AD Connect sync " -ForegroundColor Green
