# Recommended repository settings

The following GitHub settings should be enabled manually for `main` because they are repository-level controls rather than versioned files.

## Pull request protection

- require a pull request before merging;
- require the `powershell` and `shell-and-docs` jobs from the `Validate` workflow;
- require branches to be up to date before merging;
- require all review conversations to be resolved;
- block direct pushes and force pushes;
- require CODEOWNERS review when additional maintainers are added.

## Merge strategy

- enable squash merge;
- disable merge commits and rebase merge for a consistent linear history;
- automatically delete head branches after merge.

## Security

- enable private vulnerability reporting;
- enable Dependabot alerts and security updates;
- enable secret scanning and push protection when available for the repository plan;
- restrict GitHub Actions to trusted actions and require actions to be pinned to full commit SHAs.

The workflow and repository files already support these settings, but GitHub must enforce them at the repository level.
