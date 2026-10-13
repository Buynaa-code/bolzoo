import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hamtdaa/florists/florist_location.dart';
import 'package:hamtdaa/florists/florist_repository.dart';

Position position({double latitude = 47.92, double longitude = 106.92}) =>
    Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.utc(2026, 10, 13),
      accuracy: 100,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

Matcher failure(String code) =>
    isA<FloristFailure>().having((error) => error.code, 'code', code);

void main() {
  test(
    'does nothing until locate and requests a bounded single foreground fix',
    () async {
      final calls = <String>[];
      LocationSettings? usedSettings;
      final service = DeviceFloristLocation(
        serviceEnabled: () async {
          calls.add('service');
          return true;
        },
        checkPermission: () async {
          calls.add('check');
          return LocationPermission.denied;
        },
        requestPermission: () async {
          calls.add('request');
          return LocationPermission.whileInUse;
        },
        currentPosition: (settings) async {
          calls.add('position');
          usedSettings = settings;
          return position();
        },
      );
      expect(calls, isEmpty);
      final point = await service.locate();
      expect(calls, ['service', 'check', 'request', 'position']);
      expect(point.latitude, 47.92);
      expect(point.longitude, 106.92);
      expect(usedSettings?.accuracy, LocationAccuracy.medium);
      expect(usedSettings?.timeLimit, const Duration(seconds: 20));
    },
  );

  test(
    'does not request access or position when location services are off',
    () async {
      var permissionCalls = 0;
      var positionCalls = 0;
      final service = DeviceFloristLocation(
        serviceEnabled: () async => false,
        checkPermission: () async {
          permissionCalls++;
          return LocationPermission.whileInUse;
        },
        currentPosition: (_) async {
          positionCalls++;
          return position();
        },
      );
      await expectLater(
        service.locate(),
        throwsA(failure('location_disabled')),
      );
      expect(permissionCalls, 0);
      expect(positionCalls, 0);
    },
  );

  test(
    'denied and permanently denied permission never access device position',
    () async {
      for (final permission in [
        LocationPermission.denied,
        LocationPermission.deniedForever,
      ]) {
        var requests = 0;
        var positions = 0;
        final service = DeviceFloristLocation(
          serviceEnabled: () async => true,
          checkPermission: () async => permission,
          requestPermission: () async {
            requests++;
            return permission;
          },
          currentPosition: (_) async {
            positions++;
            return position();
          },
        );
        await expectLater(
          service.locate(),
          throwsA(
            failure(
              permission == LocationPermission.denied
                  ? 'permission_denied'
                  : 'permission_denied_forever',
            ),
          ),
        );
        expect(requests, permission == LocationPermission.denied ? 1 : 0);
        expect(positions, 0);
      }
    },
  );

  test(
    'maps failures and allows retry after a failed position request',
    () async {
      Object? thrown;
      final service = DeviceFloristLocation(
        serviceEnabled: () async => true,
        checkPermission: () async => LocationPermission.whileInUse,
        currentPosition: (_) async {
        if (thrown != null) throw thrown;
          return position();
        },
      );
      final failures = <Object, String>{
        TimeoutException('timed out'): 'location_timeout',
        const PermissionDeniedException('denied'): 'permission_denied',
        const LocationServiceDisabledException(): 'location_disabled',
        UnsupportedError('platform unavailable'): 'location_unavailable',
      };
      for (final entry in failures.entries) {
        thrown = entry.key;
        await expectLater(service.locate(), throwsA(failure(entry.value)));
      }
      thrown = null;
      expect((await service.locate()).isValid, isTrue);
    },
  );

  test('rejects an invalid device coordinate', () async {
    final service = DeviceFloristLocation(
      serviceEnabled: () async => true,
      checkPermission: () async => LocationPermission.whileInUse,
      currentPosition: (_) async => position(latitude: double.nan),
    );
    await expectLater(
      service.locate(),
      throwsA(failure('location_unavailable')),
    );
  });

  test(
    'prevents overlapping permission prompts or location requests',
    () async {
      final permission = Completer<LocationPermission>();
      var requests = 0;
      final service = DeviceFloristLocation(
        serviceEnabled: () async => true,
        checkPermission: () async => LocationPermission.denied,
        requestPermission: () {
          requests++;
          return permission.future;
        },
        currentPosition: (_) async => position(),
      );
      final pending = service.locate();
      await expectLater(service.locate(), throwsA(failure('busy')));
      permission.complete(LocationPermission.whileInUse);
      expect((await pending).isValid, isTrue);
      expect(requests, 1);
    },
  );

  test(
    'opens the relevant settings and handles unsupported web settings',
    () async {
      var enabled = false;
      final calls = <String>[];
      final service = DeviceFloristLocation(
        serviceEnabled: () async => enabled,
        openLocationSettings: () async {
          calls.add('location');
          return true;
        },
        openAppSettings: () async {
          calls.add('app');
          return true;
        },
      );
      expect(await service.openSettings(), isTrue);
      enabled = true;
      expect(await service.openSettings(), isTrue);
      expect(calls, ['location', 'app']);
      final webService = DeviceFloristLocation(
        serviceEnabled: () async => true,
        openAppSettings: () async => throw UnsupportedError('web'),
      );
      expect(await webService.openSettings(), isFalse);
    },
  );
}
