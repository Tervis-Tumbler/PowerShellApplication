function Install-PowerShellApplicationScheduledTask {
    param (
        $PathToScriptForScheduledTask = $PSScriptRoot,
        [Parameter(Mandatory)]$ScheduledTaskUserPassword,
        [Parameter(Mandatory)]$ScheduledTaskFunctionName,
        [Parameter(Mandatory)][ValidateSet("EveryMinuteOfEveryDay","OnceAWeekMondayMorning","OnceAWeekTuesdayMorning")]$RepetitionInterval
    )
    $ScriptFilePath = "$PathToScriptForScheduledTask\$ScheduledTaskFunctionName.ps1"
    
@"
$ScheduledTaskFunctionName
"@ | Out-File $ScriptFilePath -Force

    $ScheduledTaskAction = New-ScheduledTaskAction –Execute "Powershell.exe" -Argument "-noprofile -file $ScriptFilePath"
    $ScheduledTaskTrigger = New-ScheduledTaskTrigger -Daily -At 12am
    $ScheduledTaskTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 12am
    
    $ScheduledTaskTrigger = New-ScheduledTaskTrigger -Daily -At 12am
    $ScheduledTaskTrigger.RepetitionDuration = New-TimeSpan -Days 1
    $ScheduledTaskTrigger.RepetitionInterval = New-TimeSpan -Minutes 1

    $ScheduledTaskSettingsSet = New-ScheduledTaskSettingsSet
    $Task = Register-ScheduledTask -TaskName $ScheduledTaskFunctionName `
                    -TaskPath "\" `
                    -Action $ScheduledTaskAction `
                    -Trigger $ScheduledTaskTrigger `
                    -User "$env:USERDOMAIN\$env:USERNAME" `
                    -Password $ScheduledTaskUserPassword `
                    -Settings $ScheduledTaskSettingsSet

    $Task.Triggers[0].ExecutionTimeLimit = "PT30M"
    $task.Triggers.Repetition.Duration = "P1D" 
    $task.Triggers.Repetition.Interval = "PT1M"
    $task | Set-ScheduledTask -Password $ScheduledTaskUserPassword -User "$env:USERDOMAIN\$env:USERNAME"
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
        $Name
    )
    $RepetitionIntervals | 
    where Name -EQ $Name
}

$RepetitionIntervals = [PSCustomObject][Ordered]@{
    Name = "EveryMinuteOfEveryDay"
    ScheduledTaskTrigger = "P1D"
    Interval = "PT1M"
},
[PSCustomObject][Ordered]@{
    Name = "OnceAWeekMondayMorning"
},
[PSCustomObject][Ordered]@{
    Name = "OnceAWeekTuesdayMorning"
},
[PSCustomObject][Ordered]@{
},
[PSCustomObject][Ordered]@{
},
[PSCustomObject][Ordered]@{
}
