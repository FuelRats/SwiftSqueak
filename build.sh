#!/bin/bash
swift build
cp -R localisation .build/debug/
cp -R templates .build/debug/
cp -R regions.json .build/debug/
cp -R namedbodies.json .build/debug/

INPUT_DIR="Sources/mechasqueak/WebServer/Views"
OUTPUT_FILE="Public/css/styles.css"

echo "🔍 Finding and concatenating .css files in $INPUT_DIR..."
find "$INPUT_DIR" -type f -name "*.css" | sort | xargs cat > "$OUTPUT_FILE"

echo "✅ Built $OUTPUT_FILE"
