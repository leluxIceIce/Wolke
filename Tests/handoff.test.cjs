// SPDX-License-Identifier: Apache-2.0
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const trackURL = "https://soundcloud.com/forss/flickermood";
const resume = { id: "20008216-A28A-42D3-B7F5-76596401FDF9", url: trackURL, position: 44 };
const calls = [];
let closeTab;
let receive;
let hasResume = true;
const browser = {
    runtime: {
        onMessage: { addListener: listener => { receive = listener; } },
        sendNativeMessage: async (_, packet) => {
            calls.push(["native", packet.tab, packet.claim ?? null]);
            return hasResume ? { resume } : {};
        }
    },
    tabs: {
        onRemoved: { addListener: listener => { closeTab = listener; } },
        create: async ({ windowId, url, active }) => calls.push(["tab", windowId, url, active])
    },
    windows: {
        create: async ({ url, focused }) => { calls.push(["window", url, focused]); return { id: 20 }; },
        update: async (id, { state }) => calls.push(["update", id, state])
    }
};
vm.runInNewContext(fs.readFileSync("Sources/Safari/background.js", "utf8"), { browser, URL });

(async () => {
    const transferURL = trackURL + "#wolke=" + resume.id;
    await closeTab(1, { windowId: 8, isWindowClosing: false });
    assert.deepEqual(calls.splice(0), [["native", 1, null], ["tab", 8, transferURL, false]]);
    await closeTab(2, { windowId: 8, isWindowClosing: true });
    assert.deepEqual(calls.splice(0), [["native", 2, null], ["window", transferURL, false], ["update", 20, "minimized"]]);
    await receive({ claim: resume.id }, { tab: { id: 3 }, frameId: 0, url: transferURL });
    assert.deepEqual(calls.splice(0), [["native", 3, resume.id]]);
    await receive({ claim: resume.id }, { tab: { id: 4, incognito: true }, frameId: 0, url: transferURL });
    assert.equal(calls.length, 0);
    hasResume = false;
    await closeTab(3, { windowId: 8, isWindowClosing: false });
    assert.deepEqual(calls, [["native", 3, null]]);
    console.log("Safari fixture: background tab, last-window handoff, claim and private-tab exclusion passed");
})().catch(error => { console.error(error); process.exitCode = 1; });
