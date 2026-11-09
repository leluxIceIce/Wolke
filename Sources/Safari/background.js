// SPDX-License-Identifier: Apache-2.0
const send = async (packet) => {
    try {
        return await browser.runtime.sendNativeMessage("studio.local.wolke", packet);
    } catch {
        return {};
    }
};

browser.runtime.onMessage.addListener((packet, sender) => {
    const tab = sender.tab;
    if (!Number.isInteger(tab?.id) || tab.incognito || sender.frameId > 0) return;
    if (!/^https:\/\/(www\.)?soundcloud\.com\//.test(sender.url || tab.url || "")) return;
    return send({ tab: tab.id, track: packet.track, ack: packet.ack, claim: packet.claim, ping: packet.ping });
});

browser.tabs.onRemoved.addListener(async (id, info) => {
    const { resume } = await send({ tab: id, closed: true }) ?? {};
    if (!resume) return;
    const url = new URL(resume.url);
    url.hash = "wolke=" + resume.id;
    if (!info.isWindowClosing) {
        try {
            await browser.tabs.create({ windowId: info.windowId, url: url.href, active: false });
            return;
        } catch {
            // The last tab may have closed its window before Safari delivered the event.
        }
    }
    try {
        const player = await browser.windows.create({ url: url.href, focused: false });
        if (Number.isInteger(player?.id)) {
            await browser.windows.update(player.id, { state: "minimized" }).catch(() => {});
        }
    } catch {
        // Safari may be quitting. Wolke expires the pending transfer.
    }
});
