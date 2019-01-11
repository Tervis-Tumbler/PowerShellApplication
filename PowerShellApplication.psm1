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

function Uninstall-PowerShellApplication {
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ComputerName,
        [Parameter(Mandatory)]$EnvironmentName,
        [Parameter(Mandatory)]$ModuleName,
        [Parameter(Mandatory)]$ScheduledTaskName
    )
#    $Parameters = $PSBoundParameters
    $PSBoundParameters.Remove("ScheduledTaskName") | Out-Null
    $PowerShellApplicationInstallDirectory = Get-PowerShellApplicationInstallDirectory @PSBoundParameters
    $RemoteScriptFilePath = ConvertTo-RemotePath -Path $PowerShellApplicationInstallDirectory -ComputerName $ComputerName
    Remove-Item $RemoteScriptFilePath -Recurse

    Uninstall-TervisScheduledTask -TaskName "$ScheduledTaskName $EnvironmentName" -ComputerName $ComputerName
}

function Get-PowerShellApplicationInstallDirectory {
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ComputerName,
        [Parameter(Mandatory)]$EnvironmentName,
        [Parameter(Mandatory)]$ModuleName
    )
    process {
        $ProgramData = Invoke-Command -ComputerName $ComputerName -ScriptBlock { $env:ProgramData }
        "$ProgramData\PowerShellApplication\$EnvironmentName\$ModuleName"
    }
}

function Invoke-PowerShellApplicationPSDepend {
    param (
        $Path,
        $ModuleName,
        $TervisModuleDependencies,
        $TervisAzureDevOpsModuleDependencies,
        $PowerShellGalleryDependencies,
        $NugetDependencies,
        $PowerShellNugetDependencies
    )
    Remove-Item -Path $Path -ErrorAction SilentlyContinue -Recurse -Force
    New-Item -ItemType Directory -Path $Path -ErrorAction SilentlyContinue | Out-Null

    $PSDependInputObject =  @{
        PSDependOptions = @{
            Target = $Path
        }
    }

    if ($TervisModuleDependencies) {#Needed due to https://github.com/PowerShell/PowerShell/issues/7049
        $TervisModuleDependencies |
        ForEach-Object {
            $PSDependInputObject.Add( "Tervis-Tumbler/$_", "master")
        }
    }

    if ($TervisAzureDevOpsModuleDependencies) {
        $TervisAzureDevOpsModuleDependencies |
        ForEach-Object {
            $PSDependInputObject.Add( "https://tervis.visualstudio.com/PowerShell/_git/$_", "master")
        }
    }

    if ($PowerShellGalleryDependencies) {
        $PowerShellGalleryDependencies |
        ForEach-Object {
            Save-Module -Name $_ -Path $Path
        }
    }

    if ($NugetDependencies) {
        $NugetDependencies |
        ForEach-Object {
            $PSDependInputObjectForNugetDependencies =  @{
                PSDependOptions = @{
                    Target = $Path
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
            Invoke-PSDepend -Force -Install -InputObject $PSDependInputObjectForNugetDependencies | Out-Null
        }
    }

    if ($PowerShellNugetDependencies) {
        $PowerShellNugetDependencies |
        ForEach-Object -Begin {
            Register-PackageSource -Location https://www.nuget.org/api/v2 -name TemporaryNuget.org -Trusted -ProviderName NuGet | Out-Null
        } -Process {            
            Install-Package -Destination $Path -Source TemporaryNuget.org @_ | Out-Null
        } -End {
            UnRegister-PackageSource -Source TemporaryNuget.org | Out-Null
        }
    }

    Invoke-PSDepend -Force -Install -InputObject $PSDependInputObject | Out-Null
}

function Install-PowerShellApplicationFiles {
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ComputerName,
        [Parameter(Mandatory)]$EnvironmentName,
        [Parameter(Mandatory)]$ModuleName,
        $TervisModuleDependencies,
        $TervisAzureDevOpsModuleDependencies,
        $PowerShellGalleryDependencies,
        $NugetDependencies,
        $PowerShellNugetDependencies,
        [String]$CommandString,
        $ScriptFileName = "Script.ps1"
    )
    process {
        $PowerShellApplicationInstallDirectory = Get-PowerShellApplicationInstallDirectory -ComputerName $ComputerName -EnvironmentName $EnvironmentName -ModuleName $ModuleName
        $PowerShellApplicationInstallDirectoryRemote = $PowerShellApplicationInstallDirectory | ConvertTo-RemotePath -ComputerName $ComputerName

        $PowerShellApplicationPSDependParameters = $PSBoundParameters |
        ConvertFrom-PSBoundParameters -Property ModuleName, TervisModuleDependencies, TervisAzureDevOpsModuleDependencies, PowerShellGalleryDependencies, NugetDependencies, PowerShellNugetDependencies -AsHashTable

        Invoke-PowerShellApplicationPSDepend -Path $PowerShellApplicationInstallDirectoryRemote @PowerShellApplicationPSDependParameters

        $LoadPowerShellModulesCommandString = @"
`$TervisModulesArrayAsString = "$($TervisModuleDependencies -join ",")"
`$TervisModules = `$TervisModulesArrayAsString -split ","
`$PowershellGalleryModulesArrayAsString = "$($PowerShellGalleryDependencies -join ",")"
if(`$PowershellGalleryModulesArrayAsString){
    `$PowershellGalleryModules = `$PowershellGalleryModulesArrayAsString -split ","
}
else{
    `$PowershellGalleryModules = @()
}

Get-ChildItem -Path $PowerShellApplicationInstallDirectory -File -Recurse -Filter *.psm1 -Depth 2 |
ForEach-Object {
    if(`$_.BaseName -notin `$PowershellGalleryModules){
        Import-Module -Name `$_.Directory -Force
    }
}
`$PowershellGalleryModules | ForEach-Object {
    Import-Module -Name "$PowerShellApplicationInstallDirectory\`$_"
}
"@
        $LoadNugetDependenciesCommandString = if ($NugetDependencies -or $PowerShellNugetDependencies) {
            @"
Get-ChildItem -Path $PowerShellApplicationInstallDirectory -Recurse -Filter *.dll -Depth 3 | 
Where-Object FullName -match netstandard2.0 |
ForEach-Object {
    Add-Type -Path `$_.FullName
}
"@
        }

        $OFSBackup = $OFS
        $OFS = ""
@"
$($LoadPowerShellModulesCommandString.ToString())

$(if ($LoadNugetDependenciesCommandString){
    $LoadNugetDependenciesCommandString.ToString()
})

$CommandString
"@ |
        Out-File -FilePath $PowerShellApplicationInstallDirectoryRemote\$ScriptFileName
        
        $OFS = $OFSBackup
        [PSCustomObject]@{
            PowerShellApplicationInstallDirectory = $PowerShellApplicationInstallDirectory
            PowerShellApplicationInstallDirectoryRemote = $PowerShellApplicationInstallDirectoryRemote
        }
    }
}

function Install-PowerShellApplicationUniversalDashboard {
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ComputerName,
        [Parameter(Mandatory)]$EnvironmentName,
        [Parameter(Mandatory)]$ModuleName,
        $TervisModuleDependencies,
        $TervisAzureDevOpsModuleDependencies,
        $PowerShellGalleryDependencies,
        $NugetDependencies,
        $PowerShellNugetDependencies,
        $CommandString,
        [Switch]$UseTLS,
        $PassswordstateAPIKey,
        [Parameter(Mandatory)]$Port
    )
    process {
        if ($PassswordstateAPIKey) {
            $PSBoundParameters.CommandString = @"
Set-PasswordstateAPIKey -APIKey $PassswordstateAPIKey
Set-PasswordstateAPIType -APIType Standard

"@ + $CommandString
        }

        $PowerShellApplicationFilesParameters = $PSBoundParameters |
        ConvertFrom-PSBoundParameters -ExcludeProperty UseTLS, PassswordstateAPIKey, Port -AsHashTable

        $Result = Install-PowerShellApplicationFiles @PowerShellApplicationFilesParameters -ScriptFileName Dashboard.ps1
        $Remote = $Result.PowerShellApplicationInstallDirectoryRemote
        $Local = $Result.PowerShellApplicationInstallDirectory
    
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            nssm install $Using:ModuleName powershell.exe -file "$Using:Local\Dashboard.ps1"
            nssm set $Using:ModuleName AppDirectory $Using:Local
            New-NetFirewallRule -Name $Using:ModuleName -Profile Any -Direction Inbound -Action Allow -LocalPort $Using:Port -DisplayName $Using:ModuleName -Protocol TCP
        }

        if ($UseTLS -and -not (Test-Path -Path "$Remote\certificate.pfx")) {
            Get-PasswordstateDocument -DocumentID 11 -OutFile "$Remote\certificate.pfx" -DocumentLocation password
        }
    }
}

function Install-PowerShellApplicationPolaris {
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ComputerName,
        [Parameter(Mandatory)]$EnvironmentName,
        [Parameter(Mandatory)]$ModuleName,
        $TervisModuleDependencies,
        $TervisAzureDevOpsModuleDependencies,
        $PowerShellGalleryDependencies,
        $NugetDependencies,
        $PowerShellNugetDependencies,
        $CommandString,
        [Switch]$UseTLS,
        $PassswordstateAPIKey,
        [Parameter(Mandatory)]$Port
    )
    process {
        if ($PassswordstateAPIKey) {
            $PSBoundParameters.CommandString = @"
Set-PasswordstateAPIKey -APIKey $PassswordstateAPIKey
Set-PasswordstateAPIType -APIType Standard

"@ + $CommandString
        }

        $PowerShellApplicationFilesParameters = $PSBoundParameters |
        ConvertFrom-PSBoundParameters -ExcludeProperty UseTLS, PassswordstateAPIKey, Port -AsHashTable

        $Result = Install-PowerShellApplicationFiles @PowerShellApplicationFilesParameters -ScriptFileName Polaris.ps1
        $Remote = $Result.PowerShellApplicationInstallDirectoryRemote
        $Local = $Result.PowerShellApplicationInstallDirectory
    
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            nssm install $Using:ModuleName powershell.exe -file "$Using:Local\Polaris.ps1"
            nssm set $Using:ModuleName AppDirectory $Using:Local
            New-NetFirewallRule -Name $Using:ModuleName -Profile Any -Direction Inbound -Action Allow -LocalPort $Using:Port -DisplayName $Using:ModuleName -Protocol TCP
        }

        if ($UseTLS -and -not (Test-Path -Path "$Remote\certificate.pfx")) {
            Get-TervisPasswordSateTervisDotComWildCardCertificate -Type pfx -OutPath $Remote
            $CertificatePassword = Get-TervisPasswordSateTervisDotComWildCardCertificatePassword

            Invoke-Command -ComputerName $ComputerName -ScriptBlock {                
                $CertificateImport = Import-PfxCertificate -FilePath "$Using:Local\Certificate.pfx" -CertStoreLocation Cert:\LocalMachine\My -Password $Using:CertificatePassword
                
                $GUID = New-GUID | Select-Object -ExpandProperty GUID
                Add-NetIPHttpsCertBinding -CertificateHash $CertificateImport.Thumbprint -ApplicationId "{$GUID}" -IpPort "0.0.0.0:$Using:Port" -CertificateStoreName My -NullEncryption:$false
            }
        }
    }
}


function Install-PowerShellApplication {
    param (
        [Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ComputerName,
        [Parameter(Mandatory)]$EnvironmentName,
        [Parameter(Mandatory)]$ModuleName,
        $TervisModuleDependencies,
        $TervisAzureDevOpsModuleDependencies,
        $PowerShellGalleryDependencies,
        $NugetDependencies,
        [Parameter(Mandatory)][String]$CommandString,
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
            $Parameters.Remove($_) | Out-Null
        }
        $InstallLocations = Install-PowerShellApplicationFiles @Parameters
        $DirectoryLocal = $InstallLocations.PowerShellApplicationInstallDirectory

        Install-PowerShellApplicationScheduledTask -PathToScriptForScheduledTask $DirectoryLocal\Script.ps1 `
            -TaskName "$ScheduledTaskName $EnvironmentName" `
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