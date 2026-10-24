/// Opaque official index identity supplied by the server's address lookup.
/// It is neither a provider place ID nor proof of vehicle/road access.
class OfficialAddressIdentity {
  const OfficialAddressIdentity({
    required this.id,
    required this.indexRevision,
    required this.source,
    required this.sourceVersion,
  });

  final String id, indexRevision, source, sourceVersion;

  static OfficialAddressIdentity? fromJson(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) throw const FormatException('official_address_invalid');
    String read(String key) {
      final value = raw[key];
      if (value is! String || value.trim().isEmpty) {
        throw const FormatException('official_address_invalid');
      }
      return value;
    }

    return OfficialAddressIdentity(
      id: read('id'),
      indexRevision: read('index_revision'),
      source: read('source'),
      sourceVersion: read('source_version'),
    );
  }

  Map<String, String> toJson() {
    final fields = {
      'id': id,
      'index_revision': indexRevision,
      'source': source,
      'source_version': sourceVersion,
    };
    if (fields.values.any((value) => value.trim().isEmpty)) {
      throw const FormatException('official_address_invalid');
    }
    return Map.unmodifiable(fields);
  }
}
