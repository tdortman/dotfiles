import definePlugin from "@utils/types";

let lastFocused: Element | null = null;
let pickerToTextbox = false;

// After a mouse pick, Discord focuses the textbox and then its popout focus
// restore moves focus to the emoji button, so Enter reopens the picker.
function onFocusIn(e: FocusEvent) {
    const target = e.target as Element;
    const previous = lastFocused;
    lastFocused = target;

    if (target.matches('[role="textbox"]')) {
        pickerToTextbox = previous?.closest("#emoji-picker-tab-panel") != null;
        return;
    }

    const textbox = e.relatedTarget as HTMLElement | null;
    if (
        pickerToTextbox &&
        textbox?.matches('[role="textbox"]') &&
        target.closest('[class*="emojiButton"]')
    ) {
        pickerToTextbox = false;
        setTimeout(() => textbox.focus());
    }
}

export default definePlugin({
    name: "EmojiPickerRefocus",
    description: "Keeps focus in the message box after picking an emoji with the mouse, so Enter sends.",
    authors: [{ name: "tdortman", id: 0n }],
    enabledByDefault: true,
    start() {
        document.addEventListener("focusin", onFocusIn, true);
    },
    stop() {
        document.removeEventListener("focusin", onFocusIn, true);
        lastFocused = null;
        pickerToTextbox = false;
    },
});
