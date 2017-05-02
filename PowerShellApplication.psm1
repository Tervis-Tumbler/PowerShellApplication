#requires -module TervisScheduledTasks
function Install-PowerShellApplicationScheduledTask {
    param (
        $PathToScriptForScheduledTask = $PSScriptRoot,
        [Parameter(ParameterSetName="NoCredential")]$ScheduledTaskUsername = "$env:USERDOMAIN\$env:USERNAME",
        [Parameter(Mandatory,ParameterSetName="NoCredential")]$ScheduledTaskUserPassword,
        [Parameter(Mandatory,ParameterSetName="Credential")]$Credential,
        [Parameter(Mandatory)]$ScheduledTaskFunctionName,
        [Parameter(Mandatory)]$RepetitionInterval,
        [Parameter(Mandatory)]$ComputerName
    )
    $LocalScriptFilePath = "$PathToScriptForScheduledTask\$ScheduledTaskFunctionName.ps1"
    $RemoteScriptFilePath = ConvertTo-RemotePath -Path $LocalScriptFilePath -ComputerName $ComputerName
    if ($Credential) {
        $ScheduledTaskUsername = $Credential.UserName
        $ScheduledTaskUserPassword = $Credential.GetNetworkCredential().password
    }
    $RemoteScriptDirectory = $RemoteScriptFilePath | Split-Path -Parent
    if (-not (Test-Path -Path $RemoteScriptDirectory)) {
        New-Item -Path $RemoteScriptDirectory -ItemType Directory | Out-Null
    }
@"
$ScheduledTaskFunctionName
"@ | Out-File $RemoteScriptFilePath -Force
    $ScheduledTaskActionObject = New-ScheduledTaskAction –Execute "Powershell.exe" -Argument "-noprofile -file $LocalScriptFilePath"
    $TervisScheduledTaskArgs = @{
        ScheduledTaskName = $ScheduledTaskFunctionName
        ScheduledTaskAction = $ScheduledTaskActionObject
        ScheduledTaskUsername = $ScheduledTaskUsername
        ScheduledTaskUserPassword = $ScheduledTaskUserPassword
        RepetitionInterval = $RepetitionInterval
        ComputerName = $ComputerName
    }
    Install-TervisScheduledTask @TervisScheduledTaskArgs
}

function Uninstall-PowerShellApplicationScheduledTask {
    param (
        $PathToScriptForScheduledTask = $PSScriptRoot,
        [Parameter(Mandatory)]$ScheduledTaskFunctionName,
        [Parameter(Mandatory)]$ComputerName
    )
    Uninstall-TervisScheduledTask -ScheduledTaskName $ScheduledTaskFunctionName -ComputerName $ComputerName

    $ScriptFilePath = "$PathToScriptForScheduledTask\$ScheduledTaskFunctionName.ps1"
    $RemoteScriptFilePath = ConvertTo-RemotePath -Path $ScriptFilePath -ComputerName $ComputerName
    Remove-Item $RemoteScriptFilePath
}
