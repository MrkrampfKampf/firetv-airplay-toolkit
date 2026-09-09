@{
    # These scripts are interactive tooling: their output is meant for a person
    # watching a console, not for a pipeline. Write-Host is the correct call here,
    # so the rule against it is excluded deliberately rather than suppressed
    # inline 40 times. Every other rule stays on.
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
    )
}
