/// PATIENT APP: Medplum Patient DTO
///
/// Data Transfer Object for FHIR Patient resource from Medplum.
/// Endpoint: GET /medplum/Patient/{id}

class MedplumPatientDTO {
  const MedplumPatientDTO({
    required this.id,
    this.resourceType = 'Patient',
    this.identifier,
    this.active,
    this.name,
    this.telecom,
    this.gender,
    this.birthDate,
    this.address,
    this.photo,
  });

  /// FHIR Resource ID
  final String id;

  /// FHIR Resource Type (always "Patient")
  final String resourceType;

  /// Patient identifiers (MRN, SSN, etc.)
  final List<FhirIdentifier>? identifier;

  /// Whether patient record is active
  final bool? active;

  /// Patient names (can have multiple)
  final List<FhirHumanName>? name;

  /// Contact points (phone, email)
  final List<FhirContactPoint>? telecom;

  /// Patient gender (male, female, other, unknown)
  final String? gender;

  /// Date of birth (YYYY-MM-DD format)
  final String? birthDate;

  /// Patient addresses
  final List<FhirAddress>? address;

  /// Patient photos
  final List<FhirAttachment>? photo;

  /// Get primary/official name
  String get fullName {
    if (name == null || name!.isEmpty) return 'Unknown Patient';
    final officialName = name!.firstWhere(
      (n) => n.use == 'official',
      orElse: () => name!.first,
    );
    return officialName.fullName;
  }

  /// Get first name
  String? get firstName {
    if (name == null || name!.isEmpty) return null;
    final n = name!.first;
    return n.given?.isNotEmpty == true ? n.given!.first : null;
  }

  /// Get last name
  String? get lastName {
    if (name == null || name!.isEmpty) return null;
    return name!.first.family;
  }

  /// Get primary email
  String? get email {
    return telecom?.firstWhere(
      (t) => t.system == 'email',
      orElse: () => FhirContactPoint(),
    ).value;
  }

  /// Get primary phone
  String? get phone {
    return telecom?.firstWhere(
      (t) => t.system == 'phone',
      orElse: () => FhirContactPoint(),
    ).value;
  }

  /// Get photo URL
  String? get photoUrl {
    if (photo == null || photo!.isEmpty) return null;
    return photo!.first.url;
  }

  /// Get parsed birth date
  DateTime? get birthDateTime {
    if (birthDate == null) return null;
    return DateTime.tryParse(birthDate!);
  }

  /// Parse from JSON response
  /// TODO: Verify field names with actual API response
  factory MedplumPatientDTO.fromJson(Map<String, dynamic> json) {
    return MedplumPatientDTO(
      id: json['id']?.toString() ?? '',
      resourceType: json['resourceType'] as String? ?? 'Patient',
      identifier: (json['identifier'] as List?)
          ?.map((e) => FhirIdentifier.fromJson(e as Map<String, dynamic>))
          .toList(),
      active: json['active'] as bool?,
      name: (json['name'] as List?)
          ?.map((e) => FhirHumanName.fromJson(e as Map<String, dynamic>))
          .toList(),
      telecom: (json['telecom'] as List?)
          ?.map((e) => FhirContactPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      gender: json['gender'] as String?,
      birthDate: json['birthDate'] as String?,
      address: (json['address'] as List?)
          ?.map((e) => FhirAddress.fromJson(e as Map<String, dynamic>))
          .toList(),
      photo: (json['photo'] as List?)
          ?.map((e) => FhirAttachment.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'resourceType': resourceType,
        if (identifier != null)
          'identifier': identifier!.map((e) => e.toJson()).toList(),
        if (active != null) 'active': active,
        if (name != null) 'name': name!.map((e) => e.toJson()).toList(),
        if (telecom != null)
          'telecom': telecom!.map((e) => e.toJson()).toList(),
        if (gender != null) 'gender': gender,
        if (birthDate != null) 'birthDate': birthDate,
        if (address != null)
          'address': address!.map((e) => e.toJson()).toList(),
        if (photo != null) 'photo': photo!.map((e) => e.toJson()).toList(),
      };
}

/// FHIR HumanName datatype
class FhirHumanName {
  const FhirHumanName({
    this.use,
    this.text,
    this.family,
    this.given,
    this.prefix,
    this.suffix,
  });

  final String? use;
  final String? text;
  final String? family;
  final List<String>? given;
  final List<String>? prefix;
  final List<String>? suffix;

  String get fullName {
    if (text != null && text!.isNotEmpty) return text!;
    final parts = <String>[];
    if (prefix != null) parts.addAll(prefix!);
    if (given != null) parts.addAll(given!);
    if (family != null) parts.add(family!);
    if (suffix != null) parts.addAll(suffix!);
    return parts.join(' ');
  }

  factory FhirHumanName.fromJson(Map<String, dynamic> json) => FhirHumanName(
        use: json['use'] as String?,
        text: json['text'] as String?,
        family: json['family'] as String?,
        given: (json['given'] as List?)?.cast<String>(),
        prefix: (json['prefix'] as List?)?.cast<String>(),
        suffix: (json['suffix'] as List?)?.cast<String>(),
      );

  Map<String, dynamic> toJson() => {
        if (use != null) 'use': use,
        if (text != null) 'text': text,
        if (family != null) 'family': family,
        if (given != null) 'given': given,
        if (prefix != null) 'prefix': prefix,
        if (suffix != null) 'suffix': suffix,
      };
}

/// FHIR ContactPoint datatype
class FhirContactPoint {
  const FhirContactPoint({
    this.system,
    this.value,
    this.use,
    this.rank,
  });

  final String? system; // phone, fax, email, pager, url, sms, other
  final String? value;
  final String? use; // home, work, temp, old, mobile
  final int? rank;

  factory FhirContactPoint.fromJson(Map<String, dynamic> json) =>
      FhirContactPoint(
        system: json['system'] as String?,
        value: json['value'] as String?,
        use: json['use'] as String?,
        rank: json['rank'] as int?,
      );

  Map<String, dynamic> toJson() => {
        if (system != null) 'system': system,
        if (value != null) 'value': value,
        if (use != null) 'use': use,
        if (rank != null) 'rank': rank,
      };
}

/// FHIR Identifier datatype
class FhirIdentifier {
  const FhirIdentifier({
    this.use,
    this.type,
    this.system,
    this.value,
  });

  final String? use;
  final Map<String, dynamic>? type;
  final String? system;
  final String? value;

  factory FhirIdentifier.fromJson(Map<String, dynamic> json) => FhirIdentifier(
        use: json['use'] as String?,
        type: json['type'] as Map<String, dynamic>?,
        system: json['system'] as String?,
        value: json['value'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (use != null) 'use': use,
        if (type != null) 'type': type,
        if (system != null) 'system': system,
        if (value != null) 'value': value,
      };
}

/// FHIR Address datatype
class FhirAddress {
  const FhirAddress({
    this.use,
    this.type,
    this.text,
    this.line,
    this.city,
    this.district,
    this.state,
    this.postalCode,
    this.country,
  });

  final String? use;
  final String? type;
  final String? text;
  final List<String>? line;
  final String? city;
  final String? district;
  final String? state;
  final String? postalCode;
  final String? country;

  String get fullAddress {
    if (text != null && text!.isNotEmpty) return text!;
    final parts = <String>[];
    if (line != null) parts.addAll(line!);
    if (city != null) parts.add(city!);
    if (state != null) parts.add(state!);
    if (postalCode != null) parts.add(postalCode!);
    if (country != null) parts.add(country!);
    return parts.join(', ');
  }

  factory FhirAddress.fromJson(Map<String, dynamic> json) => FhirAddress(
        use: json['use'] as String?,
        type: json['type'] as String?,
        text: json['text'] as String?,
        line: (json['line'] as List?)?.cast<String>(),
        city: json['city'] as String?,
        district: json['district'] as String?,
        state: json['state'] as String?,
        postalCode: json['postalCode'] as String?,
        country: json['country'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (use != null) 'use': use,
        if (type != null) 'type': type,
        if (text != null) 'text': text,
        if (line != null) 'line': line,
        if (city != null) 'city': city,
        if (district != null) 'district': district,
        if (state != null) 'state': state,
        if (postalCode != null) 'postalCode': postalCode,
        if (country != null) 'country': country,
      };
}

/// FHIR Attachment datatype
class FhirAttachment {
  const FhirAttachment({
    this.contentType,
    this.url,
    this.data,
    this.title,
  });

  final String? contentType;
  final String? url;
  final String? data; // base64 encoded
  final String? title;

  factory FhirAttachment.fromJson(Map<String, dynamic> json) => FhirAttachment(
        contentType: json['contentType'] as String?,
        url: json['url'] as String?,
        data: json['data'] as String?,
        title: json['title'] as String?,
      );

  Map<String, dynamic> toJson() => {
        if (contentType != null) 'contentType': contentType,
        if (url != null) 'url': url,
        if (data != null) 'data': data,
        if (title != null) 'title': title,
      };
}

