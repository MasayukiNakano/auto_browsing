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

    tell application "Safari"
        activate
        if (count of documents) = 0 then
            make new document with properties {URL:"about:blank"}
        end if
        set workerWindow to missing value
        repeat with w in windows
            try
                if name of w is targetWindowTitle then
                    set workerWindow to w
                    exit repeat
                end if
            end try
        end repeat

        if workerWindow is missing value then
            make new document with properties {URL:placeholderURL}
            set workerWindow to front window
        end if

        try
            set name of workerWindow to targetWindowTitle
        end try

        tell workerWindow
            if (count of tabs) = 0 then
                set current tab to (make new tab)
            end if
            set workerTab to current tab
            try
                set URL of workerTab to placeholderURL
            end try
            set URL of workerTab to targetURL
            try
                set name to targetWindowTitle
            end try
        end tell

        try
            set index of workerWindow to 1
        end try
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
