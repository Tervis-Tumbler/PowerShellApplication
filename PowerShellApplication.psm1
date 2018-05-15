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
        [Parameter(Mandatory)][Alias("SchduledTaskName")]$ScheduledTaskName,
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

        $ModuleName |
        ForEach-Object { 
            $PSDependInputObject.Add( "Tervis-Tumbler/$_", "master") 
        }

        $DependentTervisModuleNames |
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
            -RepetitionInterval $RepetitionIntervalName `
            -ComputerName $ComputerName
    }
}

function Invoke-PowerShellApplicationDockerBuild {
    param (
        [Parameter(Mandatory)]$ModuleName,
        $DependentTervisModuleNames,
        [Parameter(Mandatory)][String]$CommandsString
    )
    $BuildDirectory = "$($env:TMPDIR)$($ModuleName)Docker"
    New-Item -ItemType Directory -Path $BuildDirectory -ErrorAction SilentlyContinue
    
    $PSDependInputObject =  @{
        PSDependOptions = @{
            Target = $DirectoryRemote
        }
    }

    $ModuleName |
    ForEach-Object { 
        $PSDependInputObject.Add( "Tervis-Tumbler/$_", "master") 
    }

    $DependentTervisModuleNames |
    ForEach-Object { 
        $PSDependInputObject.Add( "Tervis-Tumbler/$_", "master") 
    }
    
    Invoke-PSDepend -Force -Install -InputObject $PSDependInputObject

    Push-Location -Path $BuildDirectory

@"
**/.git
**/.vscode
"@ | Out-File -Encoding ascii -FilePath .dockerignore -Force

@"
FROM microsoft/powershell
ENV TZ=America/New_York
RUN echo `$TZ > /etc/timezone && \
    apt-get update && apt-get install -y tzdata && \
    rm /etc/localtime && \
    ln -snf /usr/share/zoneinfo/`$TZ /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata && \
    apt-get clean
COPY . /usr/local/share/powershell/Modules
#ENTRYPOINT ["pwsh", "-Command", "$CommandsString" ]
ENTRYPOINT ["pwsh"]
"@ | Out-File -Encoding ascii -FilePath .\Dockerfile -Force

    docker build --no-cache -t $ModuleName .

    Pop-Location

    Remove-Item -Path $BuildDirectory -Recurse -Force
}