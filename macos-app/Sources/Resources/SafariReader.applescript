on run argv
    if (count of argv) = 0 then
        error "URL argument is required."
    end if
    set targetURL to item 1 of argv
    set mode to "reader"
    if (count of argv) >= 2 then
        set mode to item 2 of argv
    end if
    set targetWindowTitle to "AutoBrowsing Worker"
    if (count of argv) >= 3 then
        set targetWindowTitle to item 3 of argv
    end if
    set placeholderURL to "about:blank"
    if (count of argv) >= 4 then
        set placeholderURL to item 4 of argv
    end if
    set targetWindowId to 0
    if (count of argv) >= 5 then
        try
            set targetWindowId to (item 5 of argv) as integer
        end try
    end if
    set tabDirective to "reuse"
    if (count of argv) >= 6 then
        set tabDirective to item 6 of argv
    end if
    set waitMode to "wait"
    if (count of argv) >= 7 then
        set waitMode to item 7 of argv
    end if
    set shouldWaitForLoad to (waitMode is not "nowait")

    tell application "Safari"
        activate
        if (count of documents) = 0 then
            make new document with properties {URL:"about:blank"}
        end if
        set workerWindow to missing value
        if targetWindowId > 0 then
            repeat with w in windows
                try
                    if id of w is targetWindowId then
                        set workerWindow to w
                        exit repeat
                    end if
                end try
            end repeat
        end if

        if workerWindow is missing value then
            repeat with w in windows
                try
                    if name of w is targetWindowTitle then
                        set workerWindow to w
                        exit repeat
                    end if
                end try
            end repeat
        end if

        if workerWindow is missing value then
            make new document with properties {URL:placeholderURL}
            set workerWindow to front window
            try
                set name of workerWindow to targetWindowTitle
            end try
            set targetWindowId to id of workerWindow
        end if

        set tabIndex to 1
        tell workerWindow
            if tabDirective is "new" then
                set workerTab to (make new tab with properties {URL:placeholderURL})
                set current tab to workerTab
            else
                if (count of tabs) = 0 then
                    set current tab to (make new tab)
                end if
                set workerTab to current tab
                try
                    set URL of workerTab to placeholderURL
                end try
            end if
            set URL of workerTab to targetURL
            try
                set name to targetWindowTitle
            end try
            set tabIndex to (index of workerTab)
        end tell

        try
            set index of workerWindow to 1
        end try
    end tell

    if shouldWaitForLoad then
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
    end if

    set resultMessage to ""
    if mode is "reader" and shouldWaitForLoad then
        tell application "System Events"
            keystroke "r" using {command down, shift down}
        end tell
        delay 1
        set resultMessage to "Reader shortcut sent"
    else if mode is "reader" then
        set resultMessage to "Reader mode postponed"
    else
        if shouldWaitForLoad then
            delay 0.5
        end if
        set resultMessage to "Reader mode skipped"
    end if
    return "TABINDEX=" & (tabIndex as string) & ";MESSAGE=" & resultMessage
end run
