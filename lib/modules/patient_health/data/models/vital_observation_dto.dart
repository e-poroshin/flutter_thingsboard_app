import 'package:thingsboard_app/modules/patient_health/domain/repositories/i_patient_repository.dart';

/// PATIENT APP: Vital Observation DTO (Data Layer — Inbound)
///
/// Data Transfer Object for parsing responses from
/// `GET /api/medplum/patient/{id}/observations`.
///
/// The SmartBean Proxy returns FHIR Observation resources from Medplum.
/// This DTO flattens the deeply nested FHIR structure into a simple,
/// app-friendly Dart object.
///
/// **Supported FHIR value types:**
/// - `valueQuantity`  → numeric value + unit (most common)
/// - `valueString`    → free-text result
/// - `valueInteger`   → integer value
/// - `valueBoolean`   → true/false
/// - `component`      → composite observations (e.g. Blood Pressure
///                       with systolic + diastolic)
///
/// **Example FHIR Observation (simplified):**
/// ```json
/// {
///   "resourceType": "Observation",
///   "id": "obs-123",
///   "status": "final",
///   "category": [{ "coding": [{ "code": "vital-signs" }] }],
///   "code": {
///     "coding": [{ "system": "http://loinc.org", "code": "8310-5",
///                  "display": "Body Temperature" }]
///   },
///   "effectiveDateTime": "2026-02-18T10:30:00Z",
///   "valueQuantity": { "value": 36.6, "unit": "°C" }
/// }
/// ```
class VitalObservationDto {
  const VitalObservationDto({
    required this.id,
    required this.code,
    required this.displayName,
    this.value,
    this.unit,
    this.effectiveDateTime,
    this.category,
    this.interpretation,
    this.status,
  });

  /// FHIR Observation resource ID
  final String id;

  /// LOINC / SNOMED code (e.g. `"8310-5"` for Body Temperature)
  final String code;

  /// Human-readable observation name (e.g. `"Body Temperature"`)
  final String displayName;

  /// Observation value — may be:
  /// - `double` for numeric readings
  /// - `int` for integer readings
  /// - `String` for textual results
  /// - `bool` for boolean results
  /// - `Map<String, dynamic>` for composite values (blood pressure)
  final dynamic value;

  /// Unit of measurement (e.g. `"°C"`, `"bpm"`, `"mmHg"`)
  /// Null when the value is non-numeric.
  final String? unit;

  /// When the observation was clinically effective / taken.
  final DateTime? effectiveDateTime;

  /// Observation category: `"vital-signs"`, `"laboratory"`, etc.
  final String? category;

  /// Clinical interpretation: `"Normal"`, `"High"`, `"Critical"`, etc.
  final String? interpretation;

  /// FHIR status: `"final"`, `"preliminary"`, `"amended"`, etc.
  final String? status;

  // ============================================================
  // Value Accessors
  // ============================================================

  /// Safe cast to numeric value.
  ///
  /// Returns `null` for composite / string / boolean values.
  double? get numericValue {
    if (value is num) return (value as num).toDouble();
    if (value is String) return double.tryParse(value as String);
    return null;
  }

  /// Safe cast to string value.
  String get stringValue {
    if (value == null) return '';
    if (value is Map) {
      // Composite value (e.g. BP): format as "120/80"
      final entries =
          (value as Map).values.map((v) => v?.toString() ?? '').toList();
      return entries.join('/');
    }
    return value.toString();
  }

  /// Formatted display value including unit.
  ///
  /// Examples: `"36.6 °C"`, `"120/80 mmHg"`, `"Positive"`.
  String get displayValue {
    final valStr = stringValue;
    if (unit != null && unit!.isNotEmpty) {
      return '$valStr $unit';
    }
    return valStr;
  }

  /// Whether this observation is a composite (e.g. Blood Pressure).
  bool get isComposite => value is Map;

  // ============================================================
  // Domain Entity Mapping
  // ============================================================

  /// Map to the domain layer [ClinicalObservation] entity.
  ///
  /// This is what the Repository returns to the BLoC.
  ClinicalObservation toEntity() {
    return ClinicalObservation(
      id: id,
      code: code,
      displayName: displayName,
      value: displayValue,
      effectiveDateTime: effectiveDateTime ?? DateTime.now(),
      category: category,
      interpretation: interpretation,
    );
  }

  // ============================================================
  // JSON Parsing — Single Resource
  // ============================================================

  /// Parse a single FHIR Observation resource from JSON.
  ///
  /// Handles the standard FHIR structure returned by the SmartBean
  /// Proxy (Medplum passthrough).
  factory VitalObservationDto.fromJson(Map<String, dynamic> json) {
    // ── Code / Display ─────────────────────────────────
    final (codeStr, displayStr) = _extractCoding(json['code']);

    // ── Value + Unit ───────────────────────────────────
    final (extractedValue, extractedUnit) = _extractValue(json);

    // ── Category ───────────────────────────────────────
    String? category;
    final categoryList = json['category'] as List?;
    if (categoryList != null && categoryList.isNotEmpty) {
      final firstCategory = categoryList.first;
      if (firstCategory is Map<String, dynamic>) {
        final (_, catDisplay) = _extractCoding(firstCategory);
        category = catDisplay.isNotEmpty ? catDisplay : null;
      }
    }

    // ── Interpretation ─────────────────────────────────
    String? interpretation;
    final interpList = json['interpretation'] as List?;
    if (interpList != null && interpList.isNotEmpty) {
      final firstInterp = interpList.first;
      if (firstInterp is Map<String, dynamic>) {
        final (_, interpDisplay) = _extractCoding(firstInterp);
        interpretation = interpDisplay.isNotEmpty ? interpDisplay : null;
      }
    }

    return VitalObservationDto(
      id: json['id']?.toString() ?? '',
      code: codeStr,
      displayName: displayStr,
      value: extractedValue,
      unit: extractedUnit,
      effectiveDateTime: _parseDateTime(json['effectiveDateTime']),
      category: category,
      interpretation: interpretation,
      status: json['status'] as String?,
    );
  }

  // ============================================================
  // JSON Parsing — List / Bundle
  // ============================================================

  /// Parse a list response that may be:
  /// - A plain JSON array: `[ {...}, {...} ]`
  /// - A FHIR Bundle: `{ "entry": [ { "resource": {...} } ] }`
  /// - A wrapped array: `{ "data": [...] }` or `{ "results": [...] }`
  static List<VitalObservationDto> fromJsonList(dynamic response) {
    final List<Map<String, dynamic>> items;

    if (response is List) {
      items = response
          .whereType<Map<String, dynamic>>()
          .toList();
    } else if (response is Map<String, dynamic>) {
      if (response['entry'] is List) {
        // FHIR Bundle format
        items = (response['entry'] as List)
            .map((e) {
              if (e is Map<String, dynamic>) {
                final resource = e['resource'];
                if (resource is Map<String, dynamic>) return resource;
                return e;
              }
              return <String, dynamic>{};
            })
            .where((m) => m.isNotEmpty)
            .toList();
      } else if (response['data'] is List) {
        items = (response['data'] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
      } else if (response['results'] is List) {
        items = (response['results'] as List)
            .whereType<Map<String, dynamic>>()
            .toList();
      } else {
        items = [];
      }
    } else {
      items = [];
    }

    return items.map(VitalObservationDto.fromJson).toList();
  }

  // ============================================================
  // Serialization (for caching / tests)
  // ============================================================

  /// Serialize back to a simplified JSON map.
  ///
  /// Note: this is **not** the full FHIR format — it's a flat
  /// representation for local caching or test assertions.
  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'displayName': displayName,
        if (value != null) 'value': value,
        if (unit != null) 'unit': unit,
        if (effectiveDateTime != null)
          'effectiveDateTime': effectiveDateTime!.toIso8601String(),
        if (category != null) 'category': category,
        if (interpretation != null) 'interpretation': interpretation,
        if (status != null) 'status': status,
      };

  // ============================================================
  // Private FHIR Parsing Helpers
  // ============================================================

  /// Extract `(code, display)` from a FHIR `CodeableConcept`.
  ///
  /// A `CodeableConcept` looks like:
  /// ```json
  /// {
  ///   "coding": [{ "system": "...", "code": "8310-5",
  ///                "display": "Body Temperature" }],
  ///   "text": "Body Temperature"
  /// }
  /// ```
  static (String, String) _extractCoding(dynamic codeableConcept) {
    if (codeableConcept is! Map<String, dynamic>) {
      return ('', '');
    }

    final codingList = codeableConcept['coding'] as List?;
    if (codingList != null && codingList.isNotEmpty) {
      final first = codingList.first;
      if (first is Map<String, dynamic>) {
        return (
          first['code']?.toString() ?? '',
          first['display']?.toString() ??
              codeableConcept['text']?.toString() ??
              '',
        );
      }
    }

    // Fallback to `text` field
    return ('', codeableConcept['text']?.toString() ?? '');
  }

  /// Extract `(value, unit)` from a FHIR Observation.
  ///
  /// Tries the following paths in order:
  /// 1. `valueQuantity` → `{ "value": 36.6, "unit": "°C" }`
  /// 2. `valueString`   → `"Positive"`
  /// 3. `valueInteger`  → `42`
  /// 4. `valueBoolean`  → `true`
  /// 5. `component`     → composite (e.g. Blood Pressure):
  ///    ```json
  ///    "component": [
  ///      { "code": { ... "display": "Systolic" },
  ///        "valueQuantity": { "value": 120, "unit": "mmHg" } },
  ///      { "code": { ... "display": "Diastolic" },
  ///        "valueQuantity": { "value": 80, "unit": "mmHg" } }
  ///    ]
  ///    ```
  ///    Returns `({ "Systolic": 120, "Diastolic": 80 }, "mmHg")`.
  /// 6. Direct `value` / `unit` fields (simplified proxy format).
  static (dynamic, String?) _extractValue(Map<String, dynamic> json) {
    // 1. valueQuantity (most common for vitals)
    final vq = json['valueQuantity'];
    if (vq is Map<String, dynamic>) {
      return (vq['value'], vq['unit'] as String?);
    }

    // 2. valueString
    if (json.containsKey('valueString')) {
      return (json['valueString'], null);
    }

    // 3. valueInteger
    if (json.containsKey('valueInteger')) {
      return (json['valueInteger'], null);
    }

    // 4. valueBoolean
    if (json.containsKey('valueBoolean')) {
      return (json['valueBoolean'], null);
    }

    // 5. component (composite observations like Blood Pressure)
    final components = json['component'];
    if (components is List && components.isNotEmpty) {
      final compositeValue = <String, dynamic>{};
      String? compositeUnit;

      for (final comp in components) {
        if (comp is! Map<String, dynamic>) continue;

        // Get component name from its CodeableConcept
        final (_, compDisplay) = _extractCoding(comp['code']);
        final compName =
            compDisplay.isNotEmpty ? compDisplay : 'component_${compositeValue.length}';

        // Recursively extract the component's value
        final (compVal, compUnit) = _extractValue(comp);
        compositeValue[compName] = compVal;

        // Use the first non-null unit as the composite unit
        compositeUnit ??= compUnit;
      }

      if (compositeValue.isNotEmpty) {
        return (compositeValue, compositeUnit);
      }
    }

    // 6. Simplified proxy format: direct "value" / "unit" fields
    if (json.containsKey('value')) {
      return (json['value'], json['unit'] as String?);
    }

    return (null, null);
  }

  /// Parse a DateTime from various input formats.
  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }

  // ============================================================
  // Object Overrides
  // ============================================================

  @override
  String toString() =>
      'VitalObservationDto(id: $id, code: $code, '
      'display: $displayName, value: $displayValue, '
      'date: $effectiveDateTime)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VitalObservationDto &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          code == other.code;

  @override
  int get hashCode => id.hashCode ^ code.hashCode;
}
