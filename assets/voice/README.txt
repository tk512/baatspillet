Spoken instructions for the docking screen (great for a kid who can't read yet).

Drop an OGG here named  dock_<portid>.ogg  and it plays when the boat docks
at that town, and again when the 🔊 button is tapped:

    dock_bergen.ogg
    dock_oslo.ogg
    dock_floro.ogg
    dock_leroy.ogg
    dock_klokkarvik.ogg
    dock_alversund.ogg
    dock_hjellestad.ogg

Example to say into your mic and convert:
    "Velkommen til Bergen! Ta passasjerene til en annen by."

Convert a recording to OGG (mono, small) with ffmpeg:
    ffmpeg -i "in.m4a" -ac 1 -ar 22050 -c:a libvorbis -q:a 4 dock_bergen.ogg

If no file is present, the screen just plays a boat horn as feedback.
