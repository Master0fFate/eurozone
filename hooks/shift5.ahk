; eurozone — AutoHotkey v2 hook
; Shift+4 -> euro sign (U+20AC)

#Requires AutoHotkey v2.0
#SingleInstance Force

+4::SendText("{U+20AC}")
