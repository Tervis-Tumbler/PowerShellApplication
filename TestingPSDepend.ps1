@{"Tervis-Tumbler/PowerShellApplication"=@{version="master";target="."}}|Invoke-PSDepend -Install -Force
@{"UniversalDashboard"=@{DependencyType = 'PSGalleryNuget';target="."}}|Invoke-PSDepend -Install -Force
@{"Oracle.ManagedDataAccess.Core"=@{DependencyType = 'Package';target=".";version="2.12.0-beta2";Parameters=@{ProviderName = 'nuget'}}}|Invoke-PSDepend -Install -Force
@{"Oracle.ManagedDataAccess.Core"=@{DependencyType = 'Package';target=".";Parameters=@{ProviderName = 'nuget'}}}|Invoke-PSDepend -Install -Force
@{"libphonenumber-csharp"=@{DependencyType = 'Package';target=".";Parameters=@{ProviderName = 'nuget'}}}|Invoke-PSDepend -Install -Force
@{"libphonenumber-csharp"=@{DependencyType = 'PSGalleryNuget';target=".";Source="https://www.nuget.org/api/v2"}}|Invoke-PSDepend -Install -Force


Install-PowerShellApplicationFiles -ComputerName cmagnuson10-lt -ModuleName TervisCustomer -NugetDependencies libphonenumber-csharp


Install-PowerShellApplicationFiles -ComputerName cmagnuson10-lt -ModuleName TervisCustomer -NugetDependencies @{
	"libphonenumber-csharp" = @{
		DependencyType = "PSGalleryNuget"
		Target = "."
		Source = "https://www.nuget.org/api/v2"
	}
},
 @{
	"Oracle.ManagedDataAccess.Core" = @{
		DependencyType = "Package"
		Version = "2.12.0-beta2"
		Parameters = @{
			ProviderName = "nuget"
		}
	}
}

Install-PowerShellApplicationUniversalDashboard -ComputerName localhost -ModuleName TervisCustomer -NugetDependencies @{
	"libphonenumber-csharp" = @{
		DependencyType = "PSGalleryNuget"
		Source = "https://www.nuget.org/api/v2"
	}
}

Install-PowerShellApplicationUniversalDashboard -ComputerName localhost -ModuleName TervisCustomer -TervisModuleDependencies InvokeSQL,
		OracleE-BusinessSuitePowerShell,
		PasswordstatePowerShell,
		TervisMicrosoft.PowerShell.Utility,
		TervisOracleE-BusinessSuitePowerShell,
		TervisPasswordstate,
		TervisGithub -PowerShellGalleryDependencies UniversalDashboard -NugetDependencies @{
			"libphonenumber-csharp" = @{
				DependencyType = "PSGalleryNuget"
				Source = "https://www.nuget.org/api/v2"
			}
		},
		@{
			"Oracle.ManagedDataAccess.Core" = @{
				DependencyType = "Package"
				Version = "2.12.0-beta2"
				Parameters = @{
					ProviderName = "nuget"
				}
			}
		} -CommandString "New-TervisCustomerSearchDashboard"


@() | % {1}
$ArrayList = New-Object System.Collections.ArrayList
$ArrayList | % {1}
$null | % {1}
$VarNotDefined | % {1}


@() | % -Process {1}
$ArrayList = New-Object System.Collections.ArrayList
$ArrayList | % -Process {1}
$null | % -Process {1}
$VarNotDefined | % -Process {1}