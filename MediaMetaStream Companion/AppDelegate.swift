//
//  AppDelegate.swift
//  MediaMetaStream Companion
//
//  Created by Jannik Theiß on 09.09.18.
//  Copyright © 2018 Jannik Theiß. All rights reserved.
//

import Foundation
import Cocoa
import MapKit
import Starscream

typealias Server = (name: String, ipAddress: String, port: Int)

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NetServiceBrowserDelegate, NetServiceDelegate, WebSocketDelegate {
    
    var mmsServers: [Server] = []
    
    var socket: WebSocket?
    
    // Local service browser
    var browser = NetServiceBrowser()
    
    // Instance of the service that we're looking for
    var service: NetService?
    
    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var sheetWindow: NSWindow!
    
    @IBOutlet weak var mapView: MKMapView!
    @IBOutlet weak var tableView: NSTableView!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        // Setup the browser
        browser = NetServiceBrowser()
        browser.delegate = self
        startDiscovery()
        
        let location = mapView.centerCoordinate
        let region = MKCoordinateRegionMakeWithDistance(location, 10.0, 10.0)
        mapView.setRegion(region, animated: false)
        
        
        sheetWindow.preventsApplicationTerminationWhenModal = false
        window.beginSheet(sheetWindow, completionHandler: nil)
        
        tableView.dataSource = self
        tableView.delegate = self
    }
    
    @IBAction func tableViewDoubleAction(_ sender: NSTableView) {
        let index = sender.selectedRow
        if (index >= 0 && index < mmsServers.count) {
            let selectedServer = mmsServers[sender.selectedRow]
            connect(selectedServer)
            window.endSheet(sheetWindow)
        }
    }
    
    @IBAction func disconnect(_ sender: NSButton) {
        socket?.disconnect()
    }
    
    private func startDiscovery() {
        // Make sure to reset the last known service if we want to run this a few times
        service = nil
        
        // Start the discovery
        browser.stop()
        browser.searchForServices(ofType: "_mms._tcp", inDomain: "")
    }
    
    // MARK: Service discovery
    
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        print("Search about to begin")
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("Resolve error:", sender, errorDict)
    }
    
    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        print("Search stopped")
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind svc: NetService, moreComing: Bool) {
        print("Discovered the service")
        print("- name:", svc.name)
        print("- type", svc.type)
        print("- domain:", svc.domain)
        
        // We dont want to discover more services, just need the first one
        if service != nil {
            return
        }
        
        // We stop after we find first service
        //browser.stop()
        
        // Resolve the service within 5 seconds
        service = svc
        service?.delegate = self
        service?.resolve(withTimeout: 5)
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        print("Resolved service")
        print("- addresses:", sender.addresses!)
        print("- port: \(sender.port)")
        
        // Find the IPV4 address
        if let serviceIp = resolveIPv4(addresses: sender.addresses!) {
            let newServer = (sender.name, serviceIp, sender.port)
            print("- IPv4:", serviceIp)
            if (!mmsServers.contains(where: { $0 == newServer })) {
                mmsServers.append((sender.name, serviceIp, sender.port))
                tableView.reloadData()
            }
        } else {
            print("- Did not find IPV4 address")
        }
    }
    
    // Find an IPv4 address from the service address data
    func resolveIPv4(addresses: [Data]) -> String? {
        var result: String?
        
        for addr in addresses {
            let data = addr as NSData
            var storage = sockaddr_storage()
            data.getBytes(&storage, length: MemoryLayout<sockaddr_storage>.size)
            
            if Int32(storage.ss_family) == AF_INET {
                let addr4 = withUnsafePointer(to: &storage) {
                    $0.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                        $0.pointee
                    }
                }
                
                if let ip = String(cString: inet_ntoa(addr4.sin_addr), encoding: .ascii) {
                    result = ip
                    break
                }
            }
        }
        
        return result
    }
    
    func connect(_ server: Server) {
        if (socket.map { !$0.isConnected } ?? true ) {
            let request = URLRequest(url: URL(string: "ws://\(server.ipAddress):\(server.port)")!)
            socket = WebSocket(request: request)
            socket!.delegate = self
            socket!.connect()
        }
    }
    
    func websocketDidConnect(socket: WebSocketClient) {
        print("websocket is connected")
    }
    
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        if let e = error as? WSError {
            print("websocket is disconnected: \(e.message)")
        } else if let e = error {
            print("websocket is disconnected: \(e.localizedDescription)")
        } else {
            print("websocket disconnected")
        }
        window.beginSheet(sheetWindow, completionHandler: nil)
    }
    
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        if let jsonObject = try? JSONSerialization.jsonObject(with: text.data(using: String.Encoding.utf8)!, options: []) {
            if let dictionary = jsonObject as? [String: Any] {
                if let (lat, lng) = (dictionary["lat"], dictionary["lng"]) as? (Double, Double) {
                    
                    let location = CLLocationCoordinate2D(latitude: lat, longitude: lng)
                    mapView.setCenter(location, animated: true)
                    
                    mapView.removeAnnotations(mapView.annotations)
                    
                    let annotation = MKPointAnnotation()
                    let centerCoordinate = CLLocationCoordinate2D(latitude: lat, longitude:lng)
                    annotation.coordinate = centerCoordinate
                    //annotation.title = "Title"
                    mapView.addAnnotation(annotation)
                    
                    print("Received coorinates: (\(lng), \(lat))")
                } else {
                    print("Received json: \(dictionary)")
                }
            } else {
                print("Received text: \(text)")
            }
            print("Received text: \(text)")
        }
    }
    
    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        print("Received data: \(data.count)")
    }
    
}

extension AppDelegate: NSTableViewDataSource {
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return mmsServers.count
    }
    
}

extension AppDelegate: NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cellIdentifier = NSUserInterfaceItemIdentifier(rawValue: "NameCellID")
        if let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? ServerTableCellView {
            let server = mmsServers[row]
            cell.textField?.stringValue = server.name
            cell.textField2.stringValue = "\(server.ipAddress):\(server.port)"
            return cell
        }
        return nil
    }
}
