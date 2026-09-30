# Run from the future main repository: .\app.ps1
# Terraform apply/destroy always show their plan and ask for confirmation.
$ErrorActionPreference = 'Stop'
# The Terraform subnet availability zones are also fixed to us-east-1.
$AwsRegion = 'us-east-1'
$Root = $PSScriptRoot
$Infra = Join-Path $Root 'infra'
$RepoNames = @('pricing-backend', 'pricing-dashboard')
$ServiceNames = @('pricing-backend-service', 'pricing-dashboard-service')
$Cluster = 'pricing-app-cluster'
$Database = 'pricing-app-db'
$script:MenuAwsStatus = $null
$script:MenuAwsCheckedAt = [DateTime]::MinValue

function Invoke-Native {
    param([string]$Program, [string[]]$Arguments, [switch]$Capture)
    if ($Capture) {
        # Windows PowerShell turns native stderr into ErrorRecord objects.
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $lines = @(& $Program @Arguments 2>&1)
            $code = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        if ($code -ne 0) {
            throw "$Program exited with code $($code): $($lines -join [Environment]::NewLine)"
        }
        return ($lines -join [Environment]::NewLine)
    }
    & $Program @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "$Program exited with code $LASTEXITCODE." }
}

function Get-AwsJson {
    param([string[]]$Arguments)
    $argumentsWithOutput = $Arguments + @('--region', $AwsRegion, '--output', 'json')
    $argumentsWithOutput += '--no-cli-pager'
    $json = Invoke-Native aws $argumentsWithOutput -Capture
    return ($json | ConvertFrom-Json)
}

function Connect-Aws {
    try {
        $identity = Get-AwsJson @('sts', 'get-caller-identity')
    } catch {
        Write-Host 'AWS login required.'
        try {
            Invoke-Native aws @('login', '--region', $AwsRegion)
            Read-Host 'Complete AWS login, then press Enter' | Out-Null
            $identity = Get-AwsJson @('sts', 'get-caller-identity')
        } catch {
            $script:LoginFailed = $true
            throw 'AWS login failed. Exiting.'
        }
    }
    Write-Host "AWS account: $($identity.Account); region: $AwsRegion"
    return $identity
}

function Get-StateResources {
    $path = Join-Path $Infra 'terraform.tfstate'
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $state = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    return @($state.resources | Where-Object {
        $_.mode -eq 'managed' -and @($_.instances).Count -gt 0
    })
}

function Get-StateValue {
    param([object[]]$Resources, [string]$Type, [string]$Name)
    $resource = $Resources | Where-Object { $_.type -eq $Type -and $_.name -eq $Name }
    if ($resource) { return $resource.instances[0].attributes }
}

function Assert-StateAccount {
    param([object[]]$Resources, [string]$Account)
    foreach ($resource in $Resources) {
        foreach ($instance in $resource.instances) {
            $arn = $instance.attributes.arn
            if ($arn -match '^arn:[^:]+:[^:]+:([^:]*):(\d{12}):') {
                if ($Matches[2] -ne $Account) {
                    throw 'The Terraform state belongs to a different AWS account.'
                }
                if ($Matches[1] -and $Matches[1] -ne $AwsRegion) {
                    throw 'The Terraform state belongs to a different AWS region.'
                }
            }
        }
    }
}

function Get-AwsStatus {
    $databases = @(Get-AwsJson @(
        'rds', 'describe-db-instances', '--query',
        "DBInstances[?DBInstanceIdentifier=='$Database']"
    ))
    $loadBalancers = @(Get-AwsJson @(
        'elbv2', 'describe-load-balancers', '--query',
        "LoadBalancers[?LoadBalancerName=='pricing-app-alb']"
    ))
    try {
        $response = Get-AwsJson (@(
            'ecs', 'describe-services', '--cluster', $Cluster, '--services'
        ) + $ServiceNames)
        $unexpected = @($response.failures | Where-Object { $_.reason -ne 'MISSING' })
        if ($unexpected.Count) { throw ($unexpected | ConvertTo-Json -Compress) }
        $services = @($response.services | Where-Object { $_.status -eq 'ACTIVE' })
    } catch {
        if ($_.Exception.Message -notmatch 'ClusterNotFoundException') { throw }
        $services = @()
    }
    $dbStatus = if ($databases.Count) { $databases[0].DBInstanceStatus } else { 'absent' }
    $readyServices = @($services | Where-Object {
        $_.desiredCount -ge 1 -and $_.runningCount -ge $_.desiredCount -and
        $_.pendingCount -eq 0 -and @($_.deployments).Count -eq 1 -and
        $_.deployments[0].rolloutState -eq 'COMPLETED'
    })
    $busyServices = @($services | Where-Object {
        $_.desiredCount -gt 0 -or $_.runningCount -gt 0 -or $_.pendingCount -gt 0
    })
    return [pscustomobject]@{
        Database = $dbStatus
        Services = $services
        LoadBalancers = $loadBalancers
        Running = ($dbStatus -eq 'available' -and $readyServices.Count -eq 2 -and
            $loadBalancers.Count -eq 1 -and $loadBalancers[0].State.Code -eq 'active')
        NeedsStop = ($dbStatus -notin @('absent', 'stopped') -or
            $busyServices.Count -gt 0 -or $loadBalancers.Count -gt 0)
        Exists = ($databases.Count -gt 0 -or $services.Count -gt 0 -or
            $loadBalancers.Count -gt 0)
    }
}

function New-Password {
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    $buffer = New-Object byte[] 64
    $password = New-Object Text.StringBuilder
    try {
        while ($password.Length -lt 32) {
            $random.GetBytes($buffer)
            foreach ($value in $buffer) {
                # Rejection sampling avoids bias when mapping bytes to 62 characters.
                if ($value -lt 248 -and $password.Length -lt 32) {
                    [void]$password.Append($alphabet[$value % 62])
                }
            }
        }
        return $password.ToString()
    } finally {
        $random.Dispose()
    }
}

function Copy-Repositories {
    foreach ($name in $RepoNames) {
        $destination = Join-Path $Root $name
        if (-not (Test-Path -LiteralPath $destination)) {
            Invoke-Native git @(
                'clone', '--branch', 'main', '--single-branch',
                "https://github.com/DerekThree/$name.git", $destination
            )
            Write-Host "$name cloned."
        } elseif (-not (Test-Path -LiteralPath (Join-Path $destination '.git'))) {
            throw "$destination exists but is not a Git checkout."
        } else {
            Write-Host "$name already present."
        }
    }
}

function Build-LocalImages {
    Invoke-Native docker @('info') -Capture | Out-Null
    Copy-Repositories
    foreach ($name in $RepoNames) {
        try {
            Invoke-Native docker @('image', 'inspect', "$($name):latest") -Capture | Out-Null
        } catch {
            Invoke-Native docker @(
                'build', '--platform', 'linux/amd64', '-t', "$($name):latest",
                (Join-Path $Root $name)
            )
        }
    }
}

function Open-Terminal {
    param([string]$Title, [string]$Command)
    $workingDirectory = $Root.Replace("'", "''")
    $code = "Set-Location -LiteralPath '$workingDirectory'; " +
        '$Host.UI.RawUI.WindowTitle = ' + "'$Title'; $Command"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    # These two visible terminals are the requested local app terminals.
    Start-Process -FilePath 'powershell.exe' -WorkingDirectory $Root -ArgumentList @(
        '-NoProfile', '-NoExit', '-EncodedCommand', $encoded
    ) | Out-Null
}

function Test-LocalRunning {
    $names = Invoke-Native docker @(
        'container', 'ls', '--filter', 'status=running', '--format', '{{.Names}}'
    ) -Capture
    $running = $names -split '\r?\n'
    $missing = @('pricing-postgres', 'pricing-backend', 'pricing-dashboard') | Where-Object {
        $_ -notin $running
    }
    return @($missing).Count -eq 0
}

function Start-Local {
    if (Test-LocalRunning) {
        Write-Host 'App is already running in local Docker.'
        return
    }
    Build-LocalImages
    Invoke-Native docker @('compose', 'version') -Capture | Out-Null
    $backend = Join-Path $Root 'pricing-backend'
    $envPath = Join-Path $backend '.env'
    if (-not (Test-Path -LiteralPath $envPath)) {
        $lines = @(
            'POSTGRES_DB=pricingdb'
            'POSTGRES_USER=pricinguser'
            "POSTGRES_PASSWORD=$(New-Password)"
        )
        # CreateNew preserves an existing password even if another process creates the file.
        $stream = [IO.File]::Open($envPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
        try {
            $bytes = [Text.Encoding]::UTF8.GetBytes(
                ($lines -join [Environment]::NewLine) + [Environment]::NewLine
            )
            $stream.Write($bytes, 0, $bytes.Length)
        } finally {
            $stream.Dispose()
        }
        Write-Host "Database credentials saved to $envPath"
    }
    $environment = Get-Content -LiteralPath $envPath
    foreach ($key in @('POSTGRES_DB', 'POSTGRES_USER', 'POSTGRES_PASSWORD')) {
        if (-not ($environment -match "^\s*$key\s*=\s*\S+")) {
            throw "$envPath must contain a nonempty $key."
        }
    }
    $path = $backend.Replace("'", "''")
    $compose = "docker compose --project-directory '$path' --env-file '$path\.env' " +
        "-f '$path\compose.yaml' up --no-build"
    Open-Terminal 'Pricing backend + PostgreSQL' $compose
    $containers = Invoke-Native docker @(
        'container', 'ls', '--all', '--filter', 'name=^/pricing-dashboard$', '--format', '{{.ID}}'
    ) -Capture
    if ($containers.Trim()) {
        Open-Terminal 'Pricing dashboard' 'docker start --attach pricing-dashboard'
    } else {
        Open-Terminal 'Pricing dashboard' (
            'docker run --name pricing-dashboard -p 5173:5173 ' +
            '-e API_URL=http://localhost:8080 pricing-dashboard:latest'
        )
    }
    Write-Host 'Waiting for the local Docker containers to start...'
    $deadline = [DateTime]::UtcNow.AddSeconds(60)
    while (-not (Test-LocalRunning)) {
        if ([DateTime]::UtcNow -ge $deadline) {
            throw 'Local containers did not all start. Check the backend and dashboard terminals.'
        }
        Start-Sleep -Seconds 1
    }
    Write-Host 'Dashboard: http://localhost:5173; backend: http://localhost:8080'
}

function Invoke-Terraform {
    param([string[]]$Arguments)
    Invoke-Native terraform (@("-chdir=$Infra") + $Arguments)
}

function Set-RdsAvailable {
    param([object]$Status)
    if ($Status.Database -in @('absent', 'available')) { return }
    if ($Status.Database -eq 'stopping') {
        Invoke-Native aws @(
            'rds', 'wait', 'db-instance-stopped', '--db-instance-identifier', $Database,
            '--region', $AwsRegion
        )
    }
    if ($Status.Database -in @('stopped', 'stopping')) {
        Write-Host 'Make RDS available before applying database or service changes.'
        Invoke-Terraform @(
            'apply', '-var-file=started.tfvars', '-var=import_existing=false',
            '-target=aws_rds_instance_state.pricing'
        )
    }
    Invoke-Native aws @(
        'rds', 'wait', 'db-instance-available', '--db-instance-identifier', $Database,
        '--region', $AwsRegion
    )
}

function Push-Images {
    $resources = @(Get-StateResources)
    foreach ($name in @('backend', 'dashboard')) {
        $repository = Get-StateValue $resources 'aws_ecr_repository' $name
        if (-not $repository.repository_url) { throw "Missing ECR repository: $name." }
        $registry = $repository.repository_url.Split('/')[0]
        $token = Invoke-Native aws @(
            'ecr', 'get-login-password', '--region', $AwsRegion
        ) -Capture
        try {
            $token | & docker login --username AWS --password-stdin $registry | Out-Host
            if ($LASTEXITCODE -ne 0) { throw 'Docker ECR login failed.' }
        } finally {
            $token = $null
        }
        $image = "$($repository.repository_url):latest"
        Invoke-Native docker @('tag', "pricing-$($name):latest", $image)
        Invoke-Native docker @('push', $image)
    }
}

function Wait-Services {
    param([switch]$Stopped)
    $deadline = [DateTime]::UtcNow.AddMinutes(20)
    do {
        $status = Get-AwsStatus
        if ($Stopped) {
            $busy = @($status.Services | Where-Object {
                $_.desiredCount -ne 0 -or $_.runningCount -ne 0 -or $_.pendingCount -ne 0
            })
            if (-not $busy.Count) { return }
        } elseif ($status.Running) {
            $resources = @(Get-StateResources)
            foreach ($name in @('backend', 'dashboard')) {
                $expected = Get-StateValue $resources 'aws_ecs_service' $name
                $actual = $status.Services | Where-Object {
                    $_.serviceName -eq "pricing-$name-service"
                }
                if ($actual.taskDefinition -ne $expected.task_definition) {
                    throw "The $name deployment rolled back or uses an unexpected task definition."
                }
            }
            return
        }
        Write-Host 'Waiting for ECS services...'
        Start-Sleep -Seconds 15
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'ECS did not reach the requested state within 20 minutes.'
}

function Invoke-AwsOperation {
    param([ValidateSet('Start', 'Stop', 'Destroy')][string]$Operation)
    $script:MenuAwsCheckedAt = [DateTime]::MinValue
    $identity = Connect-Aws
    $resources = @(Get-StateResources)
    Assert-StateAccount $resources $identity.Account
    $status = Get-AwsStatus
    if ($Operation -eq 'Start' -and $status.Running) {
        Write-Host 'App is already running in AWS.'
        return
    }
    if ($Operation -eq 'Stop' -and -not $status.NeedsStop) {
        Write-Host 'App is already stopped in AWS.'
        return
    }
    if (-not $resources.Count -and $status.Exists) {
        throw 'AWS infrastructure exists without local Terraform state. Import it before proceeding.'
    }
    if ($Operation -ne 'Start' -and -not $resources.Count) {
        Write-Host 'No Terraform-managed infrastructure exists.'
        return
    }
    $savedEnvironment = @{}
    foreach ($key in @('TF_VAR_aws_region', 'TF_VAR_rds_password')) {
        $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
    }
    try {
        $env:TF_VAR_aws_region = $AwsRegion
        $env:TF_VAR_rds_password = $null
        $version = Get-StateValue $resources 'aws_secretsmanager_secret_version' 'rds_password'
        if ($version) {
            $env:TF_VAR_rds_password = ($version.secret_string | ConvertFrom-Json).password
            if (-not $env:TF_VAR_rds_password) { throw 'Saved RDS password is missing.' }
        } elseif ($Operation -eq 'Start' -and $status.Database -eq 'absent') {
            $env:TF_VAR_rds_password = New-Password
        }
        Invoke-Terraform @('init')
        switch ($Operation) {
            'Start' {
                Build-LocalImages
                if ($status.Database -eq 'absent') {
                    Write-Host 'Create the database, password, and image repositories.'
                    Invoke-Terraform @(
                        'apply', '-var-file=stopped.tfvars', '-var=rds_state=available',
                        '-var=import_existing=false', '-target=aws_db_instance.pricing',
                        '-target=aws_ecr_repository.backend', '-target=aws_ecr_repository.dashboard'
                    )
                    Write-Host 'Create the remaining infrastructure with ECS at zero tasks.'
                    Invoke-Terraform @(
                        'apply', '-var-file=stopped.tfvars', '-var=rds_state=available',
                        '-var=import_existing=false'
                    )
                } else {
                    Set-RdsAvailable $status
                    Invoke-Terraform @(
                        'apply', '-var-file=started.tfvars', '-var=import_existing=false',
                        '-target=aws_ecr_repository.backend', '-target=aws_ecr_repository.dashboard'
                    )
                }
                Push-Images
                Write-Host 'Create the ALB and start both ECS services.'
                # New revisions also replace tasks left running after a partial startup,
                # so both services pull the latest images just pushed to ECR.
                Invoke-Terraform @(
                    'apply', '-var-file=started.tfvars', '-var=import_existing=false',
                    '-replace=aws_ecs_task_definition.backend',
                    '-replace=aws_ecs_task_definition.dashboard'
                )
                Wait-Services
                Invoke-Terraform @('output', '-raw', 'alb_dns_name')
                Write-Host ''
            }
            'Stop' {
                Set-RdsAvailable $status
                Write-Host 'Stop ECS and remove the ALB.'
                Invoke-Terraform @(
                    'apply', '-var-file=stopped.tfvars', '-var=rds_state=available',
                    '-var=import_existing=false'
                )
                Wait-Services -Stopped
                Write-Host 'Stop RDS after ECS has drained.'
                Invoke-Terraform @(
                    'apply', '-var-file=stopped.tfvars', '-var=import_existing=false',
                    '-target=aws_rds_instance_state.pricing'
                )
            }
            'Destroy' {
                Write-Host 'Destroy removes all managed infrastructure, database data, and ECR images.'
                Invoke-Terraform @(
                    'destroy', '-var-file=started.tfvars', '-var=import_existing=false'
                )
            }
        }
    } finally {
        foreach ($key in $savedEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($key, $savedEnvironment[$key], 'Process')
        }
    }
}

function Show-Menu {
    $available = @{}
    foreach ($cli in @('git', 'docker', 'aws', 'terraform')) {
        $available[$cli] = [bool](Get-Command $cli -ErrorAction SilentlyContinue)
    }
    $needsClone = @($RepoNames | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $Root $_))
    }).Count -gt 0
    $buildTools = @('docker')
    if ($needsClone) { $buildTools += 'git' }
    $requirements = @{
        1 = @('git')
        2 = $buildTools
        3 = $buildTools + @('aws', 'terraform')
        4 = @('aws', 'terraform')
        5 = @('aws', 'terraform')
    }
    $labels = @{
        1 = 'Only clone repos'
        2 = 'Start app in local Docker'
        3 = 'Start app in AWS'
        4 = 'Stop app in AWS'
        5 = 'Destroy infra in AWS'
    }
    $reasons = @{}
    foreach ($number in 1..5) {
        $missing = @($requirements[$number] | Where-Object { -not $available[$_] })
        if ($missing.Count) { $reasons[$number] = "$($missing -join ', ') missing" }
    }
    $reposCloned = @($RepoNames | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path (Join-Path $Root $_) '.git'))
    }).Count -eq 0
    if ($reposCloned) { $reasons[1] = 'Already cloned' }
    if ($available['docker']) {
        try {
            if (Test-LocalRunning) { $reasons[2] = 'Already running' }
        } catch {
            Write-Host 'Local Docker status unavailable.'
        }
    }
    $resources = @(Get-StateResources)
    $status = $null
    if ($available['aws']) {
        if (([DateTime]::UtcNow - $script:MenuAwsCheckedAt).TotalSeconds -ge 60) {
            Write-Host 'Checking AWS status...'
            try {
                $script:MenuAwsStatus = Get-AwsStatus
            } catch {
                $script:MenuAwsStatus = $null
                Write-Host 'AWS status unknown; login and status checks run after selection.'
            }
            $script:MenuAwsCheckedAt = [DateTime]::UtcNow
        }
        $status = $script:MenuAwsStatus
    }
    if ($status) {
        if ($status.Running) {
            $reasons[3] = (@($reasons[3], 'Already running') | Where-Object { $_ }) -join '; '
        }
        if (-not $status.NeedsStop) {
            $reasons[4] = (@(
                $reasons[4], 'Already stopped or not installed'
            ) | Where-Object { $_ }) -join '; '
        }
    }
    if (-not $resources.Count) {
        $reasons[5] = (@(
            $reasons[5], 'No Terraform-managed infrastructure'
        ) | Where-Object { $_ }) -join '; '
    }
    $recommended = if ($status -and $status.Running) { 0 }
        elseif (-not $reasons[3]) { 3 }
        elseif (-not $reasons[2]) { 2 }
        else { 0 }
    Write-Host ''
    foreach ($number in 1..5) {
        $line = "$number. $($labels[$number])"
        if ($reasons[$number]) {
            Write-Host "$line ($($reasons[$number]))" -ForegroundColor DarkGray
        } else {
            if ($number -eq $recommended) { $line += ' (recommended)' }
            Write-Host $line
        }
    }
    return $reasons
}

# Dot-sourcing exposes functions without opening the menu.
if ($MyInvocation.InvocationName -ne '.') {
    while ($true) {
        try {
            $disabled = Show-Menu
        } catch {
            Write-Host $_.Exception.Message -ForegroundColor Red
            break
        }
        try {
            $selection = Read-Host 'Choose 1-5, or Q to quit'
            if ($selection -eq 'q') { break }
            if ($selection -notmatch '^[1-5]$') { continue }
            $number = [int]$selection
            if ($disabled[$number]) {
                Write-Host $disabled[$number]
                continue
            }
            switch ($number) {
                1 { Copy-Repositories }
                2 { Start-Local }
                3 { Invoke-AwsOperation Start }
                4 { Invoke-AwsOperation Stop }
                5 { Invoke-AwsOperation Destroy }
            }
        } catch {
            Write-Host $_.Exception.Message -ForegroundColor Red
            if ($script:LoginFailed) { break }
        }
    }
}

