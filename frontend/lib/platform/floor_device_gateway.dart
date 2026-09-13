/// The shared floor device's own credential, and how the app gets hold of it
/// (issue #77, ADR-0016).
///
/// The device is provisioned out of band — registering and installing real
/// hardware is an operational task, explicitly out of this ticket's scope — so
/// the credential is supplied to the build rather than obtained at runtime.
/// `--dart-define=FLOOR_DEVICE_CREDENTIAL=...` is the provisioning seam: a
/// device image built with its own credential presents it on every floor
/// request, and a build with none shows the not-registered state instead of
/// pretending to be a device.
///
/// Tests substitute their own [FloorDeviceGateway]; the router and Bloc take
/// this abstraction, never a concrete compile-time constant.
library;

abstract class FloorDeviceGateway {
  /// The credential this device presents on the floor surface, or null when
  /// the build was not provisioned with one.
  String? get deviceCredential;
}

class ConfiguredFloorDeviceGateway implements FloorDeviceGateway {
  const ConfiguredFloorDeviceGateway();

  @override
  String? get deviceCredential {
    const value = String.fromEnvironment('FLOOR_DEVICE_CREDENTIAL');
    return value.isEmpty ? null : value;
  }
}
