#!/usr/bin/env bash
#
# Contribute <server> entries to a shared Maven settings.xml.
#
# sbt and Coursier read a directory of credentials files, but Maven takes a single -s file,
# so each calling action drops a fragment in $RUNNER_TEMP/maven-settings.d and the whole
# file is reassembled from every fragment present. That lets the CodeArtifact and proxy
# actions each add their own servers in the same job, in either order.
#
# Usage: write-maven-settings.sh <credentials-file> <server-id>...
#
# Every <server-id> gets the credentials from <credentials-file>. Ids reach the filesystem
# as fragment names, so callers must pass validated or constant values, never raw input.

set -euo pipefail

credentials_file="$1"
shift

if [[ ! -f "${credentials_file}" ]]; then
  echo "::error::no credentials file at ${credentials_file}" >&2
  exit 1
fi

settings_dir="${RUNNER_TEMP}/maven-settings.d"
settings_file="${RUNNER_TEMP}/maven-settings.xml"
mkdir -p "${settings_dir}"
chmod 700 "${settings_dir}"

# A token containing & or < would otherwise produce a settings.xml Maven cannot parse,
# which surfaces as a resolution failure rather than a syntax error.
xml_escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"
}

user="$(sed -n 's/^user=//p' "${credentials_file}" | xml_escape)"
password="$(sed -n 's/^password=//p' "${credentials_file}" | xml_escape)"

if [[ -z "${user}" || -z "${password}" ]]; then
  echo "::error::${credentials_file} carries no user/password line" >&2
  exit 1
fi

# The runner masks the raw token; the escaped form is a different string and needs its own mask.
echo "::add-mask::${password}"

for server_id in "$@"; do
  fragment="${settings_dir}/${server_id}.xml"
  install -m 600 /dev/null "${fragment}"
  printf '    <server>\n      <id>%s</id>\n      <username>%s</username>\n      <password>%s</password>\n    </server>\n' \
    "${server_id}" "${user}" "${password}" > "${fragment}"
done

install -m 600 /dev/null "${settings_file}"
{
  printf '<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">\n  <servers>\n'
  cat "${settings_dir}"/*.xml
  printf '  </servers>\n</settings>\n'
} > "${settings_file}"

echo "MAVEN_SETTINGS_FILE=${settings_file}" >> "${GITHUB_ENV}"
