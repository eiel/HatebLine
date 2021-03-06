//
//  TimelineViewController.swift
//  HatebLine
//
//  Created by 北䑓 如法 on 16/1/8.
//  Copyright © 2016年 北䑓 如法. All rights reserved.
//

import Cocoa
import Alamofire
import AwesomeCache
import Question

class TimelineViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSUserNotificationCenterDelegate {

    var parser: RSSParser!
    var parserOfMyFeed: RSSParser!
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet var bookmarkArrayController: NSArrayController!
    var bookmarks = NSMutableArray()
    var timer = Timer()
    var heightCache: Cache<NSNumber>? = { () -> Cache<NSNumber>? in
        var cache: Cache<NSNumber>
        do {
            cache = try Cache<NSNumber>(name: "heightCache")
        } catch _ {
            print("Something went wrong :(")
            return nil
        }
        return cache
    }()
    
    lazy var managedObjectContext: NSManagedObjectContext = {
        return (NSApplication.shared().delegate
            as? AppDelegate)?.managedObjectContext }()!    
    
    var sortDescriptors:[NSSortDescriptor] = [NSSortDescriptor(key: "date", ascending: false)]
    
    func favoriteUrl() -> URL? {
        guard let hatenaID = UserDefaults.standard.value(forKey: "hatenaID") as? String else {
            performSegue(withIdentifier: "ShowAccountSetting", sender: self)
            return nil
        }
        guard let url = URL(string: "http://b.hatena.ne.jp/\(hatenaID)/favorite.rss") else { return nil }
        //NSURL(string: "file:///tmp/favorite.rss")
        return url
    }

    func myFeedUrl() -> URL? {
        guard let hatenaID = UserDefaults.standard.value(forKey: "hatenaID") as? String else {
            performSegue(withIdentifier: "ShowAccountSetting", sender: self)
            return nil
        }
        guard let url = URL(string: "http://b.hatena.ne.jp/\(hatenaID)/rss") else { return nil }
        return url
    }

    func setup() {
        //QuestionBookmarkManager.sharedManager().setConsumerKey("ov8uPcRifosmAg==", consumerSecret: "/AMycQm6+fNeEFtvl1GPMWsKEFI=")
        guard let url = favoriteUrl() else { return }
        parser = RSSParser(url: url)
        guard let myUrl = myFeedUrl() else { return }
        parserOfMyFeed = RSSParser(url: myUrl)
        NSUserNotificationCenter.default.delegate = self
        timer = Timer(timeInterval: 60, target: self, selector: #selector(TimelineViewController.updateData), userInfo: nil, repeats: true)
        let runLoop = RunLoop.current
        runLoop.add(timer, forMode: RunLoopMode.commonModes)
    }
    
    func perform() {
        guard let url = favoriteUrl() else { return }
        parser.feedUrl = url
        DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.background).async(execute: {
            self.parser.parse(completionHandler: { items in
                self.mergeBookmarks(items)

                guard let url = self.myFeedUrl() else { return }
                self.parserOfMyFeed.feedUrl = url
                DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.background).async(execute: {
                    self.parserOfMyFeed.parse(completionHandler: { items in
                        self.mergeBookmarks(items)
                    })
                })
                
            })
        })
    }
    
    func mergeBookmarks(_ items: [[String: Any]]) {
        let moc = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        moc.parent = managedObjectContext
        moc.perform {
            var newBookmarks = [Bookmark]()
            for item in items.reversed() {
                guard let bookmarkUrl = item["bookmarkUrl"] as? String else { continue }
                let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Bookmark")
                request.predicate = NSPredicate(format: "bookmarkUrl == %@", bookmarkUrl)
                do {
                    let fetchedBookmarks = try moc.fetch(request) as! [Bookmark]
                    if (fetchedBookmarks.count > 0) { // exists, so update
                        let b = fetchedBookmarks.first! as Bookmark
                        if let cache = self.heightCache, let u = b.bookmarkUrl {
                            cache[u] = nil
                        }
                        if let count = item["count"] as? String, let bcount = b.page?.count {
                            if let n = Int(count), n != Int(bcount) {
                                b.page?.count = NSNumber(value: n)
                            }
                        }
                        if let comment = item["comment"] as? String {
                            if comment != b.comment {
                                b.comment = comment
                            }
                        }
                        let tags = NSMutableSet()
                        guard let tagsArray = item["tags"] as? [String] else { continue }
                        for tagString in tagsArray {
                            let tag = Tag.name(tagString, inManagedObjectContext: moc)
                            tags.add(tag)
                        }
                        b.setValue(tags, forKey: "tags")
                    } else { // does not exsist, so create
                        let bmEntity = NSEntityDescription.entity(forEntityName: "Bookmark", in: moc)
                        let bookmark = NSManagedObject(entity: bmEntity!, insertInto: moc) as! Bookmark
                        var user: NSManagedObject?
                        var page: NSManagedObject?
                        
                        let usersFetch = NSFetchRequest<NSFetchRequestResult>(entityName: "User")
                        if let creator = item["creator"] as? String {
                            usersFetch.predicate = NSPredicate(format: "name == %@", creator)
                            do {
                                let fetchedUsers = try moc.fetch(usersFetch) as! [User]
                                if (fetchedUsers.count > 0) {
                                    user = fetchedUsers.first!
                                } else {
                                    let entity = NSEntityDescription.entity(forEntityName: "User", in: moc)
                                    user = NSManagedObject(entity: entity!, insertInto: moc)
                                    user?.setValue(creator, forKey: "name")
                                }
                            } catch {
                                fatalError("Failed to fetch users: \(error)")
                            }
                        }
                        let pagesFetch = NSFetchRequest<NSFetchRequestResult>(entityName: "Page")
                        if let url = item["link"] as? String {
                            pagesFetch.predicate = NSPredicate(format: "url == %@", url)
                            do {
                                let fetchedPages = try moc.fetch(pagesFetch) as! [Page]
                                if (fetchedPages.count > 0) {
                                    page = fetchedPages.first!
                                } else {
                                    let entity = NSEntityDescription.entity(forEntityName: "Page", in: moc)
                                    page = NSManagedObject(entity: entity!, insertInto: moc)
                                    page?.setValue(url, forKey: "url")
                                    if let b = item["title"] as? String { page?.setValue(b, forKey: "title") }
                                    if let b = item["count"] as? String {
                                        if let n = Int(b) { page?.setValue(n, forKey: "count") }
                                    }
                                    if let b = item["content"] as? String {
                                        if b != "" {
                                            page?.setValue(b, forKey: "content")
                                        }
                                    }
                                }
                            } catch {
                                fatalError("Failed to fetch pages: \(error)")
                            }
                        }
                        
                        bookmark.setValue(user, forKey: "user")
                        bookmark.setValue(page, forKey: "page")
                        if let b = item["bookmarkUrl"] as? String {
                            bookmark.setValue(b, forKey: "bookmarkUrl")
                        }
                        if let b = item["date"] as? String {
                            let dateFormatter = DateFormatter()
                            let locale = Locale(identifier: "en_US_POSIX")
                            dateFormatter.locale = locale
                            dateFormatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ssZ"
                            dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
                            let date = dateFormatter.date(from: b)
                            bookmark.setValue(date, forKey: "date")
                        }
                        if let b = item["comment"] as? String {
                            if b != "" {
                                bookmark.setValue(b, forKey: "comment")
                            }
                        }
                        let tags = NSMutableSet()
                        for tagString in item["tags"] as! [String] {
                            let tag = Tag.name(tagString, inManagedObjectContext: moc)
                            tags.add(tag)
                        }
                        bookmark.setValue(tags, forKey: "tags")
                        
                        newBookmarks.append(bookmark)
                    }
                } catch {
                    fatalError("Failed to fetch bookmarks: \(error)")
                }
                
            }
            if moc.hasChanges {
                do {
                    try moc.save()
                    self.managedObjectContext.performAndWait {
                    if let enabled = UserDefaults.standard.value(forKey: "enableNotification") as? Bool, enabled {
                        self.notififyNewObjects(newBookmarks)
                    }
                    }
                } catch {
                    fatalError("Failure to save context: \(error)")
                }
            }
            self.managedObjectContext.perform {
                do {
                    try self.managedObjectContext.save()
                } catch {
                    fatalError("Failure to save main context: \(error)")
                }
            }
        }
    }

    func notififyNewObjects(_ bookmarks: [Bookmark]) {
        for bookmark: Bookmark in bookmarks {
            let notification = NSUserNotification()
            if let creator = bookmark.user?.name {
                notification.title = "\(creator) がブックマークを追加しました"
            }
            var commentString = ""
            if let comment = bookmark.comment {
                commentString = comment
            }
            if let title = bookmark.page?.title, let count = bookmark.page?.count {
                let separator = commentString == "" ? "" : " / "
                var countString = ""
                if let enabled = UserDefaults.standard.value(forKey: "includeBookmarkCount") as? Bool, enabled {
                    countString = "(\(count)) "
                }
                notification.informativeText = "\(countString)\(commentString)\(separator)\(title)"
            }
//            notification.contentImage = bookmark.user?.profileImage
            if let url = bookmark.bookmarkUrl {
                notification.userInfo = ["bookmarkUrl": url]
            }
            NSUserNotificationCenter.default.deliver(notification)
        }
    }
    
    @IBAction func reload(_ sender: AnyObject) {
        perform()
    }
    
    @IBAction func openInBrowser(_ sender: AnyObject) {
        let array = bookmarkArrayController.selectedObjects as! [Bookmark]
        if array.count > 0 {
            if let bookmark = array.first, let urlString = bookmark.page?.url, let url = URL(string: urlString) {
                NSWorkspace.shared().open(url)
            }
        }
    }

    @IBAction override func quickLookPreviewItems(_ sender: Any?) {
        let indexes = tableView.selectedRowIndexes
        if (indexes.count > 0) {
            performSegue(withIdentifier: "QuickLook", sender: self)
        }
    }

    @IBAction func openBookmarkPageInBrowser(_ sender: AnyObject) {
        let array = bookmarkArrayController.selectedObjects as! [Bookmark]
        if array.count > 0 {
            if let bookmark = array.first, let urlString = bookmark.page?.url, let url = URL(string: "http://b.hatena.ne.jp/entry/\(urlString)") {
                NSWorkspace.shared().open(url)
            }
        }
    }

    @IBAction func openUserPageInBrowser(_ sender: AnyObject) {
        let array = bookmarkArrayController.selectedObjects as! [Bookmark]
        if array.count > 0 {
            if let bookmark = array.first, let name = bookmark.user?.name, let url = URL(string: "http://b.hatena.ne.jp/\(name)/") {
                NSWorkspace.shared().open(url)
            }
        }
    }

    @IBAction func updateSearchString(_ sender: AnyObject) {
        if sender is NSSearchField {
            let field = sender as! NSSearchField
            let s = field.stringValue
            bookmarkArrayController.filterPredicate = { () -> NSPredicate? in
                if s == "" {
                    return nil
                } else {
                    return NSPredicate(format: "(page.title contains[c] %@) OR (comment contains[c] %@) OR (user.name contains[c] %@)", s, s, s)
                }
            }()
        }
    }
    
    @IBAction func showComments(_ sender: AnyObject) {
        let indexes = tableView.selectedRowIndexes
        if (indexes.count > 0) {
            performSegue(withIdentifier: "ShowComments", sender: self)
        }
    }
    
    @IBAction func showSharingServicePicker(_ sender: AnyObject) {
        if sender is NSView {
            if let array = bookmarkArrayController.selectedObjects as? [Bookmark] {
                if array.count > 0 {
                    if let bookmark = array.first, let title = bookmark.page?.title, let url = URL(string: bookmark.page?.url ?? "") {
                        let sharingServicePicker = NSSharingServicePicker(items: [title, url])
                        sharingServicePicker.show(relativeTo: sender.bounds, of: sender as! NSView, preferredEdge: NSRectEdge.minY)
                    }
                }
            }
        }
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let identifier = segue.identifier {
            switch identifier {
            case "QuickLook":
                if segue.isKind(of: TablePopoverSegue.self) {
                    let popoverSegue = segue as! TablePopoverSegue
                    popoverSegue.preferredEdge = NSRectEdge.maxX
                    popoverSegue.popoverBehavior = .transient
                    popoverSegue.anchorTableView = tableView
                let indexes = tableView.selectedRowIndexes
                if (indexes.count > 0) {
                    if let objects = bookmarkArrayController.arrangedObjects as? [AnyObject], let bookmark = objects[indexes.first!] as? Bookmark {
                        let vc = segue.destinationController as? QuickLookWebViewController
                        vc?.representedObject = bookmark.page?.url
                    }
                }
                }
            case "ShowComments":
                if segue.isKind(of: TablePopoverSegue.self) {
                    let popoverSegue = segue as! TablePopoverSegue
                    popoverSegue.preferredEdge = NSRectEdge.maxX
                    popoverSegue.popoverBehavior = .transient
                    popoverSegue.anchorTableView = tableView
                    let indexes = tableView.selectedRowIndexes
                    if (indexes.count > 0) {
                        if let objects = bookmarkArrayController.arrangedObjects as? [AnyObject], let bookmark = objects[indexes.first!] as? Bookmark {
                            let vc = segue.destinationController as? CommentsViewController
                            vc?.representedObject = bookmark.page?.url
                        }
                    }
                }
            case "ShowAccountSetting":
                break
            default:
                break
            }
            
        }
    }
    
    func refresh() {
        tableView.reloadData()
    }

    func updateData() {
        reload(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        setup()
        perform()
    }
    
/*
    // MARK: - TableView
    func numberOfRowsInTableView(tableView: NSTableView) -> Int {
        return bookmarks.count
    }
    
    func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableColumn?.identifier == "Bookmark" {
            if let cell = tableView.makeViewWithIdentifier("Bookmark", owner: self) as! BookmarkCellView? {
                let bookmark = bookmarks[row] as! NSMutableDictionary
                let username = bookmark["creator"] as! String
                cell.textField?.stringValue = username
                var com = bookmark["comment"] as! String
                if com != "" { com += "\n" }
                cell.titleTextField?.stringValue = "\(com)\(bookmark["title"] as! String)"
                cell.countTextField?.stringValue = "\(bookmark["count"] as! String) users"
                
                let dateFormatter = NSDateFormatter()
                let locale = NSLocale(localeIdentifier: "en_US_POSIX")
                dateFormatter.locale = locale
                dateFormatter.dateFormat = "yyyy'-'MM'-'dd'T'HH':'mm':'ssZ"
                dateFormatter.timeZone = NSTimeZone(forSecondsFromGMT: 0)
                //                let date = dateFormatter.dateFromString(bookmark["date"] as! String)
                
                cell.dateTextField?.stringValue = bookmark["date"] as! String
                
                let twoLetters = (username as NSString).substringToIndex(2)
                Alamofire.request(.GET, "http://cdn1.www.st-hatena.com/users/\(twoLetters)/\(username)/profile.gif")
                    .responseImage { response in
                        if let image = response.result.value {
                            cell.imageView?.wantsLayer = true
                            cell.imageView?.layer?.cornerRadius = 5.0
                            cell.imageView?.image = image
                        }
                }
                return cell
            }
        }
        return nil
    }
   */
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        var heightOfRow: CGFloat = 48
        guard let array = bookmarkArrayController.arrangedObjects as? NSArray, let bookmark = array[row] as? Bookmark else {
            return heightOfRow
        }
        guard let cache = heightCache else {
            return heightOfRow
        }
        if let u = bookmark.bookmarkUrl, let height = cache[u] {
            return CGFloat(height)
        }
        if let cell = tableView.make(withIdentifier: "Bookmark", owner: self) as! BookmarkCellView? {
            tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integer: row))
            let size = NSMakeSize(tableView.tableColumns[0].width, 43.0);
//            if let username = bookmark.user?.name {
//                cell.textField?.stringValue = username
//            }
            if let comment = bookmark.commentWithTags {
                cell.commentTextField?.attributedStringValue = comment
                cell.commentTextField?.preferredMaxLayoutWidth = size.width - (5+8+3+48)
            }
            if let title = bookmark.page?.title {
                cell.titleTextField?.stringValue = title
                // FIXME: temporarily, minus titleTextField's paddings
                cell.titleTextField?.preferredMaxLayoutWidth = size.width - (5+8+3+48+16)
            }
            // cell.countTextField?.stringValue = "\(bookmark.count) users"
//            cell.needsLayout = true
//            cell.layoutSubtreeIfNeeded()
//            NSAnimationContext.beginGrouping()
//            NSAnimationContext.currentContext().duration = 0.0
            heightOfRow = cell.fittingSize.height
//            NSAnimationContext.endGrouping()
            if let u = bookmark.bookmarkUrl {
                cache[u] = NSNumber(value: Float(heightOfRow) as Float)
            }
        }
        return heightOfRow < 48 ? 48 : heightOfRow
    }

    func tableView(_ tableView: NSTableView, willDisplayCell cell: Any, for tableColumn: NSTableColumn?, row: Int) {
        if let c = cell as? NSTableRowView {
        if (tableView.selectedRowIndexes.contains(row)) {
            c.backgroundColor = NSColor.yellow
        } else {
            c.backgroundColor = NSColor.white
        }
//        c.drawsBackground = true
        }
    }

    func tableView(_ tableView: NSTableView, shouldTypeSelectFor event: NSEvent, withCurrentSearch searchString: String?) -> Bool {
        print(event.keyCode)
        return true
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        if let tv = notification.object as? NSTableView {
            (view.window?.windowController as? MainWindowController)?.changeTabbarItemsWithState(tv.selectedRow >= 0)
        }
    }

    
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        if let info = notification.userInfo as? [String:String] {
            if let bookmarkUrl = info["bookmarkUrl"] {
                let moc = managedObjectContext
                do {
                    let request = NSFetchRequest<NSFetchRequestResult>(entityName: "Bookmark")
                    request.predicate = NSPredicate(format: "bookmarkUrl == %@", bookmarkUrl)
                    let results = try moc.fetch(request) as! [Bookmark]
                    if (results.count > 0) {
                        bookmarkArrayController.setSelectedObjects(results)
                        NSAnimationContext.runAnimationGroup({ context in
                            context.allowsImplicitAnimation = true
                            self.tableView.scrollRowToVisible(self.tableView.selectedRow)
                            }, completionHandler: nil)
                    }
                } catch {
                    fatalError("Failure: \(error)")
                }
            }

        }
    }

}
