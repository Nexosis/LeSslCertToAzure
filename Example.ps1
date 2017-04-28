# NOTE: To install, you must run Powershell elevated 
# Install-Module AzureRM -AllowClobber
# NOTE: ACMESharp has a module that conflicts with 'Get-Certificate', -AllowClobber may allow ACMESharp to override that command.
# Install-Module ACMESharp  -AllowClobber  

$scriptRoot = (Split-Path -parent $MyInvocation.MyCommand.Path)
$moduleRoot = "$scriptRoot\Modules"

if (-Not ($env:PSModulePath.Contains($moduleRoot))) {
    $env:PSModulePath = $env:PSModulePath + ";$moduleRoot"
}

Import-Module -Name Deploy-LeSslCertToAzure -Verbose

$VerbosePreference = "Continue"
$ErrorActionPreference = 'Stop'

# Login-AzureRmAccount

Deploy-LeSslCertToAzure `
                -appGatewayRgName 'web-resoucegroup-rg' `
                -appGatewayName 'mydomaintocertweb-agw' `
                -appGatewayBackendHttpSettingsName 'appGatewayBackendHttpSettings' `
                -domainToCert 'www.mydomaintocert.com' `
                -certPassword 'mySweetPassword123!@' `
                -azureDnsZone 'mydomaintocert.com' `
                -azureDnsZoneResourceGroup 'web-resoucegroup-rg' `
                -dnsAlias 'wwwDomainCom' `
                -registrationEmail 'ops@mydomaintocert.com'