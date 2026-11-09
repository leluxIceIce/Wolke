// SPDX-License-Identifier: Apache-2.0
(() => {
    "use strict";

    let active = true;
    let restoring = false;
    let timer;
    let sending = false;
    let lastHadTrack = false;
    let nextPing = 0;
    let commandID;
    let commandState;

    async function report() {
        if (!active || sending || restoring) return;
        sending = true;
        try {
            const track = commandID ? commandState : wolkePlayer.read();
            if (track || lastHadTrack || commandID) {
                const id = commandID;
                const response = await browser.runtime.sendMessage({ track, ack: id });
                if (id === commandID) commandID = undefined;
                lastHadTrack = !!track;
                if (response?.command) {
                    commandState = await wolkePlayer.run(response.command);
                    commandID = response.command.id;
                }
            } else if (Date.now() >= nextPing) {
                nextPing = Date.now() + 8_000;
                await browser.runtime.sendMessage({ ping: true });
            }
        } catch {
            // App or extension can be restarted independently.
        } finally {
            sending = false;
            clearTimeout(timer);
            timer = setTimeout(report, commandID ? 10 : lastHadTrack ? 900 : 1800);
        }
    }

    window.addEventListener("pagehide", () => {
        active = false;
        clearTimeout(timer);
    });
    window.addEventListener("pageshow", () => {
        active = true;
        report();
    });
    for (const event of ["play", "pause", "seeked", "loadedmetadata"]) {
        document.addEventListener(event, report, true);
    }
    browser.runtime.onMessage.addListener(message => {
        if (message?.wolkePopup !== true) return;
        if (!message.action) return Promise.resolve({ track: wolkePlayer.read() });
        return wolkePlayer.run(message).then(track => {
            report();
            return { track };
        });
    });

    async function start() {
        const claim = location.hash.match(/^#wolke(?:-playlist)?=([0-9a-f-]{36})$/i)?.[1];
        if (claim) {
            restoring = true;
            try {
                const { resume, playlist } = await browser.runtime.sendMessage({ claim }) ?? {};
                if ((resume || playlist) && active) {
                    history.replaceState(history.state, "", location.pathname + location.search);
                    if (playlist) await wolkePlayer.openPlaylist(playlist);
                    else await wolkePlayer.restore(resume.url, resume.position, true);
                }
            } catch {
                // A missing or expired claim leaves the normal player unchanged.
            } finally {
                restoring = false;
            }
        }
        report();
    }

    start();
})();
