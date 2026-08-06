# package-registry-actions

Shared composite actions for authenticating to the SUSE Observability AWS CodeArtifact
package registry. Consumed by every Maven publisher in the org.

## `codeartifact-auth`

Fetches a short-lived CodeArtifact authorization token and writes it to a `0600` credentials
file under `$RUNNER_TEMP`, exporting only the containing directory as
`CODEARTIFACT_CREDENTIALS_DIR`. The token never becomes a step output, never enters
`GITHUB_ENV`, and never touches the workspace.

The caller configures AWS credentials first, so that ref-dependent role selection stays
visible in the calling workflow rather than hidden in here.

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@e6de054238d6b7531b4efff3b6587d9aade6a06c # v6.2.3
  with:
    role-to-assume: ${{ env.CODEARTIFACT_REPOSITORY == 'packages' && vars.CODEARTIFACT_MAVEN_RELEASE_ROLE_ARN || vars.CODEARTIFACT_MAVEN_SNAPSHOT_ROLE_ARN }}
    aws-region: ${{ vars.CODEARTIFACT_REGION }}

- name: Authenticate to CodeArtifact
  uses: StackVista/package-registry-actions/.github/actions/codeartifact-auth@<sha> # v1
  with:
    domain: ${{ vars.CODEARTIFACT_DOMAIN }}
    domain-owner: ${{ vars.CODEARTIFACT_DOMAIN_OWNER }}
    region: ${{ vars.CODEARTIFACT_REGION }}
    repository: ${{ env.CODEARTIFACT_REPOSITORY }}
```

All four inputs are required with no defaults: a caller that omits one fails at action load
rather than authenticating against the wrong domain.

`repository` is the single repository the calling ref may publish to. A credential is written
for that repository's challenge realm only, so a snapshot build cannot answer a challenge from
the release repository even if it could otherwise reach it.

Pin by full commit SHA with a trailing version comment.

The build side of the contract — reading `CODEARTIFACT_CREDENTIALS_DIR` — lives in
`stackstate-sbt-build`'s `Authorizations.codeArtifactPublishCredentials`. See
[CodeArtifact Package Registry Configuration](https://github.com/StackVista/stackstate-mission-control/blob/main/wiki/concepts/codeartifact-package-registry-configuration.md).
