 # AzureLoginSP
PowerShell script that enables the user to run commands on the local machine against Azure.  Authentication is obtained via an Azure Service Principal which must be created prior to running this script.

prerequisites:
A service principal is created with the appropriate permissions.  
To create a service principal:
1.	Log into your Azure subscription
2.	Select Azure Active Directory
3.	Select App registrations (an app registration and a service principal are the same)
4.	Select New registration
5.	Enter a name for the service principal
6.	Select the appropriate Supported accounts types.  (default works fine)
7.	Enter the redirect URL.  You can enter https://SomeRandomName.  I use the app registration name in place of SomeRandomName
8.	Select the Register button at the bottom of the screen
Set the password for the service principal
1.	Select Azure Active Directory
2.	Select App Registrations
3.	Select the App Registration created previously
4.	Select Certificates and Secrets
5.	Select New client secret
6.	Enter a description
7.	Enter a expiry period
8.	Select Add
9.	Copy the created password.  This is the password you need to enter when running the script.  Save this password to your password vault (recommendation is to use Azure KeyVault).  Once you leave this page, the password will not be visible again.  You can create a new secret if you forget this one.
Grant the service principal the appropriate permissions.  I elected to grant the service principal contributor rights at the subscription level that my runbooks will operate in.
To grant the SP contributor rights at the subscription level:
1.	In the Azure portal, select All Services
2.	Enter Subscription (this should bring the subscriptions link to the top)
3.	Select Subscriptions
4.	If you have multiple subscriptions, select the subscription that the runbook will operate in
5.	On the subscription page, select Access Control (IAM)
6.	Select Add a role assignment 
7.	In the Role dropdown, select Contributor
8.	In the Select textbox, type the name of your service principal (app registration name)
9.	Select your service principal in the list below
10.	Select Save
Operating the script
1.	Navigate to the top of the script (the variables section).  You must change these variables to match your environment.
a.	ServicePrincipalName – Name of the app registration created previously
b.	ServicePrincipalId – ID of the app registration (you can find this if you select the app registration in the Azure portal)
c.	TenantId – ID of the tenant (directory ID)
d.	SubscriptionId – ID of the subscription
e.	AzureForGovernment – set to $true if your subscription resides in Azure for Government (US)
f.	ConnectToAzureAz – Uses Az cmdlets.  This requires you to have the Az cmdlets installed locally on your machine.
g.	ConnectToAzureAd – uses Azure Ad cmdlets.  Set to $true if you want to leverage Azure Ad cmdlets
h.	ResetPassword – Once you log in for the first time, your password for the service principal is saved as a secure string locallaly (in the %temp% directory).  This allows you to run commands without having to enter the password.  Set to $true to overwrite the current password file saved locally.  Settings this to $false will attempt to log in using the password saved locally.  If the file doesn’t exist, you will be prompted for a password
i.	$CleanUpPassword – Setting this to true deleted the password file stored locally
j.	$CleanUpLogging – Each running of this script will log locally to %temp%.  If you set this value to false, there will be a file for each running of the script stored locally.  Setting this value to true will delete all log files except the last run.  This will prevent the log files from filling up the temp directory.
k.	StorageAccountName – if writing to Azure, this is the name of the storage account.  
l.	$SAResourceGroupName – Name of the resource group of the above storage account
m.	$Container – container name that the log file will be written to
n.	$writeToAzureStorage – if set to true, the script will attempt to write logging to an Azure storage account.
With the above created and configured, the script will run and indicate whether the login was successful or not.
Adding code
Locate the if statement: if($ConnectToAzureAz).  Enter your cmdlets for Azure here.  For example, if you entered 
Get-AzVM
You should see a list of your VMs.
