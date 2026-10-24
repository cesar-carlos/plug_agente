# Windows installation and releases

## Current status

Production installer/appcast publication is blocked by the
[persona-v2 release manifest](../../contracts/persona-v2-release.json).
Windows automatic application is also disabled pending the
[updater acceptance plan](../implemente/plano_auto_update_evolution.md).
The procedures below do not override either gate.

## Guides

| Task | Document |
| --- | --- |
| Check Windows compatibility, prerequisites and startup behavior | [Requirements](requirements.md) |
| Install, uninstall and verify the application | [Installation guide](installation_guide.md) |
| Prepare versions, signing, builds and release publication | [Release guide](release_guide.md) |
| Configure feeds and diagnose the updater | [Auto-update guide](auto_update_setup.md) |
| Inspect local installer build details and optional SignPath setup | [Installer directory](../../installer/readme.md) |
| Review update threats and accepted limitations | [Threat model](../security/auto_update_threat_model.md) |

For a client installation, read requirements before following the installation
guide. [PlugPortMon](../../install_monitor.bat) is optional and should be installed
only when required.

For release preparation, follow the release guide and its gates before invoking
publication workflows. Build or dry-run evidence alone does not authorize release.
Expected installer output: `installer/dist/PlugAgente-Setup-{version}.exe`.
