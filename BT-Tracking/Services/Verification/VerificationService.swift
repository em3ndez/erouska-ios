//
//  VerificationService.swift
//  eRouska
//
//  Created by Lukáš Foldýna on 07/08/2020.
//  Copyright © 2020 Covid19CZ. All rights reserved.
//

import Foundation
import Alamofire

protocol VerificationServicing: AnyObject {

    func updateConfiguration(_ configuration: ServerConfiguration)

    typealias CodeCallback = (Result<VerificationCode, Error>) -> Void
    func requestCode(with request: VerificationCodeRequest, callback: @escaping CodeCallback)

    typealias VerifyCallback = (Result<String, Error>) -> Void
    func verify(with code: String, callback: @escaping VerifyCallback)

    typealias CertificateCallback = (Result<String, Error>) -> Void
    func requestCertificate(token: String, hmacKey: String, callback: @escaping CertificateCallback)

}

final class VerificationService: VerificationServicing {

    private var serverURL: URL
    private let headerApiKey = "X-API-Key"

    private var adminKey: String
    private var deviceKey: String

    init(configuration: ServerConfiguration) {
        serverURL = configuration.verificationURL
        adminKey = configuration.verificationAdminKey
        deviceKey = configuration.verificationDeviceKey
    }

    func updateConfiguration(_ configuration: ServerConfiguration) {
        serverURL = configuration.verificationURL
        adminKey = configuration.verificationAdminKey
        deviceKey = configuration.verificationDeviceKey
    }

    func requestCode(with request: VerificationCodeRequest, callback: @escaping CodeCallback) {
        var headers = HTTPHeaders()
        headers.add(HTTPHeader(name: headerApiKey, value: adminKey))
        // swiftlint:disable:next force_unwrapping
        AF.request(URL(string: "api/code", relativeTo: serverURL)!, method: .post, parameters: request,
                   encoder: JSONParameterEncoder.default, headers: headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: VerificationCode.self) { response in
                #if DEBUG
                debugPrint(response)
                #endif

                switch response.result {
                case .success(let result):
                    callback(.success(result))
                case .failure(let error):
                    callback(.failure(error))
                }
            }
    }

    func verify(with code: String, callback: @escaping VerifyCallback) {
        var headers = HTTPHeaders()
        headers.add(HTTPHeader(name: headerApiKey, value: deviceKey))

        let request = VerificationTokenRequest(code: code)
        // swiftlint:disable:next force_unwrapping
        AF.request(URL(string: "api/verify", relativeTo: serverURL)!, method: .post, parameters: request,
                   encoder: JSONParameterEncoder.default, headers: headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: VerificationToken.self) { response in
                #if DEBUG
                debugPrint(response)
                #endif

                switch response.result {
                case .success(let result):
                    if let token = result.token {
                        callback(.success(token))
                    } else if let error = result.error {
                        callback(.failure(VerificationError.responseError(error)))
                    } else {
                        callback(.failure(VerificationError.noData))
                    }
                case .failure(let error):
                    callback(.failure(error))
                }
            }
    }

    func requestCertificate(token: String, hmacKey: String, callback: @escaping CertificateCallback) {
        var headers = HTTPHeaders()
        headers.add(HTTPHeader(name: headerApiKey, value: deviceKey))

        let request = VerificationCertificateRequest(token: token, hmacKey: hmacKey)
        // swiftlint:disable:next force_unwrapping
        AF.request(URL(string: "api/certificate", relativeTo: serverURL)!, method: .post, parameters: request,
                   encoder: JSONParameterEncoder.default, headers: headers)
            .validate(statusCode: 200..<300)
            .responseDecodable(of: VerificationCertificate.self) { response in
                #if DEBUG
                debugPrint(response)
                #endif

                switch response.result {
                case .success(let result):
                    if let certificate = result.certificate {
                        callback(.success(certificate))
                    } else if let error = result.error {
                        callback(.failure(VerificationError.responseError(error)))
                    } else {
                        callback(.failure(VerificationError.noData))
                    }
                case .failure(let error):
                    callback(.failure(error))
                }
            }
    }

}
