Param (
    [Parameter(Mandatory=$true)]
    [string]
    $TerraformCloudApiKey,

    [Parameter(Mandatory=$true)]
    [string]
    $TerraformCloudOrgName,

    [Parameter(Mandatory=$true)]
    [string]
    $ProviderNamespace,

    [Parameter(Mandatory=$true)]
    [string]
    $ProviderName,

    [Parameter(Mandatory=$true)]
    [string]
    $ProviderGpgKeyId,

    [Parameter(Mandatory=$true)]
    [string]
    $ArtifactsJson,

    [Parameter(Mandatory=$true)]
    [string]
    $MetadataJson
)

# Parse the artifacts json
$artifacts = $ArtifactsJson | ConvertFrom-Json
# Parse the metadata json
$metadata = $MetadataJson | ConvertFrom-Json

$version = $metadata.version

# Create new provider version
# https://developer.hashicorp.com/terraform/cloud-docs/api-docs/private-registry/provider-versions-platforms#create-a-provider-version
$requestBody = @{
    data = @{
        type = "registry-provider-versions"
        attributes = @{
            version = $version
            "key-id" = $ProviderGpgKeyId
            protocols = @("4.0","5.0","6.0")
        }
    }
}

$requestBodyJson = ($requestBody | ConvertTo-Json)

$response = Invoke-RestMethod -Method "POST" `
                              -Uri "https://app.terraform.io/api/v2/organizations/$TerraformCloudOrgName/registry-providers/private/$ProviderNamespace/$ProviderName/versions" `
                              -ContentType "application/vnd.api+json" `
                              -Authentication Bearer `
                              -Token $TerraformCloudApiKey `
                              -Body $requestBodyJson

$shasums_url = $response.data.links["shasums-upload"]
$shasums_sig_url = $response.data.links["shasums-sig-upload"]

# Upload SHASUMS and SHASUMS SIG
$shasums_artifact = $artifacts | Where-Object { $_.type -eq "Checksum" } | Select-Object -First 1

Invoke-RestMethod -Method "PUT" `
                  -Uri $shasums_url `
                  -InFile $shasums_artifact.path

# The sig file is the same name with .sig appended
$shasums_sig_artifact_path = "$($shasums_artifact.path).sig"

Invoke-RestMethod -Method "PUT" `
                  -Uri $shasums_sig_url `
                  -InFile $shasums_sig_artifact_path

# For each binary, create a new Provider Platform for this version
# https://developer.hashicorp.com/terraform/cloud-docs/api-docs/private-registry/provider-versions-platforms#create-a-provider-platform

$artifacts | Where-Object { $_.type -eq "Archive" } | ForEach-Object {
    $name = $_.name
    $path = $_.path
    $os = $_.goos
    $arch = $_.goarch
    $checksum = $_.extra.Checksum

    $payload = @{
        data = @{
            type = "registry-provider-platforms"
            attributes = @{
                os = $os
                arch = $arch
                shasum = $checksum
                filename = $name
            }
        }
    }

    $payloadJson = ($payload | ConvertTo-Json)

    $response = Invoke-RestMethod -Method "POST" `
                                  -Uri "https://app.terraform.io/api/v2/organizations/$TerraformCloudOrgName/registry-providers/private/$ProviderNamespace/$ProviderName/versions/$version/platforms" `
                                  -ContentType "application/vnd.api+json" `
                                  -Authentication Bearer `
                                  -Token $TerraformCloudApiKey `
                                  -Body $payloadJson
              
    $binary_upload_url= $response.data.links["provider-binary-upload"]  
    
    Invoke-RestMethod -Method "PUT" `
                  -Uri $binary_upload_url `
                  -InFile $path
}
