import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'florist_repository.dart';

abstract class FloristLocation {
  Future<GeoPoint> locate();
  Future<bool> openSettings();
}

/// A single foreground fix, requested only by an explicit user action.
/// No background stream, persistent location cache, or coordinate logging.
class DeviceFloristLocation implements FloristLocation {
  DeviceFloristLocation({
    Future<bool> Function()? serviceEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Future<Position> Function(LocationSettings)? currentPosition,
    Future<bool> Function()? openAppSettings,
    Future<bool> Function()? openLocationSettings,
  }) : _serviceEnabled = serviceEnabled ?? Geolocator.isLocationServiceEnabled,
       _checkPermission = checkPermission ?? Geolocator.checkPermission,
       _requestPermission = requestPermission ?? Geolocator.requestPermission,
       _currentPosition = currentPosition ?? _getPosition,
       _openAppSettings = openAppSettings ?? Geolocator.openAppSettings,
       _openLocationSettings =
           openLocationSettings ?? Geolocator.openLocationSettings;

  static const _settings = LocationSettings(
    accuracy: LocationAccuracy.medium,
    timeLimit: Duration(seconds: 20),
  );
  final Future<bool> Function() _serviceEnabled;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final Future<Position> Function(LocationSettings) _currentPosition;
  final Future<bool> Function() _openAppSettings;
  final Future<bool> Function() _openLocationSettings;
  bool _locating = false;

  static Future<Position> _getPosition(LocationSettings settings) =>
      Geolocator.getCurrentPosition(locationSettings: settings);

  @override
  Future<GeoPoint> locate() async {
    if (_locating) throw const FloristFailure('busy');
    _locating = true;
    try {
      if (!await _serviceEnabled().timeout(const Duration(seconds: 10))) {
        throw const FloristFailure('location_disabled');
      }
      var permission = await _checkPermission().timeout(
        const Duration(seconds: 10),
      );
      if (permission == LocationPermission.denied) {
        // Do not time out the user's interaction with the permission dialog.
        permission = await _requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const FloristFailure('permission_denied_forever');
      }
      if (permission == LocationPermission.denied) {
        throw const FloristFailure('permission_denied');
      }
      // Browsers without the Permissions API report unableToDetermine; their
      // single-fix request presents the browser's own permission dialog.
      final position = await _currentPosition(
        _settings,
      ).timeout(const Duration(seconds: 22));
      final point = GeoPoint(position.latitude, position.longitude);
      if (!point.isValid) {
        throw const FloristFailure('location_unavailable');
      }
      return point;
    } on FloristFailure {
      rethrow;
    } on TimeoutException {
      throw const FloristFailure('location_timeout');
    } on PermissionDeniedException {
      throw const FloristFailure('permission_denied');
    } on LocationServiceDisabledException {
      throw const FloristFailure('location_disabled');
    } on PermissionRequestInProgressException {
      throw const FloristFailure('busy');
    } catch (_) {
      throw const FloristFailure('location_unavailable');
    } finally {
      _locating = false;
    }
  }

  @override
  Future<bool> openSettings() async {
    try {
      final enabled = await _serviceEnabled().timeout(
        const Duration(seconds: 10),
      );
      return await (enabled ? _openAppSettings() : _openLocationSettings())
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Settings APIs are unsupported on web; the UI can explain how to change
      // browser permissions instead of throwing an unhandled plugin error.
      return false;
    }
  }
}
