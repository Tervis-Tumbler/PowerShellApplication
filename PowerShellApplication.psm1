function Install-PowerShellApplicationScheduledTask {
    param (
        $PathToScriptForScheduledTask = $PSScriptRoot,
        [Parameter(ParameterSetName="NoCredential")]$ScheduledTaskUsername = "$env:USERDOMAIN\$env:USERNAME",
        [Parameter(Mandatory,ParameterSetName="NoCredential")]$ScheduledTaskUserPassword,
        [Parameter(Mandatory,ParameterSetName="Credential")]$Credential,
        [Parameter(Mandatory)]$ScheduledTaskFunctionName,

        [Parameter(Mandatory)]
        [Alias("RepetitionInterval")]
        [ValidateScript({ $_ | Get-RepetitionInterval })]
        $RepetitionIntervalName
    )
    if ($Credential) {
        $ScheduledTaskUsername = $Credential.UserName
        $ScheduledTaskUserPassword = $Credential.GetNetworkCredential().password
    }

    $ScriptFilePath = "$PathToScriptForScheduledTask\$ScheduledTaskFunctionName.ps1"
    
@"
$ScheduledTaskFunctionName
"@ | Out-File $ScriptFilePath -Force

    $ScheduledTaskAction = New-ScheduledTaskAction –Execute "Powershell.exe" -Argument "-noprofile -file $ScriptFilePath"
    $RepetitionInterval = $RepetitionIntervalName | Get-RepetitionInterval    
    $ScheduledTaskTrigger = $RepetitionInterval.ScheduledTaskTrigger

    $ScheduledTaskSettingsSet = New-ScheduledTaskSettingsSet
    $Task = Register-ScheduledTask -TaskName $ScheduledTaskFunctionName `
                    -TaskPath "\" `
                    -Action $ScheduledTaskAction `
                    -Trigger $ScheduledTaskTrigger `
                    -User $ScheduledTaskUsername `
                    -Password $ScheduledTaskUserPassword `
                    -Settings $ScheduledTaskSettingsSet

    if ($RepetitionInterval.TaskTriggersRepetitionDuration) {
        $task.Triggers.Repetition.Duration = $RepetitionInterval.TaskTriggersRepetitionDuration
    }
    if ($RepetitionInterval.TaskTriggersRepetitionInterval) { 
        $task.Triggers.Repetition.Interval = $RepetitionInterval.TaskTriggersRepetitionInterval
    }

    $Task.Triggers[0].ExecutionTimeLimit = "PT30M"
    $task | Set-ScheduledTask -Password $ScheduledTaskUserPassword -User $ScheduledTaskUsername
}

function Uninstall-PowerShellApplicationScheduledTask {
    param (
        $PathToScriptForScheduledTask = $PSScriptRoot,
        [Parameter(Mandatory)]$ScheduledTaskFunctionName
    )
    $Task = Get-ScheduledTask | where taskname -match $ScheduledTaskFunctionName
    $Task | Unregister-ScheduledTask

    $ScriptFilePath = "$PathToScriptForScheduledTask\$ScheduledTaskFunctionName.ps1"
    Remove-Item $ScriptFilePath
}

Function Get-RepetitionInterval {
    param (
        [Parameter(ValueFromPipeline)]$Name
    )
    $RepetitionIntervals | 
    where Name -EQ $Name
}

$RepetitionIntervals = [PSCustomObject][Ordered]@{
    Name = "EveryMinuteOfEveryDay"
    ScheduledTaskTrigger = $(New-ScheduledTaskTrigger -Daily -At 12am)
    TaskTriggersRepetitionDuration = "P1D"
    TaskTriggersRepetitionInterval = "PT1M"
},
[PSCustomObject][Ordered]@{
    Name = "OnceAWeekMondayMorning"
    ScheduledTaskTrigger = $(New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 8am)
},
[PSCustomObject][Ordered]@{
    Name = "OnceAWeekTuesdayMorning"
    ScheduledTaskTrigger = $(New-ScheduledTaskTrigger -Weekly -DaysOfWeek Tuesday -At 8am)
},
[PSCustomObject][Ordered]@{
    Name = "EverWorkdayDuringTheDayEvery15Minutes"
    ScheduledTaskTrigger = $(New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At 7am)
    TaskTriggersRepetitionDuration = "PT10H"
    TaskTriggersRepetitionInterval = "PT15M"
}
