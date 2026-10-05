const targetApps = new Set(["discord", "spotify"]);

function isOnCurrentDesktop(window) {
    return window.onAllDesktops || window.desktops.includes(workspace.currentDesktop);
}

function contains(outer, inner) {
    return inner.x >= outer.x && inner.y >= outer.y
        && inner.x + inner.width <= outer.x + outer.width
        && inner.y + inner.height <= outer.y + outer.height;
}

function minimizeCoveredApps() {
    const windows = workspace.stackingOrder;

    for (let index = 0; index < windows.length; ++index) {
        const target = windows[index];
        if (target.minimized || !isOnCurrentDesktop(target)
            || !targetApps.has(target.desktopFileName)) {
            continue;
        }

        for (let above = index + 1; above < windows.length; ++above) {
            const cover = windows[above];
            if (!cover.minimized && cover.normalWindow && cover.opacity === 1
                && isOnCurrentDesktop(cover)
                && (cover.fullScreen || cover.maximizeMode === 3)
                && contains(cover.frameGeometry, target.frameGeometry)) {
                target.minimized = true;
                break;
            }
        }
    }
}

function watch(window) {
    window.frameGeometryChanged.connect(minimizeCoveredApps);
}

workspace.stackingOrder.forEach(watch);
workspace.windowAdded.connect(window => {
    watch(window);
    minimizeCoveredApps();
});
workspace.windowActivated.connect(minimizeCoveredApps);
workspace.currentDesktopChanged.connect(minimizeCoveredApps);
minimizeCoveredApps();
