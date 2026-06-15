Harbor-master portraits for the docking screen (the face in the left frame).

Drop a PNG here named after the port id and it replaces the pixel-art
placeholder character:

    bergen.png
    oslo.png
    floro.png
    leroy.png
    alversund.png
    hjellestad.png
    klokkarvik.png

Pixel-art / retro style looks best (it's shown in a sunken "portrait well").
Roughly square, any size — it's scaled to fit. Until a file exists, a little
sailor (or a hooded figure at "scary" harbours) is drawn in code.

Tip: a harbour can be given a mood in src/data/ports.lua with  mood = "scary"
(default is "cosy") — that switches the panel to cold stone colours, a hooded
harbour master, and threatening music.
