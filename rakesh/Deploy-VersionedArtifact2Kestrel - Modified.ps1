<#
.SYNOPSIS
This script downloads zipped package from Artifactory registry and deploys its content as selfhosted Kestrel microservice 

.DESCRIPTION
Used for deploying of generic artifacts  from Artifactory, and register it in Consul

.PARAMATER artifactoryRegistryUrl
URL of Artifactory registry

.PARAMATER certurl
Full URL of SSL certificate in Artifatory

.PARAMATER tempfolder
Folder on target server where package is downloaded and backups are saved

.PARAMATER EHRvNextMicroserviceName
Name of Microservice that is going to be updated

.PARAMATER microsoftServiceName
Namee of local Microsoft service to wrap the EHR microservice around

.PARAMATER EHRvNextMicroserviceVersion
Version of microservice that will be deployed

.NOTES
Script uses nssm for service creation and modification. More details: https://nssm.cc/
Script must be run with elevated privelegies, there is block below for this purpose to restart script with elevated privelegies

Yegor Lopatin v1.0

#>

param(
                              [string] $artifactoryRegistryUrl = "http://artifactory:8081/artifactory/ehr-local-generic",
                              [string] $certurl = "http://artifactory:8081/artifactory/ehr-local-generic/certificates/dev/dev.advancedmd.com.pfx",
                              [string] $tempFolder = "c:\tmp",
                              [string] $EHRvNextMicroserviceName = "Providers",
                              [string] $consulHost = "http://localhost:8500",
                              [string] $EHRvNextMicroserviceVersion = "1.2.4",
                              [string] $backupFolder = "c:\backups"
)

#Requires -Version 4.0

function backup ($deploymentsFolder)
{
    if (!(Test-Path $backupFolder))
    {
      New-Item $backupFolder -ItemType directory
    }
    Compress-Archive -Path $deploymentsFolder -DestinationPath "$backupFolder\$(get-date -Format "dd-MM-yyyy-hh-mm").zip"
    Write-Output "Microservice folder content has been backed up to $backupFolder"

    #Leave only 30 last archives
    gci $backupFolder -Recurse| where{-not $_.PsIsContainer}| sort CreationTime -desc| select -Skip 30| Remove-Item -Force 
}

function Write-Log($message, $deployLogFile)
{
  $time = (get-date -Format "MM/dd/yyyy hh:mm")
  Write-Output $message 
  "$time`: $message" | Out-File $deployLogFile -Append
}

#############################################################################################################
# This block restarts the whole script with input arguments if it is triggered without elevated privelegies #
#############################################################################################################

# Get the ID and security principal of the current user account
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
Write-Output $myWindowsID
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
 
# Get the security principal for the Administrator role
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
 
# Check to see if we are currently running "as Administrator"
if (-NOT($myWindowsPrincipal.IsInRole($adminRole)))
{
  # We are not running "as Administrator" - so relaunch as administrator
   
  # Create a new process object that starts PowerShell
  $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
   
  # Specify the current script path and name as a parameter
  $newProcess.Arguments = $MyInvocation.Line.Replace($MyInvocation.InvocationName, $MyInvocation.MyCommand.Definition);
   
  # Indicate that the process should be elevated
  $newProcess.Verb = "runas";
   
  # Start the new process
  [System.Diagnostics.Process]::Start($newProcess);
   
  # Exit from the current, unelevated, process
  exit
}
#############################################################################################################
##############################################################################################################

$ErrorActionPreference = "Stop"
$microsoftServiceName = "API-Clinical-$EHRvNextMicroserviceName"
$deploymentsFolder = "c:\Advancedmd\EHR\MicroSvc\$EHRvNextMicroserviceName"
$deployLogFile = "$tempFolder\deployment.log"


#input data for Consul Registration/Deregistration
$publicIP = (Get-NetIPAddress| ?{($_.AddressFamily -eq "IPv4") -AND ($_.IPAddress -ne '127.0.0.1')}).IPAddress
$publicPort = "5000"
    
    
#create/clean temporary folder
if (!(Test-Path $tempFolder))
{
    New-Item $tempFolder -ItemType directory
}
else
{
    if (Test-Path $deployLogFile)
    {
      Remove-Item $deployLogFile -Force
    }  
    #Leave only 30 last archives
    #gci $tempFolder -Recurse| where{-not $_.PsIsContainer}| sort CreationTime -desc| select -Skip 30| Remove-Item -Force 
}

#download package from Artifactory
$packageName     = "$EHRvNextMicroserviceName.$EHRvNextMicroserviceVersion.zip"
$packageFullName = Join-Path $tempFolder "$packageName"
$artifactoryUrl  = "$artifactoryRegistryUrl/$EHRvNextMicroserviceName/$PackageName" 
Invoke-WebRequest -Uri $artifactoryUrl -OutFile $packageFullName -UseBasicParsing
Write-Log  "Microservice package has been downloaded to $packageFullName" $deployLogFile
    
#check if NSSM installed, and install if no
Write-Log "Checking NSSM installation..." $deployLogFile
 $p = [System.Diagnostics.Process]::Start("nssm.exe")
    if($p -eq $null)
    {
        Write-Log "NSSM utility is missed and will be installed"  $deployLogFile
        iex ((new-object net.webclient).DownloadString('https://chocolatey.org/install.ps1'))
        choco install -y nssm
    }
    else
    {
        if(!($p.HasExited)){$p.kill()}
        Write-Log "NSSM utility is already installed"  $deployLogFile
    }   

$ErrorActionPreference = "Continue"

# if service exists - deregister Consul and stop it (checking if it is running), if not - create $need2createnewservice=$true to create it
$need2CreateNewService = $FALSE
if ((get-service -Name $microsoftServiceName -ErrorAction SilentlyContinue).Name -eq $microsoftServiceName)
{
    Write-Log "Service $microsoftServiceName exists" $deployLogFile
    if ((get-service -Name $microsoftServiceName).Status -ne 'Stopped')
    {
      Write-Log "Service $microsoftServiceName is running" $deployLogFile
      Write-Log "Service $microsoftServiceName is being stopped" $deployLogFile
      Stop-Service $microsoftServiceName
      sleep 15
    }
}
else
{
    Write-Log "Service $microsoftServiceName does not exist. And will be created" $deployLogFile
    $need2CreateNewService = $TRUE
}

# if deployfolder exists - backup and clean, if no - create
if (Test-Path $deploymentsFolder)
{
    Write-Log "Backing microservice folder up..." $deployLogFile
    backup $deploymentsFolder 
    Write-Log "Cleaning up of microservice folder..." $deployLogFile
    Remove-Item "$deploymentsFolder\*" -Force -Recurse
}
else
{
    Write-Log "Creating microservice folder..." $deployLogFile
    New-Item $deploymentsFolder -type Directory
}

# extract content
Write-Log "Extract package content to microservice folder" $deployLogFile
Expand-Archive $packageFullName -DestinationPath $deploymentsFolder -Force

#download SSL certficate
$certname = $($certurl.Split('/'))[-1] 
Invoke-WebRequest -Uri $certurl -OutFile "$deploymentsFolder\$certname"  -UseBasicParsing  

# if $need2createnewservice=$true - create new ms, if no - update appdirectory and application
$application  = (Get-Item "$deploymentsFolder\*.exe").FullName
$appDirectory = (Get-Item "$deploymentsFolder\*.exe").DirectoryName

if ($need2createnewservice)
{
    Write-Log "Microsoft service creating..." $deployLogFile
    nssm install $microsoftServiceName $application
    if ((get-service -Name $microsoftServiceName).Status -eq 'Running')
    {  
      Stop-Service $microsoftServiceName  >> $deploymentLogFile
    }  
    Write-Log "Microsoft service is created successfully" $deployLogFile
}
else
{
    Write-Log "Microsoft service parameters updating..." $deployLogFile
    nssm set $microsoftServiceName application  $application
    nssm set $microsoftServiceName appdirectory $appdirectory
}

# set all parameters to service
$EHRvNextMicroserviceName = $EHRvNextMicroserviceName.ToLower()
$objectNameUser     = consul kv get $env:CONSUL_ENVIRONMENT/advancedmd/api/clinical/$EHRvNextMicroserviceName/common/Credentials/Login
$objectNamePassword = consul kv get $env:CONSUL_ENVIRONMENT/advancedmd/api/clinical/$EHRvNextMicroserviceName/common/Credentials/Password

if (($objectNameUser -eq $NULL) -OR ($objectNamePassword -eq $NULL)){
  Write-Warning "One of NT Service credentials is empty. Check NT Service credentials"    
}

nssm set $microsoftServiceName start                SERVICE_AUTO_START 
nssm set $microsoftServiceName displayName          "EHR vNext $microsoftServiceName" 
nssm set $microsoftServiceName description          "Hosts one of EHR microservices"
nssm set $microsoftServiceName ObjectName           $objectNameUser $objectNamePassword
nssm set $microsoftServiceName AppStdout            $tempFolder\EHRvNextMicroservice_stdout.log
nssm set $microsoftServiceName AppStderr            $tempFolder\EHRvNextMicroservice_errors.log
nssm set $microsoftServiceName AppStopMethodConsole 10000                                         # Time to wait after sending Control-C, (ms)
nssm set $microsoftServiceName AppExit              Default Restart                               # Action on exit [Exit, Ignore, Restart]
nssm set $microsoftServiceName AppRestartDelay      0 
nssm set $microsoftServiceName AppStdoutCreationDisposition 2                                     # Replace existing Output files
nssm set $microsoftServiceName AppStderrCreationDisposition 2                                     # Replace existing Error files
nssm set $microsoftServiceName DependOnService      Consul
 
Write-Log "Microsoft service parameters are updated successfully" $deployLogFile

#Clean     
# start it
Write-Log "Microsoft service starting..." $deployLogFile
nssm start $microsoftServiceName
     
# if service state is "running" - register to Artifactory, if no - throw the error   
if ((get-service -Name $microsoftServiceName).Status -eq 'Running')
{
    Write-Log "Microsoft service started successfully" $deployLogFile
    Write-Log "Consul registering..." $deployLogFile
    Write-Log "EHR microservice has been deployed successfully" $deployLogFile
}
else
{
    throw "$microsoftServiceName is not started." 
}