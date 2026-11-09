// SPDX-License-Identifier: Apache-2.0
"use strict";

const byID = (id) => document.getElementById(id);
const buttons = [...document.querySelectorAll("[data-action]")];
const soundCloud = /^https:\/\/(www\.)?soundcloud\.com\//i;
const formatTime = (value) => {
    const seconds = Math.max(0, Math.floor(value));
    return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0");
};
let current;
let busy = false;

function render(response, isSoundCloud) {
    current = response?.track ?? null;
    byID("player").hidden = !current;
    byID("message").hidden = !!current;
    byID("open").hidden = !!response || isSoundCloud;
    if (!current) {
        byID("message").textContent = response
            ? "SoundCloud ist verbunden. Starte einen Track in diesem Tab."
            : isSoundCloud
                ? "Erlaube Wolke in Safari den Zugriff auf soundcloud.com und lade den Tab neu."
                : "Öffne SoundCloud. Safari kann dich dort nach Zugriff für Wolke fragen.";
        return;
    }

    byID("title").textContent = current.title;
    byID("artist").textContent = current.artist;
    const cover = byID("cover");
    const artwork = current.artwork;
    cover.hidden = !/^https:\/\/[^/]+\.sndcdn\.com\//i.test(artwork ?? "");
    if (!cover.hidden && cover.getAttribute("src") !== artwork) cover.src = artwork;
    byID("progress").max = Math.max(1, current.duration);
    byID("progress").value = current.position;
    byID("time").textContent = formatTime(current.position) + " / " + formatTime(current.duration);
    for (const button of buttons) {
        const action = button.dataset.action;
        button.disabled = action === "like" ? !current.canLike
            : (action === "back" || action === "forward") && !current.duration;
        if (action === "toggle") button.textContent = current.playing ? "Pause" : "Play";
        if (action === "like") {
            button.textContent = current.liked ? "♥" : "♡";
            button.setAttribute("aria-pressed", String(current.liked));
        }
    }
}

async function update(action) {
    if (busy) return;
    busy = true;
    let isSoundCloud = false;
    try {
        const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
        isSoundCloud = soundCloud.test(tab?.url ?? "");
        const response = await browser.tabs.sendMessage(tab.id, {
            wolkePopup: true, action, url: current?.url
        });
        render(response, isSoundCloud);
    } catch {
        render(null, isSoundCloud);
    } finally {
        busy = false;
    }
}

for (const button of buttons) {
    button.addEventListener("click", () => update(button.dataset.action));
}
update();
setInterval(() => update(), 1_000);
