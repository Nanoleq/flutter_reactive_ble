import 'dart:async';
import 'dart:typed_data';
import 'package:quick_blue/quick_blue.dart';
import 'package:reactive_ble_platform_interface/reactive_ble_platform_interface.dart';

class ReactiveBleDesktopPlatformFactory {
  const ReactiveBleDesktopPlatformFactory();
  ReactiveBleDesktopPlatform create() => ReactiveBleDesktopPlatform();
}

/// An implementation of ReactiveBlePlatform using quick_blue
class ReactiveBleDesktopPlatform extends ReactiveBlePlatform {
  ReactiveBleDesktopPlatform() {
    _bleStatusController = StreamController<BleStatus>.broadcast(
      onListen: () {
        _statusTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
          final available = await QuickBlue.isBluetoothAvailable();
          final newStatus = available ? BleStatus.ready : BleStatus.unsupported;
          if (_lastStatus != newStatus) {
            _bleStatusController.add(newStatus);
            _lastStatus = newStatus;
          }
        });
      },
      onCancel: () {
        _statusTimer?.cancel();
        _statusTimer = null;
        _lastStatus = null;
      },
    );

    _characteristicValueController = StreamController.broadcast(
      onListen: () {
        QuickBlue.setValueHandler(
            (String deviceId, String characteristicId, Uint8List value) {
          final characteristicUUId = Uuid.parse(characteristicId);
          _characteristicValueController.add(CharacteristicValue(
              characteristic: QualifiedCharacteristic(
                  characteristicId: characteristicUUId,
                  serviceId: _characteristicsToService[characteristicUUId] ??
                      characteristicUUId, //TODO: FIX ME The service ID is not provided by quick_blue
                  deviceId: deviceId),
              result: Result.success(value)));
        });
      },
      onCancel: () {
        print("On Cancel");

        QuickBlue.setValueHandler(null);
      },
    );

    _connectionStateUpdateController = StreamController.broadcast(
      onListen: () {
        QuickBlue.setConnectionHandler((deviceId, state) {
          _connectionStateUpdateController.add(ConnectionStateUpdate(
              deviceId: deviceId,
              connectionState: state == BlueConnectionState.connected
                  ? DeviceConnectionState.connected
                  : DeviceConnectionState.disconnected,
              failure: null));
        });
      },
      onCancel: () {
        QuickBlue.setConnectionHandler(null);
      },
    );
  }

  late final StreamController<ConnectionStateUpdate>
      _connectionStateUpdateController;

  late final StreamController<CharacteristicValue>
      _characteristicValueController;

  late final StreamController<BleStatus> _bleStatusController;

  BleStatus? _lastStatus;

  Timer? _statusTimer;

  ///[Implemented Methods]
  @override
  Future<void> initialize() async {}

  @override
  Future<void> deinitialize() async {
    QuickBlue.setConnectionHandler(null);
    QuickBlue.setValueHandler(null);
  }

  @override
  Stream<BleStatus> get bleStatusStream => _bleStatusController.stream;

  @override
  Stream<ScanResult> get scanStream =>
      QuickBlue.scanResultStream.map((BlueScanResult device) => ScanResult(
              result: Result.success(DiscoveredDevice(
            id: device.deviceId,
            name: device.name,
            serviceData: const {},
            manufacturerData: device.manufacturerData,
            rssi: device.rssi,
            serviceUuids: const [],
          ))));

  @override
  Stream<void> scanForDevices({
    required List<Uuid> withServices,
    required ScanMode scanMode,
    required bool requireLocationServicesEnabled, // This flag is not supported
  }) =>
      Future<void>.delayed(const Duration(microseconds: 10))
          .then((value) => QuickBlue.startScan())
          .asStream();

  @override
  Stream<ConnectionStateUpdate> get connectionUpdateStream =>
      _connectionStateUpdateController.stream;

  @override
  Future<void> disconnectDevice(String deviceId) async {
    QuickBlue.disconnect(deviceId);
  }

  @override
  Stream<void> connectToDevice(
    String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  ) =>
      Future<void>.delayed(const Duration(microseconds: 10))
          .then((value) => QuickBlue.connect(id))
          .asStream();

  @override
  Future<List<DiscoveredService>> discoverServices(String deviceId) async {
    QuickBlue.discoverServices(deviceId);
    final discoveredServices = <DiscoveredService>[];
    QuickBlue.setServiceHandler((String device, String serviceId) {
      if (device == deviceId) {
        discoveredServices.add(DiscoveredService(
            serviceId: Uuid.parse(serviceId),
            characteristicIds: [],
            characteristics: []));
      }
    });
    await Future<void>.delayed(const Duration(seconds: 1));
    QuickBlue.setServiceHandler(null);
    return discoveredServices;
  }

  @override
  Future<WriteCharacteristicInfo> writeCharacteristicWithResponse(
    QualifiedCharacteristic characteristic,
    List<int> value,
  ) async {
    await QuickBlue.writeValue(
        characteristic.deviceId,
        characteristic.serviceId.toString(),
        characteristic.characteristicId.toString(),
        Uint8List.fromList(value),
        BleOutputProperty.withResponse);
    return WriteCharacteristicInfo(
      characteristic: characteristic,
      result: const Result.success(
        Unit(),
      ),
    );
  }

  @override
  Future<WriteCharacteristicInfo> writeCharacteristicWithoutResponse(
    QualifiedCharacteristic characteristic,
    List<int> value,
  ) async {
    await QuickBlue.writeValue(
        characteristic.deviceId,
        characteristic.serviceId.toString(),
        characteristic.characteristicId.toString(),
        Uint8List.fromList(value),
        BleOutputProperty.withoutResponse);
    return WriteCharacteristicInfo(
      characteristic: characteristic,
      result: const Result.success(
        Unit(),
      ),
    );
  }

  @override
  Stream<CharacteristicValue> get charValueUpdateStream =>
      _characteristicValueController.stream;

  @override
  Stream<void> readCharacteristic(QualifiedCharacteristic characteristic) =>
      QuickBlue.readValue(
              characteristic.deviceId,
              characteristic.serviceId.toString(),
              characteristic.characteristicId.toString())
          .asStream();

  // a hack to fill the service ID in setValueHandler
  final Map<Uuid, Uuid> _characteristicsToService = {};
  @override
  Stream<void> subscribeToNotifications(
    QualifiedCharacteristic characteristic,
  ) {
    _characteristicsToService[characteristic.characteristicId] =
        characteristic.serviceId;
    return QuickBlue.setNotifiable(
            characteristic.deviceId,
            characteristic.serviceId.toString(),
            characteristic.characteristicId.toString(),
            BleInputProperty.notification)
        .asStream();
  }

  @override
  Future<void> stopSubscribingToNotifications(
    QualifiedCharacteristic characteristic,
  ) =>
      QuickBlue.setNotifiable(
          characteristic.deviceId,
          characteristic.serviceId.toString(),
          characteristic.characteristicId.toString(),
          BleInputProperty.disabled);

  @override
  Future<int> requestMtuSize(String deviceId, int? mtu) =>
      QuickBlue.requestMtu(deviceId, mtu ?? 242);

  @override
  Future<Result<Unit, GenericFailure<ClearGattCacheError>?>> clearGattCache(
      String deviceId) {
    throw UnimplementedError('clearGattCache is not implemented on Desktop');
  }

  @override
  Future<ConnectionPriorityInfo> requestConnectionPriority(
      String deviceId, ConnectionPriority priority) {
    throw UnimplementedError(
        'requestConnectionPriority is not implemented on Desktop');
  }
}
