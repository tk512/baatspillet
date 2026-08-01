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

Named clips the game asks for by name (all optional -- it falls back to a sound
effect if the file isn't here). STILL TO RECORD:

    pilen_viser_vei.ogg  -- plays every time cargo goes aboard, a moment after
                            you leave the harbour, while the words "Pilen viser
                            vei" spring up over the gold arrow. Say just that:
                            "Pilen viser vei!"

    sann_spiller_du.ogg  -- plays when the help page opens (the "?" disc on the
                            title screen). The page is words for a grown-up, so
                            this is the child's share of it. Something like:
                            "Sånn spiller du Båtspillet!"

Already recorded, for reference:

    nei_spill_videre.ogg -- plays with "Vil du avslutte?" on the title screen.
                            Finn-Erik: "Nei, du må spille videre!"

Example to say into your mic and convert:
    "Velkommen til Bergen! Ta passasjerene til en annen by."

Convert a recording to OGG (mono, small). ffmpeg here has no Vorbis encoder, so
it goes through oggenc -- the two-step is the reliable path:

    ffmpeg -i "in.m4a" -ac 1 -f wav out.wav && oggenc -q 4 -o clip.ogg out.wav

Keep the recording's OWN sample rate rather than forcing 22050: a lossy clip
that is also downsampled sounds twice re-encoded. Check the level before you
ship it -- these clips sit around -15 dB mean:

    ffmpeg -i clip.ogg -af volumedetect -f null - 2>&1 | grep mean_volume

If a clip lands quiet (say -19 dB), lift the FILE, not the call site --
playNamedVoice is already at 1.0 and LÖVE will not go above it:

    ffmpeg -i "in.m4a" -ac 1 -af "volume=4.2dB,alimiter=limit=0.97" -f wav out.wav

If no file is present, the screen just plays a boat horn as feedback.
