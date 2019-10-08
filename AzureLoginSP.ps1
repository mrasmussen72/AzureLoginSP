
#region variables
$stringBuilder = New-Object System.Text.StringBuilder                                  # Logging
$global:passwordLocation = ""                                                          # Used for cleanup, ignore

#Variables
[string]    $ServicePrincipalName =                     ""                             # Azure AD APPLICATION Name.  This is precreated in Azure prior to using this script.  This is used to make messaging more readable, could be fully replaced with ServicePrincipalId
[string]    $ServicePrincipalId =                       ""                             # Azure AD application ID.
[string]    $TenantId =                                 ""                             # Tenant ID of the application (ServicePrincipalName)
[string]    $SubscriptionId =                           ""                             # Subscription ID
[bool]      $AzureForGovernment =                       $false                         # Set to $true if running cmdlets against Microsoft Azure for Government
[bool]      $ConnectToAzureAz =                         $true                          # Set to $true to run Az cmdlets 
[bool]      $ConnectToAzureAd =                         $false                         # Set to $true to run Azure-AD cmdlets.
[bool]      $ResetPassword =                            $true                          # Prompts for your password, overwriting the current file
[bool]      $CleanUpPassword =                          $false                         # Deletes the Secure String file that allows for successful logins without entering password (this will cause a prompt for the password).  Also deletes the AzxureRMContext.json file (not sure if this is the best option, but that file holds sensitive data)
[bool]      $CleanUpLogging =                           $true                          # Deletes ALL log files in the temp directory of the context of the script, that match $ServicePrinicpalName + *.log. Leaving this set to $true ensures only one log file will ever be created

# Writing to Azure variables.  Leave default if not writting to Azure.
[string]    $StorageAccountName =                       ""                             # Storage account name to write to
[string]    $SAResourceGroupName =                      ""                             # Resource group name of the storage account
[string]    $Container =                                ""                             # Container to write to the user's temp directory in this format ($AzureLoginName + "-" + $dateTime + ".log") $dateTime was the datetime the file was accessed.  
[bool]      $WriteToAzureStorage =                      $false                         # Set to $true to write to Azure.  If $true, you need to have the other writing to Azure variable set


#endregion 

#region Core Functions
function AzureAuthenticationServicePrincipal
{
    [cmdletbinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [string] $ApplicationName,
        [Parameter(Mandatory=$true)]
        [string] $ApplicationId,
        [Parameter(Mandatory=$true)]
        [string] $SubscriptionId,
        [Parameter(Mandatory=$false)]
        [bool] $AzureForGov = $false,
        [Parameter(Mandatory=$false)]
        [bool] $ConnectToAzureAz = $false,
        [Parameter(Mandatory=$false)]
        [bool] $ConnectToAzureAd = $false,
        [Parameter(Mandatory=$true)]
        [string] $TenantId,
        [Parameter(Mandatory=$false)]
        [bool] $ResetPassword = $false
    )
    try {
        $success = $false
        $SecurePasswordLocation = (($env:TEMP) + "\" + $ApplicationName + ".txt")
        $global:passwordLocation = $SecurePasswordLocation
        #password file
        if($ResetPassword)
        {
            try {Read-Host -Prompt "Enter your password for $($ApplicationName)" -assecurestring | convertfrom-securestring | out-file $SecurePasswordLocation}
            catch {throw ("Obtaining Credentials failed: " + $_.Exception.Message.ToString())}
        }
        else 
        {
            if((!(Test-Path -Path $SecurePasswordLocation)))
            {Read-Host -Prompt "Secure password file for automated login missing, enter your password for $($ApplicationName)" -assecurestring | convertfrom-securestring | out-file $SecurePasswordLocation}   
        }
    }
    catch {throw}

    try 
    {
        $secPassword = Get-Content $SecurePasswordLocation | ConvertTo-SecureString
        $azureAppCred = (New-Object System.Management.Automation.PSCredential $ApplicationId, $secPassword)
        $success = $true
    }
    catch {$success = $false}

    try {
        if($success)
        {
            #Connect AD
            if($ConnectToAzureAd)
            {
                if($AzureForGov){Connect-AzureAD -ServicePrincipal -Credential $azureAppCred -EnvironmentName AzureUSGovernment | Out-Null}
                else{Connect-AzureAD -ServicePrincipal -Credential $azureAppCred | Out-Null}
                $context = Get-AzureADUser -Top 1
                if($context){$success = $true}   
                else{$success = $false}
            }
            #Connect Az
            if($ConnectToAzureAz) 
            {
                
                try {
                    if($AzureForGov){Connect-AzAccount -ServicePrincipal -Credential $azureAppCred -EnvironmentName AzureUSGovernment -Tenant $TenantId}
                    else{Connect-AzAccount -ServicePrincipal -Credential $azureAppCred -Tenant $TenantId} # | Out-Null}
                    $context = Get-AzContext
                    Select-AzSubscription -Subscription $SubscriptionId
                    #Get-AzSubscription
                    if($context){$success = $true}
                    #if($context.Account.Id -eq $cred.UserName){$success = $true}
                    else{$success = $false}
               }
                catch {$success = $false}
            }
            if(!($success))
            {
                # error logging into account or user doesn't have subscription rights, exit
                $success = $false
                throw "$($ApplicationName) Failed to login, exiting..."
                #exit
            }   
        }
    }
    catch {$success = $false}
    return $success
}

function WriteLoggingToAzure()
{
    param(
    [string] $StorageAccountName,
    [string] $ResourceGroupName,
    [string] $BlobName,
    [string] $FileName,
    [string] $Container,
    $Context
    )

    $success = $false
    try {
        $storageAccountKey = (Get-AzStorageAccountKey -Name $StorageAccountName -ResourceGroupName $ResourceGroupName).Value[0]
        $storageContext = New-AzStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $storageAccountKey
        #write blob to Azure - option to append blobs?
        $results = (Set-AzStorageBlobContent -Container $Container -Context $storageContext -File $FileName -BlobType "Block" -Verbose -Force ).Name 
    }
    catch {$success = $false}
    if($results){$success = $true}
    return $success
}

function Write-Logging()
{
    param
    (
        [string]    $Message,
        [bool]      $WriteToAzure,
        [bool]      $WriteLocally,
        [bool]      $EndOfMessage,
        [string]    $Container,
        [string]    $BlobType = "Block",
        [string]    $StorageAccountName,
        [string]    $ResourceGroupName,
        [string]    $ServicePrincipalName,
        $StorageContext
    )
    
    try 
    {
        $success = $false
        $dateTime = Get-Date -Format yyyyMMddTHHmmss
        if($ServicePrincipalName.Length -le 0){$ServicePrincipalName='NoUserName'}
        $blobName = ($ServicePrincipalName + "-" + $dateTime + ".log")

        #Create string
        $stringBuilder.Append($dateTime.ToString()) | Out-Null
        $stringBuilder.Append( "`t==>>`t") | Out-Null
        $stringBuilder.AppendLine( $Message) | Out-Null

        if($EndOfMessage)
        {
            #Write data
            $LocalLogFileNameAndPath = (($env:TEMP) + "\" + $blobName)
            $stringBuilder.ToString() | Out-File -FilePath $LocalLogFileNameAndPath -Append -Force
            $success = $true
            
            if($WriteToAzure)
            {
                $tempFile = (($env:TEMP) + "\" + $blobName)                     # directory, no / at the end
                #$stringBuilderAzure.ToString() | Out-File $tempFile -Force     # Write the azure data locally?
                $success = WriteLoggingToAzure -StorageAccountName $StorageAccountName -ResourceGroupName $ResourceGroupName -BlobName $BlobName -Context $StorageContext -FileName $tempFile -Container $Container
            }
            $stringBuilder.Clear()
        }
        $success = $true
    }
    catch {$success = $false; throw}
    return $success
} 
#endregion

#region Untility Functions
function CleanUp
{
    param(
        [Parameter(Mandatory=$false)]
        [bool] $CleanLogging,
        [Parameter(Mandatory=$false)]
        [bool] $CleanPassword,
        [Parameter(Mandatory=$false)]
        [bool] $CleanAzureRMContextFile
    )
    if($CleanLogging){
        try 
        {
            $path = (($env:TEMP) + "\" + "" + $ServicePrincipalName + "*" + ".log")
            if(!(Test-Path $path)){throw ($path + " doesn't exist")}
            
            $logs = Get-ChildItem -Path $path #| ForEach-Object { Remove-Item -LiteralPath $_.Name }
            foreach($log in $logs)
            {
                LoggingHelper -Message ("Removing log file: " + $log.FullName)
                Remove-Item -path $log.FullName
            }
        }catch{}
    }
    if($CleanPassword){try {Remove-Item -Path $global:passwordLocation | Out-Null}catch{}}
    if($CleanAzureRMContextFile){try {Remove-Item -Path ($env:USERPROFILE + "\.Azure\AzureRmContext.json") | Out-Null}catch{}} 
}

function LoggingHelper
{
    param(
        [string]$Message,
        [bool]$EndOfMessage
    )

    if(!(Write-Logging -Message $Message -WriteToAzure $WriteToAzure -EndOfMessage $EndOfMessage -ServicePrincipalName $ServicePrincipalName -StorageAccountName $StorageAccountName `
    -ResourceGroupName $ResourceGroupName -Container $Container -WriteLocally $EndOfMessage))
    {
        #Logging returned false
        Write-Host "Failed to log codetrace"
    }
}

#endregion

#region User Function
#Add your functions here#########################

#End add your functions##########################
#endregion

#Begin Code
try 
{
    LoggingHelper -Message "Starting Script" -EndOfMessage $false
    Write-Host "Starting Script"
    $success = AzureAuthenticationServicePrincipal -TenantId $TenantId -ApplicationId $ServicePrincipalId -SubscriptionId $SubscriptionId `
        -ApplicationName $ServicePrincipalName -AzureForGov $AzureForGovernment -ConnectToAzureAz $ConnectToAzureAz `
        -ConnectToAzureAd $ConnectToAzureAd -ResetPassword $ResetPassword
    $success = $true
    if($success)
    {
        #Login Successful
        LoggingHelper -Message "Login Succeeded" -EndOfMessage $false
        Write-Host "Login Succeeded"
        
        #Az cmdlets 
        try
        {
            if($ConnectToAzureAz)
            {#Run Azure Az cmdlets here#######################################################################################################################################################


            }#End of your code################################################################################################################################################################
        } catch{Write-Host ("User Az cmdlet error: $($_.Exception.Message)")}
        

        #Azure AD cmdlets
        try 
        {
            if($ConnectToAzureAd)
            {#Run AzureAd cmdlets here#######################################################################################################################################################
    
                
            }#End of your code################################################################################################################################################################
        } catch{Write-Host ("User AD cmdlet error: $($_.Exception.Message)")}
    }
    else 
    {
        #Login Failed 
        Write-Host "Login Failed or No Access"
        LoggingHelper -Message "Login Failed or No Access" -EndOfMessage $false
    }
}
catch{LoggingHelper -Message "Error: $($_.Exception.Message)"; Write-Host ("Error: " + ($_.ToString()))}
try {if($CleanUpPassword){LoggingHelper -Message "Calling clean function" -EndOfMessage $false; CleanUp -CleanLogging $CleanUpLogging -CleanPassword $CleanUpPassword}}
catch {LoggingHelper -Message "Error cleaning up environment: $($_.Exception.Message)";Write-Host ("Error cleaning up environment: $($_.Exception.Message)")}

LoggingHelper -Message "Ending Script" -EndOfMessage $true
Write-Host "Ending Script"