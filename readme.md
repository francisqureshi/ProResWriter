

PrintWorkflow app

Topline TODO:

so the current offering makes a temp file for adding timecode track!
so instead, we should try just lifting the OCF timecode chat!!!

- [x] copy/lift timecode track from OCF, no need to calculate TC!
- [ ] copy/lift source audio tracks 
- [ ] gather material in every frame rate
    - [ ] 25
    - [ ] 24
    - [ ] 23.976
    - [ ] 30
    - [ ] 29.97
    - [ ] 59.94
    - [ ] 29.97 DF
    - [ ] 59.94 DF
    - [ ] 60




- [ ] create tests with media in framerate 

==========
Pairing workflow 

Render MM clips from grade project to live intermediate Segments folder as ProRes 4444

Add MM to app Segment group

Add the OCF to app OCF group

Pair them using:
OCF name as the Key 
+ Resolution
+ FPS 
+ SRC TC 
+ Reel Name if available 

Handle duplicates…

==========

Blank source file creation (make once)

Blank frames made, use pre-made watermarked frame. 

[
COMMON format library for known sizes?

If a new size comes along, make small video of it to be used a repeatable slug.🐌 

SRC TC burn-in might invalidate this format library 

]

Burn-in usual details
File name
Project
SRC TC

BUT…? Is this possible without sloooow render??? But blankRush also only has to be made once?…. 

Could be auto-generated as they are paired with segments.


Mirror/ Capture audio track configuration
Codec and sample rate 


Render these files to intermediate_stock folder

Set OCF files in app to in-use and connect the intermediate_stock files 

UI option to hide unused OCF

========

Printing workflow

Glues all the files together, everything must pre-baked


========

UI / dynamic refresh 

Hide / grey out unused OCF
Track segment changes
Track print render history 

Calculate lengths each print 
/ segments can be refreshed incase their size changes

Deal with media offline 


====

Node expansion 
Install on a all machines and send jobs to them for distrobuted extra speed ⚡️
