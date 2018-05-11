#requires -module TervisScheduledTasks

function Install-PowerShellApplicationScheduledTask {
    param (
        [Parameter(Mandatory)]$Credential,
        [Parameter(Mandatory,ParameterSetName="FunctionName")]$FunctionName,
        [Parameter(Mandatory,ParameterSetName="PathToScriptForScheduledTask")]$PathToScriptForScheduledTask,
        [Parameter(Mandatory,ParameterSetName="PathToScriptForScheduledTask")]$TaskName,
        [Parameter(Mandatory)]
        [ValidateScript({ $_ | Get-RepetitionInterval })]
        $RepetitionIntervalName,

        [Parameter(Mandatory)]$ComputerName
    )
    process {
        $Parameters = $PSBoundParameters | ConvertFrom-PSBoundParameters -ExcludeProperty FunctionName,PathToScriptForScheduledTask,TaskName -AsHashTable
        $Arguement = "-NoProfile " + $(
            if ($FunctionName) {
                "-Command $FunctionName"
            } else {
                "-File $PathToScriptForScheduledTask" 
            }
        )
        if ($FunctionName) {$TaskName = $FunctionName}
        Install-TervisScheduledTask -TaskName $TaskName -Execute "Powershell.exe" -Argument $Arguement @Parameters
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

function Install-PowerShellApplication {
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ComputerName,
        [Parameter(Mandatory)]$ModuleName,
        $DependentTervisModuleNames,
        [Parameter(Mandatory)][String]$ScheduledScriptCommandsString,
        [Parameter(Mandatory)]$ScheduledTasksCredential,
        [Parameter(Mandatory)]$SchduledTaskName,
        [Parameter(Mandatory)]
        [ValidateScript({ $_ | Get-RepetitionInterval })]
        $RepetitionIntervalName
    )
    process {
        $ProgramData = Invoke-Command -ComputerName $ComputerName -ScriptBlock { $env:ProgramData }
        $DirectoryLocal = "$ProgramData\PowerShellApplication\$ModuleName"
        $DirectoryRemote = $DirectoryLocal | ConvertTo-RemotePath -ComputerName $ComputerName
        Remove-Item -Path $DirectoryRemote -ErrorAction SilentlyContinue -Recurse -Force
        New-Item -ItemType Directory -Path $DirectoryRemote -ErrorAction SilentlyContinue

        $PSDependInputObject =  @{
            PSDependOptions = @{
                Target = $DirectoryRemote
            }
        }
        (@($ModuleName) + $DependentTervisModuleNames) |
        ForEach-Object { 
            $PSDependInputObject.Add( "Tervis-Tumbler/$_", "master") 
        }
        
        Invoke-PSDepend -Force -Install -InputObject $PSDependInputObject
        $OFSBackup = $OFS
        $OFS = ""
@"
Get-ChildItem -Path $DirectoryLocal -Directory | 
ForEach-Object {
    Import-Module -Name `$_.FullName -Force
}

$ScheduledScriptCommandsString
"@ |
        Out-File -FilePath $DirectoryRemote\Script.ps1
        
        $OFS = $OFSBackup

        Install-PowerShellApplicationScheduledTask -PathToScriptForScheduledTask $DirectoryLocal\Script.ps1 `
            -TaskName $SchduledTaskName `
            -Credential $ScheduledTasksCredential `
            -RepetitionInterval $RepetitionInterval `
            -ComputerName $ComputerName
    }
}