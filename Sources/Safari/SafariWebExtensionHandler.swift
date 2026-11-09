// SPDX-License-Identifier: Apache-2.0
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        let info = (context.inputItems.first as? NSExtensionItem)?.userInfo
        guard let message = info?[SFExtensionMessageKey] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: message),
              var packet = try? JSONDecoder().decode(SafariPacket.self, from: data)
        else {
            finish(context, with: SafariReply())
            return
        }
        packet.profile = (info?[SFExtensionProfileKey] as? UUID)?.uuidString
        Task {
            let body = try? JSONEncoder().encode(packet)
            let reply: SafariReply? = await LocalClient.request("safari", body: body, timeout: 2)
            finish(context, with: reply ?? SafariReply())
        }
    }

    private func finish(_ context: NSExtensionContext, with reply: SafariReply) {
        let item = NSExtensionItem()
        let data = (try? JSONEncoder().encode(reply)) ?? Data("{}".utf8)
        item.userInfo = [SFExtensionMessageKey: (try? JSONSerialization.jsonObject(with: data)) ?? [:]]
        context.completeRequest(returningItems: [item])
    }
}
