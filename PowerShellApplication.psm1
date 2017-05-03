#requires -module TervisScheduledTasks
function Install-PowerShellApplicationScheduledTask {
    param (
        $PathToScriptForScheduledTask = $PSScriptRoot,
        [Parameter(ParameterSetName="NoCredential")]$User = "$env:USERDOMAIN\$env:USERNAME",
        [Parameter(Mandatory,ParameterSetName="NoCredential")]$Password,
        [Parameter(Mandatory,ParameterSetName="Credential")]$Credential,
        [Parameter(Mandatory)]$FunctionName,
        [Parameter(Mandatory)]
        $RepetitionIntervalName,
        $ComputerName = $env:COMPUTERNAME
    )
    $LocalScriptFilePath = "$PathToScriptForScheduledTask\$FunctionName.ps1"
    $RemoteScriptFilePath = ConvertTo-RemotePath -Path $LocalScriptFilePath -ComputerName $ComputerName
    if ($Credential) {
        $User= $Credential.UserName
        $Password = $Credential.GetNetworkCredential().password
    }
    $RemoteScriptDirectory = $RemoteScriptFilePath | Split-Path -Parent
    if (-not (Test-Path -Path $RemoteScriptDirectory)) {
        New-Item -Path $RemoteScriptDirectory -ItemType Directory | Out-Null
    }
@"
$FunctionName
"@ | Out-File $RemoteScriptFilePath -Force
    $ScheduledTaskActionObject = New-ScheduledTaskAction –Execute "Powershell.exe" -Argument "-noprofile -file $LocalScriptFilePath"
    $TervisScheduledTaskArgs = @{
        TaskName = $FunctionName
        Action = $ScheduledTaskActionObject
        Username = $ScheduledTaskUsername
        UserPassword = $Password
        RepetitionInterval = $RepetitionIntervalName
        ComputerName = $ComputerName
    }
    Install-TervisScheduledTask @TervisScheduledTaskArgs
}

function Uninstall-PowerShellApplicationScheduledTask {
    param (
        $PathToScriptForScheduledTask = $PSScriptRoot,
        [Parameter(Mandatory)]$FunctionName,
        $ComputerName = $env:COMPUTERNAME
    )
    Uninstall-TervisScheduledTask -TaskName $FunctionName -ComputerName $ComputerName

    $ScriptFilePath = "$PathToScriptForScheduledTask\$FunctionName.ps1"
    $RemoteScriptFilePath = ConvertTo-RemotePath -Path $ScriptFilePath -ComputerName $ComputerName
    Remove-Item $RemoteScriptFilePath
}
