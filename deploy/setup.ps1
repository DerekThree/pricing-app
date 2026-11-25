# Run from the main repository: .\deploy\setup.ps1
# Terraform apply/destroy always show their plan and ask for confirmation.
$ErrorActionPreference = 'Stop'
# The Terraform subnet availability zones are also fixed to us-east-1.
$AwsRegion = 'us-east-1'
$AwsAppUrl = 'https://www.flasearell.com'
$Root = Split-Path -Parent $PSScriptRoot
$Infra = Join-Path $PSScriptRoot 'aws'
$Local = Join-Path $PSScriptRoot 'local'
$GitHubOwner = 'DerekThree'
$RepoNames = @('pricing-backend', 'pricing-dashboard', 'pricing-mock-server', 'pricing-engine')
$ServiceNames = @($RepoNames | ForEach-Object { "$_-service" })
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

function Ensure-StateBucket {
    param([ValidateSet('Start', 'Stop', 'Destroy')][string]$Operation)
    $bucket = 'pricing-app-tfstate'
    try {
        Invoke-Native aws @(
            's3api', 'head-bucket', '--bucket', $bucket,
            '--region', $AwsRegion, '--no-cli-pager'
        ) -Capture | Out-Null
        return
    } catch {
        $message = $_.Exception.Message
        if ($message -notmatch '(?i)\b404\b|NoSuchBucket|Not Found') {
            throw "Cannot access Terraform state bucket $($bucket): $message"
        }
    }

    if ($Operation -ne 'Start') {
        throw "Terraform state bucket $bucket is missing. Refusing to create it during $Operation."
    }

    # This bootstrap root uses the bucket as its own backend, so create the
    # empty bucket first, then import it and apply the bootstrap security settings.
    Write-Host "Creating missing Terraform state bucket $bucket..."
    Invoke-Native aws @(
        's3api', 'create-bucket', '--bucket', $bucket,
        '--region', $AwsRegion, '--no-cli-pager'
    )
    $bootstrap = Join-Path $Infra 'bootstrap'
    Invoke-Native terraform @("-chdir=$bootstrap", 'init', '-reconfigure')
    Invoke-Native terraform @("-chdir=$bootstrap", 'import', 'aws_s3_bucket.tfstate', $bucket)
    Invoke-Native terraform @("-chdir=$bootstrap", 'apply')
}

function Get-StateResources {
    $stateJson = Invoke-Native -Program 'terraform' -Arguments @("-chdir=$Infra", 'state', 'pull') -Capture
    if (-not $stateJson.Trim()) { return @() }
    $state = $stateJson | ConvertFrom-Json
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
        Running = ($dbStatus -eq 'available' -and $readyServices.Count -eq $ServiceNames.Count -and
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
                "https://github.com/$GitHubOwner/$name.git", $destination
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
        $buildContext = if ($name -in @('pricing-backend', 'pricing-mock-server', 'pricing-engine')) {
            $Root
        } else {
            Join-Path $Root $name
        }
        Invoke-Native docker @(
            'build', '--platform', 'linux/amd64', '-t', "$($name):latest",
            '-f', (Join-Path $Root "$name/Dockerfile"), $buildContext
        )
    }
}

function Open-Terminal {
    param([string]$Title, [string]$Command)
    $workingDirectory = $Root.Replace("'", "''")
    $code = "Set-Location -LiteralPath '$workingDirectory'; " +
        '$Host.UI.RawUI.WindowTitle = ' + "'$Title'; $Command"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    # Keep the Compose logs visible in the local app terminal.
    Start-Process -FilePath 'powershell.exe' -WorkingDirectory $Root -ArgumentList @(
        '-NoProfile', '-NoExit', '-EncodedCommand', $encoded
    ) | Out-Null
}

function Test-LocalRunning {
    $names = Invoke-Native docker @(
        'container', 'ls', '--filter', 'status=running',
        '--filter', 'label=com.docker.compose.project=pricing-app', '--format', '{{.Names}}'
    ) -Capture
    $running = $names -split '\r?\n'
    $missing = @('pricing-postgres') + $RepoNames | Where-Object {
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
    $envPath = Join-Path $Local '.env'
    $credentialKeys = @(
        'POSTGRES_PASSWORD', 'BACKEND_PASSWORD', 'ENGINE_PASSWORD', 'ACCOUNT_PASSWORD',
        'MOCK_SERVER_PASSWORD', 'RECOMMENDATION_PASSWORD', 'TXN_PROCESSOR_PASSWORD'
    )
    if (-not (Test-Path -LiteralPath $envPath)) {
        $lines = $credentialKeys | ForEach-Object { "$_=$(New-Password)" }
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
    foreach ($key in $credentialKeys) {
        if (-not ($environment -match "^\s*$key\s*=\s*\S+")) {
            throw "$envPath must contain a nonempty $key."
        }
    }
    $containers = (Invoke-Native docker @(
        'container', 'ls', '--all', '--format', '{{.Names}}'
    ) -Capture) -split '\r?\n'
    foreach ($name in (@('pricing-postgres') + $RepoNames)) {
        if ($name -notin $containers) { continue }
        $labels = Invoke-Native docker @(
            'inspect', '--format', '{{json .Config.Labels}}', $name
        ) -Capture | ConvertFrom-Json
        if ($labels.'com.docker.compose.project' -ne 'pricing-app') {
            Invoke-Native docker @('rm', '--force', $name)
        }
    }
    $path = $Local.Replace("'", "''")
    $compose = "docker compose --project-directory '$path' --env-file '$path\.env' " +
        "-f '$path\compose.yaml' up --no-build"
    Open-Terminal 'Pricing app' $compose
    Write-Host 'Waiting for the local Docker containers to start...'
    $deadline = [DateTime]::UtcNow.AddMinutes(3)
    while (-not (Test-LocalRunning)) {
        if ([DateTime]::UtcNow -ge $deadline) {
            throw 'Local containers did not all start. Check the Pricing app terminal.'
        }
        Start-Sleep -Seconds 1
    }
    Write-Host 'Dashboard: http://localhost:5173; backend: 8080; Mock Processor: 8081'
}

function Invoke-Terraform {
    param([string[]]$Arguments)
    Invoke-Native terraform (@("-chdir=$Infra") + $Arguments)
}

function Set-RdsAvailable {
    param([object]$Status)
    if ($Status.Database -eq 'absent') { return }
    $deadline = [DateTime]::UtcNow.AddMinutes(30)
    $startRequested = $false
    do {
        $response = Get-AwsJson @(
            'rds', 'describe-db-instances', '--db-instance-identifier', $Database
        )
        $currentState = $response.DBInstances[0].DBInstanceStatus
        if (-not $currentState) {
            throw 'AWS returned no RDS status. Terraform apply will not continue.'
        }
        if ($currentState -eq 'available') {
            Write-Host 'RDS is available. Continuing with Terraform.'
            return
        }
        if ($currentState -eq 'stopped' -and -not $startRequested) {
            Write-Host 'Starting RDS...'
            Invoke-Native aws @(
                'rds', 'start-db-instance', '--db-instance-identifier', $Database,
                '--region', $AwsRegion, '--query', 'DBInstance.DBInstanceStatus',
                '--output', 'text', '--no-cli-pager'
            )
            $startRequested = $true
        }
        Write-Host "Waiting for RDS to become available (current status: $currentState)..."
        Start-Sleep -Seconds 15
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'RDS did not become available within 30 minutes. Terraform apply will not continue.'
}

function Get-MainCommits {
    $commits = @{}
    foreach ($name in $RepoNames) {
        $commit = Invoke-Native gh @(
            'api', "repos/$GitHubOwner/$name/git/ref/heads/main", '--jq', '.object.sha'
        ) -Capture
        if ($commit -notmatch '^[0-9a-f]{40}$') {
            throw "GitHub did not return the main commit SHA for $name."
        }
        $commits[$name] = $commit
    }
    return $commits
}

function Get-EcrImageDigest {
    param([string]$Name, [string]$Commit)
    $response = Get-AwsJson @(
        'ecr', 'batch-get-image', '--repository-name', $Name,
        '--image-ids', "imageTag=$Commit"
    )
    foreach ($failure in $response.failures) {
        if ($failure.failureCode -ne 'ImageNotFound') {
            throw "ECR failed to check $($name): $($failure.failureReason)"
        }
    }
    if ($response.images) { return $response.images[0].imageId.imageDigest }
}

function Find-CiImageRun {
    param([string]$Name, [string]$Commit)
    $repository = "$GitHubOwner/$Name"
    $artifacts = Invoke-Native gh @(
        'api', "repos/$repository/actions/artifacts", '--method', 'GET',
        '-f', "name=$Name-image-$Commit", '--paginate', '--jq', '.artifacts[] | @json'
    ) -Capture
    foreach ($line in ($artifacts -split '\r?\n')) {
        if (-not $line) { continue }
        $artifact = $line | ConvertFrom-Json
        if ($artifact.expired -or $artifact.workflow_run.head_branch -ne 'main') { continue }
        $run = Invoke-Native gh @(
            'api', "repos/$repository/actions/runs/$($artifact.workflow_run.id)"
        ) -Capture | ConvertFrom-Json
        if ($run.path -eq '.github/workflows/ci.yml' -and $run.conclusion -eq 'success' -and
            $run.head_repository.full_name -eq $repository -and
            ($run.event -eq 'workflow_dispatch' -or
                ($run.event -eq 'push' -and $run.head_sha -eq $Commit))) {
            return [string]$run.id
        }
    }
}

function Start-ImageWorkflow {
    param([string]$Name, [string]$Workflow, [hashtable]$Inputs)
    $parameters = @(
        'api', "repos/$GitHubOwner/$Name/actions/workflows/$Workflow/dispatches",
        '--method', 'POST', '-H', 'X-GitHub-Api-Version: 2026-03-10',
        '-f', 'ref=main'
    )
    foreach ($key in $Inputs.Keys) {
        $parameters += @('-f', "inputs[$key]=$($Inputs[$key])")
    }
    $run = Invoke-Native gh $parameters -Capture | ConvertFrom-Json
    if (-not $run.workflow_run_id) { throw "GitHub did not return the run ID for $Name $Workflow." }
    Write-Host "Started $Name $($Workflow): $($run.html_url)"
    return [string]$run.workflow_run_id
}

function Wait-ImageWorkflow {
    param([string]$Name, [string]$RunId)
    $started = [DateTime]::UtcNow
    $deadline = $started.AddHours(1)
    $visibilityDeadline = $started.AddMinutes(1)
    $run = $null
    do {
        try {
            $run = Invoke-Native gh @(
                'api', "repos/$GitHubOwner/$Name/actions/runs/$RunId"
            ) -Capture | ConvertFrom-Json
        } catch {
            # A newly dispatched run may take a moment to appear in the API.
            if ($run -or [DateTime]::UtcNow -ge $visibilityDeadline -or
                $_.Exception.Message -notmatch '\(HTTP 404\)') {
                throw
            }
        }
        if ($run.status -eq 'completed') {
            if ($run.conclusion -eq 'success') { return }
            throw "$Name $($run.name) finished with $($run.conclusion). See $($run.html_url)."
        }
        Start-Sleep -Seconds 15
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "$Name $($run.name) is still running. See $($run.html_url)."
}

function Invoke-ServiceDeployment {
    param([string]$Name, [string]$Commit)
    $inputs = @{ operation = 'start'; commit_sha = $Commit }
    if (-not (Get-EcrImageDigest $Name $Commit)) {
        $ciRun = Find-CiImageRun $Name $Commit
        if (-not $ciRun) {
            $ciRun = Start-ImageWorkflow $Name 'ci.yml' @{ commit_sha = $Commit }
            Wait-ImageWorkflow $Name $ciRun
        }
        $inputs.ci_run_id = $ciRun
    }
    $cdRun = Start-ImageWorkflow $Name 'cd.yml' $inputs
    Wait-ImageWorkflow $Name $cdRun
    return $cdRun
}

function Invoke-PeerDeployments {
    param([hashtable]$Commits)
    $jobs = @()
    try {
        foreach ($name in ($RepoNames | Where-Object { $_ -ne 'pricing-engine' })) {
            $jobs += Start-Job -Name $name -ScriptBlock {
                param($SetupScript, $Name, $Commit)
                . $SetupScript
                Invoke-ServiceDeployment $Name $Commit | Out-Null
            } -ArgumentList $PSCommandPath, $name, $Commits[$name]
        }
        Receive-Job -Job $jobs -Wait -ErrorAction Continue
        $failed = @($jobs | Where-Object State -ne 'Completed')
        if ($failed.Count) { throw "Deployment failed for $($failed.Name -join ', ')." }
    } finally {
        $jobs | Remove-Job -Force
    }
}

function Get-EngineDeploymentId {
    param([string]$RunId)
    $directory = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
    $file = Join-Path $directory 'engine-deployment-id.txt'
    $download = @(
        'run', 'download', $RunId, '--repo', "$GitHubOwner/pricing-engine",
        '--name', 'engine-deployment-id', '--dir', $directory
    )
    try {
        try {
            Invoke-Native gh $download
        } catch {
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
            Invoke-Native gh $download
        }
        $deploymentId = (Get-Content -LiteralPath $file -Raw).Trim()
        if ($deploymentId -notmatch '^ecs-svc/[0-9]+$') {
            throw "Engine CD run $RunId did not report a valid ECS deployment ID."
        }
        return $deploymentId
    } finally {
        if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
        if (Test-Path -LiteralPath $directory) { [IO.Directory]::Delete($directory) }
    }
}

function Get-EngineService {
    $response = Get-AwsJson @(
        'ecs', 'describe-services', '--cluster', $Cluster, '--services', 'pricing-engine-service'
    )
    return $response.services | Select-Object -First 1
}

function Wait-EngineDeployment {
    param([string]$DeploymentId, [string]$Commit)
    $digest = Get-EcrImageDigest 'pricing-engine' $Commit
    if (-not $digest) { throw "The Engine image for commit $Commit is missing from ECR." }
    $deadline = [DateTime]::UtcNow.AddMinutes(20)
    $observed = $false
    do {
        $engine = Get-EngineService
        $deployment = $engine.deployments | Where-Object { $_.id -eq $DeploymentId }
        if ($deployment) { $observed = $true }
        if ($deployment.rolloutState -eq 'FAILED' -or
            ($observed -and $deployment.status -ne 'PRIMARY')) {
            throw "Engine deployment $DeploymentId failed or was replaced."
        }
        if ($deployment.rolloutState -eq 'COMPLETED' -and $engine.desiredCount -gt 0 -and
            $engine.runningCount -ge $engine.desiredCount -and $engine.pendingCount -eq 0 -and
            @($engine.deployments).Count -eq 1) {
            $tasks = Get-AwsJson @(
                'ecs', 'list-tasks', '--cluster', $Cluster,
                '--service-name', 'pricing-engine-service', '--desired-status', 'RUNNING',
                '--max-items', '1'
            )
            if ($tasks.taskArns) {
                $details = Get-AwsJson @(
                    'ecs', 'describe-tasks', '--cluster', $Cluster, '--tasks', $tasks.taskArns[0]
                )
                $task = $details.tasks | Select-Object -First 1
                if ($task.startedBy -eq $DeploymentId -and $task.healthStatus -eq 'HEALTHY') {
                    $actual = ($task.containers | Where-Object { $_.name -eq 'Main' }).imageDigest
                    if ($actual -ne $digest) {
                        throw "Engine deployment $DeploymentId is running an unexpected image."
                    }
                    return
                }
            }
        }
        Write-Host "Waiting for Engine deployment $DeploymentId..."
        Start-Sleep -Seconds 15
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Engine deployment $DeploymentId did not become healthy within 20 minutes."
}

function Wait-EngineStopped {
    $deadline = [DateTime]::UtcNow.AddMinutes(20)
    do {
        $engine = Get-EngineService
        if (-not ($engine.desiredCount -or $engine.runningCount -or $engine.pendingCount)) {
            return
        }
        Write-Host 'Waiting for Engine to stop...'
        Start-Sleep -Seconds 15
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Engine did not stop within 20 minutes.'
}

function Wait-Services {
    $deadline = [DateTime]::UtcNow.AddMinutes(20)
    do {
        $status = Get-AwsStatus
        if ($status.Running) {
            $resources = @(Get-StateResources)
            foreach ($name in @('backend', 'dashboard', 'mock_server', 'engine')) {
                $expected = Get-StateValue $resources 'aws_ecs_task_definition' $name
                $actual = $status.Services | Where-Object {
                    $_.serviceName -eq "pricing-$($name.Replace('_', '-'))-service"
                }
                if ($actual.taskDefinition -ne $expected.arn) {
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
    Ensure-StateBucket -Operation $Operation
    Invoke-Terraform @('init')
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
    $regionVar = "-var=aws_region=$AwsRegion"
    switch ($Operation) {
        'Start' {
            $commits = Get-MainCommits
            Set-RdsAvailable $status
            $serviceCounts = @{}
            foreach ($name in @('backend', 'dashboard', 'mock_server', 'engine')) {
                $service = $status.Services | Where-Object {
                    $_.serviceName -eq "pricing-$($name.Replace('_', '-'))-service"
                }
                $serviceCounts[$name] = [int]$service.desiredCount
            }
            Write-Host 'Provision infrastructure and credentials, preserving service counts.'
            Invoke-Terraform (@(
                'apply', '-var-file=started.tfvars', '-var=import_existing=false', $regionVar
            ) + @($serviceCounts.Keys | ForEach-Object {
                "-var=$($_)_desired_count=$($serviceCounts[$_])"
            }))
            $engineDeploymentId = $null
            $previousDeploymentId = $null
            if ($serviceCounts.engine -eq 0) {
                $previous = (Get-EngineService).deployments | Where-Object {
                    $_.status -eq 'PRIMARY'
                }
                $previousDeploymentId = $previous.id
            }
            try {
                $engineRun = Invoke-ServiceDeployment 'pricing-engine' $commits['pricing-engine']
                $engineDeploymentId = Get-EngineDeploymentId $engineRun
                Wait-EngineDeployment $engineDeploymentId $commits['pricing-engine']
            } catch {
                # Cleanup requires the ID from the CD run that changed Engine.
                if ($serviceCounts.engine -eq 0 -and $engineDeploymentId) {
                    try {
                        $engine = Get-EngineService
                        $primary = $engine.deployments | Where-Object {
                            $_.status -eq 'PRIMARY'
                        }
                        $rolledBack = $previousDeploymentId -and
                            $primary.id -eq $previousDeploymentId
                        if ($engine.desiredCount -gt 0 -and
                            ($primary.id -eq $engineDeploymentId -or $rolledBack)) {
                            Write-Warning 'Engine startup failed. Check the CloudWatch log.'
                            Get-AwsJson @(
                                'ecs', 'update-service', '--cluster', $Cluster,
                                '--service', $engine.serviceName, '--desired-count', '0'
                            ) | Out-Null
                            Wait-EngineStopped
                        }
                    } catch {
                        Write-Warning "Could not confirm Engine stopped: $($_.Exception.Message)"
                    }
                }
                throw
            }
            Invoke-PeerDeployments $commits
            Wait-Services
            Write-Host "Dashboard: $AwsAppUrl"
        }
        'Stop' {
            Write-Host 'Stop ECS and RDS and remove the ALB.'
            Invoke-Terraform @('apply', '-var=import_existing=false', $regionVar)
        }
        'Destroy' {
            Write-Host 'Destroy removes all managed infrastructure, database data, and ECR images.'
            Invoke-Terraform @(
                'destroy', '-var-file=started.tfvars', '-var=import_existing=false', $regionVar
            )
        }
    }
}

function Show-Menu {
    $available = @{}
    foreach ($cli in @('git', 'docker', 'aws', 'terraform', 'gh')) {
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
        3 = @('aws', 'terraform', 'gh')
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
    $stateAvailable = $true
    try {
        $resources = @(Get-StateResources)
    } catch {
        $resources = @()
        $stateAvailable = $false
        Write-Host 'Terraform state unavailable; AWS setup will initialize it after login.'
    }
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
            $reasons[3] = (@(
                $reasons[3], "Already running at $AwsAppUrl"
            ) | Where-Object { $_ }) -join '; '
        }
        if (-not $status.NeedsStop) {
            $stopReason = if ($status.Exists) { 'Already stopped' } else { 'Not installed' }
            $reasons[4] = (@(
                $reasons[4], $stopReason
            ) | Where-Object { $_ }) -join '; '
        }
    }
    if ($stateAvailable -and -not $resources.Count) {
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

