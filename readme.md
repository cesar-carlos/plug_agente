# plug_agente

Agente Windows com Socket.IO + ODBC para monitoramento e execução de consultas SQL.

[Documentação completa](docs/readme.md) | [Instalação](docs/install/readme.md)

## License

The project source code is licensed under the [MIT License](LICENSE).
Third-party components retain their respective licenses. Bundled Montserrat
fonts use the [SIL Open Font License](assets/fonts/montserrat/OFL.txt) and come
from the Google Fonts repository at commit
`8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5`.

## Code signing policy

Releases support an Ed25519 signed feed and manifest without a commercial
Authenticode certificate (`signing_provider=manifest`). Windows executables in
this mode have no verified Authenticode publisher. PFX and SignPath remain
optional signing providers. The SignPath Foundation application was declined on
2026-10-06 because the project did not yet meet its public visibility criteria.

The repository maintainer is [cesar-carlos](https://github.com/cesar-carlos).
Private signing keys stay in release secrets; clients receive public keys only.
Automatic application through the Windows service remains disabled pending
completion and validation of the transition, maintenance and recovery contract.
See [installer status](installer/readme.md) and the
[implementation plan](docs/implemente/plano_auto_update_evolution.md).

## Privacy policy

This notice describes the current source code. The operator configures the
hub, database connections and scheduled actions, and is responsible for the
data processed through them.

| Connection | Purpose and information involved |
| --- | --- |
| Configured hub (HTTP and Socket.IO) | Authentication, agent registration/profile, SQL requests and results, action results and operational diagnostics. Update diagnostics include the agent ID, versions, timestamps, signature status and error messages. |
| Configured ODBC database | Queries and their results, using the configured database credentials. The database may be local or on another host. |
| Configured SMTP server and recipients | Messages and any attachments selected by an email action. |
| GitHub Pages and release download hosts | Update checks and downloads. The default feed is `https://cesar-carlos.github.io/plug_agente/appcast.xml`; download destinations come from the feed. |
| [OpenCNPJ](https://opencnpj.org) | A company lookup sends the entered CNPJ to `api.opencnpj.org`. |
| [ViaCEP](https://viacep.com.br) | An address lookup sends the entered postal code to `viacep.com.br`. |
| Montserrat fonts | Font files are bundled with the application under the SIL Open Font License; displaying the interface does not request fonts from Google. |

Network services receive connection metadata, including the source IP address.
Their own policies apply; see [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).
The operator should also review the terms of the configured hub, database,
SMTP provider and lookup services before sending data.

Configuration, history and logs are stored locally; credentials and tokens use
the platform's secure storage. Local logs and exported diagnostics may contain
operational information and must be reviewed before sharing. Uninstalling the
application must not be treated as a guarantee that stored data, backups or
information already sent to other systems have been erased.

The installer displays this privacy notice before installation.
Questions about data held by a configured service
should be directed to its operator. General software issues can be reported in
the [repository](https://github.com/cesar-carlos/plug_agente/issues); do not post
credentials, private logs or customer data there.
