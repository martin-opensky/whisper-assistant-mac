-- Hammerspoon Voice Transcription Tool
-- Uses whisper.cpp with Metal GPU acceleration and ffmpeg for voice transcription

-- Global state
local isRecording = false
local isProcessing = false
local recordingTask = nil
local menuBarItem = nil
local recordingAlert = nil
local processingAlert = nil
local currentAudioFile = nil
local transcriptionTask = nil
local transcriptionTimeout = nil
local transcriptionProgressTimer = nil
local transcriptionStartTime = nil
local selectedPostProcessing = nil
local scriptDir = debug.getinfo(1, "S").source:match("@(.*/)")

-- Audio fade state
local savedVolume = nil
local fadeTimer = nil

-- Cleanup function to terminate any existing tasks and reset state
local function cleanup()
    if recordingTask then recordingTask:terminate() end
    if transcriptionTask then transcriptionTask:terminate() end
    if menuBarItem then menuBarItem:delete() end
    if recordingAlert then hs.alert.closeSpecific(recordingAlert) end
    if processingAlert then hs.alert.closeSpecific(processingAlert) end
    -- Stop any active fade timer and restore volume
    if fadeTimer then
        fadeTimer:stop()
        fadeTimer = nil
    end
    if savedVolume then
        local device = hs.audiodevice.defaultOutputDevice()
        if device then device:setVolume(savedVolume) end
        savedVolume = nil
    end
    -- Reset state
    isRecording = false
    isProcessing = false
    recordingTask = nil
    transcriptionTask = nil
    menuBarItem = nil
    recordingAlert = nil
    processingAlert = nil
    currentAudioFile = nil
end

-- Helper function to show alert on focused screen
local function showAlert(message, duration)
    local focusedScreen = hs.screen.mainScreen()
    return hs.alert.show(message, duration or 1.5, focusedScreen)
end

-- Helper function to fade audio volume linearly
-- targetVolume: 0-100, duration: seconds, callback: optional function to call when done
local function fadeVolume(targetVolume, duration, callback)
    -- Stop any existing fade
    if fadeTimer then
        fadeTimer:stop()
        fadeTimer = nil
    end

    local device = hs.audiodevice.defaultOutputDevice()
    if not device then
        print("Warning: No default audio output device found")
        if callback then callback() end
        return
    end

    local currentVolume = device:volume()
    if currentVolume == nil then
        print("Warning: Could not get current volume")
        if callback then callback() end
        return
    end

    local steps = 10  -- Number of steps for the fade
    local interval = duration / steps  -- Time between each step (0.05s for 0.5s duration)
    local volumeStep = (targetVolume - currentVolume) / steps
    local currentStep = 0

    fadeTimer = hs.timer.doEvery(interval, function()
        currentStep = currentStep + 1
        local newVolume = currentVolume + (volumeStep * currentStep)

        -- Clamp volume to valid range
        newVolume = math.max(0, math.min(100, newVolume))

        device:setVolume(newVolume)

        if currentStep >= steps then
            fadeTimer:stop()
            fadeTimer = nil
            -- Ensure we hit the exact target
            device:setVolume(targetVolume)
            if callback then callback() end
        end
    end)
end

-- Helper function to load settings
local function loadSettings()
    local settingsPath = scriptDir .. "settings.json"
    local file = io.open(settingsPath, "r")
    if not file then
        showAlert("Error: settings.json not found")
        return nil
    end
    local content = file:read("*all")
    file:close()
    local settings = hs.json.decode(content)
    return settings
end

-- Helper function to get available post-processing options
local function getPostProcessingChoices()
    local instructionsDir = scriptDir .. "instructions/"
    local choices = {{
        text = "None",
        subText = "No post-processing - paste raw transcription",
        value = nil  -- Special value for no processing
    }}

    -- Dynamically list all .md files from instructions/
    local handle = io.popen("ls " .. instructionsDir .. "*.md 2>/dev/null")
    if handle then
        for filepath in handle:lines() do
            local filename = filepath:match("([^/]+)%.md$")
            if filename then
                table.insert(choices, {
                    text = filename,
                    subText = "Format using " .. filename .. " instructions",
                    value = filename
                })
            end
        end
        handle:close()
    end

    return choices
end

-- Helper function to save post-processing preference
local function savePostProcessingPreference(selection)
    local settingsPath = scriptDir .. "settings.json"
    local settings = loadSettings()
    if not settings then
        print("Error: Could not load settings for saving preference")
        return
    end

    if selection then
        settings.postProcessing = selection
    else
        settings.postProcessing = hs.json.null  -- Use JSON null for "None"
    end

    -- Write back to settings.json
    local file = io.open(settingsPath, "w")
    if file then
        local success, encoded = pcall(hs.json.encode, settings, true)
        if success then
            file:write(encoded)
            print("Saved postProcessing preference: " .. (selection or "None"))
        else
            print("Error encoding settings: " .. tostring(encoded))
        end
        file:close()
    else
        print("Error: Could not open settings.json for writing")
    end
end

-- Helper function to get timestamp
local function getTimestamp()
    return os.date("%Y-%m-%d_%H-%M-%S")
end

-- Helper function to get date string for directory
local function getDateDir()
    return os.date("%Y-%m-%d")
end

-- Helper function to get time string for subdirectory
local function getTimeDir()
    return os.date("%H-%M-%S")
end

-- Helper function to clean up old transcripts (older than 7 days)
local function cleanupOldTranscripts()
    local transcriptDir = scriptDir .. "transcripts/"
    local maxAgeDays = 7

    -- Use hs.task for non-blocking cleanup
    hs.task.new(
        "/bin/bash",
        function(exitCode, stdOut, stdErr)
            if exitCode == 0 then
                local deletedCount = tonumber(stdOut:match("(%d+)")) or 0
                if deletedCount > 0 then
                    print("Cleanup: Removed " .. deletedCount .. " old transcript(s)")
                end
            else
                print("Cleanup error: " .. stdErr)
            end
        end,
        {"-c", string.format([[
            count=0
            transcript_dir="%s"
            max_age_days=%d

            # Find and delete transcript directories older than max_age_days
            for date_dir in "$transcript_dir"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]; do
                [ -d "$date_dir" ] || continue

                for time_dir in "$date_dir"/[0-9][0-9]-[0-9][0-9]-[0-9][0-9]; do
                    [ -d "$time_dir" ] || continue

                    # Check if directory is older than max_age_days
                    if [ $(find "$time_dir" -maxdepth 0 -mtime +$max_age_days 2>/dev/null | wc -l) -gt 0 ]; then
                        rm -rf "$time_dir"
                        ((count++))
                    fi
                done

                # Remove date directory if empty
                rmdir "$date_dir" 2>/dev/null
            done

            echo "$count"
        ]], transcriptDir, maxAgeDays)}
    ):start()
end

-- Helper function to save transcript
local function saveTranscript(originalText, processedText, processingType)
    local baseTranscriptDir = scriptDir .. "transcripts/"
    local dateDir = getDateDir()
    local timeDir = getTimeDir()
    local transcriptDir = baseTranscriptDir .. dateDir .. "/" .. timeDir .. "/"

    -- Create nested directory structure
    os.execute("mkdir -p " .. transcriptDir)

    -- Save original transcript (content only)
    local originalFile = io.open(transcriptDir .. "transcript.md", "w")
    if originalFile then
        originalFile:write(originalText)
        originalFile:close()
    end

    -- Save post-processed transcript to separate file if exists
    if processedText and processingType then
        local processedFile = io.open(transcriptDir .. processingType .. ".md", "w")
        if processedFile then
            processedFile:write(processedText)
            processedFile:close()
        end
    end

    print("Transcript saved to: " .. transcriptDir)
end

-- Start recording
local function startRecording()
    -- Load settings
    local settings = loadSettings()
    if not settings then
        return
    end

    local audioFile = os.tmpname() .. ".wav"
    local audioDevice = settings.audioDevice or ":1"  -- Default to built-in microphone

    -- Save current volume and fade out to 0
    local device = hs.audiodevice.defaultOutputDevice()
    if device then
        savedVolume = device:volume()
        if savedVolume and savedVolume > 0 then
            fadeVolume(0, 0.5)
        end
    end

    -- Create menu bar indicator with styled red circle
    if not menuBarItem then
        menuBarItem = hs.menubar.new()
    end
    menuBarItem:setTitle(hs.styledtext.new("●", {
        color = {red = 1.0, green = 0.0, blue = 0.0},
        font = {name = ".AppleSystemUIFont", size = 18}
    }))
    menuBarItem:setTooltip("Recording audio...")

    -- Start ffmpeg recording with configured audio device
    local ffmpegCmd = string.format(
        '/opt/homebrew/bin/ffmpeg -f avfoundation -i "%s" -ar 16000 -ac 1 -y "%s" 2>&1',
        audioDevice,
        audioFile
    )

    recordingTask = hs.task.new(
        "/bin/bash",
        function(exitCode, stdOut, stdErr)
            print("FFmpeg exit code: " .. exitCode)
            if exitCode ~= 0 then
                print("FFmpeg output: " .. stdOut)
                print("FFmpeg error: " .. stdErr)
            end
        end,
        {"-c", ffmpegCmd}
    )

    recordingTask:start()
    isRecording = true

    -- Store audio file path for later use
    currentAudioFile = audioFile

    -- Show persistent recording alert
    recordingAlert = showAlert("🎤 Recording...", "infinite")
end

-- Stop recording and transcribe
local function stopRecording()
    if not recordingTask then
        return
    end

    -- Stop recording
    recordingTask:terminate()
    local audioFile = currentAudioFile

    -- Fade volume back in to saved level
    if savedVolume and savedVolume > 0 then
        fadeVolume(savedVolume, 0.5, function()
            savedVolume = nil
        end)
    end

    -- Close persistent recording alert
    if recordingAlert then
        hs.alert.closeSpecific(recordingAlert)
        recordingAlert = nil
    end

    -- Remove menu bar indicator
    if menuBarItem then
        menuBarItem:delete()
        menuBarItem = nil
    end

    isRecording = false
    isProcessing = true

    -- Load settings and pre-set selectedPostProcessing to saved preference
    local settings = loadSettings()
    if not settings then
        return
    end
    selectedPostProcessing = settings.postProcessing

    -- Show persistent processing alert
    processingAlert = showAlert("⏸️ Transcribing...", "infinite")

    -- Show chooser immediately (in parallel with transcription)
    -- Chooser stays open during entire transcription - user can change selection anytime
    -- When transcription completes, whatever is selected will be used automatically
    local choices = getPostProcessingChoices()
    local chooser = hs.chooser.new(function(choice)
        if choice then
            -- User manually selected an option - update preference
            savePostProcessingPreference(choice.value)
            print("Post-processing option changed to: " .. (choice.value or "None"))
        end
    end)
    chooser:choices(choices)
    chooser:rows(math.min(#choices, 5))  -- Max 5 visible rows
    chooser:searchSubText(true)  -- Allow searching by subtext

    -- Pre-select last used option
    local preselectedIndex = 1  -- Default to "None"
    if settings.postProcessing then
        print("Looking for saved preference: " .. settings.postProcessing)
        for i, choice in ipairs(choices) do
            if choice.value == settings.postProcessing then
                preselectedIndex = i
                print("Pre-selecting row " .. i .. ": " .. choice.text)
                break
            end
        end
    end
    chooser:show()

    chooser:selectedRow(preselectedIndex)

    -- Start transcription immediately (in parallel with chooser)
    hs.timer.doAfter(0.5, function()
        -- Check if audio file exists and has content
        local file = io.open(audioFile, "r")
        if not file then
            chooser:hide()
            if processingAlert then
                hs.alert.closeSpecific(processingAlert)
                processingAlert = nil
            end
            showAlert("❌ Audio file not created")
            print("Error: Audio file not found at " .. audioFile)
            recordingTask = nil
            isProcessing = false
            return
        end

        local fileSize = file:seek("end")
        file:close()

        if fileSize < 1000 then  -- Less than 1KB is probably empty/corrupted
            chooser:hide()
            if processingAlert then
                hs.alert.closeSpecific(processingAlert)
                processingAlert = nil
            end
            showAlert("❌ Audio file too small")
            print("Error: Audio file size is only " .. fileSize .. " bytes")
            os.remove(audioFile)
            recordingTask = nil
            isProcessing = false
            return
        end

        print("Audio file created successfully: " .. fileSize .. " bytes")

        -- Load settings
        local settings = loadSettings()
        if not settings then
            chooser:hide()
            if processingAlert then
                hs.alert.closeSpecific(processingAlert)
                processingAlert = nil
            end
            os.remove(audioFile)
            recordingTask = nil
            isProcessing = false
            return
        end

        -- Run transcription asynchronously using hs.task
        -- Using whisper.cpp with Metal GPU acceleration for fast transcription
        local transcribeScript = scriptDir .. "transcribe.sh"
        local model = settings.model or "base.en"
        local language = settings.language or "en"

        print("Running whisper.cpp transcription with model: " .. model)

        -- Track start time for elapsed display
        transcriptionStartTime = os.time()

        -- Update alert with elapsed time every second
        transcriptionProgressTimer = hs.timer.doEvery(1, function()
            if transcriptionStartTime and processingAlert then
                local elapsed = os.time() - transcriptionStartTime
                hs.alert.closeSpecific(processingAlert)
                processingAlert = showAlert(string.format("⏸️ Transcribing... %ds", elapsed), "infinite")
            end
        end)

        transcriptionTask = hs.task.new(
            "/bin/bash",
            function(exitCode, stdOut, stdErr)
                local elapsed = transcriptionStartTime and (os.time() - transcriptionStartTime) or 0
                print(string.format("Transcription completed in %ds, exit code: %d", elapsed, exitCode))

                -- Cancel progress timer
                if transcriptionProgressTimer then
                    transcriptionProgressTimer:stop()
                    transcriptionProgressTimer = nil
                end
                transcriptionStartTime = nil

                -- Cancel timeout timer since transcription completed
                if transcriptionTimeout then
                    transcriptionTimeout:stop()
                    transcriptionTimeout = nil
                end

                -- Read currently selected option from chooser and close it
                local selectedRow = chooser:selectedRow()
                if selectedRow and selectedRow > 0 and selectedRow <= #choices then
                    local selectedChoice = choices[selectedRow]
                    selectedPostProcessing = selectedChoice.value
                    savePostProcessingPreference(selectedChoice.value)
                    print("Using selected post-processing: " .. (selectedChoice.value or "None"))
                end
                chooser:hide()

                -- Close persistent processing alert
                if processingAlert then
                    hs.alert.closeSpecific(processingAlert)
                    processingAlert = nil
                end

                -- Clean up audio file
                os.remove(audioFile)

                if exitCode == 0 then
                    local text = stdOut:gsub("^%s*(.-)%s*$", "%1") -- trim whitespace
                    if text ~= "" then
                        -- Check if post-processing is enabled (using selectedPostProcessing from chooser)
                        if selectedPostProcessing then
                            -- Show post-processing feedback
                            if processingAlert then
                                hs.alert.closeSpecific(processingAlert)
                            end
                            processingAlert = showAlert("⚙️ Processing: " .. selectedPostProcessing, "infinite")

                            -- Run post-processing using faster shell script
                            local postprocessScript = scriptDir .. "postprocess.sh"
                            local instructionFile = scriptDir .. "instructions/" .. selectedPostProcessing .. ".md"

                            print("Running post-processing with: " .. selectedPostProcessing)

                            local postprocessTask = hs.task.new(
                                "/bin/bash",
                                function(ppExitCode, ppStdOut, ppStdErr)
                                    -- Close persistent processing alert
                                    if processingAlert then
                                        hs.alert.closeSpecific(processingAlert)
                                        processingAlert = nil
                                    end

                                    local finalText = text  -- Default to original
                                    local processedText = nil

                                    if ppExitCode == 0 then
                                        processedText = ppStdOut:gsub("^%s*(.-)%s*$", "%1")
                                        if processedText ~= "" then
                                            finalText = processedText
                                            print("Post-processing successful: " .. #finalText .. " characters")
                                        else
                                            print("Warning: Post-processing returned empty, using original")
                                            processedText = nil  -- Clear if empty
                                        end
                                    else
                                        print("Post-processing error: " .. ppStdErr)
                                        print("Using original transcription")
                                        processedText = nil  -- Clear on error
                                    end

                                    -- Save transcript with both original and processed versions
                                    saveTranscript(text, processedText, selectedPostProcessing)

                                    -- Copy to clipboard
                                    hs.pasteboard.setContents(finalText)

                                    -- Paste text at cursor
                                    hs.eventtap.keyStrokes(finalText)
                                    showAlert("✓ Transcribed & Processed")

                                    recordingTask = nil
                                    currentAudioFile = nil
                                    transcriptionTask = nil
                                    isProcessing = false
                                end,
                                {postprocessScript, text, instructionFile}
                            )

                            postprocessTask:start()
                        else
                            -- No post-processing, use original transcription
                            -- Close persistent processing alert
                            if processingAlert then
                                hs.alert.closeSpecific(processingAlert)
                                processingAlert = nil
                            end

                            -- Save transcript (original only, no post-processing)
                            saveTranscript(text, nil, nil)

                            -- Copy to clipboard
                            hs.pasteboard.setContents(text)

                            -- Paste text at cursor
                            hs.eventtap.keyStrokes(text)
                            showAlert("✓ Transcribed & Copied")
                            print("Transcription successful: " .. #text .. " characters")

                            recordingTask = nil
                            currentAudioFile = nil
                            transcriptionTask = nil
                            isProcessing = false
                        end
                    else
                        -- Close persistent processing alert
                        if processingAlert then
                            hs.alert.closeSpecific(processingAlert)
                            processingAlert = nil
                        end

                        showAlert("⚠️ No speech detected")
                        print("Warning: Transcription returned empty text")

                        recordingTask = nil
                        currentAudioFile = nil
                        transcriptionTask = nil
                        isProcessing = false
                    end
                else
                    -- Close persistent processing alert
                    if processingAlert then
                        hs.alert.closeSpecific(processingAlert)
                        processingAlert = nil
                    end

                    -- Parse error from stderr for user-friendly message
                    local errorMsg = "Transcription failed"
                    if stdErr:match("Model not found") then
                        errorMsg = "Model not found - run: ollama pull llama3.2:3b"
                    elseif stdErr:match("Audio file too small") then
                        errorMsg = "Recording too short"
                    elseif stdErr:match("empty result") then
                        errorMsg = "No speech detected"
                    elseif stdErr:match("whisper%-cli") then
                        errorMsg = "Whisper error - check logs"
                    end
                    showAlert("❌ " .. errorMsg, 3)
                    print("Transcription error (stderr): " .. stdErr)

                    recordingTask = nil
                    currentAudioFile = nil
                    transcriptionTask = nil
                    isProcessing = false
                end
            end,
            {transcribeScript, audioFile, model, language}
        )

        transcriptionTask:start()

        -- Add timeout to prevent infinite hangs (90 seconds max for longer recordings)
        transcriptionTimeout = hs.timer.doAfter(90, function()
            if transcriptionTask and transcriptionTask:isRunning() then
                print("Transcription timeout after 90 seconds - terminating task")
                transcriptionTask:terminate()

                -- Cancel progress timer
                if transcriptionProgressTimer then
                    transcriptionProgressTimer:stop()
                    transcriptionProgressTimer = nil
                end
                transcriptionStartTime = nil

                -- Close alerts and chooser
                if processingAlert then
                    hs.alert.closeSpecific(processingAlert)
                    processingAlert = nil
                end
                chooser:hide()

                -- Clean up
                if audioFile and hs.fs.attributes(audioFile) then
                    os.remove(audioFile)
                end

                showAlert("❌ Transcription timed out", 3)
                recordingTask = nil
                currentAudioFile = nil
                transcriptionTask = nil
                isProcessing = false
            end
        end)
    end)
end

-- Toggle recording
local function toggleRecording()
    if isProcessing then
        showAlert("⏳ Still processing...")
        return
    end
    if isRecording then
        stopRecording()
    else
        startRecording()
    end
end

-- Setup hotkey
local function setupHotkey()
    local settings = loadSettings()
    if not settings then
        return
    end

    local mods = settings.hotkey.modifiers or {"cmd"}
    local key = settings.hotkey.key or "m"

    hs.hotkey.bind(mods, key, toggleRecording)

    showAlert("Voice transcription loaded: " .. table.concat(mods, "+") .. "+" .. key)
end

-- Clean up any existing state from previous loads
cleanup()

-- Initialize
setupHotkey()

-- Run cleanup on startup to remove old transcripts
cleanupOldTranscripts()
