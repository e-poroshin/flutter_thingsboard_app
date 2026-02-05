import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:typed_data';

/// PATIENT APP: BLE Data Parser Utility
///
/// Parses temperature and humidity data from BLE advertisement packets.
/// Supports multiple formats:
/// - ATC Custom Firmware (Service UUID 0x181A) - Environmental Sensing
/// - Xiaomi Stock Firmware (Service UUID 0xFE95) - Encrypted/Unencrypted
class BleDataParser {
  BleDataParser._();

  /// ATC Custom Firmware Service UUID (Environmental Sensing)
  static const String atcServiceUuid = '181A';

  /// Xiaomi Stock Firmware Service UUID
  static const String xiaomiServiceUuid = 'FE95';

  /// Parse temperature from scan result advertisement data
  ///
  /// Returns temperature in Celsius, or null if not found/parseable.
  /// Priority: ATC format (0x181A) > Xiaomi format (0xFE95)
  static double? parseTemperature(ScanResult result) {
    try {
      final serviceData = result.advertisementData.serviceData;

      if (serviceData.isEmpty) {
        return null;
      }

      // Priority 1: Try ATC format (Service UUID 0x181A)
      final atcTemp = _parseAtcTemperature(serviceData);
      if (atcTemp != null) {
        return atcTemp;
      }

      // Priority 2: Try Xiaomi format (Service UUID 0xFE95)
      final xiaomiTemp = _parseXiaomiTemperature(serviceData);
      if (xiaomiTemp != null) {
        return xiaomiTemp;
      }

      return null;
    } catch (e) {
      // Silently return null on parse errors
      return null;
    }
  }

  /// Parse humidity from scan result advertisement data
  ///
  /// Returns humidity percentage (0-100), or null if not found/parseable.
  static double? parseHumidity(ScanResult result) {
    try {
      final serviceData = result.advertisementData.serviceData;

      if (serviceData.isEmpty) {
        return null;
      }

      // Priority 1: Try ATC format (Service UUID 0x181A)
      final atcHumidity = _parseAtcHumidity(serviceData);
      if (atcHumidity != null) {
        return atcHumidity;
      }

      // Priority 2: Try Xiaomi format (Service UUID 0xFE95)
      final xiaomiHumidity = _parseXiaomiHumidity(serviceData);
      if (xiaomiHumidity != null) {
        return xiaomiHumidity;
      }

      return null;
    } catch (e) {
      // Silently return null on parse errors
      return null;
    }
  }

  /// Parse ATC format temperature (Service UUID 0x181A)
  ///
  /// ATC Custom format structure:
  /// - Bytes 0-5: MAC address (6 bytes)
  /// - Bytes 6-7: Temperature (big-endian int16, multiplied by 10)
  /// - Byte 8: Humidity (single byte, 0-100)
  /// - Byte 9: Battery voltage (single byte, 0-100)
  /// - Byte 10: Flags
  /// - Byte 11: Counter
  ///
  /// Example: If bytes 6-7 are [0x00, 0xCA] = 202 = 20.2°C (divide by 10)
  static double? _parseAtcTemperature(Map<Guid, List<int>> serviceData) {
    try {
      // Look for Service UUID 0x181A (can be in different formats)
      List<int>? data;
      for (final entry in serviceData.entries) {
        final uuidStr = entry.key.toString().toUpperCase();
        // Check if UUID contains 181A (might be full UUID like 0000181A-0000-1000-8000-00805f9b34fb)
        if (uuidStr.contains(atcServiceUuid)) {
          data = entry.value;
          break;
        }
      }

      if (data == null || data.length < 8) {
        // Need at least 8 bytes (6 MAC + 2 temp)
        return null;
      }

      // Log raw bytes for debugging
      print('RAW BYTES: ${data.toString()}');

      // ATC format: MAC address is in first 6 bytes, temperature starts at byte 6
      // Parse temperature from bytes 6-7 (big-endian int16)
      // Formula: ((data[6] << 8) | data[7]) / 10.0
      final tempRaw = ((data[6] << 8) | data[7]);
      
      // Convert to Celsius (divide by 10)
      final temperature = tempRaw / 10.0;

      return temperature;
    } catch (e) {
      print('Error parsing ATC temperature: $e');
      return null;
    }
  }

  /// Parse ATC format humidity (Service UUID 0x181A)
  ///
  /// ATC Custom format structure:
  /// - Bytes 0-5: MAC address (6 bytes)
  /// - Bytes 6-7: Temperature (little-endian int16, multiplied by 100)
  /// - Byte 8: Humidity (single byte, 0-100, already a percentage)
  /// - Byte 9: Battery voltage (single byte, 0-100)
  /// - Byte 10: Flags
  /// - Byte 11: Counter
  static double? _parseAtcHumidity(Map<Guid, List<int>> serviceData) {
    try {
      List<int>? data;
      for (final entry in serviceData.entries) {
        final uuidStr = entry.key.toString().toUpperCase();
        if (uuidStr.contains(atcServiceUuid)) {
          data = entry.value;
          break;
        }
      }

      if (data == null || data.length < 9) {
        // Need at least 9 bytes (6 MAC + 2 temp + 1 humidity)
        return null;
      }

      // ATC format: MAC address is in first 6 bytes, humidity is at byte 8 (single byte)
      // Humidity is already a percentage (0-100), no division needed
      final humidity = data[8].toDouble();

      // Validate humidity is in reasonable range
      if (humidity < 0 || humidity > 100) {
        return null;
      }

      return humidity;
    } catch (e) {
      print('Error parsing ATC humidity: $e');
      return null;
    }
  }

  /// Parse Xiaomi format temperature (Service UUID 0xFE95)
  ///
  /// Xiaomi format is more complex and often encrypted.
  /// This is a basic attempt - may need decryption for stock firmware.
  static double? _parseXiaomiTemperature(Map<Guid, List<int>> serviceData) {
    try {
      List<int>? data;
      for (final entry in serviceData.entries) {
        final uuidStr = entry.key.toString().toUpperCase();
        if (uuidStr.contains(xiaomiServiceUuid)) {
          data = entry.value;
          break;
        }
      }

      if (data == null || data.length < 7) {
        return null;
      }

      // Xiaomi format structure (for LYWSD03MMC):
      // Byte 0: Frame control
      // Byte 1: Frame counter
      // Bytes 2-3: MAC address (reversed)
      // Bytes 4-5: Temperature (little-endian int16, divide by 100)
      // Byte 6: Humidity

      // Check frame control (should be 0x50 for temperature/humidity)
      if (data[0] != 0x50) {
        return null;
      }

      // Parse temperature from bytes 4-5 (little-endian int16)
      final tempRaw = (data[4] | (data[5] << 8));
      final tempSigned = tempRaw > 32767 ? tempRaw - 65536 : tempRaw;
      final temperature = tempSigned / 100.0;

      return temperature;
    } catch (e) {
      return null;
    }
  }

  /// Parse Xiaomi format humidity (Service UUID 0xFE95)
  static double? _parseXiaomiHumidity(Map<Guid, List<int>> serviceData) {
    try {
      List<int>? data;
      for (final entry in serviceData.entries) {
        final uuidStr = entry.key.toString().toUpperCase();
        if (uuidStr.contains(xiaomiServiceUuid)) {
          data = entry.value;
          break;
        }
      }

      if (data == null || data.length < 7) {
        return null;
      }

      // Check frame control
      if (data[0] != 0x50) {
        return null;
      }

      // Parse humidity from byte 6
      final humidity = data[6].toDouble();

      return humidity;
    } catch (e) {
      return null;
    }
  }

  /// Check if scan result matches Xiaomi Mi Temperature Monitor 2
  ///
  /// This is a helper to filter relevant devices
  static bool isXiaomiTemperatureMonitor(ScanResult result) {
    try {
      final serviceData = result.advertisementData.serviceData;
      final deviceName = result.advertisementData.advName.toLowerCase();

      // Check for Xiaomi service UUID
      for (final entry in serviceData.entries) {
        final uuidStr = entry.key.toString().toUpperCase();
        if (uuidStr.contains(xiaomiServiceUuid) ||
            uuidStr.contains(atcServiceUuid)) {
          return true;
        }
      }

      // Check device name patterns
      if (deviceName.contains('lywsd03mmc') ||
          deviceName.contains('xiaomi') ||
          deviceName.contains('temp')) {
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }
}
