BeforeAll {
    $Root = Split-Path $PSScriptRoot
    $tools = Import-PowerShellDataFile (Join-Path $Root 'pipelines\tools.psd1')
    Import-Module powershell-yaml -RequiredVersion $tools.YamlVersion
    $ci = Get-Content (Join-Path $Root 'azure-pipelines.yml') -Raw | ConvertFrom-Yaml
    $cd = Get-Content (Join-Path $Root 'pipelines\deploy.yml') -Raw | ConvertFrom-Yaml
    $build = Get-Content (Join-Path $Root 'pipelines\templates\build.yml') -Raw | ConvertFrom-Yaml
    $environment = Get-Content (Join-Path $Root 'pipelines\templates\environment.yml') -Raw | ConvertFrom-Yaml
}

Describe 'Azure DevOps YAML contracts' {
    It 'parses every YAML file and all automation scripts' {
        $yamlFiles = @((Get-Item (Join-Path $Root 'azure-pipelines.yml'))) + @(Get-ChildItem (Join-Path $Root 'pipelines') -Recurse -Filter '*.yml')
        $yamlFiles.Count | Should -Be 7
        foreach ($file in $yamlFiles) {
            { Get-Content $file.FullName -Raw | ConvertFrom-Yaml } | Should -Not -Throw
        }
        foreach ($file in Get-ChildItem (Join-Path $Root 'pipelines\scripts') -Filter '*.ps1') {
            $tokens = $null
            $parseErrors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref] $tokens, [ref] $parseErrors)
            $parseErrors.Count | Should -Be 0
        }
    }
    It 'keeps PR validation credential-free and CD manual' {
        $ci.pr.branches.include | Should -Contain 'main'
        $cd.trigger | Should -Be 'none'
        $cd.pr | Should -Be 'none'
        @($build.stages[0].jobs[0].steps | Where-Object task -EQ 'AzureCLI@2').Count | Should -Be 0
        @($cd.parameters[0].values) -join ',' | Should -Be 'development,test,production'
    }
    It 'guards every authenticated stage against PR and non-main execution' {
        foreach ($stage in $environment.stages) {
            $stage.condition | Should -Match 'PullRequest'
            $stage.condition | Should -Match 'refs/heads/main'
        }
        $environment.stages[0].dependsOn | Should -Be 'Build'
        $environment.stages[1].dependsOn | Should -Be 'Plan'
    }
    It 'validates Bicep, portal artifacts and README options on source and pull-request changes' {
        foreach ($path in 'infra/*', 'pipelines/*', 'tests/*', 'azure-pipelines.yml', 'README.md') {
            $ci.trigger.paths.include | Should -Contain $path
            $ci.pr.paths.include | Should -Contain $path
        }
    }
    It 'uses protected environments, sequential locks and current-run compiled artifacts' {
        $deploy = $environment.stages[1]
        $deploy.lockBehavior | Should -Be 'sequential'
        $deploy.jobs[0].environment | Should -Be '${{ parameters.deploymentEnvironment }}'
        $steps = $deploy.jobs[0].strategy.runOnce.deploy.steps
        @($steps | Where-Object download -EQ 'current').Count | Should -Be 2
        @($steps | Where-Object task -EQ 'AzureCLI@2')[0].inputs.arguments | Should -Match '\-PlanDirectory'
        @($steps | Where-Object task -EQ 'AzureCLI@2')[0].inputs.arguments | Should -Not -Match '\.bicep'
    }
    It 'uses compile-time service connections and never exposes federated credentials to scripts' {
        $planTask = @($environment.stages[0].jobs[0].steps | Where-Object task -EQ 'AzureCLI@2')[0]
        $deployTask = @($environment.stages[1].jobs[0].strategy.runOnce.deploy.steps | Where-Object task -EQ 'AzureCLI@2')[0]
        $planTask.inputs.azureSubscription | Should -Be '${{ parameters.planServiceConnection }}'
        $deployTask.inputs.azureSubscription | Should -Be '${{ parameters.deployServiceConnection }}'
        foreach ($task in $planTask, $deployTask) {
            $task.inputs.addSpnToEnvironment | Should -BeFalse
            $task.inputs.visibleAzLogin | Should -BeFalse
        }
    }
    It 'isolates target subscriptions, resource groups, connections and DevOps environments' {
        $all = foreach ($envName in 'development', 'test', 'production') {
            (Get-Content (Join-Path $Root "pipelines\environments\$envName.yml") -Raw | ConvertFrom-Yaml).variables
        }
        foreach ($field in 'planServiceConnection', 'deployServiceConnection', 'subscriptionId', 'resourceGroupName', 'deploymentEnvironment') {
            @($all | ForEach-Object { $_[$field] } | Select-Object -Unique).Count | Should -Be 3
        }
    }
}
