on run argv
    if (count of argv) = 0 then
        error "URL argument is required."
    end if
    set targetURL to item 1 of argv
    set mode to "reader"
    if (count of argv) >= 2 then
        set mode to item 2 of argv
    end if

    tell application "Safari"
        activate
        if (count of documents) = 0 then
            make new document with properties {URL:"about:blank"}
        end if
        set workerWindow to window 1
        tell workerWindow
            if (count of tabs) = 0 then
                set current tab to (make new tab)
            end if
            set workerTab to current tab
            set URL of workerTab to targetURL
        end tell
    end tell

    repeat 60 times
        delay 0.5
        try
            tell application "Safari"
                tell window 1
                    tell current tab
                        set readyState to do JavaScript "document.readyState"
                        if readyState is "complete" then exit repeat
                    end tell
                end tell
            end tell
        end try
    end repeat

    delay 0.5

    if mode is "reader" then
        tell application "System Events"
            keystroke "r" using {command down, shift down}
        end tell
        delay 1
        return "Reader shortcut sent"
    else
        delay 0.5
        return "Reader mode skipped"
    end if
end run
