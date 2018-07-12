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

function Get-PowerShellApplicationInstallDirectory {
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ComputerName,
        [Parameter(Mandatory)]$ModuleName
    )
    process {
        $ProgramData = Invoke-Command -ComputerName $ComputerName -ScriptBlock { $env:ProgramData }
        "$ProgramData\PowerShellApplication\$ModuleName"
    }
}

function Invoke-PowerShellApplicationPSDepend {
    param (
        $Path
    )
    Remove-Item -Path $Path -ErrorAction SilentlyContinue -Recurse -Force
    New-Item -ItemType Directory -Path $Path -ErrorAction SilentlyContinue | Out-Null

    $PSDependInputObject =  @{
        PSDependOptions = @{
            Target = $Path
        }
    }
    
    $ModuleName |
    ForEach-Object {
        $PSDependInputObject.Add( "Tervis-Tumbler/$_", "master") 
    }

    if ($TervisModuleDependencies) {#Needed due to https://github.com/PowerShell/PowerShell/issues/7049
        $TervisModuleDependencies |
        ForEach-Object {
            $PSDependInputObject.Add( "Tervis-Tumbler/$_", "master") 
        }
    }

    if ($PowerShellGalleryDependencies) {
        $PowerShellGalleryDependencies |
        ForEach-Object {

            $PSDependInputObject.Add( $_, @{
                DependencyType = "PSGalleryNuget"
            })
        }
    }

    if ($NugetDependencies) {
        $NugetDependencies |
        ForEach-Object {
            $PSDependInputObjectForNugetDependencies =  @{
                PSDependOptions = @{
                    Target = $PowerShellApplicationInstallDirectoryRemote
                }
            }
            
            if ($_ -is [Hashtable]) {
                $PSDependInputObjectForNugetDependencies += $_    
            } else {
                $PSDependInputObjectForNugetDependencies.Add( $_, @{
                    DependencyType = "Package"
                    Parameters=@{ProviderName = "nuget"}
                })
            }
            Invoke-PSDepend -Force -Install -InputObject $PSDependInputObjectForNugetDependencies
        }
    }

    Invoke-PSDepend -Force -Install -InputObject $PSDependInputObject
}

function Install-PowerShellApplicationFiles {
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ComputerName,
        [Parameter(Mandatory)]$ModuleName,
        $TervisModuleDependencies,
        $PowerShellGalleryDependencies,
        $NugetDependencies,
        [ScriptBlock]$ScriptBlock,
        $ScriptFileName = "Script.ps1"
    )
    process {
        $PowerShellApplicationInstallDirectory = Get-PowerShellApplicationInstallDirectory -ComputerName $ComputerName -ModuleName $ModuleName
        $PowerShellApplicationInstallDirectoryRemote = $PowerShellApplicationInstallDirectory | ConvertTo-RemotePath -ComputerName $ComputerName

        Invoke-PowerShellApplicationPSDepend -Path $PowerShellApplicationInstallDirectoryRemote

        $LoadPowerShellModulesScriptBlock = {
            Get-ChildItem -Path $PowerShellApplicationInstallDirectory -File -Recurse -Filter *.psm1 -Depth 2 |
            ForEach-Object {
                Import-Module -Name $_.FullName -Force
            }
        }
        $LoadNugetDependenciesScriptBlock = if ($NugetDependencies) {
            {
                Get-ChildItem -Path $PowerShellApplicationInstallDirectory -Recurse -Filter *.dll -Depth 3 | 
                Where-Object FullName -match netstandard2.0 |
                ForEach-Object {
                    Add-Type -Path $_.FullName
                }
            }
        }

        $OFSBackup = $OFS
        $OFS = ""
@"
$($LoadPowerShellModulesScriptBlock.ToString())

$($LoadNugetDependenciesScriptBlock.ToString())

$($ScriptBlock.ToString())
"@ |
        Out-File -FilePath $PowerShellApplicationInstallDirectoryRemote\$ScriptFileName
        
        $OFS = $OFSBackup
    }
}

function Install-PowerShellApplicationUniversalDashboard {
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ComputerName,
        [Parameter(Mandatory)]$ModuleName,
        $TervisModuleDependencies,
        $PowerShellGalleryDependencies,
        $NugetDependencies,
        $ScriptBlock
    )
    process {
        Install-PowerShellApplicationFiles @PSBoundParameters -ScriptFileName Dashboard.ps1
    }
}

function Install-PowerShellApplication {
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ComputerName,
        [Parameter(Mandatory)]$ModuleName,
        $TervisModuleDependencies,
        $PowerShellGalleryDependencies,
        $NugetDependencies,
        [Parameter(Mandatory)][Scriptblock]$ScriptBlock,
        [Parameter(Mandatory)]$ScheduledTasksCredential,
        [Parameter(Mandatory)][Alias("SchduledTaskName")]$ScheduledTaskName,
        [Parameter(Mandatory)]
        [ValidateScript({ $_ | Get-RepetitionInterval })]
        $RepetitionIntervalName
    )
    process {
        $Parameters = $PSBoundParameters
        "ScheduledTasksCredential","ScheduledTaskName","RepetitionIntervalName" |
        ForEach-Object {
            $Parameters.Remove($_)
        }
        Install-PowerShellApplicationFiles @Parameters

        Install-PowerShellApplicationScheduledTask -PathToScriptForScheduledTask $DirectoryLocal\Script.ps1 `
            -TaskName $ScheduledTaskName `
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
    Install-PowerShellApplicationFiles 
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