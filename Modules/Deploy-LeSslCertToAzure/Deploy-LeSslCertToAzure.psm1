##############################################################################
#.SYNOPSIS
# Creates a SSL/TLS Certificate with Let's Encrypt Service 
# 
#
#.DESCRIPTION
# To maintain consistency with New-Object this cmdlet requires the -ComObject
# parameter to be provided and the TypeName parameter is not supported.
#
#.PARAMETER appGatewayRgName
# The name of an existing Azure Resource Group where the 
# Application Gateway is deployed.
#
#.PARAMETER appGatewayName
# The name of the Azure Application Gateway that has been deployed where the 
# SSL/TLS Certificate will be applied.
#
#.PARAMETER appGatewayBackendHttpSettingsName
# The name of the Backend HTTP Settings on the Application Gateway (these must
# already be setup and configured on the Application Gateway).
#
#.PARAMETER domainToCert
# The Common Name of the SSL/TLS Certificate (e.g. www.mydomain.com).
# 
#.PARAMETER certPassword
# The password used to encrypt the PKCS#12 PFX Certificate file.
#
#.PARAMETER azureDnsZone
# The name of the Azure DNS Zone Resource that has the authority to answer for
# the domain (e.g. if SSL/TLS Common name is www.mydomain.com, the DNS Zone 
# would be for mydomain.com).
#
#.PARAMETER azureDnsZoneResourceGroup
# The name of an existing Azure Resource Group where the 
# DNS Zone Resource, specified by azureDnsZone, is deployed.
#
#.PARAMETER dnsAlias
# The internal Alias used by ACMESharp to track the certificate, metadata, 
# and registration status.
#
#.PARAMETER registrationEmail
# The email address registred with Let's Encrypt when registering the 
# SSL/TLS Cert.
#
#.EXAMPLE
# Deploy-LeSslCertToAzure `
#                -appGatewayRgName 'web-resoucegroup-rg' `
#                -appGatewayName 'mydomaintocertweb-agw' `
#                -appGatewayBackendHttpSettingsName 'appGatewayBackendHttpSettings' `
#                -domainToCert 'www.mydomaintocert.com' `
#                -certPassword 'mySweetPassword123!@' `
#                -azureDnsZone 'mydomaintocert.com' `
#                -azureDnsZoneResourceGroup 'web-resoucegroup-rg' `
#                -dnsAlias 'wwwDomainCom' `
#                -registrationEmail 'ops@mydomaintocert.com'
##############################################################################
Function Deploy-LeSslCertToAzure() {
    Param(
        [Parameter(Mandatory=$true)]
        $appGatewayRgName,
        [Parameter(Mandatory=$true)]
        $appGatewayName,
        [Parameter(Mandatory=$true)]
        $appGatewayBackendHttpSettingsName,
        [Parameter(Mandatory=$true)]
        $domainToCert,
        [Parameter(Mandatory=$true)]
        $certPassword,
        [Parameter(Mandatory=$true)]
        $azureDnsZone,
        [Parameter(Mandatory=$true)]
        $azureDnsZoneResourceGroup,
        [Parameter(Mandatory=$true)]
        $dnsAlias,
        [Parameter(Mandatory=$true)]
        $registrationEmail
    )
    Set-StrictMode -Version 3
    ########################
    # Initialize Variables
    ########################
    Import-Module ACMESharp
  
    $VerbosePreference = "Continue"
    $ErrorActionPreference = 'Stop'
 
    $dnsCertAlias = $dnsAlias + "cert"
 
    # Create the Host name to put the _acme-challenge. prefix on.
    # if certing www.mydomain.com, would create TXT record for _acme-challenge.www.mydomain.com.
 
    $acmeValidationDnsHostName = '_acme-challenge.'  + $domainToCert.Replace(".$azureDnsZone",'')
  
    $appGwHttpsListenerName = 'appGatewayHttpsListener'
    $appGatewayFrontEndHttpsPortName = 'myFrontendHttpsPort'
    $appGatewayHttpsPort = 443
    $appGatewayHttpsRuleName = 'httpsRule'
    ###############################################################
    ###############################################################
    ###############################################################
    # location to write PFX certificate to deploy to Gateway
    $signedSslCertificate = "$scriptRoot\Certs\$dnsAlias.pfx"
 
    ###
    # STAGE ONE - Setup ACME Vault, Validation Domain OwnerShip, and submit, sign and save SSL/TLS Certificate.
    ###
    # Check to see if ACME Vault exists, if not create it
    if ((Get-ACMEVault) -eq $null) {
        Write-Verbose "ACME Cert Vault doesn't exist. Initializing..."
        Initialize-ACMEVault
    }
  
    # Script didn't handle -ErrorAction SilentlyContinue properly, put in try/catch block
    try {
        Write-Verbose "ACME Cert Vault: Getting Registration..."
        # try and get registration
        Get-ACMERegistration
    } catch {
        Write-Verbose "ACME Cert Vault: Not registered. Performing registration..."
        # Vault doesn't exist, create it.
        New-ACMERegistration -Contacts "mailto:$registrationEmail" -AcceptTos
    }
  
    # Had to use try/catch since script didn't handle -ErrorAction SilentlyContinue properly
    try {
        # See if Identifer is already registered
        Write-Verbose "Checking if ACME Identifer $dnsAlias already exists."
        (Get-ACMEIdentifier -IdentifierRef $dnsAlias)
        $dnsTxtValue = ((Get-ACMEIdentifier -IdentifierRef $dnsAlias).Challenges | Where-Object {$_.Type -eq "dns-01"}).Challenge.RecordValue 
        Write-Verbose "It exists, DNS TXT value requested is '$dnsTxtValue.'"
    } catch {
        # No Identifier, create one.
        Write-Verbose "It does not exist. Creating a new Identifier alias $dnsAlias for $domainToCert."
        New-ACMEIdentifier -Dns $domainToCert -Alias $dnsAlias
        Write-Verbose "Requesting ACME DNS TXT Record Challenge..."
        $authorizationState = Complete-ACMEChallenge $dnsAlias -ChallengeType dns-01 -Handler manual
        $dnsTxtValue = ($authorizationState.Challenges | Where-Object {$_.Type -eq "dns-01"}).Challenge.RecordValue
        Write-Verbose "Success, retrieved value $dnsTxtValue"
    }
  
    if ([string]::IsNullOrEmpty($dnsTxtValue)) {
        throw "Could not determine Proper TXT Resource Record (RR) value from ACME client."
    }
  
    # Attempt to retrieve an existing DNS record for this domain, if it exists
    Write-Verbose "Checking to see if $acmeValidationDnsHostName DNS txt record in Zone $azureDnsZone in Resource Group $azureDnsZoneResourceGroup already exists."
    $dnsRecordSet = Get-AzureRmDnsRecordSet `
                                    -Name $acmeValidationDnsHostName `
                                    -ZoneName $azureDnsZone `
                                    -ResourceGroupName $azureDnsZoneResourceGroup `
                                    -RecordType TXT `
                                    -ErrorAction SilentlyContinue
    if ($dnsRecordSet -eq $null) {
        Write-Verbose "Record does not exist for this TXT record. Creating..."
 
        $dnsRecordSet = New-AzureRmDnsRecordSet `
                    -Name $acmeValidationDnsHostName `
                    -RecordType 'TXT' `
                    -ZoneName $azureDnsZone `
                    -ResourceGroupName $azureDnsZoneResourceGroup `
                    -Ttl 60 `
                    -DnsRecords @(New-AzureRmDnsRecordConfig -Value $dnsTxtValue)
    } else {
        Write-Verbose "Record exists. Performing update."
        if ($dnsRecordSet.Records.Count -eq 0) {
            # No record at all, create a new one.
            $txtRecord = New-AzureRmDnsRecordConfig -Value $dnsTxtValue
            # Add to recordset.
            $dnsRecordSet.Records.Add($txtRecord)
        } else {
            # Found a record, but need to update it.
            $dnsRecordSet.Records[0].Value = $dnsTxtValue
        }
    }
     
    Write-Verbose "Saving DNS TXT record for let's encrypt challenge."
    Set-AzureRmDnsRecordSet -RecordSet $dnsRecordSet
  
    #give it some time to create the record so it's avail when we submit to lets encrypt.
    Start-Sleep -s 10
  
    # submit for processing
    Write-Verbose "Submitting request for DNS challenge."
    Submit-ACMEChallenge $dnsAlias -ChallengeType dns-01
  
    [string]$status = ((Update-ACMEIdentifier `
                                    $dnsAlias `
                                    -ChallengeType dns-01 `
                       ).Challenges | Where-Object {$_.Type -eq "dns-01"}).Status
  
    # Setup a timeout to wait for the Main stack to be ready / online to retrieve the Output params
    # if it's not ready right away. Typically this happens immediately.
    $timeout = new-timespan -Minutes 5
    $sw = [diagnostics.stopwatch]::StartNew()
  
    # loop until valid or 5 minute timeout is reached.
    while (-Not $status.Equals('valid')) {
        Write-Verbose "Current Status is $status."
        # check to see if timeout should occur
        if ($sw.elapsed -ge $timeout) {break;}
  
        Write-Verbose "Waiting for certificate to be valid."
        start-sleep -seconds 5
        $status = ((Update-ACMEIdentifier `
                            $dnsAlias `
                            -ChallengeType dns-01 `
                   ).Challenges | Where-Object {$_.Type -eq "dns-01"}).Status
    }
  
    if (-Not $status.Equals('valid')) {
        Write-Error "Not valid after 5 min. Status is $status."
        return
    } else {
        Write-Verbose "Cert is Valid! Deploying.."
  
        # Create a new certificate to get signed
         
        Write-Verbose "Checking to see if certificate $dnsCertAlias was already Created."
        # check to see if certificate was already created.
        $dnsCertCreated = $null
        try{
            $dnsCertCreated = (Get-ACMECertificate | Where-Object {$_.Alias -eq $dnsCertAlias})
        }
        catch{}
        if ($dnsCertCreated -eq $null) {
            Write-Verbose "Creating new certificate $dnsCertAlias to sign."
            New-ACMECertificate $dnsAlias -Generate -Alias $dnsCertAlias
            Write-Verbose "Submiting $dnsCertAlias certificate for signature."
            Submit-ACMECertificate $dnsCertAlias
        }
         
        Write-Verbose "Updating ACME Vault by storing certificate $dnsCertAlias."
        Update-ACMECertificate $dnsCertAlias
  
        Write-Verbose "Retrieving SSL Certificate in PKCS#12 format with full cert chain."
        # Retrieve the signed cert with Private key including chain (intermediate CA must be installed above for this to work)
        # and store it in the Pkcs#12 format.
        Get-ACMECertificate $dnsCertAlias -ExportPkcs12 $signedSslCertificate -CertificatePassword $certPassword -Overwrite
 
        ###
        # STAGE TWO - DEPLOY PFX to Azure Application Gateway
        ###
 
 
        Write-Verbose "Deploying Certificate to the Application Gateway $appGatewayName in resource group $appGatewayRgName."
        # Retrieve app gateway
        $appGateway = Get-AzureRmApplicationGateway -ResourceGroupName $appGatewayRgName -Name $appGatewayName
  
        # Create a new SSL port and add it to the front ends ports
        Write-Verbose "Creating SSL FrontEnd Port for SSL/TLS on TCP 443."
        Add-AzureRmApplicationGatewayFrontendPort -ApplicationGateway $appGateway -Name $appGatewayFrontEndHttpsPortName -Port $appGatewayHttpsPort
  
        $fpHttpsPort = Get-AzureRmApplicationGatewayFrontendPort -name $appGatewayFrontEndHttpsPortName -ApplicationGateway $appGateway
  
        # Load cert
        Write-Verbose "Adding SSL/TLS Certificate: $signedSslCertificate."
        Add-AzureRmApplicationGatewaySslCertificate -ApplicationGateway $appGateway -Name $dnsCertAlias -CertificateFile $signedSslCertificate -Password $certPassword
        $cert = Get-AzureRmApplicationGatewaySslCertificate -ApplicationGateway $appGateway -Name $dnsCertAlias
        # Get frontEndIP
        $fipconfig = Get-AzureRmApplicationGatewayFrontendIPConfig -ApplicationGateway $appGateway
         
        # Create a new Listener using the new https port
        Write-Verbose "Creating new HTTPS Listener..."
        Add-AzureRmApplicationGatewayHttpListener -ApplicationGateway $appGateway -Name $appGwHttpsListenerName -Protocol Https -FrontendIPConfiguration $fipconfig -FrontendPort $fpHttpsPort -SslCertificate $cert
        $listener = Get-AzureRmApplicationGatewayHttpListener -ApplicationGateway $appGateway -Name $appGwHttpsListenerName
  
        # Get ref to backend pool
        $backendPool = Get-AzureRmApplicationGatewayBackendAddressPool -ApplicationGateway $appGateway
  
        # Get backend Pool
        $poolSetting = Get-AzureRmApplicationGatewayBackendHttpSettings -ApplicationGateway $appGateway -name $appGatewayBackendHttpSettingsName
  
        #Create new rule for current backend Pool and created
        Write-Verbose "Adding new Routing Rule for new HTTPS Listener..."
        Add-AzureRmApplicationGatewayRequestRoutingRule -ApplicationGateway $appGateway -Name $appGatewayHttpsRuleName -RuleType Basic -BackendHttpSettings $poolSetting -HttpListener $listener -BackendAddressPool $backendPool
  
        Write-Verbose "Saving changes..."
        # Commit the changes to Azure
        Set-AzureRmApplicationGateway -ApplicationGateway $appGateway
    }
}