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
        NSLog("[Share:6] openMainAppAndComplete — calling openMainApp then completing after 0.3s")
        openMainApp()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            NSLog("[Share:6] openMainAppAndComplete — delay complete, calling completeExtension")
            self?.completeExtension()
        }
    }
    
    private func openMainApp() {
        guard let url = URL(string: "collectio://share") else {
            NSLog("[Share:7] openMainApp — ERROR: failed to create URL 'collectio://share'")
            return
        }
        
        NSLog("[Share:7] openMainApp — attempting to open '\(url)' via responder chain")
        
        var responder: UIResponder? = self as UIResponder
        var depth = 0
        let selector = sel_registerName("openURL:")
        while responder != nil {
            NSLog("[Share:7] openMainApp — responder[\(depth)]=\(type(of: responder!)) responds=\(responder!.responds(to: selector))")
            if responder!.responds(to: selector) {
                responder!.perform(selector, with: url)
                NSLog("[Share:7] openMainApp — SUCCESS: opened main app via responder chain at depth \(depth)")
                return
            }
            responder = responder?.next
            depth += 1
        }
        
        NSLog("[Share:7] openMainApp — FAILED: no responder in chain responded to openURL:. Data is saved in UserDefaults for next app launch.")
    }
    
    private func completeExtension() {
        NSLog("[Share:8] completeExtension — calling extensionContext.completeRequest")
        extensionContext?.completeRequest(returningItems: [], completionHandler: { [weak self] expired in
            NSLog("[Share:8] completeRequest callback — expired=\(expired)")
        })
    }
}
