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

# convert the api key into a secure string as is required by -Token
$secureApiKey = $TerraformCloudApiKey | ConvertTo-SecureString -AsPlainText -Force

# Parse the artifacts json
$artifacts = $ArtifactsJson | ConvertFrom-Json

# Parse the metadata json
$metadata = $MetadataJson | ConvertFrom-Json

# get the new version
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

$requestBodyJson = ConvertTo-Json -InputObject $requestBody -Compress -Depth 100

Write-Output "Creating new version: $version"

$response = Invoke-RestMethod -Method "POST" `
                              -Uri "https://app.terraform.io/api/v2/organizations/$TerraformCloudOrgName/registry-providers/private/$ProviderNamespace/$ProviderName/versions" `
                              -ContentType "application/vnd.api+json" `
                              -Authentication Bearer `
                              -Token $secureApiKey `
                              -Body $requestBodyJson          
                              
Write-Output "Successfully created new version: $version"           

$shasums_url = $response.data.links."shasums-upload"
$shasums_sig_url = $response.data.links."shasums-sig-upload"

# Upload SHASUMS and SHASUMS SIG
$shasums_artifact = $artifacts | Where-Object { $_.type -eq "Checksum" } | Select-Object -First 1

Write-Output "Uploading SHASUMS file"

Invoke-RestMethod -Method "PUT" `
                  -Uri $shasums_url `
                  -InFile $shasums_artifact.path

Write-Output "Successfully uploaded SHASUMS file"

# The sig file is the same name with .sig appended
$shasums_artifact = $artifacts | Where-Object { $_.type -eq "Signature" } | Select-Object -First 1

Write-Output "Uploading SHASUMS SIG file"

Invoke-RestMethod -Method "PUT" `
                  -Uri $shasums_sig_url `
                  -InFile $shasums_sig_artifact.path

Write-Output "Successfully uploaded SHASUMS SIG file"

# For each binary, create a new Provider Platform for this version
# https://developer.hashicorp.com/terraform/cloud-docs/api-docs/private-registry/provider-versions-platforms#create-a-provider-platform
$artifacts | Where-Object { $_.type -eq "Archive" } | ForEach-Object {
    $name = $_.name
    $path = $_.path
    $os = $_.goos
    $arch = $_.goarch
    $checksum = $_.extra.Checksum.Replace("sha256:","")

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

    $payloadJson = ConvertTo-Json -InputObject $payload -Compress -Depth 100

    Write-Output "Creating new platform: $os, $arch"

    $response = Invoke-RestMethod -Method "POST" `
                                  -Uri "https://app.terraform.io/api/v2/organizations/$TerraformCloudOrgName/registry-providers/private/$ProviderNamespace/$ProviderName/versions/$version/platforms" `
                                  -ContentType "application/vnd.api+json" `
                                  -Authentication Bearer `
                                  -Token $secureApiKey `
                                  -Body $payloadJson
                                  
    Write-Output "Successfully created new platform: $os, $arch"
              
    $binary_upload_url= $response.data.links."provider-binary-upload"
    
    Write-Output "Uploading binary: $name"

    Invoke-RestMethod -Method "PUT" `
                  -Uri $binary_upload_url `
                  -InFile $path
                  
    Write-Output "Successfully uploaded binary: $name"
}