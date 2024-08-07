Output examples/demo.gif
Output examples/demo.mp4
# Output examples/demo.webm

Set Shell zsh
Set FontSize 20
Set FontFamily "Berkeley Mono"
Set Width 1600
Set Height 900
Set TypingSpeed 30ms
Set Theme "Argonaut"
Set Margin 30
Set MarginFill "#242841"
Set Padding 30
Set WindowBar ColorfulRight
Set WindowBarSize 40

# Setup

Hide
Type "setopt interactivecomments" Enter
Type "cd examples/demo_project && clear" Enter
Type "MIX_ENV=test mix deps.get && clear" Enter
Type "MIX_ENV=test mix deps.compile --force && clear" Enter
Type "MIX_ENV=test mix compile && clear" Enter
Sleep 5s
Type "clear" Enter
Type "# Mneme is a snapshot testing library for Elixir..."
Show

# Recording
Sleep 300ms Enter Sleep 1s
Type "# It adds a handful of new assertions, like `auto_assert`" Sleep 300ms Enter Sleep 1s
Type "# When a new auto-assertion is run, Mneme fills in the test for you" Sleep 300ms Enter Sleep 1s
Type "# Let's try it out..." Sleep 300ms Enter Sleep 1s
Type "clear" Sleep 1.5s Enter Sleep 500ms
Type "mix test --only first_example" Sleep 300ms Enter
Sleep 4s

Type "y" Sleep 2s Enter
Sleep 2s

Type "y" Sleep 2s Enter
Sleep 3s

Type "# We accepted both patterns and the test was updated automatically" Sleep 300ms Enter Sleep 1s
Type "# You're also prompted if something changes and a pattern doesn't match anymore" Sleep 300ms Enter Sleep 1s
Type "clear" Sleep 1.5s Enter Sleep 500ms
Type "mix test --only second_example" Sleep 300ms Enter
Sleep 4s

Type "y" Sleep 2s Enter
Sleep 3s

Type "# Mneme makes your tests interactive, like a REPL" Sleep 300ms Enter Sleep 1s
Type "# If you give it a try, please share any feedback you have!" Sleep 5s

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
