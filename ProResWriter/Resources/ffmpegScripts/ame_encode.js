// AME ExtendScript for encoding with preset
// Usage: Called from Swift via AppleScript

function encodeWithPreset(sourcePath, destinationPath, presetName) {
    try {
        $.writeln("Starting AME encode...");
        $.writeln("Source: " + sourcePath);
        $.writeln("Destination: " + destinationPath);
        $.writeln("Preset: " + presetName);
        
        var exporter = app.getExporter();
        
        if (exporter) {
            // Start the export
            var encoderWrapper = exporter.exportItem(sourcePath, destinationPath, presetName);
            
            // Add event listeners
            exporter.addEventListener("onEncodeComplete", function(eventObj) {
                $.writeln("Encode Complete Status: " + eventObj.encodeCompleteStatus);
                var encodeSuccess = exporter.encodeSuccess;
                $.writeln("Encode Success: " + encodeSuccess);
            }, false);

            exporter.addEventListener("onError", function(eventObj) {
                $.writeln("Error while encoding");
                var encodeSuccess = exporter.encodeSuccess;
                $.writeln("Encode Status: " + encodeSuccess);
            }, false);
            
            $.writeln("Export started successfully");
            return "SUCCESS";
        } else {
            $.writeln("Could not get exporter");
            return "ERROR: Could not get exporter";
        }
        
    } catch (error) {
        $.writeln("Script error: " + error.toString());
        return "ERROR: " + error.toString();
    }
}

// Auto-execute if parameters are provided
if (typeof SOURCE_FILE !== 'undefined' && typeof DEST_PATH !== 'undefined' && typeof PRESET_NAME !== 'undefined') {
    encodeWithPreset(SOURCE_FILE, DEST_PATH, PRESET_NAME);
}