# container-images

Stock images for container virtual machines that behave like a small VM:
the official Debian, Ubuntu, Alpine, Rocky Linux and AlmaLinux images with
their own init system (systemd, or OpenRC on Alpine) and OpenSSH, ready to
run under the init of
[kernel-linux](https://github.com/gigahost-apps/kernel-linux) (interface
version 3, `init_system`). They are published on GHCR as
`ghcr.io/gigahost-apps/<distribution>:<version>`.

## Licence

The images contain the distributions' own software under its own licences.
Everything else in this repository is licensed under either of

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT license ([LICENSE-MIT](LICENSE-MIT))

at your option.
