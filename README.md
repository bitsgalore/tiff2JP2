# About this repo

(Very!) rough proof-of concept for TIFF to JP2 conversion workflow
based on Kakadu. Script converts directory of uncompressed TIFF images
to JP2, using KB specs for lossless preservation masters and lossy access
copies.

The script automatically chooses the appropriate bitrate values depending
on the number of samples per pixel (this works for both RGB and grayscale
images, provided that the number of bits per sample equals 8).

After conversion the following quality checks are done on the generated JP2s:

1. Check of technical properties against KB specs (jpylyzer + schematron)
2. Check on pixel values (master JP2s only)

## Dependencies

- Kakadu binaries (kdu_compress)
- Exiftool (needed for metadata extraction from TIFF)
- sed (needed to process XMP sidecar files)
- xsltproc (part of libxslt library)
- xmllint (part of libxml library)
- GraphicsMagick (ImageMagick crashes on `TIFFReadDirectory' tag in TIFFS)
- Jpylyzer
