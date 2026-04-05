# Contributing to firecracker-farm

Contributions are welcome and appreciated. To keep things organized and
maintainable, please follow these guidelines.

## How to contribute

1. **Fork this repository** on GitHub.
2. **Create a feature branch** in your fork (`git checkout -b my-feature`).
3. **Make your changes**, keeping commits focused and well-described.
4. **Run the tests** before submitting (`for t in tests/*.sh; do bash "$t" || exit 1; done`).
5. **Open a pull request** against `linuxdevel/firecracker-farm:main`.

All contributions should come through GitHub pull requests. This ensures
changes are reviewed, tested, and tracked properly.

## Guidelines

- Keep changes minimal and focused on a single concern per PR.
- Follow the existing code style (shell, 2-space indent, `set -euo pipefail`).
- Add or update tests for any new functionality.
- Do not introduce destructive operations (VM deletion, bridge teardown, etc.)
  without explicit discussion in an issue first.
- Do not commit secrets, credentials, or host-specific configuration.

## Reporting issues

Open an issue on the [GitHub issue tracker](https://github.com/linuxdevel/firecracker-farm/issues).
Include your Proxmox version, kernel version, and relevant log output.

## License

By submitting a pull request, you agree that your contribution is licensed
under the [Apache License 2.0](LICENSE), the same license as this project.
