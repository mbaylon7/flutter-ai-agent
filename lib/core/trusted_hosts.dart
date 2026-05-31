/// Hosts whose TLS certificate the app accepts even when it does not chain to a
/// trusted root authority.
///
/// This is **not** hardcoded to any single agent. Self-hosted agent gateways
/// (the app is agent-agnostic — you pair any agent by URL + port + token in
/// onboarding or Settings) commonly run a self-signed certificate. When the
/// user explicitly pairs with a host, the connect flow registers that host here
/// so its cert is accepted; switching to a different agent simply pairs a new
/// host, which registers itself the same way.
///
/// A host with a normal, CA-signed certificate never reaches this allow-list at
/// all — the platform validates it before `badCertificateCallback` ever fires.
/// So this only relaxes validation for the exact host the user chose to trust.
class TrustedHosts {
  TrustedHosts._();

  static final Set<String> _hosts = <String>{};

  /// Trust [host] (e.g. the host parsed from a paired `wsUrl`). No-op for empty.
  static void allow(String host) {
    if (host.isNotEmpty) _hosts.add(host);
  }

  /// Whether [host] has been registered by the connect flow.
  static bool isAllowed(String host) => _hosts.contains(host);
}
