#!/bin/bash
# Example audio "Zoom" movie generation
# e.g. ./audio_zoom.sh 'aliens driving a red 1966 chevy impala lowrider:6| Unreal Engine Ray Tracing:4|Photorealistic:2|text:0|watermark:0|signature:0|logo:0' inputs/ssc330B.mp3

TEXT="$1"
FILENAME="$2"
sngDataFile='./sngData.tmp'
sngLength=`ffprobe -i ${FILENAME} -show_entries format=duration -v quiet -of csv="p=0"`
printf -v sngLengthRnded %.0f "$sngLength"
ffmpeg -i $FILENAME -filter_complex ebur128  -f null   -  2>&1 |grep -v 'Summary:' | grep Parsed|sed 's|^\[.*\] ||g' > $sngDataFile
#MAX_EPOCHS=((sngLengthRnded*30)) #30fps
#MAX_EPOCHS=$3
MAX_EPOCHS=`cat $sngDataFile |wc -l` 
fps=$(($MAX_EPOCHS/$sngLengthRnded))
LR=0.1
OPTIMISER=Adam
MAX_ITERATIONS=25
SEED=`shuf -i 1-9999999999 -n 1` # Keep the same seed each epoch for more deterministic runs

# Extract
FILENAME_NO_EXT=${FILENAME%.*}
#FILE_EXTENSION=${FILENAME##*.}
FILE_EXTENSION=".png"
# Initial run
python generate.py -p="$TEXT" -opt="$OPTIMISER" -lr=$LR -i=$MAX_ITERATIONS -se=$MAX_ITERATIONS --seed=$SEED -o="$FILENAME"
cp "$FILENAME" "$FILENAME_NO_EXT"-0000."$FILE_EXTENSION"

convert "$FILENAME" -distort SRT 1.01,0 -gravity center "$FILENAME"	# Zoom
convert "$FILENAME" -distort SRT 1 -gravity center "$FILENAME"	# Rotate

# Momentary Loudness measures the loudness of the past 400 Milliseconds.
# Short Term Loudness measures the loudness of the past 3 Seconds.
# Integrated Loudness (Also called Programme Loudness) indicates how loud the programme is on average, and is measured over entire duration of material.
# Loudness Range quantifies, in LU, the statistical distribution of short term loudness within a programme. 
# True Peak indicates accurate measurements of (possible) intersample peaks. 

# Feedback image loop
for (( i=1; i<=$MAX_EPOCHS; i++ ))
do
  sng_targlufs=`sed -n ${i}p sngData.tmp| sed -r 's|^.*TARGET:-([[:digit:]]*).*|\1|g'` #target loudness
  sng_I=`sed -n ${i}p sngData.tmp| sed -r 's|[^I]*I:\s*-([[:digit:]]+\.[[:digit:]]+).*|\1|g'` #Integrated loudness
  sng_M=`sed -n ${i}p sngData.tmp| sed -r 's|[^M]*M:\s*-([[:digit:]]+\.[[:digit:]]+).*|\1|g'` #Momentary loudness
  sng_S=`sed -n ${i}p sngData.tmp| sed -r 's|.*[^S]*S:\s*-([[:digit:]]+\.[[:digit:]]+).*|\1|g'` #Short-term loudness
  #echo "100/1024*20" | bc -l # 20 is what percent of 1024
  sng_I_percent=`echo "(100/${sng_targlufs}*${sng_I}) *0.01" | bc -l` #likely too big/loud
  sng_MofI_percent=`echo "(100/${sng_I}*${sng_M}) *0.01" | bc -l` #likely too big/loud
  sng_MofS_percent=`echo "(100/${sng_S}*${sng_M}) *0.01" | bc -l` # current vs last 3 seconds... goldilocks?
  sng_SofI_percent=`echo "(100/${sng_I}*${sng_S}) *0.01" | bc -l` #likely too big/loud, but 3sec smoothing?
  printf -v sng_lufs_rnd %.0f "$sng_I"
  printf -v sng_M_rnd %.0f "$sng_M"
  printf -v sng_S_rnd %.0f "$sng_S"
  

  padded_count=$(printf "%04d" "$i")  
  python generate.py -p="$TEXT" -opt="$OPTIMISER" -lr=$LR -i=$MAX_ITERATIONS -se=$MAX_ITERATIONS --seed=$SEED -ii="$FILENAME" -o="$FILENAME"
  cp "$FILENAME" "$FILENAME_NO_EXT"-"$padded_count"."$FILE_EXTENSION"    
  convert "$FILENAME" -distort SRT ${sng_MofS_percent},0 -gravity center "$FILENAME" # Zoom
  #convert "$FILENAME" -distort SRT 1 -gravity center "$FILENAME"	# Rotate
done

# Make video - Nvidia GPU expected
ffmpeg -y -i "$FILENAME_NO_EXT"-%05d."$FILE_EXTENSION" -b:v 8M -c:v h264_nvenc -pix_fmt yuv420p -strict -2 -filter:v "minterpolate='mi_mode=mci:mc_mode=aobmc:vsbmc=1:fps=60'" video.mp4
