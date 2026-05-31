import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    for context in URLContexts {
      let url = context.url
      NSLog("[SceneDelegate:openURL] url='\(url)' scheme='\(url.scheme ?? "nil")' host='\(url.host ?? "nil")'")
      if url.scheme == "collectio" && url.host == "share" {
        NSLog("[SceneDelegate:openURL] collectio://share matched — calling handleShareExtensionURL")
        (UIApplication.shared.delegate as? AppDelegate)?.handleShareExtensionURL()
      }
    }

    super.scene(scene, openURLContexts: URLContexts)
  }
}
