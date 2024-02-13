//
//  BitcoinCoreRPC.swift
//  Pay Join
//
//  Created by Peter Denton on 2/11/24.
//

import Foundation

class BitcoinCoreRPC {
    static let shared = BitcoinCoreRPC()
    
    private init() {}
    
    func btcRPC(method: BTC_CLI_COMMAND,
                completion: @escaping ((response: Any?, errorDesc: String?)) -> Void) {
        
        let requestId = UUID().uuidString
        
        DataManager.retrieve(entityName: "Credentials") { credentials in
            guard let credentials = credentials, let rpcPassData = credentials["rpcpass"] as? Data, let rpcPass = String(data: rpcPassData, encoding: .utf8) else { return }
            
            let rpcPort = UserDefaults.standard.object(forKey: "rpcPort") as? String ?? "8332"
            let walletName = UserDefaults.standard.object(forKey: "walletName") as? String
            
            var walletUrl = "http://PayJoin:\(rpcPass)@localhost:\(rpcPort)"
            
            if let walletName = walletName {
                walletUrl += "/wallet/" + walletName
            }
            
            guard let url = URL(string: walletUrl) else {
                completion((nil, "url error"))
                return
            }
            
            var request = URLRequest(url: url)
            var timeout = 10.0
            
            switch method.stringValue {
            case "gettxoutsetinfo":
                timeout = 1000.0
                
            case "importmulti", "deriveaddresses", "loadwallet":
                timeout = 60.0
                
            default:
                break
            }
            
            let loginString = String(format: "%@:%@", "PayJoin", rpcPass)
            let loginData = loginString.data(using: String.Encoding.utf8)!
            let base64LoginString = loginData.base64EncodedString()
            request.timeoutInterval = timeout
            request.httpMethod = "POST"
            request.addValue("Basic \(base64LoginString)", forHTTPHeaderField: "Authorization")
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            
            let dict:[String:Any] = ["jsonrpc": "1.0","id": requestId,"method": method.stringValue,"params": method.paramDict]
            
            guard let jsonData = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) else {
                #if DEBUG
                print("converting to jsonData failing...")
                #endif
                return
            }
            
            request.httpBody = jsonData
            
            #if DEBUG
            print("url = \(url)")
            print("request: \(dict)")
            #endif
            
            let session = URLSession(configuration: .default)
            
            let task = session.dataTask(with: request as URLRequest) { (data, response, error) in
                guard let urlContent = data else {
                    guard let error = error else {
                        completion((nil, "Unknown error."))
                        return
                    }
                    completion((nil, error.localizedDescription))
                    return
                }
                
                guard let json = try? JSONSerialization.jsonObject(with: urlContent, options: .mutableLeaves) as? NSDictionary else {
                    if let httpResponse = response as? HTTPURLResponse {
                        switch httpResponse.statusCode {
                        case 401:
                            completion((nil, "Looks like your rpc credentials are incorrect, please double check them. If you changed your rpc creds in your bitcoin.conf you need to restart your node for the changes to take effect."))
                        case 403:
                            completion((nil, "The bitcoin-cli \(method) command has not been added to your rpcwhitelist, add \(method) to your bitcoin.conf rpcwhitelsist, reboot Bitcoin Core and try again."))
                        default:
                            completion((nil, "Unable to decode the response from your node, http status code: \(httpResponse.statusCode)"))
                        }
                    } else {
                        completion((nil, "Unable to decode the response from your node..."))
                    }
                    return
                }
                
                #if DEBUG
                print("json: \(json)")
                #endif
                
                guard let errorCheck = json["error"] as? NSDictionary else {
                    completion((json["result"], nil))
                    return
                }
                
                guard let errorMessage = errorCheck["message"] as? String else {
                    completion((nil, "Uknown error from bitcoind"))
                    return
                }
                
                completion((nil, errorMessage))
            }
            
            task.resume()
        }        
    }
}
