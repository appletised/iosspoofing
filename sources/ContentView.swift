import SwiftUI
import CoreBluetooth
import AVFoundation

class BackgroundKeeper: NSObject {
    var player: AVAudioPlayer?
    
    func start() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            
            if let path = Bundle.main.path(forResource: "silence", ofType: "wav") {
                let url = URL(fileURLWithPath: path)
                player = try AVAudioPlayer(contentsOf: url)
                player?.numberOfLoops = -1 
                player?.volume = 0.01
                player?.prepareToPlay()
                player?.play()
                print("Background Audio Started")
            } else {
                print("Silence.wav not found - Backgrounding may fail")
            }
        } catch { print("Audio Error: \(error)") }
    }
}

class BluetoothViewModel: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    let SERVICE_UUID = CBUUID(string: "1819")
    let CHAR_UUID    = CBUUID(string: "2A67")
    
    @Published var status = "Disconnected"
    @Published var receivedData = "Waiting..."
    @Published var logs: [String] = []
    
    var centralManager: CBCentralManager!
    var spooferPeripheral: CBPeripheral?
    let bgKeeper = BackgroundKeeper()
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionRestoreIdentifierKey: "GPS_SPOOFER_RESTORE_ID"])
        bgKeeper.start()
    }
    
    func log(_ msg: String) {
        print(msg)
        DispatchQueue.main.async {
            self.logs.append(msg)
            if self.logs.count > 20 { self.logs.removeFirst() }
        }
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            status = "Scanning..."
            log("Bluetooth ON.")
            let connected = centralManager.retrieveConnectedPeripherals(withServices: [SERVICE_UUID])
            if let device = connected.first {
                log("Found System-Connected Device: \(device.name ?? "Unknown")")
                connect(device)
            } else {
                centralManager.scanForPeripherals(withServices: [SERVICE_UUID], options: nil)
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        log("Found: \(peripheral.name ?? "Unknown")")
        connect(peripheral)
    }
    
    func connect(_ peripheral: CBPeripheral) {
        spooferPeripheral = peripheral
        spooferPeripheral?.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
        status = "Connecting..."
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = "Connected"
        log("Connected! Subscribing...")
        peripheral.discoverServices([SERVICE_UUID])
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services { peripheral.discoverCharacteristics([CHAR_UUID], for: service) }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for char in chars {
            if char.uuid == CHAR_UUID { peripheral.setNotifyValue(true, for: char) }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        if data.count >= 10 {
            let lat = Double(data.subdata(in: 2..<6).withUnsafeBytes { $0.load(as: Int32.self) }) / 10000000.0
            let lon = Double(data.subdata(in: 6..<10).withUnsafeBytes { $0.load(as: Int32.self) }) / 10000000.0
            
            DispatchQueue.main.async {
                self.receivedData = String(format: "Lat: %.5f\nLon: %.5f", lat, lon)
            }
        }
    }
}

struct ContentView: View {
    @StateObject var bt = BluetoothViewModel()
    var body: some View {
        VStack {
            Image(systemName: "location.fill").font(.system(size: 50)).foregroundColor(.green)
            Text("LNS Spoofer").font(.title).bold()
            Text(bt.status).foregroundColor(bt.status == "Connected" ? .green : .red)
            Divider()
            Text(bt.receivedData).font(.system(.title2, design: .monospaced)).padding()
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(bt.logs, id: \.self) { Text($0).font(.caption) }
                }
            }
        }
    }
}
