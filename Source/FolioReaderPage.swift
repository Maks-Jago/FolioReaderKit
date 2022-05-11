//
//  FolioReaderPage.swift
//  FolioReaderKit
//
//  Created by Heberti Almeida on 10/04/15.
//  Copyright (c) 2015 Folio Reader. All rights reserved.
//

import UIKit
import SafariServices
import MenuItemKit
import WebKit

/// Protocol which is used from `FolioReaderPage`s.
@objc public protocol FolioReaderPageDelegate: class {

    /**
     Notify that the page will be loaded. Note: The webview content itself is already loaded at this moment. But some java script operations like the adding of class based on click listeners will happen right after this method. If you want to perform custom java script before this happens this method is the right choice. If you want to modify the html content (and not run java script) you have to use `htmlContentForPage()` from the `FolioReaderCenterDelegate`.

     - parameter page: The loaded page
     */
    @objc optional func pageWillLoad(_ page: FolioReaderPage)

    /**
     Notifies that page did load. A page load doesn't mean that this page is displayed right away, use `pageDidAppear` to get informed about the appearance of a page.

     - parameter page: The loaded page
     */
    @objc optional func pageDidLoad(_ page: FolioReaderPage, height: CGFloat)
    
    /**
     Notifies that page receive tap gesture.
     
     - parameter recognizer: The tap recognizer
     */
    @objc optional func pageTap(_ recognizer: UITapGestureRecognizer)
}

open class FolioReaderPage: UICollectionViewCell, WKNavigationDelegate, WKUIDelegate, UIGestureRecognizerDelegate {
    weak var delegate: FolioReaderPageDelegate?
    weak var readerContainer: FolioReaderContainer?

    /// The index of the current page. Note: The index start at 1!
    open var pageNumber: Int!
    open var webView: FolioReaderWebView?

    fileprivate var colorView: UIView!
    fileprivate var shouldShowBar = true
    fileprivate var menuIsVisible = false
    var scrollDirection: ScrollDirection = .up
    private var firstLoading: Bool = true
    public var currentHTMLFileURL: URL? = nil
    
    fileprivate var readerConfig: FolioReaderConfig {
        guard let readerContainer = readerContainer else { return FolioReaderConfig() }
        return readerContainer.readerConfig
    }

    fileprivate var book: FRBook {
        guard let readerContainer = readerContainer else { return FRBook() }
        return readerContainer.book
    }

    fileprivate var folioReader: FolioReader {
        guard let readerContainer = readerContainer else { return FolioReader() }
        return readerContainer.folioReader
    }

    // MARK: - View life cicle
    
    public override init(frame: CGRect) {
        // Init explicit attributes with a default value. The `setup` function MUST be called to configure the current object with valid attributes.
        self.readerContainer = FolioReaderContainer(withConfig: FolioReaderConfig(), folioReader: FolioReader(), epubPath: "", dataDecryptor: { $0 })
        super.init(frame: frame)
        self.backgroundColor = UIColor.clear

        NotificationCenter.default.addObserver(self, selector: #selector(refreshPageMode), name: NSNotification.Name(rawValue: "needRefreshPageMode"), object: nil)
    }

    public func setup(withReaderContainer readerContainer: FolioReaderContainer) {
        self.readerContainer = readerContainer
        guard let readerContainer = self.readerContainer else { return }

        if webView == nil {
            webView = FolioReaderWebView(frame: webViewFrame(), readerContainer: readerContainer)
            webView?.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            webView?.scrollView.showsVerticalScrollIndicator = false
            webView?.scrollView.showsHorizontalScrollIndicator = false
            webView?.backgroundColor = .clear
            webView?.uiDelegate = self
            self.contentView.addSubview(webView!)
        }
        
        webView?.navigationDelegate = self

        if colorView == nil {
            colorView = UIView()
            colorView.backgroundColor = folioReader.isNight(self.readerConfig.nightModeBackground, self.readerConfig.daysModeBackground) //self.readerConfig.nightModeBackground
            webView?.scrollView.addSubview(colorView)
        }

        // Remove all gestures before adding new one
        webView?.gestureRecognizers?.forEach({ gesture in
            webView?.removeGestureRecognizer(gesture)
        })
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTapGesture(_:)))
        tapGestureRecognizer.numberOfTapsRequired = 1
        tapGestureRecognizer.delegate = self
        webView?.addGestureRecognizer(tapGestureRecognizer)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("storyboards are incompatible with truth and beauty")
    }

    deinit {
        webView?.scrollView.delegate = nil
        webView?.navigationDelegate = nil
        NotificationCenter.default.removeObserver(self)
    }

    override open func layoutSubviews() {
        super.layoutSubviews()

        webView?.setupScrollDirection()
        webView?.frame = webViewFrame()
    }

    func webViewFrame() -> CGRect {
        guard (self.readerConfig.hideBars == false) else {
            return bounds
        }

        let statusbarHeight = UIApplication.shared.statusBarFrame.size.height
        let navBarHeight = self.folioReader.readerCenter?.navigationController?.navigationBar.frame.size.height ?? CGFloat(0)
        let navTotal = self.readerConfig.shouldHideNavigationOnTap ? 0 : statusbarHeight + navBarHeight
        
        return CGRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: self.readerConfig.isDirection(bounds.height, bounds.height /*- navTotal - paddingBottom*/, bounds.height - navTotal)
        )
    }

    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    func loadHTMLString(fromFile fileURL: URL!, baseURL: URL!) {
        guard currentHTMLFileURL != fileURL else {
            return
        }
        
        currentHTMLFileURL = fileURL
        webView?.alpha = 0
        webView?.loadFileURL(fileURL, allowingReadAccessTo: baseURL)
    }

    // MARK: - WKWebView Delegate
        
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        contentDidLoad()
    }
    
    func contentDidLoad() {
        delegate?.pageWillLoad?(self)
        
        // Add the custom class based onClick listener
        self.setupClassBasedOnClickListeners()
        
        refreshPageMode()
        
        if self.readerConfig.enableTTS && !self.book.hasAudio {
            //WebViewMigration:
            webView?.js("wrappingSentencesWithinPTags()") { _ in }
            
            if let audioPlayer = self.folioReader.readerAudioPlayer, (audioPlayer.isPlaying() == true) {
                audioPlayer.readCurrentSentence()
            }
        }
        
        var needScrollToBottom = false
        if scrollDirection == .down && folioReader.readerCenter?.isScrolling == true {
            needScrollToBottom = true
        } else if scrollDirection == .right, folioReader.readerCenter?.recentlyScrolled == true {
            needScrollToBottom = true
        }
        
        UIView.animate(withDuration: 0.2, animations: {self.webView?.alpha = 1}, completion: { finished in
            self.webView?.isColors = false
            self.webView?.createMenu(options: false)
        })
        
        self.webView?.js("document.body.scrollHeight") { [weak self] result in
            let height = (result as? CGFloat) ?? 0
            
            if needScrollToBottom {
                self?.scrollPageToBottom()
            }
            
            if let `self` = self {
                self.delegate?.pageDidLoad?(self, height: height)
            }
        }
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard
            let webView = webView as? FolioReaderWebView,
            let scheme = navigationAction.request.url?.scheme else {
                decisionHandler(.allow)
                return
        }
        
        guard let url = navigationAction.request.url else { return decisionHandler(.allow) }

        if scheme == "highlight" || scheme == "highlight-with-note" {
            shouldShowBar = false

            guard let decoded = url.absoluteString.removingPercentEncoding else {
                decisionHandler(.allow)
                return
            }
            let index = decoded.index(decoded.startIndex, offsetBy: 12)
            let rect = NSCoder.cgRect(for: String(decoded[index...]))

            webView.createMenu(options: true)
            webView.setMenuVisible(true, andRect: rect)
            menuIsVisible = true

            decisionHandler(.allow)
            return
        } else if scheme == "play-audio" {
            guard let decoded = url.absoluteString.removingPercentEncoding else {
                decisionHandler(.allow)
                return
            }
            let index = decoded.index(decoded.startIndex, offsetBy: 13)
            let playID = String(decoded[index...])
            let chapter = self.folioReader.readerCenter?.getCurrentChapter()
            let href = chapter?.href ?? ""
            self.folioReader.readerAudioPlayer?.playAudio(href, fragmentID: playID)

            decisionHandler(.allow)
            return
        } else if (scheme == "file" || scheme == URLScheme.localFile.rawValue) {

            let anchorFromURL = url.fragment

            // Handle internal url
            if !url.pathExtension.isEmpty {
                let pathComponent = (self.book.opfResource.href as NSString?)?.deletingLastPathComponent
                guard let base = ((pathComponent == nil || pathComponent?.isEmpty == true) ? self.book.name : pathComponent) else {
                    decisionHandler(.allow)
                    return
                }

                let path = url.path
                let splitedPath = path.components(separatedBy: base)

                 
                // Return to avoid crash
//                 if (splitedPath.count <= 1 || splitedPath[1].isEmpty) {
//                    decisionHandler(.allow)
//                    return
//                }

                guard let href = splitedPath.last?.trimmingCharacters(in: CharacterSet(charactersIn: "/")) else {
                    decisionHandler(.allow)
                    return
                }
                
//                let href = splitedPath[1].trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let hrefPage = (self.folioReader.readerCenter?.findPageByHref(href.lastPathComponent) ?? 0) + 1

                if (hrefPage == pageNumber) {
                    // Handle internal #anchor
                    if anchorFromURL != nil {
                        handleAnchor(anchorFromURL!, avoidBeginningAnchors: false, animated: true)
                        decisionHandler(.allow)
                        return
                    }
                } else {
                    self.folioReader.readerCenter?.changePageWith(href: href, animated: true) { [weak self] in
                        if let anchorFromURL = anchorFromURL {
                            self?.handleAnchor(anchorFromURL, avoidBeginningAnchors: false, animated: true)
                        }
                    }
                }
                decisionHandler(.allow)
                return
            }

            // Handle internal #anchor
            if anchorFromURL != nil {
                handleAnchor(anchorFromURL!, avoidBeginningAnchors: false, animated: true)
                decisionHandler(.allow)
                return
            }

            decisionHandler(.allow)
            return
        } else if scheme == "mailto" {
            print("Email")
            decisionHandler(.allow)
            return
        } else if url.absoluteString != "about:blank" && scheme.contains("http") && navigationAction.navigationType == .linkActivated {
            let safariVC = SFSafariViewController(url: url)
            safariVC.view.tintColor = self.readerConfig.tintColor
            self.folioReader.readerCenter?.present(safariVC, animated: true, completion: nil)
            decisionHandler(.allow)
            return
        } else {
            // Check if the url is a custom class based onClick listerner
            let absoluteURLString = url.absoluteString
            var isClassBasedOnClickListenerScheme = false
            for listener in self.readerConfig.classBasedOnClickListeners {
                
                if scheme == listener.schemeName,
                    let range = absoluteURLString.range(of: "/clientX=") {
                    let baseURL = String(absoluteURLString[..<range.lowerBound])
                    let positionString = String(absoluteURLString[range.lowerBound...])
                    if let point = getEventTouchPoint(fromPositionParameterString: positionString) {
                        let attributeContentString = (baseURL.replacingOccurrences(of: "\(scheme)://", with: "").removingPercentEncoding)
                        // Call the on click action block
                        listener.onClickAction(attributeContentString, point)
                        // Mark the scheme as class based click listener scheme
                        isClassBasedOnClickListenerScheme = true
                    }
                }
            }

            if isClassBasedOnClickListenerScheme == false {
                // Try to open the url with the system if it wasn't a custom class based click listener
                if UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.openURL(url)
                    decisionHandler(.allow)
                    return
                }
            } else {
                decisionHandler(.allow)
                return
            }
        }

        decisionHandler(.allow)
        return
    }

    fileprivate func getEventTouchPoint(fromPositionParameterString positionParameterString: String) -> CGPoint? {
        // Remove the parameter names: "/clientX=188&clientY=292" -> "188&292"
        var positionParameterString = positionParameterString.replacingOccurrences(of: "/clientX=", with: "")
        positionParameterString = positionParameterString.replacingOccurrences(of: "clientY=", with: "")
        // Separate both position values into an array: "188&292" -> [188],[292]
        let positionStringValues = positionParameterString.components(separatedBy: "&")
        // Multiply the raw positions with the screen scale and return them as CGPoint
        if
            positionStringValues.count == 2,
            let xPos = Int(positionStringValues[0]),
            let yPos = Int(positionStringValues[1]) {
            return CGPoint(x: xPos, y: yPos)
        }
        return nil
    }

    // MARK: Gesture recognizer

    open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer.view is FolioReaderWebView {
            if otherGestureRecognizer is UILongPressGestureRecognizer {
                if UIMenuController.shared.isMenuVisible {
                    webView?.setMenuVisible(false)
                }
                return false
            }
            return true
        }
        return false
    }
    
    @objc open func handleTapGesture(_ recognizer: UITapGestureRecognizer) {
        self.delegate?.pageTap?(recognizer)
        
        if let _navigationController = self.folioReader.readerCenter?.navigationController, (_navigationController.isNavigationBarHidden == true) {
            //WebViewMigration:
            webView?.js("getSelectedText()", completion: { res in
                let selected = res as? String
                
                guard (selected == nil || selected?.isEmpty == true) else {
                    return
                }
                
                let delay = 0.4 * Double(NSEC_PER_SEC) // 0.4 seconds * nanoseconds per seconds
                let dispatchTime = (DispatchTime.now() + (Double(Int64(delay)) / Double(NSEC_PER_SEC)))
                
                DispatchQueue.main.asyncAfter(deadline: dispatchTime, execute: {
                    if (self.shouldShowBar == true && self.menuIsVisible == false) {
                        self.folioReader.readerCenter?.toggleBars()
                    }
                })
            })
            
        } else if (self.readerConfig.shouldHideNavigationOnTap == true) {
            self.folioReader.readerCenter?.hideBars()
            self.menuIsVisible = false
        }
    }

    // MARK: - Public scroll postion setter

    /**
     Scrolls the page to a given offset

     - parameter offset:   The offset to scroll
     - parameter animated: Enable or not scrolling animation
     */
    open func scrollPageToOffset(_ offset: CGFloat, animated: Bool) {
        let pageOffsetPoint = self.readerConfig.isDirection(CGPoint(x: 0, y: offset), CGPoint(x: offset, y: 0), CGPoint(x: 0, y: offset))
        webView?.scrollView.setContentOffset(pageOffsetPoint, animated: animated)
    }

    /**
     Scrolls the page to bottom
     */
        
    open func scrollPageToBottom() {
        //WebViewMigration: disable scroll
        guard let webView = webView else { return }
        
        var bottomOffset: CGPoint = .zero
        if scrollDirection == .down {
            bottomOffset = CGPoint(x: 0, y: webView.scrollView.contentSize.height - webView.scrollView.bounds.height)
        } else {
            bottomOffset = CGPoint(x: webView.scrollView.contentSize.width - webView.scrollView.bounds.width, y: 0)
        }
        
        if bottomOffset.forDirection(withConfiguration: self.readerConfig) >= 0 {
            DispatchQueue.main.async {
                self.webView?.scrollView.setContentOffset(bottomOffset, animated: false)
            }
        }
        
//        guard let webView = webView else { return }
//
//        var bottomOffset: CGPoint = .zero
//        if scrollDirection == .down {
//            let y = (superview as? UICollectionView)?.contentOffset.y ?? 0
//            let superHeight = (superview as? UICollectionView)?.bounds.height ?? 0
//            bottomOffset = CGPoint(x: 0, y: y + self.bounds.height - superHeight) //webView.scrollView.contentSize.height - webView.scrollView.bounds.height)
//        } else {
//            bottomOffset = CGPoint(x: webView.scrollView.contentSize.width - webView.scrollView.bounds.width, y: 0)
//        }
//
//        if bottomOffset.forDirection(withConfiguration: self.readerConfig) >= 0 {
//            DispatchQueue.main.async {
//                (self.superview as? UICollectionView)?.setContentOffset(bottomOffset, animated: false)
//            }
//        }
    }

    /**
     Handdle #anchors in html, get the offset and scroll to it

     - parameter anchor:                The #anchor
     - parameter avoidBeginningAnchors: Sometimes the anchor is on the beggining of the text, there is not need to scroll
     - parameter animated:              Enable or not scrolling animation
     */
    open func handleAnchor(_ anchor: String,  avoidBeginningAnchors: Bool, animated: Bool) {
        if !anchor.isEmpty {
            getAnchorOffset(anchor) { [weak self] offset in
                guard let `self` = self else {
                    return
                }
                
                switch self.readerConfig.scrollDirection {
                case .vertical, .defaultVertical:
                    let isBeginning = (offset < self.frame.forDirection(withConfiguration: self.readerConfig) * 0.5)

                    if !avoidBeginningAnchors {
                        self.scrollPageToOffset(offset, animated: animated)
                    } else if avoidBeginningAnchors && !isBeginning {
                        self.scrollPageToOffset(offset, animated: animated)
                    }
                case .horizontal, .horizontalWithVerticalContent:
                    self.scrollPageToOffset(offset, animated: animated)
                }
            }
        }
    }

    // MARK: Helper

    /**
     Get the #anchor offset in the page

     - parameter anchor: The #anchor id
     - returns: The element offset ready to scroll
     */
    func getAnchorOffset(_ anchor: String, completion: @escaping (CGFloat) -> Void) {
        //TMP: js is crashed, getElementById() return undefined and js is crashing
        completion(0)
        return
        
        let horizontal = self.readerConfig.scrollDirection == .horizontal
        
        webView?.js("getAnchorOffset(\"\(anchor)\", \(horizontal.description))", completion: { res in
            guard let strOffset = res as? String else {
                completion(0)
                return
            }
            
            completion(CGFloat((strOffset as NSString).floatValue))
        })
    }

    // MARK: Mark ID

    /**
     Audio Mark ID - marks an element with an ID with the given class and scrolls to it

     - parameter identifier: The identifier
     */
    func audioMarkID(_ identifier: String) {
        guard let currentPage = self.folioReader.readerCenter?.currentPage else {
            return
        }

        let playbackActiveClass = self.book.playbackActiveClass
        currentPage.webView?.js("audioMarkID('\(playbackActiveClass)','\(identifier)')") { _ in }
    }

    // MARK: UIMenu visibility

    override open func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard let webView = webView else { return false }

        if UIMenuController.shared.menuItems?.count == 0 {
            webView.isColors = false
            webView.createMenu(options: false)
        }

        if !webView.isShare && !webView.isColors {
            webView.js("getSelectedText()") { res in
                if let result = res as? String , result.components(separatedBy: " ").count == 1 {
                    webView.isOneWord = true
                    webView.createMenu(options: false)
                } else {
                    webView.isOneWord = false
                }
            }
        }

        return super.canPerformAction(action, withSender: sender)
    }

    // MARK: ColorView fix for horizontal layout
    @objc func refreshPageMode() {
        guard let webView = webView else { return }

        if (self.folioReader.nightMode == true) {
            // omit create webView and colorView
            let script = "document.documentElement.offsetHeight"
            //WebViewMigration:
            webView.js(script) { res in
                guard let contentHeight = res as? String else {
                    return
                }
                
                //TODO: need to find a way to get page count
//                let frameHeight = webView.frame.height
//                let lastPageHeight = frameHeight * CGFloat(webView.pageCount) - CGFloat(Double(contentHeight)!)
//                colorView.frame = CGRect(x: webView.frame.width * CGFloat(webView.pageCount-1), y: webView.frame.height - lastPageHeight, width: webView.frame.width, height: lastPageHeight)
            }
            
//            let contentHeight = webView.stringByEvaluatingJavaScript(from: script)
            
        } else {
            colorView.frame = CGRect.zero
        }
    }
    
    // MARK: - Class based click listener
    
    fileprivate func setupClassBasedOnClickListeners() {
        for listener in self.readerConfig.classBasedOnClickListeners {
            self.webView?.js("addClassBasedOnClickListener(\"\(listener.schemeName)\", \"\(listener.querySelector)\", \"\(listener.attributeName)\", \"\(listener.selectAll)\")") { _ in }
        }
    }
    
    // MARK: - Public Java Script injection
    
    /** 
     Runs a JavaScript script and returns it result. The result of running the JavaScript script passed in the script parameter, or nil if the script fails.
     
     - returns: The result of running the JavaScript script passed in the script parameter, or nil if the script fails.
     */
    open func performJavaScript(_ javaScriptCode: String, completion: @escaping (Any?) -> Void) {
        webView?.js(javaScriptCode, completion: completion)
    }
}
