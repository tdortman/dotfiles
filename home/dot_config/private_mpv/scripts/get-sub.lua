local mp = require "mp"

local function get_sub()
    local path = mp.get_property("path")

    if not path or path:match("^%a+://") then
        mp.osd_message("No local video file")
        return
    end

    mp.osd_message("Downloading English subtitles...", 30)

    mp.command_native_async({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = {
            "subliminal",
            "download",
            "-l", "en",
            "--force-embedded-subtitles",
            path,
        },
    }, function(success, result)
        if success and result.status == 0 then
            mp.commandv("rescan_external_files", "reselect")
            mp.osd_message("Subtitle downloaded")
        else
            mp.osd_message("Subtitle download failed")
        end
    end)
end

mp.add_key_binding("Ctrl+s", "download-subtitle", get_sub)
