#!/bin/bash

# Rough proof-of concept for TIFF to JP2 conversion workflow
# based on Kakadu. Script converts directory of uncompressed TIFF images
# to JP2, using KB specs for lossless preservation masters and lossy access
# copies.
#
# Script automatically chooses the appropriate bitrate values depending
# on the number of samples per pixel (works for both RGB and grayscale
# images, provided that the number of bits per sample equals 8).
#
# After conversion the following quality checks are done on the generated JP2s:
#
# 1. Check of technical properties against KB specs (jpylyzer + schematron)
# 2. Check on pixel values (master JP2s only)
#
# Dependencies:
#
# - Kakadu demo binaries (kdu_compress)
# - Exiftool (needed for metadata extraction from TIFF)
# - sed (needed to process XMP sidecar files)
# - xsltproc (part of libxslt library)
# - xmllint (part of libxml library)
# - GraphicsMagick (ImageMagick crashes on `TIFFReadDirectory' tag in TIFFS)
# - Jpylyzer
#
# TODO:
# - Analyse /parse results of compare tool
# - Combine results of wuality checks into global Pass / Fail file 
# - Check exit status of kdu_compress
# - Modularise script, refactor redundant bits into functions 
# - Tonnes of other improvements

# Installation directory
instDir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Location of Schematron XSL files
xslPath=$instDir/iso-schematron-xslt1

# Location of Schematron schemas
schemaPath=$instDir/schemas
schemaMaster=$schemaPath/master300Colour_2014.sch
schemaAccess=$schemaPath/access300Colour_2014.sch

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

# Location of Kakadu binaries
kduPath=~/kakadu

# Add Kakadu path to LD_LIBRARY_PATH
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$kduPath

# Codestream comment strings for master and access images
cCommentMaster="KB_MASTER_LOSSLESS_01/01/2015"
cCommentAccess="KB_ACCESS_LOSSY_01/01/2015"

# Files to store Kakadu stdout, stderr
stdoutKakadu="kdu_out.txt"
stderrKakadu="kdu_err.txt"

# Files to store Exiftool stdout, stderr
stdoutExif="exif_out.txt"
stderrExif="exif_err.txt"

# Files to store compare stdout, stderr
stdoutCompare="compare_out.txt"
stderrCompare="compare_err.txt"

# Files with results (pass/fail) of Schematron assessment
successFileMaster="successMaster.csv"
successFileAccess="successAccess.csv"

# Files that summarise failed tests for JP2s that didn't pass Schematron assessment
failedTestsFileMaster="failedMaster.csv" 
failedTestsFileAccess="failedAccess.csv"

#  File to store output of GraphicsMagick compare
fcompare="compare.txt"

# Remove these files if they exist already (writing to them will be done in append mode!)

if [ -f $stdoutKakadu ] ; then
  rm $stdoutKakadu
fi

if [ -f $stderrKakadu ] ; then
  rm $stderrKakadu
fi

if [ -f $stdoutExif ] ; then
  rm $stdoutExif
fi

if [ -f $stderrExif ] ; then
  rm $stderrExif
fi

if [ -f $stdoutCompare ] ; then
  rm $stdoutCompare
fi

if [ -f $stderrCompare ] ; then
  rm $stderrCompare
fi

if [ -f $successFileMaster ] ; then
    rm $successFileMaster
fi

if [ -f $successFileAccess ] ; then
    rm $successFileAccess
fi

if [ -f $failedTestsFileMaster ] ; then
    rm $failedTestsFileMaster
fi

if [ -f $failedTestsFileAccess ] ; then
    rm $failedTestsFileAccess
fi

if [ -f $fcompare ] ; then
  rm $fcompare
fi

counter=0

while IFS= read -d $'\0' -r file ; do
    # Update counter
    counter=$((counter+1))

    # File basename, extension removed
    bName=$(basename "$file" | cut -f 1 -d '.')
    
    # Output name
    outName=$bName.jp2

    # Name for temporary XMP sidecar file
    xmpName=$bName.xmp

    # Full output paths
    outMaster="$dirMaster/$outName"
    outAccess="$dirAccess/$outName"

    # Create new entry in GraphicMagick compare output file
    echo "####" >> $fcompare
    echo "Source TIFF:" $file >> $stdoutCompare
    echo "Master JP2:" $outMaster >> $stdoutCompare

    # Extract metadata from TIFF with Exiftool and write to XMP sidecar
    exiftool "$file" -o "$xmpName" >> $stdoutExif 2>> $stderrExif

    # Insert string "xml "at start of sidecar file so Kakadu knows to use XML box 
    sed -i "1s/^/xml /" "$xmpName"

    # Get SamplesPerPixel value 
    samplesPerPixel=$(exiftool -s -s -s -SamplesPerPixel "$file")

    # Determine bitrate values, depending on samplesPerPixel value
    # Since bitrate = (BPP/CompressionRatio)
    if [ $samplesPerPixel -eq 3 ] ; then
        bitratesMaster="-,4.8,2.4,1.2,0.6,0.3,0.15,0.075,0.0375,0.01875,0.009375"
        bitratesAccess="1.2,0.6,0.3,0.15,0.075,0.0375,0.01875,0.009375" 
    fi

    if [ $samplesPerPixel -eq 1 ] ; then
        bitratesMaster="-,1.6,0.8,0.4,0.2,0.1,0.05,0.025,0.0125,0.00625,0.003125"
        bitratesAccess="0.4,0.2,0.1,0.05,0.025,0.0125,0.00625,0.003125"
    fi

    # Construct Kakadu command lines (lossless master, lossy access copy)

    cmdlineMaster="$kduPath/kdu_compress -i "$file"
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

    cmdlineAccess="$kduPath/kdu_compress -i "$file"
            -o "$outAccess"
            Creversible=no
            Clevels=5
            Corder=RPCL
            Stiles={1024,1024}
            Cblk={64,64}
            Cprecincts={256,256},{256,256},{128,128}
            Clayers=8
            -rate $bitratesAccess
            Cuse_sop=yes
            Cuse_eph=yes
            Cmodes=SEGMARK
            -jp2_box "$xmpName"
            -com "$cCommentAccess""

    # Convert to JP2 (lossless master, lossy access copy)   
    $cmdlineMaster >>$stdoutKakadu 2>>$stderrKakadu
    $cmdlineAccess >>$stdoutKakadu 2>>$stderrKakadu
    
    # Run jpylyzer on master and access JP2s
    outJpylyzerMaster="jpylyzer_master.xml"
    outJpylyzerAccess="jpylyzer_access.xml"

    jpylyzer "$outMaster" > $outJpylyzerMaster
    jpylyzer "$outAccess" > $outJpylyzerAccess

    # Assess jpylyzer output using Schematron reference application
    if [ $counter == "1" ]; then
        # We only need to generate xx1_*.sch, xx2_*.sch and xxx_*.xsl once
        xsltproc --path $xslPath $xslPath/iso_dsdl_include.xsl $schemaMaster > xxx1_master.sch
        xsltproc --path $xslPath $xslPath/iso_abstract_expand.xsl xxx1_master.sch > xxx2_master.sch
        xsltproc --path $xslPath $xslPath/iso_svrl_for_xslt1.xsl xxx2_master.sch > xxx_master.xsl
        xsltproc --path $xslPath $xslPath/iso_dsdl_include.xsl $schemaAccess > xxx1_access.sch
        xsltproc --path $xslPath $xslPath/iso_abstract_expand.xsl xxx1_access.sch > xxx2_access.sch
        xsltproc --path $xslPath $xslPath/iso_svrl_for_xslt1.xsl xxx2_access.sch > xxx_access.xsl
    fi

    outSchematronMaster="schematronMaster.xml"
    outSchematronAccess="schematronAccess.xml"

    xsltproc --path $xslPath xxx_master.xsl $outJpylyzerMaster > $outSchematronMaster
    xsltproc --path $xslPath xxx_access.xsl $outJpylyzerAccess > $outSchematronAccess
    
    # Extract failed tests from Schematron output
    
    # Line below extracts literal test
    failedTestsMaster=$(xmllint --xpath "//*[local-name()='schematron-output']/*[local-name()='failed-assert']/@test" $outSchematronMaster)
    failedTestsAccess=$(xmllint --xpath "//*[local-name()='schematron-output']/*[local-name()='failed-assert']/@test" $outSchematronAccess)

    # This is just in case anything went wrong with the Schematron validation
    schematronFileSizeMaster=$(wc -c < $outSchematronMaster)
    schematronFileSizeAccess=$(wc -c < $outSchematronAccess)

    if [ $schematronFileSizeMaster == 0 ]; then
        failedTestsMaster="SchematronFailure"
    fi
        
    if [ $schematronFileSizeAccess == 0 ]; then
        failedTestsAccess="SchematronFailure"
    fi

    # JP2 passed policy-based assessment if failedTests is empty 

    if [ ! "$failedTestsMaster" ]
    then
        successMaster="Pass"
    else
        successMaster="Fail"
        # Failed tests to output file
        echo \"$outMaster\",$failedTestsMaster >> $failedTestsMasterFile
    fi

    if [ ! "$failedTestsAccess" ]
    then
        successAccess="Pass"
    else
        successAccess="Fail"
        # Failed tests to output file
        echo \"$outAccess\",$failedTestsAccess >> $failedTestsAccessFile
    fi

    # Write success file (lists validation outcome for each EPUB)
    echo \"$outMaster\",$successMaster >> $successFileMaster
    echo \"$outAccess\",$successAccess >> $successFileAccess

    # Check if pixel values of master JP2 are identical to source TIFF
    gm compare -metric PAE "$file" "$outMaster"  >> $stdoutCompare 2>> $stderrCompare

    # Remove temp files
    rm $xmpName
    rm $outJpylyzerMaster
    rm $outJpylyzerAccess
    rm $outSchematronMaster
    rm $outSchematronAccess

done < <(find $dirIn -maxdepth 1 -type f -regex '.*\.\(tif\|tiff\|TIF\|TIFF\)' -print0)

rm xxx*.sch
rm xxx*.xsl

