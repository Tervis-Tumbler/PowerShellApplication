#requires -module TervisScheduledTasks, PSDepend

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
        [Parameter(Mandatory)]$ScheduledTaskName
    )
    process {
        $ProgramData = Invoke-Command -ComputerName $ComputerName -ScriptBlock { $env:ProgramData }
        "$ProgramData\PowerShellApplication\$EnvironmentName\$ScheduledTaskName"
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
    
    Invoke-PSDepend -Force -Install -InputObject $PSDependInputObject | Out-Null

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

    if ($PowerShellGalleryDependencies) {
        $PowerShellGalleryDependencies |
        ForEach-Object {
            Save-Module @_ -Path $Path -AcceptLicense
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
}

function Install-PowerShellApplicationFiles {
    param (
        [Parameter(Mandatory,ParameterSetName="ComputerName",ValueFromPipelineByPropertyName)]$ComputerName,
        [Parameter(Mandatory,ParameterSetName="PowerShellApplicationInstallDirectory")]$PowerShellApplicationInstallDirectory,
        [Parameter(Mandatory,ParameterSetName="PowerShellApplicationInstallDirectory")]$PowerShellApplicationInstallDirectoryRemote,
        [Parameter(Mandatory)]$EnvironmentName,
        [Parameter(Mandatory)]$ModuleName,
        [Parameter(Mandatory)]$ScheduledTaskName,
        $TervisModuleDependencies,
        $TervisAzureDevOpsModuleDependencies,
        $PowerShellGalleryDependencies,
        $NugetDependencies,
        $PowerShellNugetDependencies,
        [String]$CommandString,
        [Switch]$UseTLS,
        $PasswordstateAPIKey,
        [String]$ParamBlock,
        $ScriptFileName = "Script.ps1"
    )
    process {
        if ($ComputerName) {
            $PowerShellApplicationInstallDirectory = Get-PowerShellApplicationInstallDirectory -ComputerName $ComputerName -EnvironmentName $EnvironmentName -ScheduledTaskName $ScheduledTaskName
            $PowerShellApplicationInstallDirectoryRemote = $PowerShellApplicationInstallDirectory | ConvertTo-RemotePath -ComputerName $ComputerName     
        }

        if ($PasswordstateAPIKey) {
            $CommandString = @"
Set-PasswordstateAPIKey -APIKey $PasswordstateAPIKey
Set-PasswordstateAPIType -APIType Standard
Set-PasswordstateComputerName -ComputerName passwordstate.tervis.com

"@ + $CommandString
        }

        $PowerShellApplicationPSDependParameters = $PSBoundParameters |
        ConvertFrom-PSBoundParameters -Property ModuleName, TervisModuleDependencies, TervisAzureDevOpsModuleDependencies, PowerShellGalleryDependencies, NugetDependencies, PowerShellNugetDependencies -AsHashTable

        $ProgressPreferenceBefore = $ProgressPreference
        $ProgressPreference = "SilentlyContinue"
        Invoke-PowerShellApplicationPSDepend -Path $PowerShellApplicationInstallDirectoryRemote @PowerShellApplicationPSDependParameters
        $ProgressPreference = $ProgressPreferenceBefore

        $LoadPowerShellModulesCommandString = @"
Set-Location -Path $PowerShellApplicationInstallDirectory
`$TervisModulesArrayAsString = "$($TervisModuleDependencies -join ",")$(if($TervisAzureDevOpsModuleDependencies){",$($TervisAzureDevOpsModuleDependencies -join ",")"})"
`$TervisModules = `$TervisModulesArrayAsString -split ","
`$PowershellGalleryModulesArrayAsString = "$($PowerShellGalleryDependencies.Name -join ",")"
if(`$PowershellGalleryModulesArrayAsString){
    `$PowershellGalleryModules = `$PowershellGalleryModulesArrayAsString -split ","
} else {
    `$PowershellGalleryModules = @()
}

`$PSM1Files = Get-ChildItem -Path $PowerShellApplicationInstallDirectory -File -Recurse -Filter *.psm1 -Depth 2
`$TervisModules |
ForEach-Object {
    `$PSM1File = `$PSM1Files | 
    Where-Object BaseName -eq `$_

    if(`$PSM1File.BaseName -notin `$PowershellGalleryModules){
        Import-Module -Name `$PSM1File.Directory -Force -Global
    }
}

`$PowershellGalleryModules | ForEach-Object {
    Import-Module -Name "$PowerShellApplicationInstallDirectory\`$_" -Global
}
"@
        $LoadNugetDependenciesCommandString = if ($NugetDependencies -or $PowerShellNugetDependencies) {
            @"
Get-ChildItem -Path $PowerShellApplicationInstallDirectory |
Where-Object BaseName -NotIn (`$PowershellGalleryModules + `$TervisModules) |
Get-ChildItem -Recurse -Filter *.dll -Depth 3 | 
Where-Object FullName -match netstandard2.0 |
ForEach-Object {
    Add-Type -Path `$_.FullName
}
"@
        }

        $OFSBackup = $OFS
        $OFS = ""
@"
$($ParamBlock.ToString())
$($LoadPowerShellModulesCommandString.ToString())

$(if ($LoadNugetDependenciesCommandString){
    $LoadNugetDependenciesCommandString.ToString()
})
`$ProgressPreference = "SilentlyContinue"
$CommandString
"@ |
        Out-File -FilePath $PowerShellApplicationInstallDirectoryRemote\$ScriptFileName

        if ($UseTLS) {
            Get-TervisPasswordSateTervisDotComWildCardCertificate -Type pfx -OutPath $PowerShellApplicationInstallDirectoryRemote
        }

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
        $PasswordstateAPIKey,
        [Parameter(Mandatory)]$Port
    )
    process {
        $PowerShellApplicationFilesParameters = $PSBoundParameters |
        ConvertFrom-PSBoundParameters -ExcludeProperty Port -AsHashTable

        $Result = Install-PowerShellApplicationFiles @PowerShellApplicationFilesParameters -ScriptFileName Dashboard.ps1
        $Remote = $Result.PowerShellApplicationInstallDirectoryRemote
        $Local = $Result.PowerShellApplicationInstallDirectory
    
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            nssm install $Using:ModuleName powershell.exe -file "$Using:Local\Dashboard.ps1" | Write-Verbose
            nssm set $Using:ModuleName AppDirectory $Using:Local | Write-Verbose
            New-NetFirewallRule -Name $Using:ModuleName -Profile Any -Direction Inbound -Action Allow -LocalPort $Using:Port -DisplayName $Using:ModuleName -Protocol TCP | Write-Verbose
        }

        $Remote
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
        $PasswordstateAPIKey,
        [Parameter(Mandatory)]$Ports
    )
    process {

        $PowerShellApplicationFilesParameters = $PSBoundParameters |
        ConvertFrom-PSBoundParameters -ExcludeProperty Ports -AsHashTable

        $Result = Install-PowerShellApplicationFiles @PowerShellApplicationFilesParameters -ScriptFileName Polaris.ps1 -ParamBlock @"
param (
    `$Port
)
"@
        $Remote = $Result.PowerShellApplicationInstallDirectoryRemote
        $Local = $Result.PowerShellApplicationInstallDirectory
    
        Invoke-Command -ComputerName $ComputerName -ScriptBlock {
            foreach ($Port in $Using:Ports) {
                $ServiceName = "$Using:ModuleName $Port"
                nssm install $ServiceName powershell.exe -file "$Using:Local\Polaris.ps1 -Port $Port"
                nssm set $ServiceName AppDirectory $Using:Local    
                New-NetFirewallRule -Name $ServiceName -Profile Any -Direction Inbound -Action Allow -LocalPort $Port -DisplayName $ServiceName -Protocol TCP
            }
        }

        if ($UseTLS) {
            $CertificatePassword = Get-TervisPasswordSateTervisDotComWildCardCertificatePassword

            Invoke-Command -ComputerName $ComputerName -ScriptBlock {                
                $CertificateImport = Import-PfxCertificate -FilePath "$Using:Local\Certificate.pfx" -CertStoreLocation Cert:\LocalMachine\My -Password $Using:CertificatePassword
                
                foreach ($Port in $Using:Ports) {
                    $GUID = New-GUID | Select-Object -ExpandProperty GUID
                    netsh http add sslcert ipport=0.0.0.0:$Port certhash="$($CertificateImport.Thumbprint)" appid="{$GUID}"
                    #The following fails with "Cannot create a file when that file already exists." when the same cert is used on multiple ports
                    #Add-NetIPHttpsCertBinding -CertificateHash $CertificateImport.Thumbprint -ApplicationId "{$GUID}" -IpPort "0.0.0.0:$Port" -CertificateStoreName My -NullEncryption:$false
                }
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
        "ScheduledTasksCredential","RepetitionIntervalName" |
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
        [Parameter(Mandatory)]$EnvironmentName,
        [Parameter(Mandatory)]$ModuleName,
        $TervisModuleDependencies,
        $TervisAzureDevOpsModuleDependencies,
        $PowerShellGalleryDependencies,
        $NugetDependencies,
        $PowerShellNugetDependencies,
        $CommandString,
        [Switch]$UseTLS,
        $PasswordstateAPIKey,
        [Parameter(Mandatory)]$Port,
        $DirectoryOfFilesToIncludeInContainer
    )
    process {
        $PowerShellApplicationFilesParameters = $PSBoundParameters |
        ConvertFrom-PSBoundParameters -ExcludeProperty Port -AsHashTable
        $PowerShellApplicationInstallDirectoryRemote = New-TemporaryDirectory -TemporaryFolderType System

        $Result = Install-PowerShellApplicationFiles @PowerShellApplicationFilesParameters `
            -PowerShellApplicationInstallDirectory "/opt/tervis/$ModuleName" `
            -PowerShellApplicationInstallDirectoryRemote $PowerShellApplicationInstallDirectoryRemote

        Copy-Item -Path $DirectoryOfFilesToIncludeInContainer -Destination $PowerShellApplicationInstallDirectoryRemote -Recurse
        Push-Location -Path $PowerShellApplicationInstallDirectoryRemote

@"
**/.git
**/.vscode
"@ | Out-File -Encoding ascii -FilePath .dockerignore -Force
    
@"
FROM mcr.microsoft.com/powershell:6.2.0-alpine-3.8
COPY . /opt/tervis/$ModuleName
ENTRYPOINT ["pwsh","-file","/opt/tervis/$ModuleName/Script.ps1"]
EXPOSE $Port
"@ | Out-File -Encoding ascii -FilePath .\Dockerfile -Force
    
        $Module = Get-Module -Name $ModuleName
        $VersionNumber = $Module.Version.ToString()
        $ContainerImageIdentifier = "$($ModuleName.ToLower()):v$VersionNumber"
        docker build --no-cache --tag $ContainerImageIdentifier .
    
        Pop-Location
    
        #Remove-Item -Path $PowerShellApplicationInstallDirectoryRemote -Recurse -Force
        $ContainerImageIdentifier
    }
}