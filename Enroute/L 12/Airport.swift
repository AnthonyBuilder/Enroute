//
//  Airport.swift
//  Enroute
//
//  Created by Anthony on 11/06/21.
//  Copyright © 2021 Stanford University. All rights reserved.
//

import Combine
import CoreData

extension Airport {
    static func withICAO(_ icao: String, context: NSManagedObjectContext) -> Airport {
        // look up icao in Core Data
        let request = fetchRequest(NSPredicate(format: "icao_ = %@", icao))
        let airports = (try? context.fetch(request)) ?? []
        if let airport = airports.first {
            // if found, return it
            return airport
        } else {
            // if not, create one and fetch from FlightAware
            let airport = Airport(context: context)
            airport.icao = icao
            AirportInfoRequest.fetch(icao) { airportInfo in
                self.update(from: airportInfo, context: context)
            }
            return airport
        }
    }
    
    static func update(from info: AirportInfo, context: NSManagedObjectContext) {
        if let icao = info.icao {
            let airport = self.withICAO(icao, context: context)
            airport.latitude = info.latitude
            airport.longitude = info.longitude
            airport.name = info.name
            airport.location = info.location
            airport.timezone = info.timezone
            airport.objectWillChange.send()
            airport.flightsTo.forEach { $0.objectWillChange.send() }
            airport.flightsFrom.forEach { $0.objectWillChange.send() }

            try? context.save()
        }
    }
    
    var flightsTo: Set<Flight> {
        get { (flightsTo_ as? Set<Flight>) ?? [] }
        set { flightsTo_ = newValue as NSSet}
    }
    
    var flightsFrom: Set<Flight> {
        get { (flightsFrom_ as? Set<Flight>) ?? [] }
        set { flightsFrom_ = newValue as NSSet }
    }
    
}

extension Airport: Comparable {
    var icao: String {
        get { icao_! }
        set { icao_ = newValue }
    }
    
    var friendlyName: String {
        let friendly = AirportInfo.friendlyName(name: self.name ?? "", location: self.location ?? "")
        return friendly.isEmpty ? icao : friendly
    }
    
    public var id: String { icao }

    public static func < (lhs: Airport, rhs: Airport) -> Bool {
        lhs.location ?? lhs.friendlyName < rhs.location ?? rhs.friendlyName
    }
}

// realize request to found respective airport with predicate
extension Airport {
    static func fetchRequest(_ predicate: NSPredicate) -> NSFetchRequest<Airport> {
        let request = NSFetchRequest<Airport>(entityName: "Airport")
        request.sortDescriptors = [NSSortDescriptor(key: "location", ascending: true)]
        request.predicate = predicate
        return request
    }
}

extension Airport {
    func fetchEncomingFlights() {
        Self.flightAwareRequest?.stopFetching()
        if let context = managedObjectContext {
            Self.flightAwareRequest = EnrouteRequest.create(airport: icao, howMany: 120)
            Self.flightAwareRequest?.fetch(andRepeatEvery: 10)
            Self.flightAwareResultsCancellable = Self.flightAwareRequest?.results.sink { results in
                for faflight in results {
                    Flight.update(from: faflight, in: context)
                }
                do {
                    try context.save()
                } catch(let error) {
                    print("Não foi possivel salvar o vôo atualizando CoreData: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private static var flightAwareRequest: EnrouteRequest!
    private static var flightAwareResultsCancellable: AnyCancellable?
}
