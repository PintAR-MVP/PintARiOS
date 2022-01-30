//
//  API.swift
//  PintAR
//
//  Created by Niklas Amslgruber on 13.01.22.
//

import Foundation
import Combine

enum API {
	
	enum APIError: Error {
		case noResponse
		case badServerResponse(statusCode: Int)
		case decodingError(message: String)
		case encodingError
		case invalidURL
		case apiError(message: String)
	}
	
	enum HTTPMethod: String {
		case GET
		case POST
		case DELETE
		case PUT
	}
	
	private static let baseURL = "https://api.pint-ar.de/"
	
	// MARK: - SEARCH
	
	/// Search for all products that match the search query
	///
	/// Sample implementation on how to subscribe to the API and receive its `Products` or possible `APIError` codes
	///  ```
	///  API.search(with: SearchQuery(text: "sample"))
	///        .sink(receiveCompletion: { result in
	///            switch result {
	///            case .finished:
	///                print("Successfully requested search data")
	///            case .failure(let error):
	///                print("Request failed with error \(error)")
	///            }
	///        }, receiveValue: { value in
	///            print("Received \(value.matches.count) results.")
	///        })
	///        .store(in: &cancellableSet)
	/// ```
	/// - Parameter query: Filters for querying the product database
	/// - Throws: API error if something went wrong
	/// - Returns: Publisher with products
	static func search(with query: SearchQuery) -> AnyPublisher<[Product], APIError> {
		// Construct URL Request
		guard let url = constructURL(for: "search") else {
			return Fail(error: APIError.invalidURL).eraseToAnyPublisher()
		}
		var request = URLRequest(url: url)
		request.httpMethod = HTTPMethod.POST.rawValue
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		
		// Encode query as JSON to use as request body
		let jsonEncoder = JSONEncoder()
		jsonEncoder.keyEncodingStrategy = .convertToSnakeCase
		
		guard let body = try? jsonEncoder.encode(query) else {
			return Fail(error: APIError.encodingError).eraseToAnyPublisher()
		}
		
		request.httpBody = body
		
		// Request data
		return URLSession.shared.dataTaskPublisher(for: request)
			.tryMap { element -> Data in
				guard let httpResponse = element.response as? HTTPURLResponse else {
					throw APIError.noResponse
				}
				let statusCode = httpResponse.statusCode
				
				guard statusCode == 200 else {
					throw APIError.badServerResponse(statusCode: statusCode)
				}
				return element.data
			}
			.decode(type: Products.self, decoder: JSONDecoder())
			.mapError { error in
				switch error {
				case let decodingError as DecodingError:
					return APIError.decodingError(message: decodingError.localizedDescription.debugDescription)
				case let apiError as APIError:
					return apiError
				default:
					return APIError.apiError(message: error.localizedDescription.debugDescription)
				}
			}
			.map { $0.matches }
			.share()
			.eraseToAnyPublisher()
	}
	
	// MARK: - SUBMIT
	
	// COMING SOON: Wait until documentation is ready
	
	// MARK: - Helper
	
	private static func constructURL(for path: String) -> URL? {
		return URL(string: "\(baseURL)\(path)")
	}
}
