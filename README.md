# package-registry-actions

Shared composite actions for authenticating to the SUSE Observability AWS CodeArtifact
package registry — the per-repository *publish* credential, and the org-wide read-only
*proxy* credential every dependency-resolving build needs.

## For developers

Publishing of artifacts can only be done from Github workflows, not from any local machine. However, to 
be able to build any of our code you need access to the package-registry-proxy. We use a proxy to have local (for our workflows) caching and to avoid the annoying authentication mechanism for AWS CodeArtifacts. 

Configuration for SBT and Gradle local builds (we're configuring Gradle to look for the same SBT credentials file, so no need to copy). Create the `~/.sbt/packages-registry-proxy.credentials` with this contents (insert your username and password as described in the [credentials section](#proxy-credentials)):

```
realm=Packages Registry Proxy
host=packages.tooling.stackstate.io
user=<username>
password=<password>
```

### Proxy credentials

If you don't have credentials yet for the GitLab Proxy follow these instructions:
* Think of a new password and store that safely (for example in your Bitwarden vault) and put it into the configuration files for SBT and gradle
* Your username is the first part of your SUSE mail address, for example for `remco.beckers@suse.com` the username is `remco.beckers`.
* Use `openssl passwd -apr1` and input your new password to generate a hash
* Email it to vladimir.iliakov@suse.com in the following format: <login>:<generated hash>, for example:
`remco.beckers:$apr1$mA6m50K0$npoYrA/LsDRRqXgZ1P3VH1`
* Vladimir will add you to the proxy user list

## For Github workflows

### `codeartifact-auth`

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

### `package-registry-proxy-auth`

Writes the shared read-only proxy credential to a `0600` credentials file under `$RUNNER_TEMP`,
exporting its path as `PACKAGE_REGISTRY_PROXY_CREDENTIALS_FILE`. The token never becomes a step
output and never enters the build's process environment.

```yaml
- name: Authenticate to the package registry proxy
  uses: StackVista/package-registry-actions/.github/actions/package-registry-proxy-auth@<sha> # v1
  with:
    username: ${{ vars.PACKAGE_REGISTRY_PROXY_USER }}
    token: ${{ secrets.PACKAGE_REGISTRY_PROXY_TOKEN }}
```

Both inputs are required and must be non-empty, so a job with an unset org variable fails here
rather than at a `401` from the proxy.

The proxy host and realm are constants in the action, matching the proxy URLs being build
constants — a per-caller override could only ever disagree with them. This is the CI half of the
developer `~/.sbt/packages-registry-proxy.credentials` convention, so the build reads one
credentials file in both cases and needs no environment-variable path at all.

### Other credential formats

Both actions write the sbt/Ivy/Coursier credentials file by default, and can additionally emit
the same credential in two other formats:

| input | writes | for |
| --- | --- | --- |
| `maven-settings: true` | `settings.xml`, path exported as `MAVEN_SETTINGS_FILE` | `mvn -s "$MAVEN_SETTINGS_FILE"` |
| `netrc: true` | a `machine` entry appended to `~/.netrc` | `pip`, `pip-compile`, `twine`, `curl --netrc`, `git` |

Both are additive, so the CodeArtifact and proxy actions can each contribute their entries in
the same job, in either order. Nothing needs to be passed to the consuming tool for netrc
beyond `curl`'s `--netrc`; the rest read `~/.netrc` on their own. When writing a `pip.conf`,
emit the index URL only and leave the credential in netrc — see
[CI credential patterns](https://github.com/StackVista/stackstate-mission-control/blob/main/wiki/concepts/ci-credentials.md).
