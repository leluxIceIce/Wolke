// SPDX-License-Identifier: Apache-2.0
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

const url = "https://soundcloud.com/forss/flickermood";
let active = true;
let liked = false;
let time = 44;
let signedIn = true;
let ready = true;
let moreOpen = false;
let playlistOpens = 0;
let previousClicks = 0;
let nextClicks = 0;
let nextDisabled = false;

const element = (properties = {}) => Object.defineProperties({
    querySelector: () => null,
    getAttribute: () => null,
    classList: { contains: () => false }
}, Object.getOwnPropertyDescriptors(properties));
const title = element({ href: url, title: "Flickermood" });
const artist = element({ title: "Forss" });
const play = element({
    get title() { return active ? "Pause current" : "Play current"; },
    click: () => { active = !active; }
});
const like = element({
    get title() { return liked ? "Unlike" : "Like"; },
    click: () => { liked = !liked; }
});
const previous = element({ click: () => { previousClicks += 1; } });
const next = element({
    get disabled() { return nextDisabled; },
    click: () => { nextClicks += 1; }
});
const art = element();
const timeline = element({
    getBoundingClientRect: () => ({ left: 40, top: 20, width: 426, height: 12 }),
    getAttribute: key => ({ "aria-valuemax": "213", "aria-valuenow": String(time) })[key] ?? null,
    dispatchEvent: event => {
        if (event.type === "mousedown") time = (event.clientX - 40) / 2;
    }
});
const badge = element({
    querySelector: selector => {
        if (selector.includes("titleLink")) return title;
        if (selector.includes("lightLink")) return artist;
        if (selector.includes("like")) return like;
        if (selector.includes(".image__full")) return art;
        return null;
    }
});
const bar = element({
    querySelector: selector => {
        if (selector.includes(".playbackSoundBadge")) return ready ? badge : null;
        if (selector.includes(".playControl")) return play;
        if (selector.includes("progressWrapper")) return timeline;
        if (selector.includes("skipControl__previous")) return previous;
        if (selector.includes("skipControl__next")) return next;
        return null;
    }
});
const document = {
    querySelector: selector => {
        if (selector.includes(".playControls")) return bar;
        if (selector.includes(".sc-button-more")) return element({ click: () => { moreOpen = true; } });
        if (selector.includes("loginButton")) return signedIn ? null : element();
        if (selector.includes(".soundTitle__playButton")) return element({ click: () => {
            ready = true;
            active = true;
        } });
        return null;
    },
    querySelectorAll: selector => selector === "audio" ? [] : [
        element({ title: "Add to Next up", click: () => assert.fail("Wrong menu action") }),
        ...(moreOpen ? [element({ title: "Zu einer Playlist hinzufügen", click: () => { playlistOpens += 1; } })] : [])
    ]
};
const context = vm.createContext({
    document, navigator: {}, window: {}, URL, location: new URL(url), setTimeout: fn => fn(),
    getComputedStyle: () => ({ backgroundImage: 'url("https://i1.sndcdn.com/artworks-test-t120x120.jpg")' }),
    MouseEvent: class { constructor(type, properties) { Object.assign(this, { type }, properties); } }
});
vm.runInContext(fs.readFileSync("Sources/Safari/player.js", "utf8"), context);
const player = context.wolkePlayer;

(async () => {
    const state = player.read();
    assert.equal(state.title, "Flickermood");
    assert.equal(state.artist, "Forss");
    assert.equal(state.artwork, "https://i1.sndcdn.com/artworks-test-large.jpg");
    assert.equal(state.duration, 213);
    assert.equal(state.position, 44);
    assert.equal(state.playing, true);
    assert.equal(state.canPrevious, true);
    assert.equal(state.canNext, true);
    await player.run({ url, action: "previous" });
    await player.run({ url, action: "next" });
    nextDisabled = true;
    assert.equal((await player.run({ url, action: "next" })).canNext, false);
    assert.equal(previousClicks, 1);
    assert.equal(nextClicks, 1);
    assert.equal((await player.run({ url, action: "back" })).position, 29);
    assert.equal((await player.run({ url, action: "forward" })).position, 44);
    assert.equal((await player.run({ url, action: "toggle" })).playing, false);
    assert.equal((await player.run({ url, action: "like" })).liked, true);
    assert.equal((await player.run({ url, action: "like" })).liked, false);
    signedIn = false;
    assert.equal((await player.run({ url, action: "like" })).liked, false);
    assert.equal(player.read().canLike, false);
    assert.equal((await player.run({ url: "https://soundcloud.com/forss/other", action: "toggle" })).playing, false);
    ready = false;
    const restored = await player.restore(url, 87, true);
    assert.equal(restored.position, 87);
    assert.equal(restored.playing, true);
    assert.equal(await player.openPlaylist("https://soundcloud.com/forss/other"), false);
    assert.equal(await player.openPlaylist(url), true);
    assert.equal(playlistOpens, 1);
    console.log("Player fixture: metadata, seeks, skip controls, playback, likes, resume and playlist chooser passed");
})().catch(error => { console.error(error); process.exitCode = 1; });
