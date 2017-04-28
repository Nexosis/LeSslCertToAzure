# LeSslCertToAzure
 
This is a quick automation module I threw together to create a SSL/TLS Certificate with Let's Encrypt Service and apply to an Azure Application Gateway.
 
For more information on this Powershell module, read the blog post here
[Automatic Deployment of Let's Encrypt SSL/TLS Certificates on Azure App Gateway](http://content.nexosis.com/blog/automatic-deployment-lets-encrypt-on-azure-app-gateway)
 
### Powershell Module Dependencies:
```
PS> Install-Module AzureRm -AllowClobber
PS> Install-Module ACMESharp -AllowClobber
```

### Deploy-LeSslCertToAzure Usage
```
NAME
    Deploy-LeSslCertToAzure
    
SYNOPSIS
    Creates a SSL/TLS Certificate with Let's Encrypt Service
    
SYNTAX
    Deploy-LeSslCertToAzure [-appGatewayRgName] <Object> [-appGatewayName] <Object> [-appGatewayBackendHttpSettingsName] <Object> [-domainToCert] <Object> [-certPassword] <Object> 
    [-azureDnsZone] <Object> [-azureDnsZoneResourceGroup] <Object> [-dnsAlias] <Object> [-registrationEmail] <Object> [<CommonParameters>]
    
DESCRIPTION
    To maintain consistency with New-Object this cmdlet requires the -ComObject
    parameter to be provided and the TypeName parameter is not supported.
    
RELATED LINKS

REMARKS
    To see the examples, type: "get-help Deploy-LeSslCertToAzure -examples".
    For more information, type: "get-help Deploy-LeSslCertToAzure -detailed".
    For technical information, type: "get-help Deploy-LeSslCertToAzure -full".
```

### References
 - [Let's Encrypt](https://letsencrypt.org/)
 - [Internals of App Service Certificate](https://azure.microsoft.com/en-us/blog/internals-of-app-service-certificate/)
 - [ACMESharp](https://github.com/ebekker/ACMESharp/wiki/Quick-Start#method-3---handling-the-dns-challenge-manually)
 - [Configure an application gateway for SSL offload by using Azure Resource Manager](https://docs.microsoft.com/en-us/azure/application-gateway/application-gateway-ssl-arm) 
 - [How to: Install the Windows Azure Cmdlets Module](https://msdn.microsoft.com/en-us/library/dn135248(v=nav.70).aspx)