import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  override func sceneDidBecomeActive(_ scene: UIScene) {
    NSLog("[SceneDelegate] sceneDidBecomeActive — checking pending share payload")
    (UIApplication.shared.delegate as? AppDelegate)?.handleShareExtensionURL()
    super.sceneDidBecomeActive(scene)
  }

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    for context in URLContexts {
      let url = context.url
      NSLog("[SceneDelegate:openURL] url='\(url)' scheme='\(url.scheme ?? "nil")' host='\(url.host ?? "nil")'")
      let isShareDeepLink =
        (url.scheme == "collectio" && url.host == "share") ||
        (url.scheme == "com.sneha.iosfinds" && url.host == "share")
      if isShareDeepLink {
        NSLog("[SceneDelegate:openURL] share deep link matched — calling handleShareExtensionURL")
        (UIApplication.shared.delegate as? AppDelegate)?.handleShareExtensionURL()
      }
    }

    super.scene(scene, openURLContexts: URLContexts)
  }
}
