//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by sneha.s4 on 23/03/26.
//

import UIKit
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    
    private let appGroupId = "group.com.sneha.iosfinds"
    private let sharedKey = "ShareKey"
    private var didHandleShare = false

    override func viewDidLoad() {
        super.viewDidLoad()
        // Avoid flashing the extension UI while we hand off to the host app.
        view.isHidden = true
        view.alpha = 0
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        NSLog("[Share:1] viewDidAppear — didHandleShare=\(didHandleShare)")
        
        // Ensure we only handle the share once
        guard !didHandleShare else {
            NSLog("[Share:1] viewDidAppear — already handled, skipping")
            return
        }
        didHandleShare = true
        
        NSLog("[Share:1] viewDidAppear — proceeding to handleExtensionItems")
        handleExtensionItems()
    }
    
    private func handleExtensionItems() {
        NSLog("[Share:2] handleExtensionItems — inputItems count=\(extensionContext?.inputItems.count ?? -1)")
        
        guard let items = extensionContext?.inputItems as? [NSExtensionItem],
              let firstItem = items.first,
              let attachments = firstItem.attachments,
              !attachments.isEmpty else {
            NSLog("[Share:2] handleExtensionItems — GUARD FAILED: no items/attachments. Completing.")
            NSLog("[Share:2] inputItems=\(String(describing: extensionContext?.inputItems))")
            completeExtension()
            return
        }
        
        NSLog("[Share:2] handleExtensionItems — attachments count=\(attachments.count)")
        for (i, att) in attachments.enumerated() {
            NSLog("[Share:2] attachment[\(i)] registeredTypeIdentifiers=\(att.registeredTypeIdentifiers)")
        }
        
        handleSharedContent(attachments: attachments)
    }
    
    private func handleSharedContent(attachments: [NSItemProvider]) {
        NSLog("[Share:3] handleSharedContent — scanning \(attachments.count) attachment(s)")
        
        for (i, attachment) in attachments.enumerated() {
            NSLog("[Share:3] attachment[\(i)] hasURL=\(attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier)) hasText=\(attachment.hasItemConformingToTypeIdentifier(UTType.text.identifier))")
            
            // Handle URLs
            if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                NSLog("[Share:3] attachment[\(i)] — loading as URL type")
                attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (item, error) in
                    guard let self = self else { return }
                    if let error = error {
                        NSLog("[Share:3] attachment[\(i)] — loadItem URL error: \(error)")
                    }
                    NSLog("[Share:3] attachment[\(i)] — loaded item type=\(type(of: item)) value=\(String(describing: item))")
                    if let url = item as? URL {
                        NSLog("[Share:3] attachment[\(i)] — resolved as URL: \(url.absoluteString)")
                        self.saveSharedUrl(url.absoluteString)
                        self.openMainAppAndComplete()
                    } else if let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) {
                        NSLog("[Share:3] attachment[\(i)] — resolved as Data→URL: \(url.absoluteString)")
                        self.saveSharedUrl(url.absoluteString)
                        self.openMainAppAndComplete()
                    } else {
                        NSLog("[Share:3] attachment[\(i)] — could not cast item to URL or Data. Completing.")
                        self.completeExtension()
                    }
                }
                return
            }
            
            // Handle text (which might contain URLs)
            if attachment.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                NSLog("[Share:3] attachment[\(i)] — loading as text type")
                attachment.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] (item, error) in
                    guard let self = self else { return }
                    if let error = error {
                        NSLog("[Share:3] attachment[\(i)] — loadItem text error: \(error)")
                    }
                    NSLog("[Share:3] attachment[\(i)] — loaded text=\(String(describing: item))")
                    if let text = item as? String,
                       let url = self.extractUrl(from: text) {
                        NSLog("[Share:3] attachment[\(i)] — extracted URL from text: \(url)")
                        self.saveSharedUrl(url)
                        self.openMainAppAndComplete()
                    } else {
                        NSLog("[Share:3] attachment[\(i)] — no URL found in text. Completing.")
                        self.completeExtension()
                    }
                }
                return
            }
        }
        
        NSLog("[Share:3] handleSharedContent — no URL or text attachment matched. Completing.")
        completeExtension()
    }
    
    private func extractUrl(from text: String) -> String? {
        NSLog("[Share:4] extractUrl from text='\(text.prefix(200))'")
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        let result = matches?.first?.url?.absoluteString
        NSLog("[Share:4] extractUrl result=\(result ?? "nil")")
        return result
    }
    
    private func saveSharedUrl(_ url: String) {
        NSLog("[Share:5] saveSharedUrl — url='\(url)' appGroup='\(appGroupId)' key='\(sharedKey)'")
        if let userDefaults = UserDefaults(suiteName: appGroupId) {
            userDefaults.set(url, forKey: sharedKey)
            let synced = userDefaults.synchronize()
            let readBack = userDefaults.string(forKey: sharedKey)
            NSLog("[Share:5] saveSharedUrl — synchronize=\(synced) readBack='\(readBack ?? "nil")'")
        } else {
            NSLog("[Share:5] saveSharedUrl — ERROR: could not open UserDefaults for appGroup '\(appGroupId)'")
        }
    }
    
    private func openMainAppAndComplete() {
        NSLog("[Share:6] openMainAppAndComplete — opening host app")
        openMainApp { [weak self] in
            // Brief delay so iOS can switch to the host app before the sheet dismisses.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self?.completeExtension()
            }
        }
    }

    /// Deep links registered on the host app (Runner/Info.plist CFBundleURLSchemes).
    private var hostAppOpenURLs: [URL] {
        [
            URL(string: "collectio://share"),
            URL(string: "com.sneha.iosfinds://share"),
        ].compactMap { $0 }
    }

    private func openMainApp(completion: @escaping () -> Void) {
        let urls = hostAppOpenURLs
        guard !urls.isEmpty else {
            NSLog("[Share:7] openMainApp — ERROR: no host app URLs configured")
            completion()
            return
        }

        tryOpenHostApp(urls: urls, index: 0) { opened in
            NSLog("[Share:7] openMainApp — finished, hostAppOpened=\(opened)")
            completion()
        }
    }

    private func tryOpenHostApp(urls: [URL], index: Int, completion: @escaping (Bool) -> Void) {
        guard index < urls.count else {
            completion(false)
            return
        }

        let url = urls[index]
        NSLog("[Share:7] tryOpenHostApp — attempt \(index + 1)/\(urls.count) url=\(url.absoluteString)")

        openHostAppViaResponderChain(url: url)

        guard let context = extensionContext else {
            NSLog("[Share:7] tryOpenHostApp — extensionContext nil, responder chain only")
            completion(true)
            return
        }

        DispatchQueue.main.async {
            context.open(url) { [weak self] success in
                NSLog("[Share:7] tryOpenHostApp — extensionContext.open success=\(success) url=\(url.absoluteString)")
                if success {
                    completion(true)
                    return
                }
                self?.tryOpenHostApp(urls: urls, index: index + 1, completion: completion)
            }
        }
    }

    /// Fallback when [NSExtensionContext.open] returns false (common on recent iOS versions).
    private func openHostAppViaResponderChain(url: URL) {
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                NSLog("[Share:7] openHostAppViaResponderChain — performed openURL on \(String(describing: type(of: current)))")
                return
            }
            responder = current.next
        }
        NSLog("[Share:7] openHostAppViaResponderChain — no responder handled openURL:")
    }
    
    private func completeExtension() {
        NSLog("[Share:8] completeExtension — calling extensionContext.completeRequest")
        extensionContext?.completeRequest(returningItems: [], completionHandler: { expired in
            NSLog("[Share:8] completeRequest callback — expired=\(expired)")
        })
    }
}
