//
//  User.swift
//  HatebLine
//
//  Created by 北䑓 如法 on 16/1/11.
//  Copyright © 2016年 北䑓 如法. All rights reserved.
//

import Foundation
import CoreData
import Alamofire
import Cocoa

class User: NSManagedObject {

// Insert code here to add functionality to your managed object subclass
    var __profileImage: NSImage? = nil
    
    var profileImage: NSImage? {
        if let image = self.__profileImage {
            return image
        } else {
            if let n = name {
            let twoLetters = (n as NSString).substring(to: 2)
            if let url = URL(string: "http://cdn1.www.st-hatena.com/users/\(twoLetters)/\(n)/profile.gif") {
                Alamofire.request(url).response { response in
                    if let d = response.data {
                        self.willChangeValue(forKey: "profileImage")
                        self.__profileImage = NSImage(data: d)
                        self.didChangeValue(forKey: "profileImage")
                    }
                }
                }
            }
            return nil
        }
    }
}
