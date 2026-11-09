// SPDX-License-Identifier: Apache-2.0
(() => {
    "use strict";

    const find = (selector, root = document) => root?.querySelector(selector);
    const label = (element) => element?.getAttribute("aria-label") || element?.title || "";
    const titleText = (element) => element?.title || find("[aria-hidden=true]", element)?.textContent.trim() || element?.textContent.trim() || "";
    const wait = (ms) => new Promise(resolve => setTimeout(resolve, ms));

    function trackURL(value) {
        if (!value) return null;
        try {
            const url = new URL(value, location.origin);
            const parts = url.pathname.split("/").filter(Boolean);
            if (!["soundcloud.com", "www.soundcloud.com"].includes(url.hostname)
                || url.protocol !== "https:" || url.port || url.username || url.password
                || parts.length !== 2) return null;
            return "https://soundcloud.com/" + parts.join("/");
        } catch {
            return null;
        }
    }

    function seconds(value) {
        const match = String(value ?? "").match(/\b(?:\d+:){1,2}\d{2}\b/);
        return match ? match[0].split(":").reduce((sum, part) => sum * 60 + Number(part), 0) : 0;
    }

    function controls() {
        const bar = find(".playControls, [data-testid='playback-controls']");
        const badge = find(".playbackSoundBadge, [data-testid='now-playing']", bar);
        const title = find("a.playbackSoundBadge__titleLink, a.playbackSoundBadge__title, a[data-testid='track-title']", badge);
        const play = find(".playControl, .playControls__play, button[data-testid='play-pause']", bar);
        const previous = find(".skipControl__previous, button[aria-label='Skip to previous'], button[aria-label='Zum vorherigen Track']", bar);
        const next = find(".skipControl__next, button[aria-label='Skip to next'], button[aria-label='Zum nächsten Track']", bar);
        const like = find(".playbackSoundBadge__like, .sc-button-like, button[data-testid='like']", badge);
        const timeline = find(".playbackTimeline__progressWrapper, .playbackTimeline [role='slider'], [data-testid='seek-bar']", bar);
        const audioElements = [...document.querySelectorAll("audio")].filter(item => item.currentSrc);
        const audio = audioElements.find(item => !item.paused) ?? audioElements.at(-1);
        return { bar, badge, title, play, like, timeline, audio, previous, next };
    }

    function canSkip(button) {
        return !!button && !button.disabled && button.getAttribute("aria-disabled") !== "true"
            && !button.classList.contains("disabled");
    }

    function playing(controls) {
        const { play, audio } = controls;
        if (play?.classList.contains("playing")
            || play?.classList.contains("m-playing")
            || /pause|pausieren/i.test(label(play))) return true;
        return !!audio && !audio.paused && !audio.ended;
    }

    function artwork(badge, metadata) {
        const image = find(".image__full, img", badge) ?? find(".sc-artwork", badge);
        const css = image ? getComputedStyle(image).backgroundImage : "";
        const url = image?.currentSrc || css.match(/url\(["']?([^"')]+)["']?\)/)?.[1]
            || metadata?.artwork?.at(-1)?.src;
        if (!url) return null;
        return url.replace(/-(?:tiny|small|badge|t\d+x\d+)(?=\.[a-z]+(?:\?|$))/i, "-large");
    }

    function read() {
        const ui = controls();
        const url = trackURL(ui.title?.href);
        if (!url) return null;
        const metadata = navigator.mediaSession?.metadata;
        const author = find(".playbackSoundBadge__lightLink, .playbackSoundBadge__context a, [data-testid='track-artist']", ui.badge);
        const duration = Number(ui.timeline?.getAttribute("aria-valuemax"))
            || seconds(titleText(find(".playbackTimeline__duration", ui.bar)))
            || (Number.isFinite(ui.audio?.duration) ? ui.audio.duration : 0);
        const position = ui.audio && Number.isFinite(ui.audio.currentTime) ? ui.audio.currentTime
            : Number(ui.timeline?.getAttribute("aria-valuenow"))
                || seconds(titleText(find(".playbackTimeline__timePassed", ui.bar)));
        const liked = !!ui.like && (ui.like.getAttribute("aria-pressed") === "true"
            || ui.like.classList.contains("sc-button-selected")
            || /unlike|gefällt mir nicht mehr/i.test(label(ui.like)));
        return {
            url, title: titleText(ui.title) || metadata?.title || "SoundCloud",
            artist: titleText(author) || metadata?.artist || "",
            artwork: artwork(ui.badge, metadata),
            duration, position, playing: playing(ui), liked,
            canLike: !!ui.like && !ui.like.disabled && !find(".header__loginMenu .loginButton"),
            canPrevious: canSkip(ui.previous), canNext: canSkip(ui.next)
        };
    }

    function seek(position, state, ui) {
        const target = Math.max(0, Math.min(position, state.duration - 0.1));
        if (ui.audio && Number.isFinite(ui.audio.duration)) {
            ui.audio.currentTime = target;
            return true;
        }
        if (!ui.timeline || !state.duration) return false;
        const rect = ui.timeline.getBoundingClientRect();
        if (!rect.width) return false;
        const coordinates = {
            bubbles: true, cancelable: true, button: 0, view: window,
            clientX: rect.left + rect.width * target / state.duration,
            clientY: rect.top + rect.height / 2
        };
        ui.timeline.dispatchEvent(new MouseEvent("mousedown", { ...coordinates, buttons: 1 }));
        ui.timeline.dispatchEvent(new MouseEvent("mouseup", coordinates));
        ui.timeline.dispatchEvent(new MouseEvent("click", coordinates));
        return true;
    }

    async function run(command) {
        const state = read();
        if (!state || state.url !== command.url) return state;
        const ui = controls();
        switch (command.action) {
        case "toggle":
            ui.play?.click();
            break;
        case "previous":
        case "next": {
            const skip = command.action === "next" ? ui.next : ui.previous;
            if (canSkip(skip)) skip.click();
            break;
        }
        case "like":
            if (state.canLike) ui.like.click();
            break;
        case "back":
        case "forward":
            if (state.duration) seek(state.position + (command.action === "back" ? -15 : 15), state, ui);
            break;
        }
        await wait(command.action === "like" ? 600 : 250);
        return read();
    }

    async function restore(url, position, shouldPlay) {
        // Wait for the track page to hydrate, even when SoundCloud already restored its own queue.
        let lastAttempt = -8;
        for (let attempt = 0; attempt < 48; attempt++) {
            let state = read();
            if (state?.url === url && state.playing && state.duration) {
                seek(position, state, controls());
                if (!shouldPlay) controls().play?.click();
                await wait(250);
                state = read();
                if (state?.url === url) return state;
            }

            if (attempt - lastAttempt >= 8) {
                const button = state?.url === url ? controls().play
                    : find(".soundTitle__playButton .playButton, .soundTitle .sc-button-play, .fullHero__playerArea .sc-button-play, main button[data-testid='play-button']");
                if (button && trackURL(location.href) === url && !state?.playing
                    && !button.classList.contains("sc-button-pause") && !find(".auth-modal iframe")) {
                    button.click();
                    lastAttempt = attempt;
                }
            }
            await wait(250);
        }
        return null;
    }

    async function openPlaylist(url) {
        let openedMore = false;
        for (let attempt = 0; attempt < 40 && trackURL(location.href) === url; attempt++) {
            const direct = find(".soundActions .sc-button-addtoset, .listenEngagement .sc-button-addtoset");
            const buttons = document.querySelectorAll(
                ".soundActions button, .listenEngagement button, [role='menuitem'], .moreActions__button"
            );
            const playlist = direct || [...buttons].find(item =>
                /add to playlist|(?:zu(?:r| einer?)?|in eine) playlist hinzufügen/i.test(label(item) || titleText(item))
            );
            if (playlist && !playlist.disabled) {
                playlist.click();
                return true;
            }
            if (!openedMore) {
                const more = find(".soundActions .sc-button-more, .listenEngagement .sc-button-more");
                if (more) {
                    more.click();
                    openedMore = true;
                }
            }
            await wait(250);
        }
        return false;
    }

    globalThis.wolkePlayer = { read, run, restore, openPlaylist };
})();
