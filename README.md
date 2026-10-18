# container-images

Stock images for container virtual machines that behave like a small VM:
the official Debian, Ubuntu, Alpine, Rocky Linux and AlmaLinux images with
their own init system (systemd, or OpenRC on Alpine) and OpenSSH, ready to
run under the init of
[kernel-linux](https://github.com/gigahost-apps/kernel-linux) (interface
version 3, `init_system`). They are published on GHCR as
`ghcr.io/gigahost-apps/<name>:<version>`.

## The images

| Image | Name and tag | Init | Stop signal |
|---|---|---|---|
| Debian 13 (trixie) | `debian:13` | systemd | 37 (`SIGRTMIN+3`) |
| Debian 12 (bookworm) | `debian:12` | systemd | 37 (`SIGRTMIN+3`) |
| Ubuntu 26.04 LTS | `ubuntu:26.04` | systemd | 37 (`SIGRTMIN+3`) |
| Ubuntu 24.04 LTS | `ubuntu:24.04` | systemd | 37 (`SIGRTMIN+3`) |
| Ubuntu 22.04 LTS | `ubuntu:22.04` | systemd | 37 (`SIGRTMIN+3`) |
| Alpine Linux 3.24 | `alpine:3.24` | busybox init running OpenRC | 12 (`SIGUSR2`) |
| Rocky Linux 10 | `rockylinux:10` | systemd | 37 (`SIGRTMIN+3`) |
| Rocky Linux 9 | `rockylinux:9` | systemd | 37 (`SIGRTMIN+3`) |
| AlmaLinux 10 | `almalinux:10` | systemd | 37 (`SIGRTMIN+3`) |
| AlmaLinux 9 | `almalinux:9` | systemd | 37 (`SIGRTMIN+3`) |

[`images.toml`](images.toml) lists them with their bases, the official
images on Docker Hub, pinned by digest. Each image's command is
`/sbin/init`, run as the container's init system; its `STOPSIGNAL` is the
signal on which that init shuts down cleanly (the kernel delivers no other
to it). Labels: `org.opencontainers.image.source`, `.title`, `.version`,
`.revision`, `cloud.gigahost.init-system` (`systemd` or `openrc`) and
`cloud.gigahost.ssh-user` (`root`).

What each image holds: the init system (with D-Bus on systemd), the
OpenSSH server, `iproute2`, `ping`, CA certificates, `curl`, `less`, a
small `vi`, `procps`, `sudo`, cron and the time zone data, and the
distribution's package manager set up for its usual mirrors. There is no
kernel, boot loader, firmware, NetworkManager or cloud-init: the
platform's init configures `eth0`, the host name, `/etc/hosts` and
`/etc/resolv.conf` before the image's init starts, and nothing in the
image changes them. For a container machine the systemd images mask the
gettys (the console is the machine's log), `systemd-networkd`,
`systemd-resolved`, `systemd-timesyncd` (the guest clock is the host's
`kvm-clock`), `systemd-firstboot`, udev (`/sys` is read-only),
`systemd-remount-fs` and `networking.service`
([`common/masked-units`](common/masked-units)); Alpine runs no getty and
no `networking` service.

SSH: root logs in with the keys the platform writes to
`/root/.ssh/authorized_keys`, never with a password
(`PermitRootLogin prohibit-password`, `PasswordAuthentication no`,
`KbdInteractiveAuthentication no`). sshd starts at boot.

Per instance: an image holds no SSH host keys and an empty
`/etc/machine-id`. Each instance makes its own host keys at its first
boot, before sshd starts (`gigahost-ssh-host-keys.service` on Debian and
Ubuntu, `sshd-keygen@.service` on Rocky and Alma, sshd's OpenRC service on
Alpine), and systemd makes its machine ID; both are kept on the instance's
disk from then on.

## Building and testing

```sh
scripts/build.sh [NAME[:VERSION]...]       # podman; tags localhost/gigahost-images/<name>:<version>
tests/structure.sh [NAME[:VERSION]...]     # checks the built images without booting them
tests/boot.sh --kernel DIR [NAME[:VERSION]...]
```

A bare name selects every version of it; no name selects every image.

`tests/structure.sh` checks that an image holds no host key, machine ID,
random seed or password hash, that the SSH policy is in force
(`sshd -T`, after `ssh-keygen -A` in a throwaway container), the masked
units, the services enabled at boot, the init at `/sbin/init`, the
packages above and the image's labels, command and stop signal.

`tests/boot.sh` boots each image as a container machine under QEMU with
KVM, with a kernel-linux release's `bzImage` and `initramfs.cpio.zst` in
`DIR` (kernel-linux's `scripts/build.sh` makes them). The root disk is the
image's files on ext4 (`mkfs.ext4 -d`; the init's unpack mode, which the
platform uses, is kernel-linux's to test). Each image boots three
instances: two from fresh disks at 256 MiB of memory, then the first again
at 512 MiB. Each must reach `running` with no failed unit (OpenRC: every
service of its runlevels started), accept a throwaway key for root over
SSH, run cron and `crontab`, keep the platform's address, route and name
server, and end with a `poweroff` report when powered off from inside; the
two instances must have different host keys and machine IDs, and the
first must keep its own across its two boots. The last boot also reaches
the package mirrors (`apt-get update`, `dnf makecache`, `apk update`): dnf
on EL 9 needs more than 256 MiB without swap. It reports each image's boot
time to `running`, `MemAvailable` at 256 MiB and its gzip-compressed size.
It needs podman, `qemu-system-x86_64`, `/dev/kvm`, `mkfs.ext4`, `ssh` and
network access.

## Publishing

[CI](.github/workflows/ci.yml) builds every image and runs
`tests/structure.sh` on pull requests and pushes. On pushes to `main` it
then pushes the tested images to `ghcr.io/gigahost-apps/<name>:<version>`
and `:<version>-<YYYYMMDD>`, and writes `images.json` (each image's name,
version, display name, reference by the digest pushed, init, stop signal
and SSH user) as a workflow artifact and as the asset of a release
`images-<YYYYMMDD>-<n>`. The boot test does not run in CI: it needs KVM
and a kernel-linux build.

A weekly [workflow](.github/workflows/update-bases.yml) runs
`scripts/update-bases.sh`, which moves each base to the digest its tag
names now (and Alpine to its current release), and opens a pull request
when one moved.

For the maintainer:

- A package GHCR creates on a workflow's first push may start private.
  Set each package (`debian`, `ubuntu`, `alpine`, `rockylinux`,
  `almalinux`) public once, in its package settings; the images are meant
  to be pulled without credentials.
- The weekly workflow needs "Allow GitHub Actions to create and approve
  pull requests" in the repository's Actions settings. A pull request it
  opens does not start CI by itself (GitHub runs no workflow for the
  workflow token's events): close and reopen it, or push to its branch,
  to run the checks.

## Licence

The images contain the distributions' own software under its own licences.
Everything else in this repository is licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT license ([LICENSE-MIT](LICENSE-MIT))

at your option.
