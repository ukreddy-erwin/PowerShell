param(
                            [Parameter(Mandatory=$true)]  [string] $EHRvNextMicroserviceName , #= "Providers",
                            [Parameter(Mandatory=$true)]  [string] $EHRvNextMicroserviceVersion , #= "1.2.4"
                            [Parameter(Mandatory=$false)]  [string] $artifactoryRegistryUrl = "http://192.168.1.10:8081/artifactory/example-repo-local" #"http://artifactory:8081/artifactory/ehr-local-generic",
                            
)

#Requires -Version 4.0

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

$deployLogFile = "$env:temp\artifactdelete.log"



$artifactoryUrl  = "$artifactoryRegistryUrl/$EHRvNextMicroserviceName" 

#API will be accessed from here for getting file info.
$arrartifactoryRegistryUrl = @($artifactoryRegistryUrl.split('/'))
$apiartifactoryRegistryUrl = $($arrartifactoryRegistryUrl[0 .. $($arrartifactoryRegistryUrl.Count - 2)] -join "/") + "/api/storage/" + $arrartifactoryRegistryUrl[$arrartifactoryRegistryUrl.Count -1] + "/" + $EHRvNextMicroserviceName

$ZipList = (invoke-webrequest -Uri $apiartifactoryRegistryUrl -Method GET -Headers $headers | ConvertFrom-Json).children.uri

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic') | Out-Null


$user = [Microsoft.VisualBasic.Interaction]::InputBox("Enter Username of Artifactory", "Username", "$env:username") #"admin"
$pass = [Microsoft.VisualBasic.Interaction]::InputBox("Enter Password of Artifactory", "Password") #"Notallowed1!"
$pair = "${user}:${pass}"
$bytes = [System.Text.Encoding]::ASCII.GetBytes($pair)
$base64 = [System.Convert]::ToBase64String($bytes)
$basicAuthValue = "Basic $base64"
$headers = @{ Authorization = $basicAuthValue }


foreach($element in $ZipList)
{
    $version = [version]($element -replace "/$EHRvNextMicroserviceName.", "" -replace ".zip", "")
    if($version -eq $null)
    {
       Write-Log "Skipped deletion of file $element as unable to retrieve version info"  $deployLogFile 
    }
    elseif($version -lt $EHRvNextMicroserviceVersion)
    {
        invoke-webrequest -Uri $($artifactoryUrl + $element) -Method Delete -Headers $headers
        Write-Log "Deleted file $element"  $deployLogFile
    }
    else
    {
        Write-Log "Skipped deletion of file $element as greater or equal to version: $($version.tostring())"  $deployLogFile
    }
}



