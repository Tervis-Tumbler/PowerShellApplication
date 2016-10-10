function Install-PowerShellApplicationScheduledTask {
    param (
        $PathToScriptForScheduledTask = $PSScriptRoot,
        [Parameter(Mandatory)]$ScheduledTaskUserPassword,
        [Parameter(Mandatory)]$ScheduledTaskFunctionName,
        
        [Parameter(Mandatory)]
        [ValidateSet("EveryMinuteOfEveryDay","OnceAWeekMondayMorning","OnceAWeekTuesdayMorning")]
        $RepetitionInterval
    )
    $ScriptFilePath = "$PathToScriptForScheduledTask\$ScheduledTaskFunctionName.ps1"
    
@"
$ScheduledTaskFunctionName
"@ | Out-File $ScriptFilePath -Force

    $ScheduledTaskAction = New-ScheduledTaskAction –Execute "Powershell.exe" -Argument "-noprofile -file $ScriptFilePath"
    $ScheduledTaskTrigger = Get-PowerShellApplicationScheduledTaskTrigger -RepetitionInterval $RepetitionInterval

    $ScheduledTaskSettingsSet = New-ScheduledTaskSettingsSet
    $Task = Register-ScheduledTask -TaskName $ScheduledTaskFunctionName `
                    -TaskPath "\" `
                    -Action $ScheduledTaskAction `
                    -Trigger $ScheduledTaskTrigger `
                    -User "$env:USERDOMAIN\$env:USERNAME" `
                    -Password $ScheduledTaskUserPassword `
                    -Settings $ScheduledTaskSettingsSet

    if ($RepetitionInterval -eq "EveryMinuteOfEveryDay") {
        #There is a bug in Register-ScheduledTask that will not honor values for the RepetitionDuration and RepetitionInterval properties of ScheduledTaskTrigger
        #so these have to be set after the task has been created

        $task.Triggers.Repetition.Duration = "P1D" 
        $task.Triggers.Repetition.Interval = "PT1M"
    }

    $Task.Triggers[0].ExecutionTimeLimit = "PT30M"
    $task | Set-ScheduledTask -Password $ScheduledTaskUserPassword -User "$env:USERDOMAIN\$env:USERNAME"
}

Function Get-PowerShellApplicationScheduledTaskTrigger {
    param (
        [Parameter(Mandatory)]
        [ValidateSet("EveryMinuteOfEveryDay","OnceAWeekMondayMorning","OnceAWeekTuesdayMorning")]
        $RepetitionInterval
    )
    if ($RepetitionInterval -eq "EveryMinuteOfEveryDay") {         
        $ScheduledTaskTrigger = New-ScheduledTaskTrigger -Daily -At 12am
        $ScheduledTaskTrigger.RepetitionDuration = New-TimeSpan -Days 1
        $ScheduledTaskTrigger.RepetitionInterval = New-TimeSpan -Minutes 1
        $ScheduledTaskTrigger
    } elseif ($RepetitionInterval -eq "OnceAWeekMondayMorning") {
        New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At 8am        
    } elseif ($RepetitionInterval -eq "OnceAWeekTuesdayMorning") {
        New-ScheduledTaskTrigger -Weekly -DaysOfWeek Tuesday -At 8am        
    }
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
