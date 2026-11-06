import CoreBluetooth

// PIN платы. Должен совпадать со строкой  String pin = "1234";  в прошивке KT_Dash.
let boardPin = "1234"

/// Связь с платой по Bluetooth LE: ищет плату KT Dash, подключается, принимает данные и отправляет команды.
final class BleLink: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private let svcUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxUUID  = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")   // сюда пишем команды
    private let txUUID  = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")   // отсюда приходят данные
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rx: CBCharacteristic?
    private var buffer = ""

    /// Вызывается для каждой полной строки с данными (JSON).
    var onLine: ((String) -> Void)?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func write(_ cmd: String) {
        guard let p = peripheral, let c = rx, p.state == .connected else { return }
        p.writeValue(Data(cmd.utf8), for: c, type: .withResponse)
    }

    private func startScan() {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(withServices: [svcUUID], options: nil)
    }

    private func retry() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.startScan() }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn { startScan() }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        buffer = ""
        peripheral.discoverServices([svcUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        retry()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        rx = nil
        retry()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for s in peripheral.services ?? [] where s.uuid == svcUUID {
            peripheral.discoverCharacteristics([rxUUID, txUUID], for: s)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == rxUUID { rx = c }
            if c.uuid == txUUID { peripheral.setNotifyValue(true, for: c) }
        }
        if rx != nil { write("pin=" + boardPin) }       // без PIN плата не принимает команды
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == txUUID,
              let d = characteristic.value,
              let s = String(data: d, encoding: .utf8) else { return }
        buffer += s
        while let i = buffer.firstIndex(of: "\n") {
            let line = String(buffer[buffer.startIndex..<i])
            buffer.removeSubrange(buffer.startIndex...i)
            if !line.isEmpty { onLine?(line) }
        }
        if buffer.count > 2000 { buffer = "" }
    }
}
