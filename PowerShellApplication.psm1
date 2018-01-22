#requires -module TervisScheduledTasks

function Install-PowerShellApplicationScheduledTask {
    param (
        [Parameter(Mandatory)]$Credential,        
        [Parameter(Mandatory)]$FunctionName,        
        [Parameter(Mandatory)]
        [ValidateScript({ $_ | Get-RepetitionInterval })]
        $RepetitionIntervalName,

        [Parameter(Mandatory)]$ComputerName
    )
    process {
        $Parameters = $PSBoundParameters | ConvertFrom-PSBoundParameters -ExcludeProperty $FunctionName -AsHashTable
        Install-TervisScheduledTask -TaskName $FunctionName -Execute "Powershell.exe" -Argument "-Command $FunctionName -NoProfile" @Parameters
    }
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
