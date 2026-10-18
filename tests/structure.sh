#!/bin/bash
# Checks built stock images without booting them: no host keys and no
# machine ID in them, the SSH policy, the masked units, the services
# enabled at boot, the init at the command's path, the image's config.
#
#   tests/structure.sh [NAME[:VERSION]...]   (every image without arguments)
#
# Each image is the one scripts/build.sh tagged
# (localhost/gigahost-images/<name>:<version>), or IMAGE=REF for a single
# NAME:VERSION.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scripts/lib.sh
. "${repo}/scripts/lib.sh"

selected=$(select_images "$@")
if [[ -n ${IMAGE:-} && $(wc -l <<< "${selected}") != 1 ]]; then
    echo "structure.sh: IMAGE names one image; select one NAME:VERSION" >&2
    exit 1
fi
masked_units=$(grep -v -E '^(#|$)' "${repo}/common/masked-units" | tr '\n' ' ')
failures=0

fail() {
    echo "  FAIL: $*"
    failures=$((failures + 1))
}

# The checks inside the image, as POSIX sh: one "FAIL ..." line each that
# fails. The arguments: the init system, then the units to see masked.
# shellcheck disable=SC2016 # expanded by the image's shell
inside='
set -u
init=$1
shift
fail() { echo "FAIL $*"; }
for key in /etc/ssh/ssh_host_*; do
    [ -e "${key}" ] && fail "host key ${key} in the image"
done
if [ "${init}" = systemd ]; then
    [ -f /etc/machine-id ] && [ ! -s /etc/machine-id ] || fail "/etc/machine-id is not an empty file"
else
    [ ! -s /etc/machine-id ] || fail "/etc/machine-id is not empty"
fi
if [ -e /var/lib/dbus/machine-id ] || [ -L /var/lib/dbus/machine-id ]; then
    fail "/var/lib/dbus/machine-id is in the image"
fi
# Nothing of one instance is shared by all: no random seed, no keys or
# password hashes.
for path in /var/lib/systemd/random-seed /var/lib/seedrng /var/lib/systemd/credential.secret /root/.ssh/*; do
    [ -e "${path}" ] && fail "${path} is in the image"
done
awk -F: '\''$2 ~ /^\$/ { print $1 }'\'' /etc/shadow | while read -r user; do
    fail "${user} has a password hash"
done
[ -x /sbin/init ] || fail "/sbin/init is not an executable"
for path in /boot/vmlinuz /usr/sbin/NetworkManager /usr/bin/cloud-init /etc/netplan /usr/sbin/chronyd /usr/sbin/dhclient; do
    [ -e "${path}" ] && fail "${path} is in the image"
done
for tool in ip ping curl less vi ps sudo crontab ssh-keygen; do
    command -v "${tool}" > /dev/null || fail "no ${tool}"
done
[ -f /etc/ssl/certs/ca-certificates.crt ] || [ -f /etc/pki/tls/certs/ca-bundle.crt ] || fail "no CA certificates"
[ -e /usr/share/zoneinfo/UTC ] || fail "no time zone data"
if [ "${init}" = systemd ]; then
    for unit in "$@"; do
        [ "$(readlink "/etc/systemd/system/${unit}")" = /dev/null ] || fail "${unit} is not masked"
    done
    if [ -e /etc/systemd/system/gigahost-ssh-host-keys.service ]; then
        enabled="gigahost-ssh-host-keys.service ssh.service cron.service"
    else
        enabled="sshd.service crond.service"
    fi
    for unit in ${enabled}; do
        [ "$(systemctl is-enabled "${unit}" 2> /dev/null)" = enabled ] || fail "${unit} is not enabled"
    done
    if systemctl cat ssh.socket > /dev/null 2>&1; then
        [ "$(systemctl is-enabled ssh.socket 2> /dev/null)" != enabled ] || fail "ssh.socket is enabled"
    fi
else
    grep -q -E "^(tty|ttyS|console)[0-9]*::respawn" /etc/inittab && fail "/etc/inittab starts a getty"
    for service in sshd crond; do
        [ -e "/etc/runlevels/default/${service}" ] || fail "${service} is not in the default runlevel"
    done
    for level in /etc/runlevels/*; do
        [ -e "${level}/networking" ] && fail "networking is in the runlevel ${level##*/}"
    done
    grep -q "^root:[!]" /etc/shadow && fail "root is locked, which refuses its keys"
fi
# sshd accepts its configuration once an instance has made its keys, and
# the policy is in force.
ssh-keygen -A > /dev/null
mkdir -p /run/sshd
sshd=$(command -v sshd || echo /usr/sbin/sshd)
"${sshd}" -t || fail "sshd -t refuses the configuration"
config=$("${sshd}" -T 2> /dev/null)
echo "${config}" | grep -q -x -E "permitrootlogin (prohibit-password|without-password)" || fail "root may log in with a password"
echo "${config}" | grep -q -x "passwordauthentication no" || fail "password authentication is on"
echo "${config}" | grep -q -x "kbdinteractiveauthentication no" || fail "keyboard-interactive authentication is on"
true
'

while IFS=$'\t' read -r -u 3 name version _family init stop_signal _base display_name; do
    image=${IMAGE:-$(image_tag "${name}" "${version}")}
    before=${failures}
    echo "structure.sh: ${image} (${display_name})"
    if ! config=$(podman image inspect --format json "${image}" 2> /dev/null); then
        fail "${image} is not built (scripts/build.sh ${name}:${version})"
        continue
    fi
    problems=$(python3 - "${version}" "${display_name}" "${init}" "${stop_signal}" 3<<< "${config}" << 'PYTHON'
import json, os, signal, sys
version, title, init, stop = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
image = json.load(os.fdopen(3))[0]
config = image.get("Config") or {}
labels = config.get("Labels") or {}
want = {
    "org.opencontainers.image.source": "https://github.com/gigahost-apps/container-images",
    "org.opencontainers.image.title": title,
    "org.opencontainers.image.version": version,
    "cloud.gigahost.init-system": init,
    "cloud.gigahost.ssh-user": "root",
}
for key, value in want.items():
    if labels.get(key) != value:
        print(f"label {key} is {labels.get(key)!r}, not {value!r}")
if config.get("Cmd") != ["/sbin/init"] or config.get("Entrypoint"):
    print(f"the command is {config.get('Entrypoint')} {config.get('Cmd')}, not /sbin/init alone")
names = {"SIGRTMIN+3": signal.SIGRTMIN + 3, "SIGUSR2": signal.SIGUSR2}
got = config.get("StopSignal", "")
if names.get(got, -1) != stop:
    print(f"the stop signal is {got!r}, not signal {stop}")
for key in ("Volumes", "ExposedPorts"):
    if config.get(key):
        print(f"the image declares {key}: {sorted(config[key])}")
if image.get("Architecture") != "amd64" or image.get("Os") != "linux":
    print(f"the image is for {image.get('Os')}/{image.get('Architecture')}")
PYTHON
    )
    while IFS= read -r problem; do
        [[ -n ${problem} ]] && fail "${problem}"
    done <<< "${problems}"
    # shellcheck disable=SC2086 # one unit a word
    inside_out=$(podman run --rm --network none --entrypoint /bin/sh "${image}" -c "${inside}" sh "${init}" ${masked_units} 2>&1) \
        || fail "the checks inside the image did not run: ${inside_out}"
    while IFS= read -r line; do
        case ${line} in
            FAIL\ *) fail "${line#FAIL }" ;;
        esac
    done <<< "${inside_out}"
    [[ ${failures} == "${before}" ]] && echo "  ok"
done 3<<< "${selected}"

if [[ ${failures} != 0 ]]; then
    echo "structure.sh: ${failures} check(s) failed"
    exit 1
fi
echo "structure.sh: all checks passed"
