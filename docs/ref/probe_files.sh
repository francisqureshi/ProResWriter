  for folder in /Volumes/WI-64/__POST/__DAVINCI\ FILES/_TEST_MATERIAL/*/; do
    for file in "$folder"*; do
      if [ -f "$file" ]; then
        echo "=== $(basename "$file") ==="
        ffprobe -v error -show_entries stream=index,codec_type,codec_name,r_frame_rate,avg_frame_rate:stream_tags=timecode:format_tags=timecode "$file" | sed 's/TAG:/  /'
        echo ""
      fi
    done
  done > fps_fraction_output.txt
