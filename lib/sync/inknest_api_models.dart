class InkNestCloudUser {
  const InkNestCloudUser({
    required this.id,
    required this.email,
    required this.createdAt,
    this.privacyPolicyVersion,
    this.termsVersion,
    this.agreementsAcceptedAt,
  });

  final String id;
  final String email;
  final DateTime createdAt;
  final String? privacyPolicyVersion;
  final String? termsVersion;
  final DateTime? agreementsAcceptedAt;

  factory InkNestCloudUser.fromJson(Map<String, Object?> json) {
    return InkNestCloudUser(
      id: _requiredString(json, 'id'),
      email: _requiredString(json, 'email'),
      createdAt: _requiredDateTime(json, 'createdAt'),
      privacyPolicyVersion: json['privacyPolicyVersion'] as String?,
      termsVersion: json['termsVersion'] as String?,
      agreementsAcceptedAt: _optionalDateTime(json, 'agreementsAcceptedAt'),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'privacyPolicyVersion': privacyPolicyVersion,
    'termsVersion': termsVersion,
    'agreementsAcceptedAt': agreementsAcceptedAt?.toUtc().toIso8601String(),
  };

  InkNestCloudUser copyWith({
    String? privacyPolicyVersion,
    String? termsVersion,
    DateTime? agreementsAcceptedAt,
  }) => InkNestCloudUser(
    id: id,
    email: email,
    createdAt: createdAt,
    privacyPolicyVersion: privacyPolicyVersion ?? this.privacyPolicyVersion,
    termsVersion: termsVersion ?? this.termsVersion,
    agreementsAcceptedAt: agreementsAcceptedAt ?? this.agreementsAcceptedAt,
  );
}

class InkNestCloudDevice {
  const InkNestCloudDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.createdAt,
    required this.lastSeenAt,
    required this.current,
    this.revokedAt,
  });

  final String id;
  final String name;
  final String platform;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final DateTime? revokedAt;
  final bool current;

  factory InkNestCloudDevice.fromJson(Map<String, Object?> json) {
    final current = json['current'];
    if (current is! bool) {
      throw const FormatException('device.current must be a boolean.');
    }
    return InkNestCloudDevice(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      platform: _requiredString(json, 'platform'),
      createdAt: _requiredDateTime(json, 'createdAt'),
      lastSeenAt: _requiredDateTime(json, 'lastSeenAt'),
      revokedAt: _optionalDateTime(json, 'revokedAt'),
      current: current,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'platform': platform,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'lastSeenAt': lastSeenAt.toUtc().toIso8601String(),
    'revokedAt': revokedAt?.toUtc().toIso8601String(),
    'current': current,
  };
}

class InkNestAuthSession {
  const InkNestAuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
    required this.user,
    required this.device,
  });

  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;
  final InkNestCloudUser user;
  final InkNestCloudDevice device;

  InkNestAuthSession copyWith({InkNestCloudUser? user}) => InkNestAuthSession(
    accessToken: accessToken,
    refreshToken: refreshToken,
    tokenType: tokenType,
    expiresIn: expiresIn,
    user: user ?? this.user,
    device: device,
  );

  factory InkNestAuthSession.fromJson(Map<String, Object?> json) {
    final expiresIn = json['expiresIn'];
    if (expiresIn is! int || expiresIn <= 0) {
      throw const FormatException('expiresIn must be a positive integer.');
    }
    final tokenType = _requiredString(json, 'tokenType');
    if (tokenType != 'bearer') {
      throw FormatException('Unsupported tokenType: $tokenType');
    }
    return InkNestAuthSession(
      accessToken: _requiredString(json, 'accessToken'),
      refreshToken: _requiredString(json, 'refreshToken'),
      tokenType: tokenType,
      expiresIn: expiresIn,
      user: InkNestCloudUser.fromJson(_requiredObject(json, 'user')),
      device: InkNestCloudDevice.fromJson(_requiredObject(json, 'device')),
    );
  }

  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'tokenType': tokenType,
    'expiresIn': expiresIn,
    'user': user.toJson(),
    'device': device.toJson(),
  };
}

class InkNestApiError {
  const InkNestApiError({
    required this.code,
    required this.message,
    required this.details,
  });

  final String code;
  final String message;
  final Map<String, Object?> details;

  factory InkNestApiError.fromJson(Map<String, Object?> json) {
    final rawDetails = json['details'];
    return InkNestApiError(
      code: _requiredString(json, 'code'),
      message: _requiredString(json, 'message'),
      details: rawDetails == null
          ? const {}
          : Map.unmodifiable(_asObject(rawDetails, 'error.details')),
    );
  }
}

String _requiredString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String || value.isEmpty || value.trim() != value) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value;
}

int requiredNonNegativeInt(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! int || value < 0) {
    throw FormatException('$field must be a non-negative integer.');
  }
  return value;
}

double requiredPositiveDouble(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! num || !value.isFinite || value <= 0) {
    throw FormatException('$field must be a positive finite number.');
  }
  return value.toDouble();
}

DateTime _requiredDateTime(Map<String, Object?> json, String field) {
  final value = _requiredString(json, field);
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$field must be an ISO-8601 timestamp.');
  }
  return parsed;
}

DateTime? _optionalDateTime(Map<String, Object?> json, String field) {
  return json[field] == null ? null : _requiredDateTime(json, field);
}

Map<String, Object?> _requiredObject(Map<String, Object?> json, String field) {
  return _asObject(json[field], field);
}

Map<String, Object?> _asObject(Object? value, String field) {
  if (value is! Map<Object?, Object?> ||
      value.keys.any((key) => key is! String)) {
    throw FormatException('$field must be a JSON object.');
  }
  return value.cast<String, Object?>();
}

Map<String, Object?> copyJsonObject(Object? value, String field) {
  Object? copy(Object? input) {
    return switch (input) {
      null || bool() || String() || num() => input,
      List<Object?>() => input.map(copy).toList(growable: false),
      Map<Object?, Object?>() => {
        for (final entry in input.entries)
          if (entry.key is String) entry.key as String: copy(entry.value),
      },
      _ => throw FormatException('$field contains a non-JSON value.'),
    };
  }

  final object = _asObject(value, field);
  if (object.keys.length != (value as Map<Object?, Object?>).keys.length) {
    throw FormatException('$field contains a non-string key.');
  }
  return Map.unmodifiable(copy(object)! as Map<String, Object?>);
}

List<Map<String, Object?>> requiredObjectList(
  Map<String, Object?> json,
  String field,
) {
  final value = json[field];
  if (value is! List<Object?>) {
    throw FormatException('$field must be a list.');
  }
  return [
    for (var index = 0; index < value.length; index++)
      _asObject(value[index], '$field[$index]'),
  ];
}

List<String> requiredUniqueStringList(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! List<Object?> || value.any((item) => item is! String)) {
    throw FormatException('$field must be a list of strings.');
  }
  final values = value.cast<String>();
  if (values.any((item) => item.isEmpty || item.trim() != item) ||
      values.toSet().length != values.length) {
    throw FormatException('$field must contain unique, non-empty IDs.');
  }
  return List.unmodifiable(values);
}

String requiredSha256(Map<String, Object?> json, String field) {
  final value = _requiredString(json, field);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('$field must be a lowercase SHA-256 value.');
  }
  return value;
}

bool sameStringSet(Iterable<String> left, Iterable<String> right) {
  final leftSet = left.toSet();
  final rightSet = right.toSet();
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}

void validateUniqueResourceIds(Iterable<String> ids, String field) {
  final values = ids.toList();
  if (values.any((id) => id.isEmpty || id.trim() != id) ||
      values.toSet().length != values.length) {
    throw FormatException('$field contains duplicate or empty IDs.');
  }
}

DateTime requiredDateTime(Map<String, Object?> json, String field) =>
    _requiredDateTime(json, field);

String requiredString(Map<String, Object?> json, String field) =>
    _requiredString(json, field);
