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

-- Log file path for persistent error logging
local logFile = scriptDir .. "whisper-assistant.log"

-- Helper function to write to persistent log file
local function logToFile(message)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local file = io.open(logFile, "a")
    if file then
        file:write(timestamp .. ": " .. message .. "\n")
        file:close()
    end
    print(message)  -- Also print to Hammerspoon console
end

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
            logToFile("Saved postProcessing preference: " .. (selection or "None"))
        else
            logToFile("Error encoding settings: " .. tostring(encoded))
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
-- Also cleans up recordings older than 1 day
local function cleanupOldTranscripts()
    local transcriptDir = scriptDir .. "transcripts/"
    local maxAgeDays = 7
    local recordingMaxAgeDays = 1  -- Keep recordings for 1 day only

    -- Use hs.task for non-blocking cleanup
    hs.task.new(
        "/bin/bash",
        function(exitCode, stdOut, stdErr)
            if exitCode == 0 then
                local transcriptCount = tonumber(stdOut:match("transcripts:(%d+)")) or 0
                local recordingCount = tonumber(stdOut:match("recordings:(%d+)")) or 0
                if transcriptCount > 0 then
                    logToFile("Cleanup: Removed " .. transcriptCount .. " old transcript(s)")
                end
                if recordingCount > 0 then
                    logToFile("Cleanup: Removed " .. recordingCount .. " old recording(s)")
                end
            else
                logToFile("Cleanup error: " .. stdErr)
            end
        end,
        {"-c", string.format([[
            transcript_count=0
            recording_count=0
            transcript_dir="%s"
            max_age_days=%d
            recording_max_age_days=%d

            # Find and delete transcript directories older than max_age_days
            for date_dir in "$transcript_dir"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]; do
                [ -d "$date_dir" ] || continue

                for time_dir in "$date_dir"/[0-9][0-9]-[0-9][0-9]-[0-9][0-9]; do
                    [ -d "$time_dir" ] || continue

                    # Check if directory is older than max_age_days
                    if [ $(find "$time_dir" -maxdepth 0 -mtime +$max_age_days 2>/dev/null | wc -l) -gt 0 ]; then
                        rm -rf "$time_dir"
                        ((transcript_count++))
                    else
                        # For directories not being deleted, check for old recordings (older than 1 day)
                        for wav_file in "$time_dir"/*.wav; do
                            [ -f "$wav_file" ] || continue
                            if [ $(find "$wav_file" -mtime +$recording_max_age_days 2>/dev/null | wc -l) -gt 0 ]; then
                                rm -f "$wav_file"
                                ((recording_count++))
                            fi
                        done
                    fi
                done

                # Remove date directory if empty
                rmdir "$date_dir" 2>/dev/null
            done

            echo "transcripts:$transcript_count recordings:$recording_count"
        ]], transcriptDir, maxAgeDays, recordingMaxAgeDays)}
    ):start()
end

-- Helper function to save transcript and recording
-- existingDir: optional path to existing transcript directory (to ensure recording and transcript are in same dir)
-- audioFile: path to the source audio file (will be copied, not moved)
local function saveTranscript(originalText, processedText, processingType, existingDir, audioFile)
    local transcriptDir
    if existingDir then
        transcriptDir = existingDir
    else
        local baseTranscriptDir = scriptDir .. "transcripts/"
        local dateDir = getDateDir()
        local timeDir = getTimeDir()
        transcriptDir = baseTranscriptDir .. dateDir .. "/" .. timeDir .. "/"
    end

    -- Create nested directory structure (may already exist if recording was saved)
    os.execute("mkdir -p " .. transcriptDir)

    -- Save original transcript (content only)
    if originalText then
        local originalFile = io.open(transcriptDir .. "transcript.md", "w")
        if originalFile then
            originalFile:write(originalText)
            originalFile:close()
        end
    end

    -- Save post-processed transcript to separate file if exists
    if processedText and processingType then
        local processedFile = io.open(transcriptDir .. processingType .. ".md", "w")
        if processedFile then
            processedFile:write(processedText)
            processedFile:close()
        end
    end

    -- Copy audio file to transcript directory for recovery
    if audioFile then
        local destAudioFile = transcriptDir .. "recording.wav"
        local copyResult = os.execute(string.format('cp "%s" "%s"', audioFile, destAudioFile))
        if copyResult then
            logToFile("Recording saved to: " .. destAudioFile)
        else
            logToFile("Warning: Failed to copy recording to " .. destAudioFile)
        end
    end

    logToFile("Transcript saved to: " .. transcriptDir)
    return transcriptDir
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
            logToFile("FFmpeg exit code: " .. exitCode)
            if exitCode ~= 0 and exitCode ~= 255 then  -- 255 is normal termination
                logToFile("FFmpeg output: " .. stdOut)
                logToFile("FFmpeg error: " .. stdErr)
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

-- Helper function to save recording to transcripts directory (returns saved path)
local function saveRecordingToTranscripts(audioFile)
    if not audioFile then return nil end

    local baseTranscriptDir = scriptDir .. "transcripts/"
    local dateDir = getDateDir()
    local timeDir = getTimeDir()
    local transcriptDir = baseTranscriptDir .. dateDir .. "/" .. timeDir .. "/"

    -- Create nested directory structure
    os.execute("mkdir -p " .. transcriptDir)

    -- Copy audio file immediately
    local destAudioFile = transcriptDir .. "recording.wav"
    local copyResult = os.execute(string.format('cp "%s" "%s"', audioFile, destAudioFile))
    if copyResult then
        logToFile("Recording saved immediately to: " .. destAudioFile)
        return transcriptDir
    else
        logToFile("ERROR: Failed to save recording to " .. destAudioFile)
        return nil
    end
end

-- Stop recording and transcribe
local function stopRecording()
    if not recordingTask then
        return
    end

    -- Stop recording
    recordingTask:terminate()
    local audioFile = currentAudioFile
    logToFile("Recording stopped, audio file: " .. (audioFile or "nil"))

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

    -- Prepare transcript directory path for saving recording
    local baseTranscriptDir = scriptDir .. "transcripts/"
    local dateDir = os.date("%Y-%m-%d")
    local timeDir = os.date("%H-%M-%S")
    local transcriptDir = baseTranscriptDir .. dateDir .. "/" .. timeDir .. "/"
    local savedTranscriptDir = transcriptDir

    -- Show chooser immediately (in parallel with transcription)
    local choices = getPostProcessingChoices()
    local chooser = hs.chooser.new(function(choice)
        if choice then
            savePostProcessingPreference(choice.value)
        end
    end)
    chooser:choices(choices)
    chooser:rows(math.min(#choices, 5))
    chooser:searchSubText(true)

    local preselectedIndex = 1
    if settings.postProcessing then
        for i, choice in ipairs(choices) do
            if choice.value == settings.postProcessing then
                preselectedIndex = i
                break
            end
        end
    end
    chooser:show()
    chooser:selectedRow(preselectedIndex)

    -- Use hs.task for EVERYTHING - hs.timer is unreliable when chooser is active
    -- This task: 1) waits for ffmpeg to finish writing, 2) saves recording, 3) starts transcription
    local saveAndTranscribeTask = hs.task.new(
        "/bin/bash",
        function(saveExitCode, saveStdOut, saveStdErr)
            -- This callback is RELIABLE - it runs when the shell command completes
            logToFile("Save task completed, exit code: " .. saveExitCode)

            if saveExitCode == 0 then
                logToFile("Recording saved to: " .. transcriptDir .. "recording.wav")
            else
                logToFile("ERROR: Save failed: " .. saveStdErr)
            end

            -- Now run transcription - wrap in pcall for safety
            local ok, err = pcall(function()
                -- Verify audio file
                local file = io.open(audioFile, "r")
                if not file then
                    chooser:hide()
                    if processingAlert then hs.alert.closeSpecific(processingAlert); processingAlert = nil end
                    showAlert("❌ Audio file not found")
                    logToFile("Error: Audio file not found at " .. (audioFile or "nil"))
                    isProcessing = false
                    return
                end
                local fileSize = file:seek("end")
                file:close()

                if fileSize < 1000 then
                    chooser:hide()
                    if processingAlert then hs.alert.closeSpecific(processingAlert); processingAlert = nil end
                    showAlert("❌ Audio too small")
                    logToFile("Error: Audio file size is only " .. fileSize .. " bytes")
                    isProcessing = false
                    return
                end

                logToFile("Audio verified: " .. fileSize .. " bytes, starting whisper")

                -- Get transcription settings
                local transcribeScript = scriptDir .. "transcribe.sh"
                local model = settings.model or "base.en"
                local language = settings.language or "en"

                transcriptionStartTime = os.time()

                -- Progress timer (this one is less critical)
                transcriptionProgressTimer = hs.timer.doEvery(1, function()
                    if transcriptionStartTime and processingAlert then
                        local elapsed = os.time() - transcriptionStartTime
                        hs.alert.closeSpecific(processingAlert)
                        processingAlert = showAlert(string.format("⏸️ Transcribing... %ds", elapsed), "infinite")
                    end
                end)

                -- Run whisper transcription
                transcriptionTask = hs.task.new(
                    "/bin/bash",
                    function(exitCode, stdOut, stdErr)
                        local elapsed = transcriptionStartTime and (os.time() - transcriptionStartTime) or 0
                        logToFile(string.format("Transcription completed in %ds, exit code: %d", elapsed, exitCode))

                        if transcriptionProgressTimer then transcriptionProgressTimer:stop(); transcriptionProgressTimer = nil end
                        transcriptionStartTime = nil
                        if transcriptionTimeout then transcriptionTimeout:stop(); transcriptionTimeout = nil end

                        -- Get selected post-processing option
                        local selectedRow = chooser:selectedRow()
                        if selectedRow and selectedRow > 0 and selectedRow <= #choices then
                            local selectedChoice = choices[selectedRow]
                            selectedPostProcessing = selectedChoice.value
                            savePostProcessingPreference(selectedChoice.value)
                            logToFile("Using post-processing: " .. (selectedChoice.value or "None"))
                        end
                        chooser:hide()

                        if processingAlert then hs.alert.closeSpecific(processingAlert); processingAlert = nil end
                        os.remove(audioFile)

                        if exitCode == 0 then
                            local text = stdOut:gsub("^%s*(.-)%s*$", "%1")
                            if text ~= "" then
                                if selectedPostProcessing then
                                    processingAlert = showAlert("⚙️ Processing: " .. selectedPostProcessing, "infinite")
                                    local postprocessScript = scriptDir .. "postprocess.sh"
                                    local instructionFile = scriptDir .. "instructions/" .. selectedPostProcessing .. ".md"

                                    local postprocessTask = hs.task.new(
                                        "/bin/bash",
                                        function(ppExitCode, ppStdOut, ppStdErr)
                                            if processingAlert then hs.alert.closeSpecific(processingAlert); processingAlert = nil end
                                            local finalText = text
                                            local processedText = nil

                                            if ppExitCode == 0 then
                                                processedText = ppStdOut:gsub("^%s*(.-)%s*$", "%1")
                                                if processedText ~= "" then
                                                    finalText = processedText
                                                    logToFile("Post-processing successful: " .. #finalText .. " chars")
                                                end
                                            else
                                                logToFile("Post-processing error: " .. ppStdErr)
                                            end

                                            saveTranscript(text, processedText, selectedPostProcessing, savedTranscriptDir, nil)
                                            hs.pasteboard.setContents(finalText)
                                            hs.eventtap.keyStrokes(finalText)
                                            showAlert("✓ Transcribed & Processed")
                                            isProcessing = false
                                        end,
                                        {postprocessScript, text, instructionFile}
                                    )
                                    postprocessTask:start()
                                else
                                    saveTranscript(text, nil, nil, savedTranscriptDir, nil)
                                    hs.pasteboard.setContents(text)
                                    hs.eventtap.keyStrokes(text)
                                    showAlert("✓ Transcribed & Copied")
                                    logToFile("Transcription successful: " .. #text .. " chars")
                                    isProcessing = false
                                end
                            else
                                showAlert("⚠️ No speech detected")
                                logToFile("Warning: Empty transcription")
                                isProcessing = false
                            end
                        else
                            showAlert("❌ Transcription failed", 3)
                            logToFile("Transcription error: " .. stdErr)
                            isProcessing = false
                        end
                    end,
                    {transcribeScript, audioFile, model, language}
                )

                transcriptionTask:start()

                -- Timeout for hung transcriptions
                transcriptionTimeout = hs.timer.doAfter(90, function()
                    if transcriptionTask and transcriptionTask:isRunning() then
                        logToFile("ERROR: Transcription timeout - recording saved at: " .. savedTranscriptDir)
                        transcriptionTask:terminate()
                        if transcriptionProgressTimer then transcriptionProgressTimer:stop() end
                        if processingAlert then hs.alert.closeSpecific(processingAlert) end
                        chooser:hide()
                        showAlert("❌ Timeout\nRecording saved", 3)
                        isProcessing = false
                    end
                end)
            end)

            if not ok then
                logToFile("CRITICAL ERROR: " .. tostring(err))
                chooser:hide()
                if processingAlert then hs.alert.closeSpecific(processingAlert); processingAlert = nil end
                showAlert("❌ Error - check logs", 3)
                isProcessing = false
            end
        end,
        {"-c", string.format('sleep 0.5 && mkdir -p "%s" && cp "%s" "%s"', transcriptDir, audioFile, transcriptDir .. "recording.wav")}
    )

    saveAndTranscribeTask:start()
    logToFile("Save task started")
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
