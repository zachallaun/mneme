Output examples/demo.gif
Output examples/demo.mp4
# Output examples/demo.webm

Set Shell "bash"
Set FontSize 22
Set FontFamily "Berkeley Mono"
Set Width 1600
Set Height 800
Set Padding 20
Set TypingSpeed 30ms
Set Theme "Argonaut"

# Setup

Hide
Type "cd examples/demo_project && clear" Enter
Type "MIX_ENV=test mix deps.get && clear" Enter
Type "MIX_ENV=test mix deps.compile --force && clear" Enter
Type "MIX_ENV=test mix compile && clear" Enter
Sleep 5s
Type "clear" Enter
Show

# Recording

Type "# Mneme is a snapshot testing library" Sleep 300ms Enter Sleep 1s
Type "# It introduces a new assertion macro: auto_assert" Sleep 300ms Enter Sleep 1s
Type "# When a new auto-assertion is found, Mneme generates a pattern for you" Sleep 300ms Enter Sleep 1s
Type "# Let's see what it looks like..." Sleep 300ms Enter Sleep 1s
Type "clear && mix test --only first_example" Sleep 1.5s Enter
Sleep 4s

Type "y" Sleep 2s Enter
Sleep 2s

Type "y" Sleep 2s Enter
Sleep 3s

Type "# We accepted both patterns and the test was updated automatically" Sleep 300ms Enter Sleep 1s
Type "# You're also prompted if something changes and a pattern doesn't match" Sleep 300ms Enter Sleep 1s
Type "clear && mix test --only second_example" Sleep 1.5s Enter
Sleep 4s

Type "y" Sleep 2s Enter
Sleep 3s

Type "# Testing with Mneme can be really interactive and fun!" Sleep 300ms Enter Sleep 1s
Type "# Give it a try and please share any feedback you have!" Sleep 5s

# VHS documentation
#
# Output:
#   Output <path>.gif               Create a GIF output at the given <path>
#   Output <path>.mp4               Create an MP4 output at the given <path>
#   Output <path>.webm              Create a WebM output at the given <path>
#
# Require:
#   Require <string>                Ensure a program is on the $PATH to proceed
#
# Settings:
#   Set FontSize <number>           Set the font size of the terminal
#   Set FontFamily <string>         Set the font family of the terminal
#   Set Height <number>             Set the height of the terminal
#   Set Width <number>              Set the width of the terminal
#   Set LetterSpacing <float>       Set the font letter spacing (tracking)
#   Set LineHeight <float>          Set the font line height
#   Set LoopOffset <float>%         Set the starting frame offset for the GIF loop
#   Set Theme <json|string>         Set the theme of the terminal
#   Set Padding <number>            Set the padding of the terminal
#   Set Framerate <number>          Set the framerate of the recording
#   Set PlaybackSpeed <float>       Set the playback speed of the recording
#
# Sleep:
#   Sleep <time>                    Sleep for a set amount of <time> in seconds
#
# Type:
#   Type[@<time>] "<characters>"    Type <characters> into the terminal with a
#                                   <time> delay between each character
#
# Keys:
#   Backspace[@<time>] [number]     Press the Backspace key
#   Down[@<time>] [number]          Press the Down key
#   Enter[@<time>] [number]         Press the Enter key
#   Space[@<time>] [number]         Press the Space key
#   Tab[@<time>] [number]           Press the Tab key
#   Left[@<time>] [number]          Press the Left Arrow key
#   Right[@<time>] [number]         Press the Right Arrow key
#   Up[@<time>] [number]            Press the Up Arrow key
#   Down[@<time>] [number]          Press the Down Arrow key
#   PageUp[@<time>] [number]        Press the Page Up key
#   PageDown[@<time>] [number]      Press the Page Down key
#   Ctrl+<key>                      Press the Control key + <key> (e.g. Ctrl+C)
#
# Display:
#   Hide                            Hide the subsequent commands from the output
#   Show                            Show the subsequent commands in the output
