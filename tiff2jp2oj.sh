#!/bin/bash

# POC TIFF to JP2 conversion with OpenJpeg

# Installation directory
instDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"


# Display usage message if command line does not contain expected
# number of arguments
if [ "$#" -ne 2 ] ; then
  echo "Usage: tiff2JP2.sh dirIn dirOut" >&2
  exit 1
fi

# Input and output directories
dirIn="$1"
dirOut="$2"
dirMaster="$dirOut/master"
dirAccess="$dirOut/access"

if ! [ -d "$dirIn" ] ; then
  echo "input directory does not exist" >&2
  exit 1
fi

if ! [ -d "$dirOut" ] ; then
  mkdir "$dirOut"
fi

if ! [ -d "$dirMaster" ] ; then
  mkdir "$dirMaster"
fi

if ! [ -d "$dirAccess" ] ; then
  mkdir "$dirAccess"
fi

# Add OpenJPEG path to LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib

# Codestream comment strings for master and access images
cCommentMaster="KB_MASTER_LOSSLESS_01/01/2015"
cCommentAccess="KB_ACCESS_LOSSY_01/01/2015"

# Files to store OPJ stdout, stderr
stdoutOPJ="opj_out.txt"
stderrOPJ="opj_err.txt"

# Remove these files if they exist already (writing to them will be done in append mode!)

if [ -f $stdoutOPJ ] ; then
  rm $stdoutOPJ
fi

if [ -f $stderrOPJ ] ; then
  rm $stderrOPJ
fi


counter=0

while IFS= read -d $'\0' -r file ; do
    # Update counter
    counter=$((counter+1))

    # File basename, extension removed
    bName=$(basename "$file" | cut -f 1 -d '.')
    
    # Output name
    outName=$bName.jp2

    # Full output paths
    outMaster="$dirMaster/$outName"
    outAccess="$dirAccess/$outName"

    echo "Input file: "$file
    echo "Output file: "$outName

    # Construct OpenJPEG Kakadu command lines (lossless master, lossy access copy)

    cmdlineMaster="opj_compress -i "$file"
            -o "$outMaster"
            Creversible=yes
            Clevels=5
            Corder=RPCL
            Stiles={1024,1024}
            Cblk={64,64}
            Cprecincts={256,256},{256,256},{128,128}
            Clayers=11
            -rate $bitratesMaster
            Cuse_sop=yes
            Cuse_eph=yes
            Cmodes=SEGMARK
            -jp2_box "$xmpName"
            -com "$cCommentMaster""

    cmdlineAccess="opj_compress -i "$file"
            -o "$outAccess"
            -I
            -n 6
            -p RPCL
            -t 1024,1024
            -b 64,64
            -c [256,256],[256,256],[128,128],[128,128],[128,128],[128,128]
            -r 2560,1280,640,320,160,80,40,20
            -SOP
            -EPH
            -M 32
            -C "$cCommentAccess""

    # Convert to JP2 (lossless master, lossy access copy)   
    #$cmdlineMaster >>$stdoutOPJ 2>>$stderrOPJ
    $cmdlineAccess >>$stdoutOPJ 2>>$stderrOPJ
    
done < <(find $dirIn -maxdepth 1 -type f -regex '.*\.\(tif\|tiff\|TIF\|TIFF\)' -print0)


