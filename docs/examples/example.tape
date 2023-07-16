# Setup

Hide

Set Shell zsh
Set FontSize 18
Set FontFamily "Berkeley Mono"
Set Width 1600
Set Height 900
Set Margin 30
Set MarginFill "#242841"
Set Padding 30
Set WindowBar ColorfulRight
Set WindowBarSize 40
Set Theme "Argonaut"
Set TypingSpeed 30ms

Type "cd docs/examples" Enter
Type "alias cat='bat --plain'" Enter
Type "mix deps.get && mix compile" Enter
Sleep 6s
Ctrl+L

Show

# Record

Type "cat example.exs" Sleep 500ms Enter
Sleep 2s

Type "mix test example.exs" Sleep 500ms Enter
Sleep 3s
Type "y" Sleep 2s Enter
Sleep 1s

Type "cat example.exs" Sleep 500ms Enter
Sleep 3s
