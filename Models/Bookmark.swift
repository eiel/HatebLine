//
//  Bookmark.swift
//  HatebLine
//
//  Created by 北䑓 如法 on 16/1/11.
//  Copyright © 2016年 北䑓 如法. All rights reserved.
//

import Foundation
import CoreData
import Cocoa

class Bookmark: NSManagedObject {

    var commentWithTags: NSAttributedString? {
        let stringTags = tags?.flatMap { ($0 as! Tag).name ?? "" }
        return Helper.commentWithTags(comment, tags: stringTags)
    }
    
    var timeAgo: String? {
        return self.date?.timeAgo
    }

}
