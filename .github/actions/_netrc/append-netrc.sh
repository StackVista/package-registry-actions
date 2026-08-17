#!/usr/bin/env bash
#
# Append a credentials file's host/user/password to ~/.netrc, for pip, twine, curl --netrc
# and every other netrc-aware client.
#
# Usage: append-netrc.sh <credentials-file>
#
# Appending rather than rewriting lets the CodeArtifact and proxy actions each add their own
# machine entry in the same job, in either order.

set -euo pipefail

credentials_file="$1"

if [[ ! -f "${credentials_file}" ]]; then
  echo "::error::no credentials file at ${credentials_file}" >&2
  exit 1
fi

host="$(sed -n 's/^host=//p' "${credentials_file}")"
user="$(sed -n 's/^user=//p' "${credentials_file}")"
password="$(sed -n 's/^password=//p' "${credentials_file}")"

if [[ -z "${host}" || -z "${user}" || -z "${password}" ]]; then
  echo "::error::${credentials_file} carries no host/user/password line" >&2
  exit 1
fi

# netrc tokens are whitespace-delimited and curl supports no quoting, so a password
# containing whitespace would silently authenticate as a truncated value.
if [[ "${password}" =~ [[:space:]] ]]; then
  echo "::error::password contains whitespace, which netrc cannot represent" >&2
  exit 1
fi

netrc_file="${HOME}/.netrc"
[[ -f "${netrc_file}" ]] || install -m 600 /dev/null "${netrc_file}"
chmod 600 "${netrc_file}"
printf 'machine %s\n  login %s\n  password %s\n' "${host}" "${user}" "${password}" \
  >> "${netrc_file}"
