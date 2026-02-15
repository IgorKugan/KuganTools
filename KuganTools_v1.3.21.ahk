; =========================================
; Ragnarok WASD + Mouse Mode (AHK v1)
; v1.3.21 - Real screen coords + DPI-aware + Lazy mode + Extra Keys (wheel remap + extra key clicks)
; Works ONLY when rtales.bin is the active window
;
; Mouse Mode FIX (Tap):
; - While doing "down at click point" and waiting to return, cursor is HARD-LOCKED at click point.
; - If user releases before return happens (tap), we do LButton up AT CLICK POINT, THEN return cursor.
; - If holding (hold), lock lasts only during the initial delay, then releases (mouse free while holding).
; =========================================

#NoEnv
#SingleInstance Force
#InstallKeybdHook
#UseHook On
SendMode Input
SetBatchLines, -1
ListLines, Off

; --- DPI awareness (IMPORTANT for correct screen coords in windowed/borderless/fullscreen on any DPI) ---
; Best effort: try Per-Monitor v2, fallback to SetProcessDPIAware if unavailable.
hUser := DllCall("GetModuleHandle", "str", "user32.dll", "ptr")
if (!hUser)
    hUser := DllCall("LoadLibrary", "str", "user32.dll", "ptr")
pDpiCtx := DllCall("GetProcAddress", "ptr", hUser, "astr", "SetProcessDpiAwarenessContext", "ptr")
if (pDpiCtx)
    DllCall(pDpiCtx, "ptr", -4, "ptr") ; DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
else
    DllCall("SetProcessDPIAware")
CoordMode, Mouse, Screen


OnExit, __KuganCleanup

StopWalk_Init()

; ---------------- Fixed Game EXE ----------------
global gGameExe := "rtales.bin"

; ---------------- Master State ----------------
global gEnabled := false

; Per-mode toggles
global gWASDOn := 1
global gMouseOn := 0

; WASD pause (Enter)
global gWASDPaused := false

; Mouse Mode sub-modes (exclusive)
global gMouseCapsMode := 1     ; default on
global gMouseRightMode := 0

; Points
global gCenterX := ""
global gCenterY := ""
global gClickX  := ""
global gClickY  := ""

; Points in RELATIVE coordinates (0.0 - 1.0) so it works in fullscreen / borderless / windowed and any resolution
global gCenterRX := ""   ; Center relative X
global gCenterRY := ""   ; Center relative Y
global gClickRX  := ""   ; Click point relative X
global gClickRY  := ""   ; Click point relative Y

; Reference client size captured when points were set (used to auto-scale distances)
global gRefClientW := 0
global gRefClientH := 0

; Last known game client rect (screen coords)
global gGameClientL := 0
global gGameClientT := 0
global gGameClientW := 0
global gGameClientH := 0

; WASD distances
global gDist := 100
global gCapsDist := 20

; WASD delays
global gDownDelayMs := 0
global gClickMoveDelayMs := 0

; WASD stop
global gStopDist := 12
global gStopMinHoldMs := 120
; WASD ramp (aceleração / desaceleração)
; - gRampAccel: quão rápido chega na direção (0.10 a 0.35)
; - gRampDecel: quão rápido volta quando solta (0.08 a 0.25)
; - gRampEps: tolerância pra considerar "parou"
global gRampAccel := 0.20
global gRampDecel := 0.12
global gRampEps   := 0.04
global gVelX := 0.0
global gVelY := 0.0



; WASD state machine (evita zigzag por reentrada de Timer/Sleep)
global gWASDState := 0   ; 0=idle, 1=waitDown, 2=waitMove, 3=active
global gWASDDueTick := 0
global gWASDStartDx := 0.0
global gWASDStartDy := 0.0

; Gamepad (Xbox/joystick) suporte básico (analógico -> direção)
global gPadOn := 0
global gPadJoy := 1
global gPadDeadzone := 18  ; % (0-40)

; Mouse Mode delays
global gMouseClickMoveDelayMs := 10
global gMouseSpamDelayMs := 100  ; anti-spam ms

; Mouse Right Click inversion: when this is set (1) and the user has selected
; Modo Right Click, the macro will trigger on the Right button instead of the
; Left, leaving the left button in its normal behavior.  CapsLock still
; temporarily disables the macro.  Default is 0 (no inversion).
global gMouseRightInvert := 0
global gDefaultMouseRightInvert := 0

; -----------------------------------------------------------------------------
; Default configuration values for the reset button.  These values correspond to
; the standard settings shown in the screenshots provided (e.g. WASD distance
; of 200, Caps distance 38, delays of 10ms, etc.).  The Reset Defaults button
; will restore the in-memory variables and GUI controls to these values without
; modifying saved capture points or the hotkey.  Adjust these defaults here if
; you wish to change what Reset Defaults does.
global gDefaultWASDOn := 1
global gDefaultMouseOn := 1
global gDefaultMouseCapsMode := 1
global gDefaultMouseRightMode := 0
global gDefaultDist := 200
global gDefaultCapsDist := 38
global gDefaultDownDelayMs := 10
global gDefaultClickMoveDelayMs := 10
global gDefaultStopDist := 90
global gDefaultMouseClickMoveDelayMs := 1
global gDefaultMouseSpamDelayMs := 100

; Movement mode: 0 = WASD keys (default), 1 = Arrow keys.  This controls which
; set of keys the user uses for directional movement.  A pair of radio
; buttons in the WASD tab allows the user to toggle between these modes.
global gUseArrows := 0
global gDefaultUseArrows := 0

; -----------------------------------------------------------------------------
; Ghost Target (retículo virtual)
; -----------------------------------------------------------------------------
; Quando ativado, enquanto você está andando (WASD/Setas) o cursor fica TRAVADO no ponto
; de movimento do jogo (Click/Center), e o movimento físico do mouse (Raw Input) move um
; retículo "fantasma" (Ghost Target) dentro da área do jogo.
; Ao soltar o movimento, o cursor volta para o Ghost Target e você pode mirar/atacar.
global gGhostTarget := 0
global gDefaultGhostTarget := 0

; Auto Attack Mode (optional sub-mode for Ghost priority)
; - Adds LButton as a stop-walk override key
; - When you press WASD/Arrows, we send a directional double-click (no click-region)
global gAutoAttackMode := 0
global gDefaultAutoAttackMode := 0

; -----------------------------------------------------------------------------
; Lazy mode (element -> hold skill until click/WASD)
; -----------------------------------------------------------------------------
; Enable/disable Lazy mode from the Lazy mode tab.
; When an element hotkey is pressed:
;   1) Send the element hotkey to the game
;   2) Press and HOLD the Skill hotkey
; The Skill is released only when the user physically clicks LButton OR presses movement (WASD/Arrows).
; Start/Stop global toggle disables this entire module.
global gLazyModeOn := 0
global gDefaultLazyModeOn := 0

; Hotkeys (set in GUI)
global gLazySkillHK := ""
global gLazySagradoHK := ""
global gLazySombrioHK := ""
global gLazyFogoHK := ""
global gLazyVentoHK := ""
global gLazyNeutroHK := ""
global gLazyAguaHK := ""
global gLazyFantasmaHK := ""
global gLazyTerraHK := ""

; Runtime
global gLazyActive := false
global gLazyHoldKey := ""
global gLazyHoldCtrl := 0
global gLazyHoldAlt := 0
global gLazyHoldShift := 0
global gLazyHoldWin := 0

; Lazy cancel edge-tracking (so it doesn't instantly cancel if you're already holding keys)
global gLazyPrevLBtn := 0
global gLazyPrevRBtn := 0
global gLazyPrevMBtn := 0
global gLazyPrevX1Btn := 0
global gLazyPrevX2Btn := 0
global gLazyPrevW := 0
global gLazyPrevA := 0
global gLazyPrevS := 0
global gLazyPrevD := 0
global gLazyPrevUp := 0
global gLazyPrevLeft := 0
global gLazyPrevDown := 0
global gLazyPrevRight := 0

; Registered hotkeys cache (so we can unhook safely when values change)
global gLazyRegKeys := []
global gLazyPrevElemSagrado := 0
global gLazyPrevElemSombrio := 0
global gLazyPrevElemFogo := 0
global gLazyPrevElemVento := 0
global gLazyPrevElemNeutro := 0
global gLazyPrevElemAgua := 0
global gLazyPrevElemFantasma := 0
global gLazyPrevElemTerra := 0

; -----------------------------------------------------------------------------
; Extra Keys (WheelUp/WheelDown -> send chosen keys; hold CapsLock to scroll normally)
; -----------------------------------------------------------------------------
global gExtraKeysOn := 0
global gDefaultExtraKeysOn := 0
global gExtraWheelUpHK := ""
global gExtraWheelDownHK := ""

global gExtraClick1HK := ""
global gExtraClick2HK := ""

; Extra Keys click points (stored as absolute + relative to game client)
global gExtraClick1X := ""
global gExtraClick1Y := ""
global gExtraClick2X := ""
global gExtraClick2Y := ""
global gExtraClick1RX := ""
global gExtraClick1RY := ""
global gExtraClick2RX := ""
global gExtraClick2RY := ""

; Poll edge tracking for the click hotkeys
global gExtraPrevClick1 := 0
global gExtraPrevClick2 := 0





; Ghost runtime
global gGhostActive := false
global gGhostRetX := 0
global gGhostRetY := 0
global gGhostHwnd := 0
global gGhostGameL := 0
global gGhostGameT := 0
global gGhostGameR := 0
global gGhostGameB := 0
global gGhostScale := 1.0

; Stop movement when other keys are pressed (skills etc)
; When triggered, we immediately stop the held click and (if Ghost is active) teleport cursor to the ghost reticle.
; Also latches until movement keys are released to prevent instantly resuming while still holding WASD/Arrows.
global gStopWalkRequest := false
global gStopWalkLatch := false
global gStopWalkEnabled := 0  ; disabled for now (future scheme)
global gIgnoreLButtonEdgesUntil := 0  ; ignore synthetic LButton edges until this tick



; Start/Stop hotkey text
global gStartStopHK := ""
global gStartStopHK_Active := ""

; WASD runtime
global gLDown := false
global gHoldStartTick := 0
global gLastDx := 0
global gLastDy := 0
global gHadMove := false

; --- Stop direction latch (prevents "axis snap" on diagonal key release) ---
; Problem: when releasing diagonal (e.g., A+S) the keys may not be read as
; released on the same 10ms tick. A single tick with only one key still down
; would overwrite gLastDx/gLastDy to an axis direction (e.g., down), so the
; StopDistance action snaps to axis instead of keeping the diagonal.
; Fix: remember the last *diagonal* direction for a short window and prefer it
; for StopDistance if the last direction right before release is axis.
global gLastInputDx := 0.0
global gLastInputDy := 0.0
global gLastInputTick := 0
global gLastDiagDx := 0.0
global gLastDiagDy := 0.0
global gLastDiagTick := 0
global gDiagLatchMs := 45
global gStopDirValid := false
global gStopDirX := 0.0
global gStopDirY := 0.0

; CapsLock "tap movement" (anti-spam) while in WASD mode
; When CapsLock is held:
; - Movement happens as discrete taps (no continuous hold movement)
; - At most 1 tap every gCapsTapCooldownMs (default 80ms)
global gCapsTapCooldownMs := 80
global gCapsTapHoldMs := 30         ; how long to keep LButton down while offset at direction
global gCapsTapNextAllowedTick := 0

; Caps tap state machine (no Sleep)
global gCapsTapState := 0           ; 0=idle, 1=waitDown, 2=waitMoveDelay, 3=hold
global gCapsTapDueTick := 0
global gCapsTapDirX := 0.0
global gCapsTapDirY := 0.0

; Track key edges so a HOLD does not auto-repeat in Caps tap mode
global gPrevW := 0, gPrevA := 0, gPrevS := 0, gPrevD := 0
global gPrevUp := 0, gPrevLeft := 0, gPrevDown := 0, gPrevRight := 0


; Mouse Mode runtime
global gMouseBusy := false
global gMouseNextAllowedTick := 0
global gMouseOrigX := 0
global gMouseOrigY := 0
global gMouseHaveOrig := false
global gMouseReturnPending := false
global gMouseReturnDueTick := 0
global gMouseDownActive := false
global gMouseDownTick := 0


; -----------------------------------------------------------------------------
; ForwardLeftClick: Pass the left mouse button event through unmodified.
; When Right Click inversion is active, we want the left button to behave
; normally (e.g. interact with game UI) without triggering the macro.  The
; standard $*LButton hooks swallow the original event, so sending another
; LButton down/up from within the hook simply triggers our hotkeys again and
; the click never reaches the game.  To work around this, temporarily disable
; the Mouse Mode (gMouseOn) while injecting the synthetic click.  This
; prevents our hooks from firing on the synthetic event and allows it to pass
; through to the target window.  The `side` parameter should be either
; "down" or "up".
ForwardLeftClick(side) {
    global gMouseOn
    ; Save current Mouse Mode state and disable it while forwarding
    oldMouseOn := gMouseOn
    gMouseOn := 0
    ; Send the appropriate left click event.  Using SendEvent ensures a
    ; low-level event that most games will recognize.  Because gMouseOn is
    ; temporarily zero, our own hooks will not intercept this event.
    if (side = "down") {
        SendEvent, {LButton down}
    } else {
        SendEvent, {LButton up}
    }
    ; Restore original Mouse Mode state
    gMouseOn := oldMouseOn
}

; ---- Hard Lock (cursor force) ----
global gHardLockOn := false
global gHardLockX := 0
global gHardLockY := 0
global gHardLockUntilTick := 0

; Capture points mode
global gCaptureMode := ""
global gCaptureArmed := false

; Hotkey edit locking
global gHotkeyEditArmed := false

; Config
global gIniPath := A_ScriptDir . "\config.ini"
LoadConfig()

; -----------------------------------------------------------------------------
; Register a previously saved Start/Stop hotkey immediately on launch.  When
; the script loads the config file, gStartStopHK contains any hotkey stored in
; config.ini.  By invoking RegisterStartStopHotkey here, we ensure that the
; chosen hotkey is active as soon as the GUI appears, without requiring the
; user to reassign it manually.  Note that this call must occur before the
; first `return` in the auto‑execute section; otherwise it would never run.
RegisterStartStopHotkey(gStartStopHK)
; Additional modules from KuganTools_v1.5: XDourada and Full Protection (FP)
; Include the FindText library for pattern detection used by Full Protection.  Ensure
; this file is present in the same directory as the script.
#Include %A_ScriptDir%\FindText.ahk

; Alias config file path for convenience
global configFile := gIniPath

; === XDourada bar configuration variables ===
global xDouradaEnabled
global barWidth
global barHeight
global showNumbers
global bar1X, bar1Y, bar1Color, bar1Key, bar1Seconds, BeepEnabled1
global bar2X, bar2Y, bar2Color, bar2Key, bar2Seconds, BeepEnabled2
global bar1Running := 0
global bar2Running := 0
global remainingTime1 := 0
global remainingTime2 := 0

; === Full Protection (FP) variables ===
global TextPattern_FP := "|<FP>**55$14.zjg3D0nkAzXD0nkDg330kkA8|<FP2>**18$14.zDg3D0nkAzXD0nkDg330kkA8|<FP3>**30$14.zDA3D0nkAzXD0nkDA330kkA8"
global FP_searchArea := { x1: 0, y1: 0, x2: A_ScreenWidth, y2: A_ScreenHeight }
global FP_iconPos := { x: 0, y: 0 }
global FP_timerDuration := 600000 ; 10 minutes
global FP_warningTime := 10000
global FP_timerStart := 0
global FP_isRunning := false
global FP_isFlashing := false
global FP_iconFlashVisible := false
global FP_iconGUI := "FP_IconDisplay"
global FP_markerGUI := "FP_MarkerDisplay"
global FP_currentResetMacroHotkey := ""
global FP_lastFound := 0
global FP_missingThreshold := 6000
global FP_resetMacroKey

; === Comandos (Chat commands) ===
; Five command slots that the user can configure.  These values are loaded from
; the configuration file and displayed in the Comandos tab.  The defaults
; correspond to the first three commands specified by the user; the last two
; slots default to blank.
global Cmd1, Cmd2, Cmd3, Cmd4, Cmd5

; Additional colour picker variables for ShowMouseColor
global searchColor := ""
global selectedColor := ""
global ColorTipCreated := false

; === Read XDourada configuration from the INI file ===
IniRead, xDouradaEnabled, %configFile%, XDourada, Enabled, 0
IniRead, barWidth, %configFile%, XDourada, barWidth, 60
IniRead, barHeight, %configFile%, XDourada, barHeight, 10
IniRead, showNumbers, %configFile%, XDourada, ShowNumbers, 1

; Read bar 1 configuration
IniRead, bar1X, %configFile%, Bar1, timerX, 930
IniRead, bar1Y, %configFile%, Bar1, timerY, 590
IniRead, bar1Color, %configFile%, Bar1, barColor, B20606
IniRead, bar1Key, %configFile%, Bar1, ActivationKey, a
IniRead, bar1Seconds, %configFile%, Bar1, Duration, 59
IniRead, BeepEnabled1, %configFile%, Bar1, BeepEnabled, 1

; Read bar 2 configuration
IniRead, bar2X, %configFile%, Bar2, timerX, 930
IniRead, bar2Y, %configFile%, Bar2, timerY, 625
IniRead, bar2Color, %configFile%, Bar2, barColor, 008206
IniRead, bar2Key, %configFile%, Bar2, ActivationKey, s
IniRead, bar2Seconds, %configFile%, Bar2, Duration, 120
IniRead, BeepEnabled2, %configFile%, Bar2, BeepEnabled, 0

; === Read Full Protection configuration ===
IniRead, fpx1, %configFile%, FullProtection, x1, 0
IniRead, fpy1, %configFile%, FullProtection, y1, 0
IniRead, fpx2, %configFile%, FullProtection, x2, %A_ScreenWidth%
IniRead, fpy2, %configFile%, FullProtection, y2, %A_ScreenHeight%
FP_searchArea := { x1: fpx1, y1: fpy1, x2: fpx2, y2: fpy2 }

IniRead, fpix, %configFile%, FullProtection, icon_x, 0
IniRead, fpiy, %configFile%, FullProtection, icon_y, 0
FP_iconPos := { x: fpix, y: fpiy }

IniRead, fp_rk, %configFile%, FullProtection, ResetMacro, F6
FP_resetMacroKey := Trim(fp_rk)

; === Read Comandos configuration ===
; Load the five command strings from the INI file.  If not present, use the
; default values provided by the user.
IniRead, Cmd1, %configFile%, Commands, Cmd1, /walkdelay
IniRead, Cmd2, %configFile%, Commands, Cmd2, /skip
IniRead, Cmd3, %configFile%, Commands, Cmd3, @packetfilter APGCBOHM GSPGCBOHM TPGCBOHM BSPGCBOH
IniRead, Cmd4, %configFile%, Commands, Cmd4,
IniRead, Cmd5, %configFile%, Commands, Cmd5,

; === Initialize XDourada and FP hotkeys ===
Gosub, InitializeXDouradaHotkeys
FP_UpdateResetHotkey()

; =========================
; GUI
; =========================
; Use a resizable window with standard caption and minimize/maximize buttons.
Gui, +Resize +MinimizeBox +MaximizeBox
Gui, Font, s10, Segoe UI

Gui, Add, Text, x12 y12 w120 h20, Game EXE:
Gui, Add, Text, x140 y12 w420 h20 vLblExe, % gGameExe " (locked)"

Gui, Add, Text, x12 y42 w120 h20, Center point:
Gui, Add, Text, x140 y42 w420 h20 vLblCenter, (não definido)

Gui, Add, Text, x12 y66 w120 h20, Click point:
Gui, Add, Text, x140 y66 w420 h20 vLblClick, (não definido)

Gui, Add, Button, x12  y92 w170 h28 gArmSetCenter, Definir Centro
Gui, Add, Button, x190 y92 w170 h28 gArmSetClick,  Definir Clique
Gui, Add, Button, x368 y92 w80  h28 gSaveConfig,    Salvar
Gui, Add, Button, x456 y92 w80  h28 gResetDefaults, Default

Gui, Add, Text, x12 y126 w640 h18, Clique em "Definir" e depois clique na tela para capturar o ponto. Enter pausa/despausa o WASD para digitar no chat.

; Include a new "Comandos" tab for game chat commands.
Gui, Add, Tab2, x12 y150 w720 h270 vMainTab, WASD Mode|Mouse Mode|XDourada|Full Protection - FP|Comandos|Lazy mode|Extra Keys

; ---------------- TAB 1: WASD ----------------
Gui, Tab, 1
Gui, Add, Checkbox, x28 y182 w220 h22 vChkWASDOn gOnToggleWASD Checked%gWASDOn%, Ativar WASD Mode

    Gui, Add, Text, x28 y258 w210 h20, Walk Distance (px):
    Gui, Add, Edit, x250 y255 w90 h24 vEdDist, %gDist%

    Gui, Add, Text, x28 y288 w210 h20, Walk Distance (Caps Hold) (px):
    Gui, Add, Edit, x250 y285 w90 h24 vEdCapsDist, %gCapsDist%

    Gui, Add, Text, x28 y318 w210 h20, Delay (ms):
    Gui, Add, Edit, x250 y315 w90 h24 vEdDelay, %gDownDelayMs%
    Gui, Add, Text, x350 y318 w360 h20, (antes de LButton down no Click point)

    Gui, Add, Text, x28 y348 w210 h20, Click Move Delay (ms):
    Gui, Add, Edit, x250 y345 w90 h24 vEdClickMoveDelay, %gClickMoveDelayMs%
    Gui, Add, Text, x350 y348 w360 h20, (depois do down -> antes de mover)

    Gui, Add, Text, x28 y378 w210 h20, Stop Distance (px):
    Gui, Add, Edit, x250 y375 w90 h24 vEdStopDist, %gStopDist%
    Gui, Add, Text, x350 y378 w360 h20, (soltar após hold: parar mais cedo)

    ; Movement mode selection: WASD vs Arrow keys.  Only one can be selected.
    ; Place movement mode radio buttons directly below the "Ativar WASD Mode" checkbox to
    ; conserve vertical space.  Only one may be selected.
    Gui, Add, Radio, x28 y214 w220 h22 vChkUseWasd gOnMovementMode Group, Modo WASD
    Gui, Add, Radio, x28 y236 w220 h22 vChkUseArrows gOnMovementMode, Modo Setas do Teclado
    
    Gui, Add, Checkbox, x260 y214 w320 h22 vChkGhostTarget gOnGhostTarget Checked%gGhostTarget%, Ghost Target (retículo virtual)
    Gui, Add, Checkbox, x260 y236 w220 h22 vChkAutoAttack gOnAutoAttack Checked%gAutoAttackMode%, Auto Attack Mode
; Removed the explanatory text to avoid overlapping with bottom controls.

    ; Initialize movement mode radio buttons based on the saved preference.  If
    ; gUseArrows = 1, check the Arrow radio; otherwise check the WASD radio.
    GuiControl,, ChkUseWasd, % (gUseArrows ? 0 : 1)
    GuiControl,, ChkUseArrows, % gUseArrows

; ---------------- TAB 2: Mouse ----------------
Gui, Tab, 2
Gui, Add, Checkbox, x28 y182 w220 h22 vChkMouseOn gOnToggleMouse Checked%gMouseOn%, Ativar Mouse Mode

; Use radio buttons for Capslock and Right Click modes so only one can be selected.
Gui, Add, Radio, x28 y214 w220 h22 vChkMouseCaps gOnMouseCapsMode Group Checked%gMouseCapsMode%, Modo Capslock
Gui, Add, Text, x46 y236 w650 h28, O modo Capslock: você deve segurar o CapsLock para interagir com NPCs e clicar em botões.

    Gui, Add, Radio, x28 y270 w220 h22 vChkMouseRight gOnMouseRightMode Checked%gMouseRightMode%, Modo Right Click
    Gui, Add, Text, x46 y292 w650 h40, O modo Right Click: você pode clicar em NPCs com o botão direito. Para girar a câmera, segure CapsLock e use o botão direito.

    ; Checkbox to invert Right Click mode: when checked, macro triggers only on
    ; the right mouse button (left click is normal).  Only relevant for Modo
    ; Right Click.
    Gui, Add, Checkbox, x28 y334 w300 h22 vChkMouseRightInvert gOnMouseRightInvert Checked%gMouseRightInvert%, Inverter macro: usar botão direito

    Gui, Add, Text, x28 y364 w250 h20, Mouse Click Move Delay (ms):
    Gui, Add, Edit, x290 y361 w90 h24 vEdMouseCMD, %gMouseClickMoveDelayMs%
    Gui, Add, Text, x390 y364 w320 h20, (depois do down no Click point -> voltar)

    Gui, Add, Text, x28 y394 w250 h20, Anti-spam (ms):
    Gui, Add, Edit, x290 y391 w90 h24 vEdMouseSpam, %gMouseSpamDelayMs%
    Gui, Add, Text, x390 y394 w320 h20, (limita a 1 clique por X ms)
    
    ; ---------------- TAB 3: XDourada ----------------
    Gui, Tab, 3
    ; XDourada section imported from KuganTools_v1.5
    Gui, Add, GroupBox, x28 y182 w300 h100, XDourada
    Gui, Add, CheckBox, x38 y207 vXDouradaToggle Checked%xDouradaEnabled%, Enabled
    Gui, Add, Button, x38 y232 w280 gShowConfigGUI, Configure Bars

    ; ---------------- TAB 4: Full Protection - FP ----------------
    Gui, Tab, 4
    ; Full Protection (FP) section imported from KuganTools_v1.5
    Gui, Add, GroupBox, x28 y182 w300 h220, Full Protection (FP)
    Gui, Add, Button, x38 y207 w135 gFP_SetTopLeft, Set Top-Left
    Gui, Add, Button, x183 y207 w135 gFP_SetBottomRight, Set Bot-Right
    Gui, Add, Button, x38 y242 w135 gFP_SetIconPos, Set Icon Pos
    Gui, Add, Button, x183 y242 w135 gFP_TestIconLocation, Test Icon
    Gui, Add, Button, x38 y277 w135 vFP_StartStopBtn gFP_StartStop, Start FP
    Gui, Add, Button, x183 y277 w135 gFP_ResetTimer, Reset Timer
    Gui, Add, Text, x38 y312 w280 vFP_StatusText, Status: Stopped
    Gui, Add, Text, x38 y327 w280 vFP_TimerText, Time: 10:00
    Gui, Add, Text, x38 y342, Reset Timer Key:
    Gui, Add, Hotkey, x183 y339 w130 vFP_ResetMacroKey gFP_ResetKeyChanged, % FP_resetMacroKey

    ; ---------------- TAB 5: Comandos ----------------
    Gui, Tab, 5
    ; Comandos section: allow the user to define chat commands to send to the game.
    ; Create a group box to visually separate this area.
    Gui, Add, GroupBox, x28 y182 w300 h240, Comandos
    ; Command 1: preset value from config or default (/walkdelay)
    Gui, Add, Edit, x38 y207 w200 h22 vCmd1Edit, %Cmd1%
    Gui, Add, Button, x243 y205 w75 h25 gSendCommand1, Enviar
    ; Command 2: preset value from config or default (/skip)
    Gui, Add, Edit, x38 y237 w200 h22 vCmd2Edit, %Cmd2%
    Gui, Add, Button, x243 y235 w75 h25 gSendCommand2, Enviar
    ; Command 3: preset value from config or default (@packetfilter ...)
    Gui, Add, Edit, x38 y267 w200 h22 vCmd3Edit, %Cmd3%
    Gui, Add, Button, x243 y265 w75 h25 gSendCommand3, Enviar
    ; Command 4: user-defined value or blank
    Gui, Add, Edit, x38 y297 w200 h22 vCmd4Edit, %Cmd4%
    Gui, Add, Button, x243 y295 w75 h25 gSendCommand4, Enviar
    ; Command 5: user-defined value or blank
    Gui, Add, Edit, x38 y327 w200 h22 vCmd5Edit, %Cmd5%
    Gui, Add, Button, x243 y325 w75 h25 gSendCommand5, Enviar
    ; Unlock FPS button: sends Ctrl+Home to the game
    Gui, Add, Button, x38 y357 w280 h25 gUnlockFPS, Unlock FPS

    
    ; ---------------- TAB 6: Lazy mode ----------------
    Gui, Tab, 6
    Gui, Add, GroupBox, x28 y182 w660 h220, Lazy mode
    Gui, Add, Checkbox, x38 y207 w260 h22 vChkLazyOn gOnLazyToggle Checked%gLazyModeOn%, Ativar Lazy mode

    Gui, Add, Text, x38 y235 w80 h20, Skill:
    Gui, Add, Hotkey, x120 y231 w140 h24 vLazySkillHK gOnLazyChanged, % gLazySkillHK

    ; Left column
    Gui, Add, Text, x38 y268 w80 h20, Sagrado
    Gui, Add, Hotkey, x120 y264 w140 h24 vLazySagradoHK gOnLazyChanged, % gLazySagradoHK

    Gui, Add, Text, x38 y298 w80 h20, Sombrio
    Gui, Add, Hotkey, x120 y294 w140 h24 vLazySombrioHK gOnLazyChanged, % gLazySombrioHK

    Gui, Add, Text, x38 y328 w80 h20, Fogo
    Gui, Add, Hotkey, x120 y324 w140 h24 vLazyFogoHK gOnLazyChanged, % gLazyFogoHK

    Gui, Add, Text, x38 y358 w80 h20, Vento
    Gui, Add, Hotkey, x120 y354 w140 h24 vLazyVentoHK gOnLazyChanged, % gLazyVentoHK

    ; Right column
    Gui, Add, Text, x320 y268 w80 h20, Neutro
    Gui, Add, Hotkey, x402 y264 w140 h24 vLazyNeutroHK gOnLazyChanged, % gLazyNeutroHK

    Gui, Add, Text, x320 y298 w80 h20, Agua
    Gui, Add, Hotkey, x402 y294 w140 h24 vLazyAguaHK gOnLazyChanged, % gLazyAguaHK

    Gui, Add, Text, x320 y328 w80 h20, Fantasma
    Gui, Add, Hotkey, x402 y324 w140 h24 vLazyFantasmaHK gOnLazyChanged, % gLazyFantasmaHK

    Gui, Add, Text, x320 y358 w80 h20, Terra
    Gui, Add, Hotkey, x402 y354 w140 h24 vLazyTerraHK gOnLazyChanged, % gLazyTerraHK




    ; ---------------- TAB 7: Extra Keys ----------------
    Gui, Tab, 7
    Gui, Add, GroupBox, x28 y182 w660 h190, Extra Keys
    Gui, Add, Checkbox, x38 y207 w260 h22 vChkExtraKeysOn gOnExtraKeysToggle Checked%gExtraKeysOn%, Ativar Extra Keys

    Gui, Add, Text, x38 y240 w120 h20, Scroll Up:
    Gui, Add, Hotkey, x160 y236 w140 h24 vExtraWheelUpHK gOnExtraKeysChanged, % gExtraWheelUpHK

    Gui, Add, Text, x38 y270 w120 h20, Scroll Down:
    Gui, Add, Hotkey, x160 y266 w140 h24 vExtraWheelDownHK gOnExtraKeysChanged, % gExtraWheelDownHK

    Gui, Add, Text, x38 y300 w600 h20, Segure CapsLock para usar o scroll normal.


    Gui, Add, Text, x38 y330 w120 h20, Extra Key 1:
    Gui, Add, Hotkey, x160 y326 w140 h24 vExtraClick1HK gOnExtraKeysChanged, % gExtraClick1HK
    Gui, Add, Button, x320 y324 w80 h26 gArmExtraClick1, Definir
    Gui, Add, Text, x410 y330 w260 h20 vLblExtraClick1, (não definido)

    Gui, Add, Text, x38 y360 w120 h20, Extra Key 2:
    Gui, Add, Hotkey, x160 y356 w140 h24 vExtraClick2HK gOnExtraKeysChanged, % gExtraClick2HK
    Gui, Add, Button, x320 y354 w80 h26 gArmExtraClick2, Definir
    Gui, Add, Text, x410 y360 w260 h20 vLblExtraClick2, (não definido)

Gui, Tab

; Bottom controls
Gui, Add, Button, x12 y432 w120 h32 gStartMacro vBtnStart, Start
Gui, Add, Button, x140 y432 w120 h32 gStopMacro Disabled vBtnStop, Stop

Gui, Add, Text, x280 y438 w120 h20 vLblHotkey, Hotkey Start/Stop:
; Use a Hotkey control instead of a read-only edit box to capture hotkeys directly.
Gui, Add, Hotkey, x410 y432 w140 h24 vEdHotkey gHotkeyChanged, %gStartStopHK%
Gui, Add, Text, x560 y436 w170 h18, (pressione para editar)

Gui, Add, Text, x12 y472 w720 h24 vLblStatus, Status: STOPPED

UpdateCenterLabel()
UpdateClickLabel()
UpdateExtraClick1Label()
UpdateExtraClick2Label()
Gui, Show, w750 h510, KuganTools_v1.3.21
return

; =========================
; Enter pause (no hijack)
; =========================
#If (gEnabled && IsGameActive())
~*Enter::
    ToggleWASDPause()
return
#If

; =========================
; Capture points
; =========================
ArmSetCenter:
    StartCapture("center")
return

ArmSetClick:
    StartCapture("click")
return

ArmExtraClick1:
    StartCapture("extra1")
return

ArmExtraClick2:
    StartCapture("extra2")
return

#If (gCaptureArmed)
~*LButton::
    CapturePoint()
return
#If

; =========================

; =========================
; Extra Keys (Wheel remap)
; =========================
#If (gEnabled && IsGameActive() && gExtraKeysOn)
$WheelUp::
    if (GetKeyState("CapsLock","P")) {
        ; Allow normal scroll while holding CapsLock
        SendInput, {WheelUp}
        return
    }
    sendStr := Lazy_HotkeyToSendTap(gExtraWheelUpHK)
    if (sendStr = "") {
        ; If not configured, keep normal scroll
        SendInput, {WheelUp}
        return
    }
    SendInput, %sendStr%
    ; If the mapped key matches a Lazy mode element key, trigger the skill-hold too.
    Lazy_TryTriggerFromSimHK(gExtraWheelUpHK)
return

$WheelDown::
    if (GetKeyState("CapsLock","P")) {
        SendInput, {WheelDown}
        return
    }
    sendStr := Lazy_HotkeyToSendTap(gExtraWheelDownHK)
    if (sendStr = "") {
        SendInput, {WheelDown}
        return
    }
    SendInput, %sendStr%
    ; If the mapped key matches a Lazy mode element key, trigger the skill-hold too.
    Lazy_TryTriggerFromSimHK(gExtraWheelDownHK)
return
#If

; Extra Keys: poll optional "double click at point" hotkeys (physical key state, like Lazy mode)
Extra_PollClickKeys() {
    global gEnabled, gExtraKeysOn, gExtraClick1HK, gExtraClick2HK
    global gExtraPrevClick1, gExtraPrevClick2

    if (!gEnabled || !gExtraKeysOn)
        return
    if (!IsGameActive())
        return
    ; While holding CapsLock, Extra Keys should not fire (lets you use things normally).
    if (GetKeyState("CapsLock","P"))
        return

    p := Lazy_IsHotkeyPressed(gExtraClick1HK)
    if (p && !gExtraPrevClick1)
        Extra_DoDoubleClick(1)
    gExtraPrevClick1 := p

    p := Lazy_IsHotkeyPressed(gExtraClick2HK)
    if (p && !gExtraPrevClick2)
        Extra_DoDoubleClick(2)
    gExtraPrevClick2 := p
}

Extra_ResetPrevClickKeys() {
    global gExtraClick1HK, gExtraClick2HK
    global gExtraPrevClick1, gExtraPrevClick2
    gExtraPrevClick1 := Lazy_IsHotkeyPressed(gExtraClick1HK) ? 1 : 0
    gExtraPrevClick2 := Lazy_IsHotkeyPressed(gExtraClick2HK) ? 1 : 0
}

Extra_DoDoubleClick(idx) {
    x := "", y := ""
    if (!Extra_ResolveClickPoint(idx, x, y)) {
        SoundBeep, 650, 60
        return
    }
    Extra_SendDoubleClickAt(x, y)
}

Extra_ResolveClickPoint(idx, ByRef outX, ByRef outY) {
    global gGameExe
    global gExtraClick1X, gExtraClick1Y, gExtraClick2X, gExtraClick2Y
    global gExtraClick1RX, gExtraClick1RY, gExtraClick2RX, gExtraClick2RY
    global gExtraClick1X, gExtraClick1Y, gExtraClick1RX, gExtraClick1RY
    global gExtraClick2X, gExtraClick2Y, gExtraClick2RX, gExtraClick2RY

    if (idx = 1) {
        ax := gExtraClick1X, ay := gExtraClick1Y, rx := gExtraClick1RX, ry := gExtraClick1RY
    } else {
        ax := gExtraClick2X, ay := gExtraClick2Y, rx := gExtraClick2RX, ry := gExtraClick2RY
    }

    ; Prefer relative-to-client (survives windowed/borderless/fullscreen)
    hwnd := WinExist("ahk_exe " . gGameExe)
    if (hwnd && rx != "" && ry != "") {
        if (Game_GetClientRectScreen(hwnd, cl, ct, cw, ch) && cw > 0 && ch > 0) {
            outX := Round(cl + (rx * cw))
            outY := Round(ct + (ry * ch))
            ClampToVirtualScreen(outX, outY)
            return true
        }
    }

    ; Fallback: absolute screen point
    if (ax = "" || ay = "")
        return false
    outX := ax + 0
    outY := ay + 0
    ClampToVirtualScreen(outX, outY)
    return true
}

Extra_SendDoubleClickAt(x, y) {
    global gMouseBusy, gIgnoreLButtonEdgesUntil

    ; Prevent other systems (AutoAttack stop-walk / Mouse Mode) from treating this as a user click.
    gIgnoreLButtonEdgesUntil := A_TickCount + 120
    prevBusy := gMouseBusy
    gMouseBusy := true

    MouseGetPos, ox, oy
    DllCall("SetCursorPos", "Int", x, "Int", y)
    Sleep, 8
    ; Two clean clicks
    SendEvent, {LButton}
    Sleep, 35
    SendEvent, {LButton}
    Sleep, 8
    DllCall("SetCursorPos", "Int", ox, "Int", oy)

    gMouseBusy := prevBusy
}

; Mouse Mode hooks
; =========================
#If (gEnabled && IsGameActive() && gMouseOn && !GetKeyState("CapsLock","P"))
$*LButton::
    ; We only process mouse clicks when Mouse Mode is enabled.  If for some
    ; reason this hook fires with gMouseOn off, simply return to avoid
    ; interfering with normal behavior.
    if (!gMouseOn)
        return
    ; If the macro is currently busy (i.e. it generated its own left-click
    ; events), do not interfere.  This prevents recursion and ensures that
    ; macro-generated clicks (for moving the character) are not mistaken for
    ; user clicks.
    if (gMouseBusy)
        return
    ; In Right Click mode with inversion active, the user expects the left
    ; mouse button to behave normally (interact with UI) and the macro to
    ; trigger on right-click instead.  Forward the left-button press to the
    ; game without invoking the macro.
    if (gMouseRightMode && gMouseRightInvert) {
        ForwardLeftClick("down")
        return
    }
    ; Otherwise, begin Mouse Mode (left-click triggers the macro).
    MouseMode_Down()
return

$*LButton Up::
    ; If the macro is busy handling a click (e.g. holding the button down),
    ; route release events through the macro to finish movement logic.  This
    ; check must occur before inversion logic so that macro-generated release
    ; events do not get forwarded incorrectly.
    if (gMouseDownActive) {
        MouseMode_Up()
        return
    }
    ; In Right Click inversion mode, forward user-generated left-button
    ; releases directly to the game without invoking the macro.
    if (gMouseRightMode && gMouseRightInvert) {
        ForwardLeftClick("up")
        return
    }
    ; No macro is active; simply send the up event through.
    SendEvent, {LButton up}
return
#If

; Right Click Mode remap:
#If (gEnabled && IsGameActive() && gMouseOn && gMouseRightMode && !GetKeyState("CapsLock","P"))
$*RButton::
    ; Invert mode: trigger macro directly on the right button.  Otherwise,
    ; remap to left-click to leverage the existing left-button macro.
    if (gMouseRightInvert) {
        ; If the macro is busy, do nothing
        if (gMouseBusy)
            return
        MouseMode_Down()
    } else {
        SendEvent, {LButton down}
    }
    return

$*RButton Up::
    if (gMouseRightInvert) {
        if (gMouseDownActive)
            MouseMode_Up()
        else
            SendEvent, {LButton up}
    } else {
        SendEvent, {LButton up}
    }
    return
#If

; =========================
; WASD tick triggers
; =========================
#If (gEnabled && IsGameActive())
~*w::Gosub, ForceTick
~*a::Gosub, ForceTick
~*s::Gosub, ForceTick
~*d::Gosub, ForceTick
~*w up::Gosub, ForceTick
~*a up::Gosub, ForceTick
~*s up::Gosub, ForceTick
~*d up::Gosub, ForceTick

    ; Arrow key tick triggers (for movement mode = arrows).  These are always
    ; defined, but only meaningful when gUseArrows=1.  They cause TickMove to
    ; run immediately on arrow key down/up events.
    ~*Up::Gosub, ForceTick
    ~*Left::Gosub, ForceTick
    ~*Down::Gosub, ForceTick
    ~*Right::Gosub, ForceTick
    ~*Up up::Gosub, ForceTick
    ~*Left up::Gosub, ForceTick
    ~*Down up::Gosub, ForceTick
    ~*Right up::Gosub, ForceTick
#If

ForceTick:
    ; Se uma tecla "não-movimento" for pressionada durante o walk-hold,
    ; para o movimento imediatamente (exclui WASD ou Setas dependendo do modo).
    StopWalk_CheckHotkey()
    Gosub, TickMove
return

; =========================
; GUI handlers
; =========================
OnToggleWASD:
OnToggleMouse:
    ; Update variables when generic toggle controls change.
    Gui, Submit, NoHide
return

OnGhostTarget:
    ; Apenas captura o estado do checkbox (ApplyGuiToVars também pega em Start/Save)
    Gui, Submit, NoHide
return

OnAutoAttack:
    ; Apenas captura o estado do checkbox
    Gui, Submit, NoHide
return

OnLazyToggle:
OnLazyChanged:
    Gui, Submit, NoHide
    ApplyGuiToVars(false)
    Lazy_UpdateHotkeys()
return

OnExtraKeysToggle:
OnExtraKeysChanged:
    Gui, Submit, NoHide
    ApplyGuiToVars(false)
    Extra_ResetPrevClickKeys()
return


OnMouseCapsMode:
OnMouseRightMode:
    ; Update variables when one of the mouse mode radios changes and enforce exclusivity.
    Gui, Submit, NoHide
    ; Ensure that only one of the two modes can be active at a time.
    if (A_GuiControl = "ChkMouseCaps") {
        GuiControl,, ChkMouseRight, 0
    } else {
        GuiControl,, ChkMouseCaps, 0
    }
return

; Called when the user toggles the movement mode radio buttons (WASD vs arrow
; keys).  Submits the form without hiding the GUI and enforces that only one
; of the movement radio buttons can be selected at a time.  The actual state
; of gUseArrows is assigned in ApplyGuiToVars.
OnMovementMode:
    Gui, Submit, NoHide
    ; Ensure only one mode is selected at a time.
    if (A_GuiControl = "ChkUseWasd") {
        GuiControl,, ChkUseArrows, 0
    } else {
        GuiControl,, ChkUseWasd, 0
    }
    ; Update the runtime variable immediately so movement mode takes effect
    ; without having to click Save/Start.
    gUseArrows := (ChkUseArrows ? 1 : 0)
return

; The old edit-based hotkey editing has been replaced by a Hotkey control.
HotkeyEditClick:
    return

; Called whenever the user assigns a new Start/Stop hotkey via the Hotkey control.
HotkeyChanged:
    Gui, Submit, NoHide
    gStartStopHK := Trim(EdHotkey)
    RegisterStartStopHotkey(gStartStopHK)
return

SaveConfig:
    ; Submit all GUI fields to update their associated variables.  Using NoHide
    ; keeps the window visible while reading the control values.
    Gui, Submit, NoHide
    ; Apply standard WASD/Mouse settings from the GUI to internal variables.
    ApplyGuiToVars(true)

    ; -------------------------------------------------------------------------
    ; Persist core macro settings to disk
    ; -------------------------------------------------------------------------
    ; General toggles and modes
    IniWrite, %gWASDOn%,                %gIniPath%, Settings, WASDOn
    IniWrite, %gMouseOn%,               %gIniPath%, Settings, MouseOn
    IniWrite, %gMouseCapsMode%,         %gIniPath%, Settings, MouseCapsMode
    IniWrite, %gMouseRightMode%,        %gIniPath%, Settings, MouseRightMode
    ; Distances and delays
    IniWrite, %gDist%,                  %gIniPath%, Settings, Distance
    IniWrite, %gCapsDist%,              %gIniPath%, Settings, CapsHoldDistance
    IniWrite, %gDownDelayMs%,           %gIniPath%, Settings, DelayMs
    IniWrite, %gClickMoveDelayMs%,      %gIniPath%, Settings, ClickMoveDelayMs
    IniWrite, %gStopDist%,              %gIniPath%, Settings, StopDist
    IniWrite, %gMouseClickMoveDelayMs%, %gIniPath%, Settings, MouseClickMoveDelayMs
    IniWrite, %gMouseSpamDelayMs%,      %gIniPath%, Settings, MouseSpamDelayMs
    ; Capture points
    IniWrite, %gCenterX%,               %gIniPath%, Settings, CenterX
    IniWrite, %gCenterY%,               %gIniPath%, Settings, CenterY
    IniWrite, %gClickX%,                %gIniPath%, Settings, ClickX
    IniWrite, %gClickY%,                %gIniPath%, Settings, ClickY

    IniWrite, %gCenterRX%,              %gIniPath%, Settings, CenterRX
    IniWrite, %gCenterRY%,              %gIniPath%, Settings, CenterRY
    IniWrite, %gClickRX%,               %gIniPath%, Settings, ClickRX
    IniWrite, %gClickRY%,               %gIniPath%, Settings, ClickRY
    IniWrite, %gRefClientW%,            %gIniPath%, Settings, RefClientW
    IniWrite, %gRefClientH%,            %gIniPath%, Settings, RefClientH
    ; Hotkey and inversion settings
    IniWrite, %gStartStopHK%,           %gIniPath%, Settings, StartStopHK
    IniWrite, %gMouseRightInvert%,      %gIniPath%, Settings, MouseRightInvert
    ; Movement mode (0=WASD, 1=Arrow)
    IniWrite, %gUseArrows%,             %gIniPath%, Settings, UseArrows
    IniWrite, %gGhostTarget%,          %gIniPath%, Settings, GhostTarget

    IniWrite, %gAutoAttackMode%,       %gIniPath%, Settings, AutoAttackMode
    ; -------------------------------------------------------------------------
    ; Persist XDourada settings
    ; -------------------------------------------------------------------------
    ; Update xDouradaEnabled from the checkbox if present.  Without this, the
    ; script would only update the flag after a Save-Bar operation or restart.
    if (XDouradaToggle != "")
        xDouradaEnabled := (XDouradaToggle ? 1 : 0)
    ; Save global toggles and bar dimensions
    IniWrite, %xDouradaEnabled%,       %gIniPath%, XDourada, Enabled
    IniWrite, %barWidth%,              %gIniPath%, XDourada, barWidth
    IniWrite, %barHeight%,             %gIniPath%, XDourada, barHeight
    ; Persist bar 1 configuration
    IniWrite, %bar1Key%,               %gIniPath%, Bar1, ActivationKey
    IniWrite, %bar1X%,                 %gIniPath%, Bar1, timerX
    IniWrite, %bar1Y%,                 %gIniPath%, Bar1, timerY
    IniWrite, %bar1Color%,             %gIniPath%, Bar1, barColor
    IniWrite, %bar1Seconds%,           %gIniPath%, Bar1, Duration
    IniWrite, %BeepEnabled1%,          %gIniPath%, Bar1, BeepEnabled
    ; Persist bar 2 configuration
    IniWrite, %bar2Key%,               %gIniPath%, Bar2, ActivationKey
    IniWrite, %bar2X%,                 %gIniPath%, Bar2, timerX
    IniWrite, %bar2Y%,                 %gIniPath%, Bar2, timerY
    IniWrite, %bar2Color%,             %gIniPath%, Bar2, barColor
    IniWrite, %bar2Seconds%,           %gIniPath%, Bar2, Duration
    IniWrite, %BeepEnabled2%,          %gIniPath%, Bar2, BeepEnabled

    ; -------------------------------------------------------------------------
    ; Persist Full Protection settings
    ; -------------------------------------------------------------------------
    ; Search area and icon position are stored in associative arrays.  Write
    ; each coordinate separately to the INI file.  These values are updated
    ; whenever the user clicks the Set Top-Left, Set Bot-Right or Set Icon
    ; position buttons.
    IniWrite, % FP_searchArea.x1,      %gIniPath%, FullProtection, x1
    IniWrite, % FP_searchArea.y1,      %gIniPath%, FullProtection, y1
    IniWrite, % FP_searchArea.x2,      %gIniPath%, FullProtection, x2
    IniWrite, % FP_searchArea.y2,      %gIniPath%, FullProtection, y2
    IniWrite, % FP_iconPos.x,          %gIniPath%, FullProtection, icon_x
    IniWrite, % FP_iconPos.y,          %gIniPath%, FullProtection, icon_y
    ; Persist the FP reset macro hotkey (captured from the Hotkey control)
    GuiControlGet, FP_resetMacroKey,, FP_ResetMacroKey
    FP_resetMacroKey := Trim(FP_resetMacroKey)
    IniWrite, % FP_resetMacroKey,      %gIniPath%, FullProtection, ResetMacro
    ; Re-register the reset macro hotkey so it takes effect immediately
    FP_UpdateResetHotkey()

    ; ---------------------------------------------------------------------
    ; Persist chat commands (Comandos)
    ; ---------------------------------------------------------------------
    ; After Gui, Submit the variables Cmd1Edit..Cmd5Edit contain the text
    ; entered by the user.  Copy them into the corresponding global CmdN
    ; variables and write them to the INI file.
    ; Persist chat commands: ensure assignments affect the global CmdN variables.
    ; Declare the variables as global within this function so that the updated
    ; values propagate outside the function scope. Without this, the assignments
    ; would create local variables and the UI would not reflect the saved values
    ; on subsequent opens.
    global Cmd1, Cmd2, Cmd3, Cmd4, Cmd5
    Cmd1 := Cmd1Edit
    Cmd2 := Cmd2Edit
    Cmd3 := Cmd3Edit
    Cmd4 := Cmd4Edit
    Cmd5 := Cmd5Edit
    IniWrite, %Cmd1%, %gIniPath%, Commands, Cmd1
    IniWrite, %Cmd2%, %gIniPath%, Commands, Cmd2
    IniWrite, %Cmd3%, %gIniPath%, Commands, Cmd3
    IniWrite, %Cmd4%, %gIniPath%, Commands, Cmd4
    IniWrite, %Cmd5%, %gIniPath%, Commands, Cmd5

    ; ---------------------------------------------------------------------
    ; Persist Lazy mode
    ; ---------------------------------------------------------------------
    IniWrite, %gLazyModeOn%,     %gIniPath%, LazyMode, Enabled
    IniWrite, %gLazySkillHK%,    %gIniPath%, LazyMode, Skill
    IniWrite, %gLazySagradoHK%,  %gIniPath%, LazyMode, Sagrado
    IniWrite, %gLazySombrioHK%,  %gIniPath%, LazyMode, Sombrio
    IniWrite, %gLazyFogoHK%,     %gIniPath%, LazyMode, Fogo
    IniWrite, %gLazyVentoHK%,    %gIniPath%, LazyMode, Vento
    IniWrite, %gLazyNeutroHK%,   %gIniPath%, LazyMode, Neutro
    IniWrite, %gLazyAguaHK%,     %gIniPath%, LazyMode, Agua
    IniWrite, %gLazyFantasmaHK%, %gIniPath%, LazyMode, Fantasma
    IniWrite, %gLazyTerraHK%,    %gIniPath%, LazyMode, Terra

    ; ---------------------------------------------------------------------
    ; Persist Extra Keys
    ; ---------------------------------------------------------------------
    IniWrite, %gExtraKeysOn%,       %gIniPath%, ExtraKeys, Enabled
    IniWrite, %gExtraWheelUpHK%,    %gIniPath%, ExtraKeys, WheelUp
    IniWrite, %gExtraWheelDownHK%,  %gIniPath%, ExtraKeys, WheelDown
    IniWrite, %gExtraClick1HK%,      %gIniPath%, ExtraKeys, Click1HK
    IniWrite, %gExtraClick2HK%,      %gIniPath%, ExtraKeys, Click2HK
    IniWrite, %gExtraClick1X%,       %gIniPath%, ExtraKeys, Click1X
    IniWrite, %gExtraClick1Y%,       %gIniPath%, ExtraKeys, Click1Y
    IniWrite, %gExtraClick2X%,       %gIniPath%, ExtraKeys, Click2X
    IniWrite, %gExtraClick2Y%,       %gIniPath%, ExtraKeys, Click2Y
    IniWrite, %gExtraClick1RX%,      %gIniPath%, ExtraKeys, Click1RX
    IniWrite, %gExtraClick1RY%,      %gIniPath%, ExtraKeys, Click1RY
    IniWrite, %gExtraClick2RX%,      %gIniPath%, ExtraKeys, Click2RX
    IniWrite, %gExtraClick2RY%,      %gIniPath%, ExtraKeys, Click2RY

    ; Provide auditory feedback and update the status label
    SoundBeep, 900, 80
    SoundBeep, 1100, 80
    GuiControl,, LblStatus, Status: SALVO (config.ini)
return

; Restore all tunable parameters to their default values.  This does not
; overwrite saved capture points or the start/stop hotkey, and it does not
; save to disk until you click "Salvar".  It simply updates the GUI and
; internal variables to the defaults defined at the top of this script.
ResetDefaults:
    ; Assign default values to state variables
    gWASDOn := gDefaultWASDOn
    gMouseOn := gDefaultMouseOn
    gMouseCapsMode := gDefaultMouseCapsMode
    gMouseRightMode := gDefaultMouseRightMode
    gDist := gDefaultDist
    gCapsDist := gDefaultCapsDist
    gDownDelayMs := gDefaultDownDelayMs
    gClickMoveDelayMs := gDefaultClickMoveDelayMs
    gStopDist := gDefaultStopDist
    gMouseClickMoveDelayMs := gDefaultMouseClickMoveDelayMs
    gMouseSpamDelayMs := gDefaultMouseSpamDelayMs

    ; Reset mouse right-click inversion flag
    gMouseRightInvert := gDefaultMouseRightInvert

    ; Reset movement mode (WASD vs Arrow)
    gUseArrows := gDefaultUseArrows

    ; Reset Ghost Target
    gGhostTarget := gDefaultGhostTarget
    gAutoAttackMode := gDefaultAutoAttackMode

    ; Update checkbox/radio states
    GuiControl,, ChkWASDOn, % gWASDOn
    GuiControl,, ChkMouseOn, % gMouseOn
    GuiControl,, ChkMouseCaps, % gMouseCapsMode
    GuiControl,, ChkMouseRight, % gMouseRightMode
    GuiControl,, ChkMouseRightInvert, % gMouseRightInvert
    GuiControl,, ChkGhostTarget, % gGhostTarget
    GuiControl,, ChkAutoAttack, % gAutoAttackMode

    ; Update movement mode radio buttons
    GuiControl,, ChkUseWasd, % (gUseArrows ? 0 : 1)
    GuiControl,, ChkUseArrows, % gUseArrows

    ; Update numeric edit controls
    GuiControl,, EdDist, % gDist
    GuiControl,, EdCapsDist, % gCapsDist
    GuiControl,, EdDelay, % gDownDelayMs
    GuiControl,, EdClickMoveDelay, % gClickMoveDelayMs
    GuiControl,, EdStopDist, % gStopDist
    GuiControl,, EdMouseCMD, % gMouseClickMoveDelayMs
    GuiControl,, EdMouseSpam, % gMouseSpamDelayMs

    ; Provide visual feedback to the user
    GuiControl,, LblStatus, Status: PADRÕES RESTAURADOS (não salvo)
return

StartMacro:
    Gui, Submit, NoHide
    ApplyGuiToVars(false)

    ; Update XDourada enabled state from the checkbox on the XDourada tab.  When the
    ; user checks the XDourada toggle and starts the macro, this ensures the bar
    ; timers are allowed to run without requiring a manual save.  The variable
    ; XDouradaToggle is populated by Gui, Submit.  Coerce it to a boolean.
    xDouradaEnabled := (XDouradaToggle ? 1 : 0)

    if (gCenterX = "" || gCenterY = "") {
        SoundBeep, 800, 120
        GuiControl,, LblStatus, Status: DEFINA O CENTRO (botão)
        return
    }
    if (gClickX = "" || gClickY = "") {
        SoundBeep, 800, 120
        GuiControl,, LblStatus, Status: DEFINA O CLIQUE (botão)
        return
    }

    gEnabled := true
    Lazy_UpdateHotkeys()
    gWASDPaused := false

    gLDown := false
    gHoldStartTick := 0
    gLastDx := 0, gLastDy := 0, gHadMove := false

    MouseMode_Reset()

    GuiControl, Disable, BtnStart
    GuiControl, Enable, BtnStop
    GuiControl,, LblStatus, Status: RUNNING (somente quando %gGameExe% estiver ativo)

    SetTimer, TickMove, 10
return

StopMacro:
    ; Lazy mode safety: never leave a held skill down
    Lazy_ReleaseSkill()
    Lazy_ClearHotkeys()
    gEnabled := false
    SetTimer, TickMove, Off

    ReleaseClick(false)
    Ghost_Cancel()
    MouseMode_Reset()

    gLDown := false
    gHoldStartTick := 0
    gLastDx := 0, gLastDy := 0, gHadMove := false

    GuiControl, Enable, BtnStart
    GuiControl, Disable, BtnStop
    GuiControl,, LblStatus, Status: STOPPED
return

GuiClose:
GuiEscape:
    Gosub, StopMacro
    ExitApp

; =========================
; GUI resize handler
; =========================
; Adjusts the positions and sizes of controls when the window is resized to keep
; the layout responsive. The Tab control is expanded to fill available space and
; the bottom controls are anchored to the bottom.
GuiSize:
    ; Ignore minimize events (EventInfo=1).
    if (A_EventInfo = 1)
        return
    ; Calculate dynamic sizes based on the current window dimensions.
    tabX  := 12
    tabY  := 150
    tabW  := A_GuiWidth  - (tabX * 2)
    ; Leave space for bottom buttons and status (approx 110px).
    tabH  := A_GuiHeight - tabY - 110
    if (tabH < 0)
        tabH := 0

    GuiControl, Move, MainTab, % "x" tabX " y" tabY " w" tabW " h" tabH

    ; Position the Start/Stop buttons near the bottom.
    btnY := tabY + tabH + 10
    GuiControl, Move, BtnStart, % "x12 y" btnY
    GuiControl, Move, BtnStop,  % "x140 y" btnY

    ; Position the hotkey label and control.
    hotkeyY := btnY + 6
    GuiControl, Move, LblHotkey, % "x280 y" hotkeyY
    GuiControl, Move, EdHotkey,  % "x410 y" btnY

    ; Update the status label at the bottom.
    statusY := btnY + 40
    GuiControl, Move, LblStatus, % "x12 y" statusY " w" (A_GuiWidth - 24)
return


; =========================
; Helpers
; =========================
IsGameActive() {
    global gGameExe
    return WinActive("ahk_exe " . gGameExe)
}

; Get the GAME CLIENT rectangle in SCREEN coordinates (handles borders/titlebar in windowed mode)
Game_GetClientRectScreen(hwnd, ByRef l, ByRef t, ByRef w, ByRef h) {
    VarSetCapacity(rc, 16, 0)
    if (!DllCall("GetClientRect", "Ptr", hwnd, "Ptr", &rc))
        return false
    w := NumGet(rc, 8, "Int")
    h := NumGet(rc, 12, "Int")
    if (w <= 0 || h <= 0)
        return false

    VarSetCapacity(pt, 8, 0)
    NumPut(0, pt, 0, "Int")
    NumPut(0, pt, 4, "Int")
    if (!DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", &pt))
        return false

    l := NumGet(pt, 0, "Int")
    t := NumGet(pt, 4, "Int")
    return true
}

; Monitor rect (screen coords) for the monitor that contains the game window (multi-monitor safe)
Game_GetMonitorRect(hwnd, ByRef ml, ByRef mt, ByRef mw, ByRef mh) {
    MONITOR_DEFAULTTONEAREST := 2
    hMon := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", MONITOR_DEFAULTTONEAREST, "Ptr")
    if (!hMon)
        return false

    VarSetCapacity(mi, 40, 0) ; MONITORINFO
    NumPut(40, mi, 0, "UInt")
    if (!DllCall("GetMonitorInfo", "Ptr", hMon, "Ptr", &mi))
        return false

    left   := NumGet(mi, 4,  "Int")
    top    := NumGet(mi, 8,  "Int")
    right  := NumGet(mi, 12, "Int")
    bottom := NumGet(mi, 16, "Int")

    ml := left
    mt := top
    mw := right - left
    mh := bottom - top
    return (mw > 0 && mh > 0)
}

; Monitor rect (screen coords) for the monitor that contains a GIVEN POINT (multi-monitor safe).
; This is crucial when converting old absolute points captured on a different monitor.
Mon_GetRectFromPoint(px, py, ByRef ml, ByRef mt, ByRef mw, ByRef mh) {
    VarSetCapacity(pt, 8, 0)
    NumPut(px, pt, 0, "Int")
    NumPut(py, pt, 4, "Int")

    MONITOR_DEFAULTTONEAREST := 2
    hMon := DllCall("MonitorFromPoint", "Int64", NumGet(pt, 0, "Int64"), "UInt", MONITOR_DEFAULTTONEAREST, "Ptr")
    if (!hMon)
        return false

    VarSetCapacity(mi, 40, 0) ; MONITORINFO
    NumPut(40, mi, 0, "UInt")
    if (!DllCall("GetMonitorInfo", "Ptr", hMon, "Ptr", &mi))
        return false

    left   := NumGet(mi, 4,  "Int")
    top    := NumGet(mi, 8,  "Int")
    right  := NumGet(mi, 12, "Int")
    bottom := NumGet(mi, 16, "Int")

    ml := left
    mt := top
    mw := (right - left)
    mh := (bottom - top)
    return (mw > 0 && mh > 0)
}


; If the user captured points in fullscreen before, absolute coords may not match windowed mode.
; This tries to derive relative coords automatically (client if possible, otherwise monitor-based).
Points_MaybeInferRelative() {
    global gCenterX, gCenterY, gClickX, gClickY
    global gCenterRX, gCenterRY, gClickRX, gClickRY
    global gRefClientW, gRefClientH
    global gGameExe

    hwnd := WinExist("ahk_exe " . gGameExe)
    if (!hwnd)
        return

    hasClient := Game_GetClientRectScreen(hwnd, cl, ct, cw, ch)

    ; Treat exact corners as "probably wrong" so we can re-infer safely (center/click should almost never be (0,0)).
    centerLooksBad := ((gCenterRX != "") && ((gCenterRX+0 = 0 && gCenterRY+0 = 0) || (gCenterRX+0 = 1 && gCenterRY+0 = 1)))
    clickLooksBad  := ((gClickRX  != "") && ((gClickRX+0  = 0 && gClickRY+0  = 0) || (gClickRX+0  = 1 && gClickRY+0  = 1)))

    ; Try infer CENTER relative coords from existing absolute coords
    if ((gCenterRX = "" || centerLooksBad) && gCenterX != "" && gCenterY != "") {
        if (hasClient && gCenterX >= cl && gCenterX <= (cl+cw) && gCenterY >= ct && gCenterY <= (ct+ch)) {
            gCenterRX := (gCenterX - cl) / cw
            gCenterRY := (gCenterY - ct) / ch
            gRefClientW := cw
            gRefClientH := ch
        } else if (Mon_GetRectFromPoint(gCenterX, gCenterY, ml, mt, mw, mh)) {
            ; Fallback: compute relative inside the monitor where the point was captured.
            gCenterRX := (gCenterX - ml) / mw
            gCenterRY := (gCenterY - mt) / mh
            if (gRefClientW <= 0) {
                gRefClientW := mw
                gRefClientH := mh
            }
        }

        if (gCenterRX != "") {
            if (gCenterRX < 0)
                gCenterRX := 0
            else if (gCenterRX > 1)
                gCenterRX := 1

            if (gCenterRY < 0)
                gCenterRY := 0
            else if (gCenterRY > 1)
                gCenterRY := 1
        }
    }

    ; Try infer CLICK relative coords from existing absolute coords
    if ((gClickRX = "" || clickLooksBad) && gClickX != "" && gClickY != "") {
        if (hasClient && gClickX >= cl && gClickX <= (cl+cw) && gClickY >= ct && gClickY <= (ct+ch)) {
            gClickRX := (gClickX - cl) / cw
            gClickRY := (gClickY - ct) / ch
            if (gRefClientW <= 0) {
                gRefClientW := cw
                gRefClientH := ch
            }
        } else if (Mon_GetRectFromPoint(gClickX, gClickY, ml2, mt2, mw2, mh2)) {
            ; Fallback: compute relative inside the monitor where the point was captured.
            gClickRX := (gClickX - ml2) / mw2
            gClickRY := (gClickY - mt2) / mh2
            if (gRefClientW <= 0) {
                gRefClientW := mw2
                gRefClientH := mh2
            }
        }

        if (gClickRX != "") {
            if (gClickRX < 0)
                gClickRX := 0
            else if (gClickRX > 1)
                gClickRX := 1

            if (gClickRY < 0)
                gClickRY := 0
            else if (gClickRY > 1)
                gClickRY := 1
        }
    }
}




; Update cached client rect + resolve relative points into screen coords
Points_UpdateResolved() {
    global gCenterX, gCenterY, gClickX, gClickY
    global gCenterRX, gCenterRY, gClickRX, gClickRY
    global gGameClientL, gGameClientT, gGameClientW, gGameClientH
    global gGameExe

    hwnd := WinExist("ahk_exe " . gGameExe)
    if (!hwnd)
        return false

    Points_MaybeInferRelative()

    if (!Game_GetClientRectScreen(hwnd, cl, ct, cw, ch))
        return false

    gGameClientL := cl
    gGameClientT := ct
    gGameClientW := cw
    gGameClientH := ch

    if (gCenterRX != "") {
        gCenterX := Round(cl + (gCenterRX * cw))
        gCenterY := Round(ct + (gCenterRY * ch))
    }
    if (gClickRX != "") {
        gClickX := Round(cl + (gClickRX * cw))
        gClickY := Round(ct + (gClickRY * ch))
    }
    return true
}

; Scale factor for distances when switching between fullscreen / windowed / different resolutions.
; Uses the client size captured when points were set (RefClientW/H).
GetClientScale() {
    global gRefClientW, gRefClientH, gGameClientW, gGameClientH
    if (gRefClientW <= 0 || gRefClientH <= 0)
        return 1.0
    if (gGameClientW <= 0 || gGameClientH <= 0)
        return 1.0
    sx := gGameClientW / gRefClientW
    sy := gGameClientH / gRefClientH
    ; be conservative: use the smaller scaling so you don't overshoot
    scale := (sx < sy) ? sx : sy
    if (scale <= 0.05)
        scale := 1.0
    return scale
}



UpdateCenterLabel() {
    global gCenterX, gCenterY
    if (gCenterX = "" || gCenterY = "")
        GuiControl,, LblCenter, (não definido)
    else
        GuiControl,, LblCenter, X:%gCenterX%  Y:%gCenterY%
}

UpdateClickLabel() {
    global gClickX, gClickY
    if (gClickX = "" || gClickY = "")
        GuiControl,, LblClick, (não definido)
    else
        GuiControl,, LblClick, X:%gClickX%  Y:%gClickY%
}

UpdateExtraClick1Label() {
    global gExtraClick1X, gExtraClick1Y
    if (gExtraClick1X = "" || gExtraClick1Y = "")
        GuiControl,, LblExtraClick1, (não definido)
    else
        GuiControl,, LblExtraClick1, X:%gExtraClick1X%  Y:%gExtraClick1Y%
}

UpdateExtraClick2Label() {
    global gExtraClick2X, gExtraClick2Y
    if (gExtraClick2X = "" || gExtraClick2Y = "")
        GuiControl,, LblExtraClick2, (não definido)
    else
        GuiControl,, LblExtraClick2, X:%gExtraClick2X%  Y:%gExtraClick2Y%
}

ApplyGuiToVars(fromSaveBtn := false) {
    global ChkWASDOn, ChkMouseOn, ChkMouseCaps, ChkMouseRight
    global ChkMouseRightInvert
    global ChkUseWasd, ChkUseArrows
    global ChkGhostTarget
    global ChkAutoAttack
    global ChkLazyOn
    global ChkExtraKeysOn
    global ExtraWheelUpHK, ExtraWheelDownHK, ExtraClick1HK, ExtraClick2HK
    global LazySkillHK, LazySagradoHK, LazySombrioHK, LazyFogoHK, LazyVentoHK, LazyNeutroHK, LazyAguaHK, LazyFantasmaHK, LazyTerraHK
global EdDist, EdCapsDist, EdDelay, EdClickMoveDelay, EdStopDist, EdMouseCMD, EdMouseSpam, EdHotkey
    global gWASDOn, gMouseOn, gMouseCapsMode, gMouseRightMode
    global gMouseRightInvert
    global gUseArrows
    global gLazyModeOn, gLazySkillHK, gLazySagradoHK, gLazySombrioHK, gLazyFogoHK, gLazyVentoHK, gLazyNeutroHK, gLazyAguaHK, gLazyFantasmaHK, gLazyTerraHK
    global gGhostTarget
    global gAutoAttackMode
    global gLazyModeOn, gLazySkillHK, gLazySagradoHK, gLazySombrioHK, gLazyFogoHK, gLazyVentoHK, gLazyNeutroHK, gLazyAguaHK, gLazyFantasmaHK, gLazyTerraHK
    global gExtraKeysOn, gExtraWheelUpHK, gExtraWheelDownHK, gExtraClick1HK, gExtraClick2HK
    global gExtraClick1X, gExtraClick1Y, gExtraClick2X, gExtraClick2Y
    global gExtraClick1RX, gExtraClick1RY, gExtraClick2RX, gExtraClick2RY, gExtraClick1HK, gExtraClick2HK
    global gDist, gCapsDist, gDownDelayMs, gClickMoveDelayMs, gStopDist
    global gMouseClickMoveDelayMs, gMouseSpamDelayMs
    global gStartStopHK

    gWASDOn := (ChkWASDOn ? 1 : 0)
    gMouseOn := (ChkMouseOn ? 1 : 0)

    if (ChkMouseCaps && ChkMouseRight) {
        ChkMouseRight := 0
        GuiControl,, ChkMouseRight, 0
    }
    gMouseCapsMode  := (ChkMouseCaps ? 1 : 0)
    gMouseRightMode := (ChkMouseRight ? 1 : 0)

    if (EdDist != "")
        gDist := Max(1, EdDist + 0)
    if (EdCapsDist != "")
        gCapsDist := Max(1, EdCapsDist + 0)
    if (EdDelay != "")
        gDownDelayMs := Max(0, EdDelay + 0)
    if (EdClickMoveDelay != "")
        gClickMoveDelayMs := Max(0, EdClickMoveDelay + 0)
    if (EdStopDist != "")
        gStopDist := Max(0, EdStopDist + 0)

    if (EdMouseCMD != "")
        gMouseClickMoveDelayMs := Max(0, EdMouseCMD + 0)
    if (EdMouseSpam != "")
        gMouseSpamDelayMs := Max(0, EdMouseSpam + 0)

    ; Movement mode: if both radios were somehow set, default to WASD.
    if (ChkUseWasd && ChkUseArrows) {
        ChkUseArrows := 0
        GuiControl,, ChkUseArrows, 0
    }
    gUseArrows := (ChkUseArrows ? 1 : 0)

    ; Ghost Target checkbox
    gGhostTarget := (ChkGhostTarget ? 1 : 0)
    gAutoAttackMode := (ChkAutoAttack ? 1 : 0)

    gStartStopHK := Trim(EdHotkey)

    ; Mouse Right Click inversion flag
    gMouseRightInvert := (ChkMouseRightInvert ? 1 : 0)

    ; Lazy mode
    gLazyModeOn := (ChkLazyOn ? 1 : 0)
    gLazySkillHK := Trim(LazySkillHK)
    gLazySagradoHK := Trim(LazySagradoHK)
    gLazySombrioHK := Trim(LazySombrioHK)
    gLazyFogoHK := Trim(LazyFogoHK)
    gLazyVentoHK := Trim(LazyVentoHK)
    gLazyNeutroHK := Trim(LazyNeutroHK)
    gLazyAguaHK := Trim(LazyAguaHK)
    gLazyFantasmaHK := Trim(LazyFantasmaHK)
    gLazyTerraHK := Trim(LazyTerraHK)

    ; Extra Keys
    gExtraKeysOn := (ChkExtraKeysOn ? 1 : 0)
    gExtraWheelUpHK := Trim(ExtraWheelUpHK)
    gExtraWheelDownHK := Trim(ExtraWheelDownHK)
    gExtraClick1HK := Trim(ExtraClick1HK)
    gExtraClick2HK := Trim(ExtraClick2HK)
}

LoadConfig() {
    global gIniPath
    global gWASDOn, gMouseOn, gMouseCapsMode, gMouseRightMode
    global gGhostTarget, gAutoAttackMode
    global gDist, gCapsDist, gDownDelayMs, gClickMoveDelayMs, gStopDist
    global gMouseClickMoveDelayMs, gMouseSpamDelayMs
    global gCenterX, gCenterY, gClickX, gClickY
    global gCenterRX, gCenterRY, gClickRX, gClickRY, gRefClientW, gRefClientH
    global gStartStopHK
    global gUseArrows
    global gLazyModeOn, gLazySkillHK, gLazySagradoHK, gLazySombrioHK, gLazyFogoHK, gLazyVentoHK, gLazyNeutroHK, gLazyAguaHK, gLazyFantasmaHK, gLazyTerraHK
    global gExtraKeysOn, gExtraWheelUpHK, gExtraWheelDownHK

    if !FileExist(gIniPath)
        return

    IniRead, vWASD,  %gIniPath%, Settings, WASDOn, 1
    IniRead, vMouse, %gIniPath%, Settings, MouseOn, 0
    IniRead, vMCaps, %gIniPath%, Settings, MouseCapsMode, 1
    IniRead, vMRgt,  %gIniPath%, Settings, MouseRightMode, 0

    IniRead, vDist,  %gIniPath%, Settings, Distance, 100
    IniRead, vCaps,  %gIniPath%, Settings, CapsHoldDistance, 20
    IniRead, vDelay, %gIniPath%, Settings, DelayMs, 0
    IniRead, vCMD,   %gIniPath%, Settings, ClickMoveDelayMs, 0
    IniRead, vStop,  %gIniPath%, Settings, StopDist, 12

    IniRead, vMCMD,  %gIniPath%, Settings, MouseClickMoveDelayMs, 10
    IniRead, vMSP,   %gIniPath%, Settings, MouseSpamDelayMs, 100

    IniRead, vCX, %gIniPath%, Settings, CenterX,
    IniRead, vCY, %gIniPath%, Settings, CenterY,
    IniRead, vKX, %gIniPath%, Settings, ClickX,
    IniRead, vKY, %gIniPath%, Settings, ClickY,

    IniRead, vCRX, %gIniPath%, Settings, CenterRX,
    IniRead, vCRY, %gIniPath%, Settings, CenterRY,
    IniRead, vKRX, %gIniPath%, Settings, ClickRX,
    IniRead, vKRY, %gIniPath%, Settings, ClickRY,
    IniRead, vRefW, %gIniPath%, Settings, RefClientW, 0
    IniRead, vRefH, %gIniPath%, Settings, RefClientH, 0

    IniRead, vHK, %gIniPath%, Settings, StartStopHK,
    IniRead, vRightInvert, %gIniPath%, Settings, MouseRightInvert, 0
    IniRead, vUseArrows, %gIniPath%, Settings, UseArrows, 0
    IniRead, vGhost, %gIniPath%, Settings, GhostTarget, 0
    IniRead, vAutoAttack, %gIniPath%, Settings, AutoAttackMode, 0

    ; Lazy mode
    IniRead, vLazyOn, %gIniPath%, LazyMode, Enabled, 0
    IniRead, vLazySkill, %gIniPath%, LazyMode, Skill,
    IniRead, vLazySagrado, %gIniPath%, LazyMode, Sagrado,
    IniRead, vLazySombrio, %gIniPath%, LazyMode, Sombrio,
    IniRead, vLazyFogo, %gIniPath%, LazyMode, Fogo,
    IniRead, vLazyVento, %gIniPath%, LazyMode, Vento,
    IniRead, vLazyNeutro, %gIniPath%, LazyMode, Neutro,
    IniRead, vLazyAgua, %gIniPath%, LazyMode, Agua,
    IniRead, vLazyFantasma, %gIniPath%, LazyMode, Fantasma,
    IniRead, vLazyTerra, %gIniPath%, LazyMode, Terra,

    ; Extra Keys
    IniRead, vExtraOn, %gIniPath%, ExtraKeys, Enabled, 0
    IniRead, vExtraUp, %gIniPath%, ExtraKeys, WheelUp,
    IniRead, vExtraDown, %gIniPath%, ExtraKeys, WheelDown,
    IniRead, vExtraC1HK, %gIniPath%, ExtraKeys, Click1HK,
    IniRead, vExtraC2HK, %gIniPath%, ExtraKeys, Click2HK,
    IniRead, vExtraC1X, %gIniPath%, ExtraKeys, Click1X,
    IniRead, vExtraC1Y, %gIniPath%, ExtraKeys, Click1Y,
    IniRead, vExtraC2X, %gIniPath%, ExtraKeys, Click2X,
    IniRead, vExtraC2Y, %gIniPath%, ExtraKeys, Click2Y,
    IniRead, vExtraC1RX, %gIniPath%, ExtraKeys, Click1RX,
    IniRead, vExtraC1RY, %gIniPath%, ExtraKeys, Click1RY,
    IniRead, vExtraC2RX, %gIniPath%, ExtraKeys, Click2RX,
    IniRead, vExtraC2RY, %gIniPath%, ExtraKeys, Click2RY,

    gWASDOn := (vWASD + 0) ? 1 : 0
    gMouseOn := (vMouse + 0) ? 1 : 0
    gMouseCapsMode := (vMCaps + 0) ? 1 : 0
    gMouseRightMode := (vMRgt + 0) ? 1 : 0

    gDist := vDist + 0
    gCapsDist := vCaps + 0
    gDownDelayMs := vDelay + 0
    gClickMoveDelayMs := vCMD + 0
    gStopDist := vStop + 0

    gMouseClickMoveDelayMs := vMCMD + 0
    gMouseSpamDelayMs := vMSP + 0

    if (vCX != "ERROR" && vCX != "")
        gCenterX := vCX + 0
    if (vCY != "ERROR" && vCY != "")
        gCenterY := vCY + 0
    if (vKX != "ERROR" && vKX != "")
        gClickX := vKX + 0
    if (vKY != "ERROR" && vKY != "")
        gClickY := vKY + 0


    ; Relative points + reference size (optional, for windowed/fullscreen independence)
    if (vCRX != "ERROR" && vCRX != "")
        gCenterRX := vCRX + 0.0
    if (vCRY != "ERROR" && vCRY != "")
        gCenterRY := vCRY + 0.0
    if (vKRX != "ERROR" && vKRX != "")
        gClickRX := vKRX + 0.0
    if (vKRY != "ERROR" && vKRY != "")
        gClickRY := vKRY + 0.0
    if (vRefW != "ERROR")
        gRefClientW := vRefW + 0
    if (vRefH != "ERROR")
        gRefClientH := vRefH + 0

    if (vHK != "ERROR")
        gStartStopHK := Trim(vHK)

    ; Right click inversion (1 = invert macro to right click).  Coerce to 0/1.
    if (vRightInvert != "ERROR")
        gMouseRightInvert := (vRightInvert + 0) ? 1 : 0

    ; Movement mode (0 = WASD keys, 1 = Arrow keys).  Coerce to 0/1.
    if (vUseArrows != "ERROR")
        gUseArrows := (vUseArrows + 0) ? 1 : 0

    if (vGhost != "ERROR")
        gGhostTarget := (vGhost + 0) ? 1 : 0

    if (vAutoAttack != "ERROR")
        gAutoAttackMode := (vAutoAttack + 0) ? 1 : 0

    ; Lazy mode values
    if (vLazyOn != "ERROR")
        gLazyModeOn := (vLazyOn + 0) ? 1 : 0

    if (vLazySkill != "ERROR")
        gLazySkillHK := Trim(vLazySkill)
    if (vLazySagrado != "ERROR")
        gLazySagradoHK := Trim(vLazySagrado)
    if (vLazySombrio != "ERROR")
        gLazySombrioHK := Trim(vLazySombrio)
    if (vLazyFogo != "ERROR")
        gLazyFogoHK := Trim(vLazyFogo)
    if (vLazyVento != "ERROR")
        gLazyVentoHK := Trim(vLazyVento)
    if (vLazyNeutro != "ERROR")
        gLazyNeutroHK := Trim(vLazyNeutro)
    if (vLazyAgua != "ERROR")
        gLazyAguaHK := Trim(vLazyAgua)
    if (vLazyFantasma != "ERROR")
        gLazyFantasmaHK := Trim(vLazyFantasma)
    if (vLazyTerra != "ERROR")
        gLazyTerraHK := Trim(vLazyTerra)

    ; Extra Keys values
    if (vExtraOn != "ERROR")
        gExtraKeysOn := (vExtraOn + 0) ? 1 : 0
    if (vExtraUp != "ERROR")
        gExtraWheelUpHK := Trim(vExtraUp)
    if (vExtraDown != "ERROR")
        gExtraWheelDownHK := Trim(vExtraDown)

    if (vExtraC1HK != "ERROR")
        gExtraClick1HK := Trim(vExtraC1HK)
    if (vExtraC2HK != "ERROR")
        gExtraClick2HK := Trim(vExtraC2HK)

    if (vExtraC1X != "ERROR" && vExtraC1X != "")
        gExtraClick1X := vExtraC1X + 0
    if (vExtraC1Y != "ERROR" && vExtraC1Y != "")
        gExtraClick1Y := vExtraC1Y + 0
    if (vExtraC2X != "ERROR" && vExtraC2X != "")
        gExtraClick2X := vExtraC2X + 0
    if (vExtraC2Y != "ERROR" && vExtraC2Y != "")
        gExtraClick2Y := vExtraC2Y + 0

    if (vExtraC1RX != "ERROR" && vExtraC1RX != "")
        gExtraClick1RX := vExtraC1RX + 0.0
    if (vExtraC1RY != "ERROR" && vExtraC1RY != "")
        gExtraClick1RY := vExtraC1RY + 0.0
    if (vExtraC2RX != "ERROR" && vExtraC2RX != "")
        gExtraClick2RX := vExtraC2RX + 0.0
    if (vExtraC2RY != "ERROR" && vExtraC2RY != "")
        gExtraClick2RY := vExtraC2RY + 0.0
}

StartCapture(mode) {
    global gCaptureMode, gCaptureArmed
    gCaptureMode := mode
    gCaptureArmed := true
    ToolTip, Clique na tela para capturar o ponto..., 20, 20
    SetTimer, CaptureTimeout, -5000
}

CaptureTimeout:
    global gCaptureArmed, gCaptureMode
    if (gCaptureArmed) {
        gCaptureArmed := false
        gCaptureMode := ""
        ToolTip
    }
return

; Called when the user toggles the Right Click inversion checkbox.  This flag
; determines whether, in Modo Right Click, only the right button should
; trigger the macro while the left button is normal.  CapsLock still
; temporarily disables the macro.
OnMouseRightInvert:
    Gui, Submit, NoHide
    gMouseRightInvert := (ChkMouseRightInvert ? 1 : 0)
return

CapturePoint() {
    global gCaptureMode, gCaptureArmed
    global gCenterX, gCenterY, gClickX, gClickY
    global gCenterRX, gCenterRY, gClickRX, gClickRY
    global gRefClientW, gRefClientH
    global gGameExe

    if (!gCaptureArmed)
        return

    MouseGetPos, mx, my

    ; Try to store points as relative to the GAME client area (works in fullscreen/borderless/windowed)
    rx := "", ry := "", cw := 0, ch := 0
    hwnd := WinExist("ahk_exe " . gGameExe)
    if (hwnd) {
        if (Game_GetClientRectScreen(hwnd, cl, ct, cw, ch)) {
            if (cw > 0 && ch > 0) {
                rx := (mx - cl) / cw
                ry := (my - ct) / ch
                ; clamp
                if (rx < 0)
                    rx := 0
                else if (rx > 1)
                    rx := 1
                if (ry < 0)
                    ry := 0
                else if (ry > 1)
                    ry := 1
            }
        }
    }

    if (gCaptureMode = "center") {
        gCenterX := mx, gCenterY := my
        if (rx != "") {
            gCenterRX := rx, gCenterRY := ry
            gRefClientW := cw, gRefClientH := ch
        }
        UpdateCenterLabel()
    } else if (gCaptureMode = "click") {
        gClickX := mx, gClickY := my
        if (rx != "") {
            gClickRX := rx, gClickRY := ry
            gRefClientW := cw, gRefClientH := ch
        }
        UpdateClickLabel()
    } else if (gCaptureMode = "extra1") {
        gExtraClick1X := mx, gExtraClick1Y := my
        if (rx != "") {
            gExtraClick1RX := rx, gExtraClick1RY := ry
        }
        UpdateExtraClick1Label()
    } else if (gCaptureMode = "extra2") {
        gExtraClick2X := mx, gExtraClick2Y := my
        if (rx != "") {
            gExtraClick2RX := rx, gExtraClick2RY := ry
        }
        UpdateExtraClick2Label()
    }

    gCaptureArmed := false
    gCaptureMode := ""
    ToolTip
}


ToggleWASDPause() {
    global gWASDPaused, gWASDOn
    if (!gWASDOn)
        return

    gWASDPaused := !gWASDPaused
    if (gWASDPaused) {
        ToolTip, Chat ativo, 20, 20
        SetTimer, HideChatTip, -3000
    } else {
        ToolTip
    }
}

HideChatTip:
    ToolTip
return

IsCapsHeld() {
    return GetKeyState("CapsLock", "P")
}

GetActiveDistance() {
    global gDist, gCapsDist
    scale := GetClientScale()
    dist := IsCapsHeld() ? gCapsDist : gDist
    return Round(dist * scale)
}


ApplyDeadzone(val, dz) {
    ; dz em [0..1]
    a := Abs(val)
    if (a <= dz)
        return 0.0
    ; reescala pra manter 0..1 fora da deadzone
    scaled := (a - dz) / (1.0 - dz)
    return (val > 0 ? scaled : -scaled)
}

GetKeyboardVector(ByRef dx, ByRef dy) {
    global gUseArrows
    global gLazyModeOn, gLazySkillHK, gLazySagradoHK, gLazySombrioHK, gLazyFogoHK, gLazyVentoHK, gLazyNeutroHK, gLazyAguaHK, gLazyFantasmaHK, gLazyTerraHK
    if (!gUseArrows) {
        w := GetKeyState("w","P")
        a := GetKeyState("a","P")
        s := GetKeyState("s","P")
        d := GetKeyState("d","P")
        dx := (d ? 1 : 0) - (a ? 1 : 0)
        dy := (s ? 1 : 0) - (w ? 1 : 0)
    } else {
        up := GetKeyState("Up","P")
        left := GetKeyState("Left","P")
        downk := GetKeyState("Down","P")
        right := GetKeyState("Right","P")
        dx := (right ? 1 : 0) - (left ? 1 : 0)
        dy := (downk ? 1 : 0) - (up ? 1 : 0)
    }
    return (dx != 0 || dy != 0)
}

GetGamepadVector(ByRef dx, ByRef dy) {
    global gPadOn, gPadJoy, gPadDeadzone
    dx := 0.0, dy := 0.0
    if (!gPadOn)
        return 0.0

    ; AHK v1 lê eixos como 0..100 (centro ~50)
    x := GetKeyState(gPadJoy . "JoyX")
    y := GetKeyState(gPadJoy . "JoyY")
    if (x = "" || y = "")
        return 0.0

    fx := (x - 50) / 50.0
    fy := (y - 50) / 50.0

    dz := gPadDeadzone / 100.0
    fx := ApplyDeadzone(fx, dz)
    fy := ApplyDeadzone(fy, dz)

    ; clamp
    if (fx > 1)  fx := 1
    if (fx < -1) fx := -1
    if (fy > 1)  fy := 1
    if (fy < -1) fy := -1

    dx := fx
    dy := fy

    ; magnitude (0..~1.4) - mas dx/dy já está em [-1..1]
    mag := Sqrt(dx*dx + dy*dy)
    if (mag < 0.0001) {
        dx := 0.0, dy := 0.0
        return 0.0
    }
    return mag
}
ApproachNum(curr, target, step) {
    if (step <= 0)
        return target
    if (curr < target) {
        curr += step
        if (curr > target)
            curr := target
    } else if (curr > target) {
        curr -= step
        if (curr < target)
            curr := target
    }
    return curr
}

StopMoveDirectional() {
    global gCenterX, gCenterY, gStopDist, gLastDx, gLastDy, gHadMove
    global gCursorLockActive
    global gStopDirValid, gStopDirX, gStopDirY
    if (!gHadMove)
        return false
    if (gStopDist <= 0)
        return false

    ; Refresh points for current windowed/fullscreen position
    Points_UpdateResolved()
    if (gCenterX = "" || gCenterY = "")
        return false

    dx := gLastDx
    dy := gLastDy
    if (gStopDirValid) {
        dx := gStopDirX
        dy := gStopDirY
    }

    scaledStop := Round(gStopDist * GetClientScale())
    sx := Round(gCenterX + dx * scaledStop)
    sy := Round(gCenterY + dy * scaledStop)
    ; Se Ghost Target estiver travando o cursor via ClipCursor, use CursorLock_MoveTo.
    if (gCursorLockActive)
        CursorLock_MoveTo(sx, sy)
    else
        MouseMove, %sx%, %sy%, 0
    return true
}

; =========================
; Start/Stop Hotkey register
; =========================
RegisterStartStopHotkey(hk) {
    global gStartStopHK_Active

    if (gStartStopHK_Active != "") {
        Hotkey, % gStartStopHK_Active, ToggleStartStop, Off
        gStartStopHK_Active := ""
    }

    hk := Trim(hk)
    if (hk = "")
        return

    ; Prepend a tilde (~) to the hotkey to ensure the key's native function
    ; continues to work in other programs.  This prevents our macro from
    ; hijacking the key and allows multiple scripts to share the same key.
    ; Reject empty or disallowed hotkeys.  Hotkeys containing Ctrl, Alt, Shift,
    ; Enter or Escape (Esc) are not permitted for Start/Stop.
    hk := Trim(hk)
    if (hk = "")
        return
    if (InStr(hk, "Ctrl") || InStr(hk, "Alt") || InStr(hk, "Shift")
        || hk = "Enter" || hk = "Esc" || hk = "Escape") {
        SoundBeep, 700, 120
        return
    }

    ; Attempt to convert the key name to a scancode.  This makes keys like
    ; backtick more reliable across layouts.  If conversion fails (sc=0), we'll
    ; fall back to using the key name directly with escaping.
    scCode := GetKeySC(hk)
    if (scCode != 0) {
        hex := Format("{:03X}", scCode)
        hkRegister := "~SC" . hex
    } else {
        hkRegister := hk
        ; Prepend tilde for pass‑through if missing
        if (SubStr(hkRegister, 1, 1) != "~")
            hkRegister := "~" . hkRegister
        ; Escape literal backticks by doubling them (`` -> ````)
        hkRegister := StrReplace(hkRegister, "``", "````")
    }

    Hotkey, % hkRegister, ToggleStartStop, On UseErrorLevel
    if (ErrorLevel) {
        SoundBeep, 700, 120
        return
    }
    gStartStopHK_Active := hkRegister
}

ToggleStartStop:
    global gEnabled
    if (gEnabled) {
        SoundBeep, 1100, 60
        SoundBeep, 900, 60
        Gosub, StopMacro
    } else {
        SoundBeep, 900, 60
        SoundBeep, 1100, 60
        Gosub, StartMacro
    }
return

; =========================
; Hard Lock (force cursor)
; =========================
HardLock_Start(x, y, durationMs) {
    global gHardLockOn, gHardLockX, gHardLockY, gHardLockUntilTick
    gHardLockX := x, gHardLockY := y
    gHardLockUntilTick := A_TickCount + Max(0, durationMs)
    gHardLockOn := true
    SetTimer, HardLock_Tick, 5
}

HardLock_Update(x, y) {
    global gHardLockX, gHardLockY
    gHardLockX := x, gHardLockY := y
}

HardLock_Stop() {
    global gHardLockOn
    gHardLockOn := false
    SetTimer, HardLock_Tick, Off
}

HardLock_Tick:
    global gHardLockOn, gHardLockX, gHardLockY, gHardLockUntilTick
    if (!gHardLockOn) {
        SetTimer, HardLock_Tick, Off
        return
    }
    if (A_TickCount >= gHardLockUntilTick) {
        gHardLockOn := false
        SetTimer, HardLock_Tick, Off
        return
    }
    DllCall("SetCursorPos", "Int", gHardLockX, "Int", gHardLockY)
return

; =========================
; Cursor Lock (ClipCursor) + Raw Mouse Delta (optional)
; =========================
; Why: Forcing the cursor back with SetCursorPos can still let it "escape" for a few ms if you flick fast,
; which can make the click happen in the wrong place. ClipCursor prevents ANY drift.
; Bonus: we capture raw mouse deltas while locked, so after the lock ends we can restore
; the cursor to where your hand actually moved (approximation).
;
; NOTE: Raw deltas are device movement units (not Windows-accelerated pixels). It still feels
; much closer than snapping back to the old position.

global gCursorLockActive := false
global gRawMouseInited := false
global gRawCaptureOn := false
global gRawDX := 0
global gRawDY := 0
global gRawMouseOk := false  ; becomes true if we successfully registered raw input

CursorLock_Start(x, y) {
    global gCursorLockActive
    gCursorLockActive := true

    ; Clip to a 1x1 px rectangle (right/bottom are exclusive)
    VarSetCapacity(RECT, 16, 0)
    NumPut(x,   RECT, 0,  "Int")
    NumPut(y,   RECT, 4,  "Int")
    NumPut(x+1, RECT, 8,  "Int")
    NumPut(y+1, RECT, 12, "Int")
    DllCall("ClipCursor", "Ptr", &RECT)
    DllCall("SetCursorPos", "Int", x, "Int", y)
}

; Move the 1x1 ClipCursor "cage" to a NEW point while keeping the lock active.
; We use this right before unlocking so the cursor cannot "drift" away from the
; click point (or get pushed by buffered movement) in the tiny gap between
; unlock and restore.
CursorLock_MoveTo(x, y) {
    global gCursorLockActive
    if (!gCursorLockActive) {
        CursorLock_Start(x, y)
        return
    }

    VarSetCapacity(RECT, 16, 0)
    NumPut(x,   RECT, 0,  "Int")
    NumPut(y,   RECT, 4,  "Int")
    NumPut(x+1, RECT, 8,  "Int")
    NumPut(y+1, RECT, 12, "Int")
    DllCall("ClipCursor", "Ptr", &RECT)
    DllCall("SetCursorPos", "Int", x, "Int", y)
}

CursorLock_Stop() {
    global gCursorLockActive
    if (!gCursorLockActive)
        return
    DllCall("ClipCursor", "Ptr", 0)
    gCursorLockActive := false
}

RawMouse_Init() {
    global gRawMouseInited, gRawMouseOk
    if (gRawMouseInited)
        return

    gRawMouseOk := false
    ; Listen for WM_INPUT (0x00FF)
    OnMessage(0x00FF, "RawMouse_WM_INPUT")

    ; RAWINPUTDEVICE size = 8 + A_PtrSize  (2+2+4 + ptr)
    ridSize := 8 + A_PtrSize
    VarSetCapacity(RID, ridSize, 0)
    NumPut(0x01, RID, 0, "UShort")            ; UsagePage: Generic
    NumPut(0x02, RID, 2, "UShort")            ; Usage: Mouse
    NumPut(0x00000100, RID, 4, "UInt")        ; RIDEV_INPUTSINK (receive even if not focused)
    NumPut(A_ScriptHwnd, RID, 8, "Ptr")       ; target window

    ok := DllCall("RegisterRawInputDevices", "Ptr", &RID, "UInt", 1, "UInt", ridSize)
    if (ok)
        gRawMouseOk := true

    gRawMouseInited := true
}

RawMouse_BeginCapture() {
    global gRawCaptureOn, gRawDX, gRawDY
    gRawDX := 0
    gRawDY := 0
    gRawCaptureOn := true
}

RawMouse_EndCapture(ByRef dx, ByRef dy) {
    global gRawCaptureOn, gRawDX, gRawDY
    dx := gRawDX
    dy := gRawDY
    gRawCaptureOn := false
}

RawMouse_CancelCapture() {
    global gRawCaptureOn
    gRawCaptureOn := false
}

RawMouse_WM_INPUT(wParam, lParam) {
    global gRawCaptureOn, gRawDX, gRawDY, gRawMouseOk
    if (!gRawCaptureOn || !gRawMouseOk)
        return

    size := 0
    RID_INPUT := 0x10000003
    headerSize := 8 + (A_PtrSize*2) ; RAWINPUTHEADER

    DllCall("GetRawInputData", "Ptr", lParam, "UInt", RID_INPUT, "Ptr", 0, "UInt*", size, "UInt", headerSize)
    if (size <= 0)
        return

    VarSetCapacity(raw, size, 0)
    got := DllCall("GetRawInputData", "Ptr", lParam, "UInt", RID_INPUT, "Ptr", &raw, "UInt*", size, "UInt", headerSize)
    if (got != size)
        return

    off := headerSize
    dx := NumGet(raw, off + 12, "Int") ; RAWMOUSE.lLastX
    dy := NumGet(raw, off + 16, "Int") ; RAWMOUSE.lLastY

    gRawDX += dx
    gRawDY += dy
}

ClampToVirtualScreen(ByRef x, ByRef y) {
    SysGet, vLeft, 76
    SysGet, vTop,  77
    SysGet, vW,    78
    SysGet, vH,    79

    vRight := vLeft + vW - 1
    vBottom := vTop + vH - 1

    if (x < vLeft)
        x := vLeft
    else if (x > vRight)
        x := vRight

    if (y < vTop)
        y := vTop
    else if (y > vBottom)
        y := vBottom
}

; =========================
; Ghost Target (retículo virtual) - usa Raw Input + ClipCursor
; =========================
Ghost_UpdateGameRect() {
    global gGameExe
    global gGhostGameL, gGhostGameT, gGhostGameR, gGhostGameB

    hwnd := WinExist("ahk_exe " . gGameExe)
    if (!hwnd)
        return false

    VarSetCapacity(rc, 16, 0)
    if (!DllCall("GetClientRect", "Ptr", hwnd, "Ptr", &rc))
        return false

    w := NumGet(rc, 8, "Int")
    h := NumGet(rc, 12, "Int")
    if (w <= 0 || h <= 0)
        return false

    VarSetCapacity(pt, 8, 0)
    NumPut(0, pt, 0, "Int")
    NumPut(0, pt, 4, "Int")
    if (!DllCall("ClientToScreen", "Ptr", hwnd, "Ptr", &pt))
        return false

    l := NumGet(pt, 0, "Int")
    t := NumGet(pt, 4, "Int")

    gGhostGameL := l
    gGhostGameT := t
    gGhostGameR := l + w - 1
    gGhostGameB := t + h - 1
    return true
}

Ghost_ClampToGame(ByRef x, ByRef y) {
    global gGhostGameL, gGhostGameT, gGhostGameR, gGhostGameB
    ; Se não conseguiu ler a área do jogo, cai pro virtual screen (multi-monitor)
    if (gGhostGameR <= gGhostGameL || gGhostGameB <= gGhostGameT) {
        ClampToVirtualScreen(x, y)
        return
    }
    if (x < gGhostGameL)
        x := gGhostGameL
    else if (x > gGhostGameR)
        x := gGhostGameR

    if (y < gGhostGameT)
        y := gGhostGameT
    else if (y > gGhostGameB)
        y := gGhostGameB
}

Ghost_GuiEnsure() {
    global gGhostHwnd
    if (gGhostHwnd)
        return

    ; Click-through overlay
    Gui, Ghost:New, +AlwaysOnTop -Caption +ToolWindow +E0x20 +LastFound +HwndhGhost
    Gui, Ghost:Margin, 0, 0
    Gui, Ghost:Color, 010101
    WinSet, TransColor, 010101

    ; Retículo simples e compatível (ASCII "+") com sombra preta
    Gui, Ghost:Font, s20 bold, Segoe UI
    Gui, Ghost:Add, Text, x1 y1 w28 h28 Center BackgroundTrans c000000, +
    Gui, Ghost:Add, Text, x0 y0 w28 h28 Center BackgroundTrans cFF0000, +

    gGhostHwnd := hGhost
}

Ghost_GuiShowAt(x, y) {
    global gGhostHwnd
    Ghost_GuiEnsure()

    ; Centraliza o retículo no ponto
    gx := x - 14
    gy := y - 14
    Gui, Ghost:Show, % "x" gx " y" gy " w28 h28 NoActivate"
}

Ghost_GuiHide() {
    global gGhostHwnd
    if (gGhostHwnd)
        Gui, Ghost:Hide
}

Ghost_GuiDestroy() {
    global gGhostHwnd
    if (gGhostHwnd) {
        Gui, Ghost:Destroy
        gGhostHwnd := 0
    }
}

Ghost_Begin(lockX, lockY) {
    global gGhostActive, gGhostRetX, gGhostRetY, gGhostTarget
    global gRawMouseOk, gCursorLockActive, gGhostScale

    if (!gGhostTarget)
        return false

    ; Se já tem lock ativo (ex: MouseMode), não mistura.
    if (gCursorLockActive)
        return false

    ; Atualiza área do jogo pra clamp
    Ghost_UpdateGameRect()

    ; Pega posição atual do mouse (mira real) e usa como retículo inicial
    MouseGetPos, mx, my
    gGhostRetX := mx
    gGhostRetY := my
    Ghost_ClampToGame(gGhostRetX, gGhostRetY)
    Ghost_GuiShowAt(gGhostRetX, gGhostRetY)

    ; Precisamos de Raw Input pra mover o retículo enquanto o cursor está travado
    RawMouse_Init()
    if (!gRawMouseOk) {
        ToolTip, Ghost Target: Raw Input falhou.`nRode o script como ADMIN., 20, 20
        SetTimer, __GhostTipOff, -1200
        Ghost_GuiHide()
        return false
    }

    RawMouse_BeginCapture()
    CursorLock_Start(lockX, lockY)
    gGhostActive := true
    return true
}

__GhostTipOff:
    ToolTip
return

Ghost_Tick() {
    global gGhostActive, gGhostRetX, gGhostRetY, gGhostScale

    if (!gGhostActive)
        return

    ; Mantém clamp atualizado se a janela mexer (barato o suficiente)
    Ghost_UpdateGameRect()

    dx := 0, dy := 0
    RawMouse_EndCapture(dx, dy)
    ; reinicia captura imediatamente
    RawMouse_BeginCapture()

    if (dx != 0 || dy != 0) {
        gGhostRetX := gGhostRetX + Round(dx * gGhostScale)
        gGhostRetY := gGhostRetY + Round(dy * gGhostScale)
        Ghost_ClampToGame(gGhostRetX, gGhostRetY)
        Ghost_GuiShowAt(gGhostRetX, gGhostRetY)
    }
}

Ghost_EndAndTeleport() {
    global gGhostActive, gGhostRetX, gGhostRetY

    if (!gGhostActive)
        return

    ; aplica um último delta antes de finalizar
    Ghost_Tick()

    ; Move a "cage" pro ponto alvo e desbloqueia (evita drift ao soltar)
    CursorLock_MoveTo(gGhostRetX, gGhostRetY)
    Sleep, 1
    CursorLock_Stop()
    HardLock_Start(gGhostRetX, gGhostRetY, 12)

    RawMouse_CancelCapture()
    gGhostActive := false
    Ghost_GuiDestroy()
}

Ghost_Cancel() {
    global gGhostActive
    if (!gGhostActive)
        return
    CursorLock_Stop()
    RawMouse_CancelCapture()
    HardLock_Stop()
    Lazy_ReleaseSkill()
    Lazy_ClearHotkeys()
    gGhostActive := false
    Ghost_GuiDestroy()
}


; -----------------------------------------------------------------------------
; -----------------------------------------------------------------------------
; Stop-walk (skills) helpers
; -----------------------------------------------------------------------------
StopWalk_Init() {
    global gStopWalkKeys, gStopWalkPrev, gStopWalkPrevLButton

    gStopWalkKeys := []

; ========= Stop-walk key set (matches your screenshot) =========
; F1..F9
Loop, 9
    gStopWalkKeys.Push("F" . A_Index)

; Number row 1..9
Loop, 9
    gStopWalkKeys.Push("" . A_Index)

; Numpad 1..9
Loop, 9
    gStopWalkKeys.Push("Numpad" . A_Index)

; Letters (EXCLUDING W A S D)
; Row: Q W E R T Y U I O  -> remove W
; Row: A S D F G H J K L  -> remove A S D
; Row: Z X C V B N M
letters := "QERTYUIOFGHJKLZXCVBNM"
Loop, Parse, letters
    gStopWalkKeys.Push(A_LoopField)

; Prev states map (edge detection)
    gStopWalkPrev := {}
    gStopWalkPrevLButton := (GetKeyState("LButton", "P") ? 1 : 0)
    for _, k in gStopWalkKeys
        gStopWalkPrev[k] := 0
}

StopWalk_SyncPrev() {
    global gStopWalkKeys, gStopWalkPrev, gStopWalkPrevLButton, gAutoAttackMode
    if (!IsObject(gStopWalkPrev))
        return
    for _, k in gStopWalkKeys
        gStopWalkPrev[k] := (GetKeyState(k, "P") ? 1 : 0)

    if (gAutoAttackMode)
        gStopWalkPrevLButton := (GetKeyState("LButton", "P") ? 1 : 0)
}

StopWalk_IsMovementKey(key) {
    global gUseArrows
    global gLazyModeOn, gLazySkillHK, gLazySagradoHK, gLazySombrioHK, gLazyFogoHK, gLazyVentoHK, gLazyNeutroHK, gLazyAguaHK, gLazyFantasmaHK, gLazyTerraHK
    k := Format("{:L}", key)

    if (!gUseArrows) {
        return (k = "w" || k = "a" || k = "s" || k = "d")
    } else {
        ; In arrow mode, arrows are movement keys
        return (key = "Up" || key = "Left" || key = "Down" || key = "Right")
    }
}

StopWalk_Request() {
    global gStopWalkRequest, gStopWalkLatch
    gStopWalkRequest := true
    gStopWalkLatch := true
}

StopWalk_PollOtherKeys() {
    global gStopWalkKeys, gStopWalkPrev, gStopWalkRequest
    global gStopWalkPrevLButton, gAutoAttackMode, gIgnoreLButtonEdgesUntil
    global gLDown, gWASDState, gGhostActive

    ; Só faz sentido quando está andando/segurando
    if (!gLDown && gWASDState = 0 && !gGhostActive)
        return

    if (gStopWalkRequest)
        return

    for _, k in gStopWalkKeys {
        st := (GetKeyState(k, "P") ? 1 : 0)
        prev := gStopWalkPrev[k]

        if (st && !prev) {
            ; Ignora teclas de movimento do modo atual
            if (!StopWalk_IsMovementKey(k)) {
                StopWalk_Request()
                break
            }
        }
        gStopWalkPrev[k] := st
    }

    ; Auto Attack Mode: LButton press also stops walking
    if (gAutoAttackMode && !gStopWalkRequest) {
        stL := (GetKeyState("LButton", "P") ? 1 : 0)

        ; Ignore synthetic clicks/down generated by the script (e.g. WASD double-click / walk-hold)
        if (A_TickCount < gIgnoreLButtonEdgesUntil) {
            gStopWalkPrevLButton := stL
        } else {
            if (stL && !gStopWalkPrevLButton)
                StopWalk_Request()
            gStopWalkPrevLButton := stL
        }
    }
}

StopWalk_ExtractKeyFromHotkey(hk) {
    ; Remove prefixes (~, *) e remove " up" no final
    key := hk
    key := RegExReplace(key, "i)^\s*[~\*\$]+")
    key := RegExReplace(key, "i)\s+up$")
    return key
}

StopWalk_CheckHotkey() {
    global gLDown, gWASDState, gGhostActive
    ; Só quando está andando/segurando
    if (!gLDown && gWASDState = 0 && !gGhostActive)
        return

    hk := A_ThisHotkey
    if (hk = "")
        return

    key := StopWalk_ExtractKeyFromHotkey(hk)
    if (key = "")
        return

    ; Se for uma tecla "não-movimento" do modo atual, dispara stop.
    if (!StopWalk_IsMovementKey(key))
        StopWalk_Request()
}


; EMERGENCY UNLOCK (in case the cursor ever gets stuck clipped/locked)
; Press Ctrl+Alt+End to release any cursor lock immediately.
^!End::
    CursorLock_Stop()
    RawMouse_CancelCapture()
    HardLock_Stop()
    Lazy_ReleaseSkill()
    Lazy_ClearHotkeys()
return

; =========================
; Mouse Mode (FIXED TAP) - ClipCursor
; =========================
MouseMode_Reset() {
    global gMouseBusy, gMouseNextAllowedTick
    global gMouseHaveOrig, gMouseReturnPending
    global gMouseDownActive, gMouseDownTick

    SetTimer, MouseMode_ReturnTimer, Off
    gMouseBusy := false
    gMouseNextAllowedTick := 0
    gMouseHaveOrig := false
    gMouseReturnPending := false
    gMouseDownActive := false
    gMouseDownTick := 0

    CursorLock_Stop()
    RawMouse_CancelCapture()
    HardLock_Stop()
    Lazy_ReleaseSkill()
    Lazy_ClearHotkeys()
}

MouseMode_Down() {
    global gClickX, gClickY
    global gMouseClickMoveDelayMs, gMouseSpamDelayMs
    global gMouseOrigX, gMouseOrigY, gMouseHaveOrig
    global gMouseReturnPending, gMouseReturnDueTick
    global gMouseBusy, gMouseNextAllowedTick
    global gMouseDownActive, gMouseDownTick

    ; Ensure Click point is resolved for current window position/size
    Points_UpdateResolved()

    if (gClickX = "" || gClickY = "")
        return

    if (A_TickCount < gMouseNextAllowedTick)
        return

    gMouseBusy := true
    gMouseDownActive := true
    gMouseDownTick := A_TickCount
    gMouseNextAllowedTick := A_TickCount + Max(0, gMouseSpamDelayMs)

    ; save original cursor position
    MouseGetPos, ox, oy
    gMouseOrigX := ox, gMouseOrigY := oy
    gMouseHaveOrig := true

    ; LOCK cursor at click point (cannot drift) + capture your physical mouse movement (if raw input works)
    RawMouse_Init()
    RawMouse_BeginCapture()
    CursorLock_Start(gClickX, gClickY)

    ; press down at click point
    SendEvent, {LButton down}

    ; schedule return
    gMouseReturnDueTick := A_TickCount + Max(0, gMouseClickMoveDelayMs)
    gMouseReturnPending := true
    SetTimer, MouseMode_ReturnTimer, 1
}

MouseMode_ReturnTimer:
    global gMouseReturnPending, gMouseReturnDueTick
    global gMouseHaveOrig, gMouseOrigX, gMouseOrigY
    global gRawMouseOk

    if (!gMouseReturnPending) {
        SetTimer, MouseMode_ReturnTimer, Off
        return
    }

    if (A_TickCount >= gMouseReturnDueTick) {
        ; End capture first (doesn't depend on the lock).
        dx := 0, dy := 0
        RawMouse_EndCapture(dx, dy)

        if (gMouseHaveOrig) {
            ; If raw input isn't available, dx/dy will be 0 (fallback: snap to original)
            nx := gMouseOrigX + dx
            ny := gMouseOrigY + dy
            ClampToVirtualScreen(nx, ny)

            ; IMPORTANT: move the clip "cage" to the RETURN point first,
            ; then unlock. This avoids the cursor "walking away" from HP on unlock.
            CursorLock_MoveTo(nx, ny)
            Sleep, 1
            CursorLock_Stop()

            ; tiny stabilizer to beat any queued motion (keep VERY short)
            HardLock_Start(nx, ny, 12)
        } else {
            CursorLock_Stop()
        }

        gMouseReturnPending := false
        SetTimer, MouseMode_ReturnTimer, Off
    }
return

MouseMode_Up() {
    global gMouseReturnPending, gMouseHaveOrig, gMouseOrigX, gMouseOrigY
    global gMouseBusy, gMouseDownActive, gMouseDownTick
    global gClickX, gClickY
    global gMouseClickMoveDelayMs

    ; TAP case: user released BEFORE return happened
    if (gMouseReturnPending) {
        SetTimer, MouseMode_ReturnTimer, Off

        elapsed := A_TickCount - gMouseDownTick
        remain := Max(0, gMouseClickMoveDelayMs - elapsed)

        ; keep the lock for the remaining delay (so the click can't happen elsewhere)
        if (remain > 0)
            Sleep, %remain%

        ; IMPORTANT: release UP AT CLICK POINT
        DllCall("SetCursorPos", "Int", gClickX, "Int", gClickY)
        SendEvent, {LButton up}

        ; now return cursor to where your hand actually moved during the lock (or original if raw not available)
        dx := 0, dy := 0
        RawMouse_EndCapture(dx, dy)

        if (gMouseHaveOrig) {
            nx := gMouseOrigX + dx
            ny := gMouseOrigY + dy
            ClampToVirtualScreen(nx, ny)

            ; Same trick: move the clip "cage" to the return point, THEN unlock.
            CursorLock_MoveTo(nx, ny)
            Sleep, 1
            CursorLock_Stop()
            HardLock_Start(nx, ny, 12)
        } else {
            CursorLock_Stop()
        }

        gMouseReturnPending := false
        gMouseBusy := false
        gMouseDownActive := false
        gMouseDownTick := 0
        return
    }

    ; HOLD case: return already happened (mouse is free while holding)
    SendEvent, {LButton up}

    gMouseBusy := false
    gMouseDownActive := false
    gMouseDownTick := 0
}


; =========================
; Lazy mode (element -> hold skill)
; =========================
Lazy_ElementPressed:
    ; Handler label for all element hotkeys.
    Lazy_HandleElement(A_ThisHotkey)
return

Lazy__ReleaseTimer:
    ; One-shot: release held skill shortly after a mouse down edge.
    Lazy_ReleaseSkill()
return

Lazy_UpdateHotkeys() {
    ; NOTE: We now POLL element keys instead of registering dynamic Hotkey() handlers.
    ; This avoids games/overlays eating the hotkeys and keeps the element key passing through normally.
    Lazy_ClearHotkeys()
    Lazy_ResetElemPrev()
}

Lazy_RegOne(hk) {
    global gLazyRegKeys
    if (hk = "")
        return
    ; Register using a single shared label
    Hotkey, %hk%, Lazy_ElementPressed, On UseErrorLevel
    if (!ErrorLevel)
        gLazyRegKeys.Push(hk)
}

Lazy_ClearHotkeys() {
    global gLazyRegKeys, gGameExe

    ; Disable under the same context we registered (game window only)
    Hotkey, IfWinActive, % "ahk_exe " . gGameExe
    if (!IsObject(gLazyRegKeys))
        gLazyRegKeys := []
    for _, hk in gLazyRegKeys {
        if (hk != "")
            Hotkey, %hk%, Off, UseErrorLevel
    }
    gLazyRegKeys := []
    Hotkey, IfWinActive
}

Lazy_HandleElement(hk) {
    global gEnabled, gLazyModeOn, gLazySkillHK, gLazyActive
    if (!gEnabled || !gLazyModeOn)
        return
    if (!IsGameActive())
        return
    if (gLazySkillHK = "") {
        SoundBeep, 700, 80
        return
    }

    ; The element key itself should pass through physically. We only hold the skill key.
    if (!gLazyActive)
        Lazy_PressSkillDown()
}

Lazy_TryTriggerFromSimHK(simHK) {
    ; Called when another feature (e.g. Extra Keys wheel remap) *sends* a key that should also
    ; behave like a Lazy element hotkey. Since Lazy mode polls *physical* key states, a SendInput
    ; won't be detected, so we bridge it here.
    global gEnabled, gLazyModeOn, gLazySkillHK
    if (!gEnabled || !gLazyModeOn)
        return
    if (!IsGameActive())
        return
    if (gLazySkillHK = "")
        return
    if (Lazy_IsElementHotkey(simHK))
        Lazy_PressSkillDown()
}

Lazy_IsElementHotkey(hk) {
    global gLazySagradoHK, gLazySombrioHK, gLazyFogoHK, gLazyVentoHK
    global gLazyNeutroHK, gLazyAguaHK, gLazyFantasmaHK, gLazyTerraHK
    return Hotkey_Equals(hk, gLazySagradoHK)
        || Hotkey_Equals(hk, gLazySombrioHK)
        || Hotkey_Equals(hk, gLazyFogoHK)
        || Hotkey_Equals(hk, gLazyVentoHK)
        || Hotkey_Equals(hk, gLazyNeutroHK)
        || Hotkey_Equals(hk, gLazyAguaHK)
        || Hotkey_Equals(hk, gLazyFantasmaHK)
        || Hotkey_Equals(hk, gLazyTerraHK)
}

Hotkey_Equals(hkA, hkB) {
    hkA := Trim(hkA), hkB := Trim(hkB)
    if (hkA = "" || hkB = "")
        return false
    pA := Lazy_ParseHotkey(hkA)
    pB := Lazy_ParseHotkey(hkB)
    if (!IsObject(pA) || !IsObject(pB))
        return false
    return (pA.key = pB.key
        && pA.ctrl = pB.ctrl
        && pA.alt = pB.alt
        && pA.shift = pB.shift
        && pA.win = pB.win)
}


Lazy_ResetElemPrev() {
    global gLazySagradoHK, gLazySombrioHK, gLazyFogoHK, gLazyVentoHK
    global gLazyNeutroHK, gLazyAguaHK, gLazyFantasmaHK, gLazyTerraHK
    global gLazyPrevElemSagrado, gLazyPrevElemSombrio, gLazyPrevElemFogo, gLazyPrevElemVento
    global gLazyPrevElemNeutro, gLazyPrevElemAgua, gLazyPrevElemFantasma, gLazyPrevElemTerra

    gLazyPrevElemSagrado := Lazy_IsHotkeyPressed(gLazySagradoHK) ? 1 : 0
    gLazyPrevElemSombrio := Lazy_IsHotkeyPressed(gLazySombrioHK) ? 1 : 0
    gLazyPrevElemFogo := Lazy_IsHotkeyPressed(gLazyFogoHK) ? 1 : 0
    gLazyPrevElemVento := Lazy_IsHotkeyPressed(gLazyVentoHK) ? 1 : 0
    gLazyPrevElemNeutro := Lazy_IsHotkeyPressed(gLazyNeutroHK) ? 1 : 0
    gLazyPrevElemAgua := Lazy_IsHotkeyPressed(gLazyAguaHK) ? 1 : 0
    gLazyPrevElemFantasma := Lazy_IsHotkeyPressed(gLazyFantasmaHK) ? 1 : 0
    gLazyPrevElemTerra := Lazy_IsHotkeyPressed(gLazyTerraHK) ? 1 : 0
}

Lazy_IsHotkeyPressed(hk) {
    if (hk = "" || hk = "ERROR")
        return 0
    parts := Lazy_ParseHotkey(hk)
    if (!IsObject(parts) || parts.key = "")
        return 0

    if (parts.ctrl && !GetKeyState("Ctrl", "P"))
        return 0
    if (parts.alt && !GetKeyState("Alt", "P"))
        return 0
    if (parts.shift && !GetKeyState("Shift", "P"))
        return 0
    if (parts.win && !(GetKeyState("LWin", "P") || GetKeyState("RWin", "P")))
        return 0

    return GetKeyState(parts.key, "P") ? 1 : 0
}

Lazy_PollElements() {
    global gEnabled, gLazyModeOn, gLazySkillHK
    global gLazySagradoHK, gLazySombrioHK, gLazyFogoHK, gLazyVentoHK
    global gLazyNeutroHK, gLazyAguaHK, gLazyFantasmaHK, gLazyTerraHK
    global gLazyPrevElemSagrado, gLazyPrevElemSombrio, gLazyPrevElemFogo, gLazyPrevElemVento
    global gLazyPrevElemNeutro, gLazyPrevElemAgua, gLazyPrevElemFantasma, gLazyPrevElemTerra

    if (!gEnabled || !gLazyModeOn)
        return
    if (!IsGameActive())
        return
    ; If skill is not set, do nothing (avoid beeping every tick).
    if (gLazySkillHK = "")
        return

    p := Lazy_IsHotkeyPressed(gLazySagradoHK)
    if (p && !gLazyPrevElemSagrado)
        Lazy_PressSkillDown()
    gLazyPrevElemSagrado := p

    p := Lazy_IsHotkeyPressed(gLazySombrioHK)
    if (p && !gLazyPrevElemSombrio)
        Lazy_PressSkillDown()
    gLazyPrevElemSombrio := p

    p := Lazy_IsHotkeyPressed(gLazyFogoHK)
    if (p && !gLazyPrevElemFogo)
        Lazy_PressSkillDown()
    gLazyPrevElemFogo := p

    p := Lazy_IsHotkeyPressed(gLazyVentoHK)
    if (p && !gLazyPrevElemVento)
        Lazy_PressSkillDown()
    gLazyPrevElemVento := p

    p := Lazy_IsHotkeyPressed(gLazyNeutroHK)
    if (p && !gLazyPrevElemNeutro)
        Lazy_PressSkillDown()
    gLazyPrevElemNeutro := p

    p := Lazy_IsHotkeyPressed(gLazyAguaHK)
    if (p && !gLazyPrevElemAgua)
        Lazy_PressSkillDown()
    gLazyPrevElemAgua := p

    p := Lazy_IsHotkeyPressed(gLazyFantasmaHK)
    if (p && !gLazyPrevElemFantasma)
        Lazy_PressSkillDown()
    gLazyPrevElemFantasma := p

    p := Lazy_IsHotkeyPressed(gLazyTerraHK)
    if (p && !gLazyPrevElemTerra)
        Lazy_PressSkillDown()
    gLazyPrevElemTerra := p
}

Lazy_PollCancel() {
    global gLazyActive, gUseArrows, gWASDOn
    global gLazyPrevLBtn, gLazyPrevRBtn, gLazyPrevMBtn, gLazyPrevX1Btn, gLazyPrevX2Btn
    global gLazyPrevW, gLazyPrevA, gLazyPrevS, gLazyPrevD
    global gLazyPrevUp, gLazyPrevLeft, gLazyPrevDown, gLazyPrevRight

    if (!gLazyActive)
        return

    ; Cancel (release held skill) on ANY physical mouse button DOWN edge.
    ; We release a tiny moment later so the click DOWN is still seen with the skill held.
    curL  := GetKeyState("LButton",  "P") ? 1 : 0
    curR  := GetKeyState("RButton",  "P") ? 1 : 0
    curM  := GetKeyState("MButton",  "P") ? 1 : 0
    curX1 := GetKeyState("XButton1", "P") ? 1 : 0
    curX2 := GetKeyState("XButton2", "P") ? 1 : 0

    if ((curL && !gLazyPrevLBtn) || (curR && !gLazyPrevRBtn) || (curM && !gLazyPrevMBtn) || (curX1 && !gLazyPrevX1Btn) || (curX2 && !gLazyPrevX2Btn)) {
        SetTimer, Lazy__ReleaseTimer, Off
        SetTimer, Lazy__ReleaseTimer, -25
        gLazyPrevLBtn := curL
        gLazyPrevRBtn := curR
        gLazyPrevMBtn := curM
        gLazyPrevX1Btn := curX1
        gLazyPrevX2Btn := curX2
        return
    }

    gLazyPrevLBtn := curL
    gLazyPrevRBtn := curR
    gLazyPrevMBtn := curM
    gLazyPrevX1Btn := curX1
    gLazyPrevX2Btn := curX2

    ; Cancel on NEW movement key press (edge) only when WASD mode is enabled
    if (!gWASDOn)
        return

    if (gUseArrows) {
        up := GetKeyState("Up","P") ? 1 : 0
        left := GetKeyState("Left","P") ? 1 : 0
        downk := GetKeyState("Down","P") ? 1 : 0
        right := GetKeyState("Right","P") ? 1 : 0

        if ((up && !gLazyPrevUp) || (left && !gLazyPrevLeft) || (downk && !gLazyPrevDown) || (right && !gLazyPrevRight)) {
            Lazy_ReleaseSkill()
            return
        }

        gLazyPrevUp := up
        gLazyPrevLeft := left
        gLazyPrevDown := downk
        gLazyPrevRight := right
    } else {
        w := GetKeyState("w","P") ? 1 : 0
        a := GetKeyState("a","P") ? 1 : 0
        s := GetKeyState("s","P") ? 1 : 0
        d := GetKeyState("d","P") ? 1 : 0

        if ((w && !gLazyPrevW) || (a && !gLazyPrevA) || (s && !gLazyPrevS) || (d && !gLazyPrevD)) {
            Lazy_ReleaseSkill()
            return
        }

        gLazyPrevW := w
        gLazyPrevA := a
        gLazyPrevS := s
        gLazyPrevD := d
    }
}


Lazy_PressSkillDown() {
    global gLazySkillHK, gLazyActive
    global gLazyHoldKey, gLazyHoldCtrl, gLazyHoldAlt, gLazyHoldShift, gLazyHoldWin
    global gUseArrows
    global gLazyPrevLBtn, gLazyPrevRBtn, gLazyPrevMBtn, gLazyPrevX1Btn, gLazyPrevX2Btn
    global gLazyPrevW, gLazyPrevA, gLazyPrevS, gLazyPrevD
    global gLazyPrevUp, gLazyPrevLeft, gLazyPrevDown, gLazyPrevRight

    if (gLazyActive)
        return

    parts := Lazy_ParseHotkey(gLazySkillHK)
    if (!IsObject(parts) || parts.key = "")
        return

    ; Save what we're holding (so we can release cleanly later)
    gLazyHoldCtrl  := parts.ctrl
    gLazyHoldAlt   := parts.alt
    gLazyHoldShift := parts.shift
    gLazyHoldWin   := parts.win
    gLazyHoldKey   := parts.key

    ; Press modifiers down first (physical)
    if (gLazyHoldCtrl)
        Lazy_PhysKeyDown("LCtrl")
    if (gLazyHoldAlt)
        Lazy_PhysKeyDown("LAlt")
    if (gLazyHoldShift)
        Lazy_PhysKeyDown("LShift")
    if (gLazyHoldWin)
        Lazy_PhysKeyDown("LWin")

    ; Hold the skill key down (physical)
    Lazy_PhysKeyDown(gLazyHoldKey)
    gLazyActive := true

    ; Init edge tracking so we only cancel on NEW click/move after activation
    gLazyPrevLBtn  := GetKeyState("LButton", "P") ? 1 : 0
    gLazyPrevRBtn  := GetKeyState("RButton", "P") ? 1 : 0
    gLazyPrevMBtn  := GetKeyState("MButton", "P") ? 1 : 0
    gLazyPrevX1Btn := GetKeyState("XButton1", "P") ? 1 : 0
    gLazyPrevX2Btn := GetKeyState("XButton2", "P") ? 1 : 0

    if (gUseArrows) {
        gLazyPrevUp := GetKeyState("Up","P") ? 1 : 0
        gLazyPrevLeft := GetKeyState("Left","P") ? 1 : 0
        gLazyPrevDown := GetKeyState("Down","P") ? 1 : 0
        gLazyPrevRight := GetKeyState("Right","P") ? 1 : 0
    } else {
        gLazyPrevW := GetKeyState("w","P") ? 1 : 0
        gLazyPrevA := GetKeyState("a","P") ? 1 : 0
        gLazyPrevS := GetKeyState("s","P") ? 1 : 0
        gLazyPrevD := GetKeyState("d","P") ? 1 : 0
    }
}


Lazy_ReleaseSkill() {
    global gLazyActive
    global gLazyHoldKey, gLazyHoldCtrl, gLazyHoldAlt, gLazyHoldShift, gLazyHoldWin
    global gLazyPrevLBtn, gLazyPrevRBtn, gLazyPrevMBtn, gLazyPrevX1Btn, gLazyPrevX2Btn
    global gLazyPrevW, gLazyPrevA, gLazyPrevS, gLazyPrevD
    global gLazyPrevUp, gLazyPrevLeft, gLazyPrevDown, gLazyPrevRight

    if (!gLazyActive)
        return

    ; Release main key first
    if (gLazyHoldKey != "")
        Lazy_PhysKeyUp(gLazyHoldKey)

    ; Release modifiers
    if (gLazyHoldWin)
        Lazy_PhysKeyUp("LWin")
    if (gLazyHoldShift)
        Lazy_PhysKeyUp("LShift")
    if (gLazyHoldAlt)
        Lazy_PhysKeyUp("LAlt")
    if (gLazyHoldCtrl)
        Lazy_PhysKeyUp("LCtrl")

    gLazyActive := false
    gLazyHoldKey := ""
    gLazyHoldCtrl := 0, gLazyHoldAlt := 0, gLazyHoldShift := 0, gLazyHoldWin := 0

    ; Reset cancel edge tracking
    gLazyPrevLBtn := 0
    gLazyPrevRBtn := 0
    gLazyPrevMBtn := 0
    gLazyPrevX1Btn := 0
    gLazyPrevX2Btn := 0
    gLazyPrevW := 0, gLazyPrevA := 0, gLazyPrevS := 0, gLazyPrevD := 0
    gLazyPrevUp := 0, gLazyPrevLeft := 0, gLazyPrevDown := 0, gLazyPrevRight := 0
}



; -------------------------
; Lazy mode: physical key helpers (works better with other programs)
; -------------------------
Lazy_PhysKeyDown(keyName) {
    vk := GetKeyVK(keyName)
    sc := GetKeySC(keyName)
    if (!vk)
        return false

    ext := 0
    if (sc > 0xFF) {
        ext := 1
        sc := sc & 0xFF
    }

    ; KEYEVENTF_EXTENDEDKEY = 1, KEYUP = 2
    flags := ext ? 1 : 0
    DllCall("keybd_event", "UChar", vk, "UChar", sc, "UInt", flags, "UPtr", 0)
    return true
}

Lazy_PhysKeyUp(keyName) {
    vk := GetKeyVK(keyName)
    sc := GetKeySC(keyName)
    if (!vk)
        return false

    ext := 0
    if (sc > 0xFF) {
        ext := 1
        sc := sc & 0xFF
    }

    flags := 2 | (ext ? 1 : 0)
    DllCall("keybd_event", "UChar", vk, "UChar", sc, "UInt", flags, "UPtr", 0)
    return true
}

; Tap a hotkey-control string physically (handles modifiers like ^ ! + #).
Lazy_PhysTapHotkey(hk) {
    parts := Lazy_ParseHotkey(hk)
    if (!IsObject(parts) || parts.key = "")
        return

    ; Down mods
    if (parts.ctrl)
        Lazy_PhysKeyDown("LCtrl")
    if (parts.alt)
        Lazy_PhysKeyDown("LAlt")
    if (parts.shift)
        Lazy_PhysKeyDown("LShift")
    if (parts.win)
        Lazy_PhysKeyDown("LWin")

    ; Tap key
    Lazy_PhysKeyDown(parts.key)
    Sleep, 10
    Lazy_PhysKeyUp(parts.key)

    ; Up mods
    if (parts.win)
        Lazy_PhysKeyUp("LWin")
    if (parts.shift)
        Lazy_PhysKeyUp("LShift")
    if (parts.alt)
        Lazy_PhysKeyUp("LAlt")
    if (parts.ctrl)
        Lazy_PhysKeyUp("LCtrl")
}

; Convert a Hotkey-control string (e.g. "^!F1") into a Send-able tap sequence (e.g. "^!{F1}").
Lazy_HotkeyToSendTap(hk) {
    parts := Lazy_ParseHotkey(hk)
    if (!IsObject(parts) || parts.key = "")
        return ""
    mods := ""
    if (parts.ctrl)
        mods .= "^"
    if (parts.alt)
        mods .= "!"
    if (parts.shift)
        mods .= "+"
    if (parts.win)
        mods .= "#"
    return mods . "{" . parts.key . "}"
}

; Parses Hotkey strings from AHK Hotkey GUI control.
; Supports prefixes: ^ ! + # and also "X & Y" combos (we use the last key).
Lazy_ParseHotkey(hk) {
    if (hk = "" || hk = "ERROR")
        return ""

    hk := Trim(hk)

    ; Strip common hotkey prefixes (tilde/wildcard/$) if present
    Loop {
        ch0 := SubStr(hk, 1, 1)
        if (ch0 = "~" || ch0 = "*" || ch0 = "$") {
            hk := SubStr(hk, 2)
            continue
        }
        break
    }
    hk := Trim(hk)

    ; If it's a custom combo like "a & b", keep the last key (b)
    if InStr(hk, " & ") {
        parts2 := StrSplit(hk, " & ")
        hk := parts2[parts2.MaxIndex()]
        hk := Trim(hk)
    }

    ctrl := 0, alt := 0, shift := 0, win := 0
    Loop {
        ch := SubStr(hk, 1, 1)
        if (ch = "^") {
            ctrl := 1
            hk := SubStr(hk, 2)
            continue
        }
        if (ch = "!") {
            alt := 1
            hk := SubStr(hk, 2)
            continue
        }
        if (ch = "+") {
            shift := 1
            hk := SubStr(hk, 2)
            continue
        }
        if (ch = "#") {
            win := 1
            hk := SubStr(hk, 2)
            continue
        }
        break
    }

    hk := Trim(hk)
    if (hk = "")
        return ""

    return { ctrl: ctrl, alt: alt, shift: shift, win: win, key: hk }
}

; -------------------------
; OnExit cleanup (prevents cursor from staying clipped if script is closed/crashes)
; -------------------------
__KuganCleanup:
    ; Always allow the script to close (GUI X, tray Exit, Alt+F4, etc.)
    ; We disable the handler first to avoid any recursion when calling ExitApp.
    Critical
    OnExit,  ; disable this OnExit handler
    CursorLock_Stop()
    RawMouse_CancelCapture()
    HardLock_Stop()
    Lazy_ReleaseSkill()
    Lazy_ClearHotkeys()
    ExitApp
return


; =========================
; WASD Core Loop
; =========================
TickMove:
    ; Evita timer reentrar durante a execução (isso causa zigzag/jitter)
    Critical, 30

    global gEnabled, gWASDOn, gWASDPaused, gLDown
    global gCenterX, gCenterY, gClickX, gClickY
    global gDownDelayMs, gClickMoveDelayMs, gHoldStartTick
    global gLastDx, gLastDy, gHadMove, gUseArrows
    global gStopDist, gStopMinHoldMs
    global gLastInputDx, gLastInputDy, gLastInputTick
    global gLastDiagDx, gLastDiagDy, gLastDiagTick, gDiagLatchMs
    global gStopDirValid, gStopDirX, gStopDirY
    global gWASDState, gWASDDueTick, gWASDStartDx, gWASDStartDy
    global gCapsTapCooldownMs, gCapsTapHoldMs, gCapsTapNextAllowedTick
    global gCapsTapState, gCapsTapDueTick, gCapsTapDirX, gCapsTapDirY
    global gPrevW, gPrevA, gPrevS, gPrevD, gPrevUp, gPrevLeft, gPrevDown, gPrevRight

    if (!gEnabled)
        return

    ; Lazy mode: detect element presses and hold skill
    Lazy_PollElements()

    ; Lazy mode: release held skill on physical click or movement
    Lazy_PollCancel()

    ; Extra Keys: double-click hotkeys
    Extra_PollClickKeys()

    if (!IsGameActive()) {
        if (gLDown)
            ReleaseClick(false)
        Ghost_Cancel()
        gWASDState := 0
        gCapsTapState := 0
        ; sincroniza prev keys pra nao gerar edge ao voltar
        if (!gUseArrows) {
            gPrevW := GetKeyState("w","P")
            gPrevA := GetKeyState("a","P")
            gPrevS := GetKeyState("s","P")
            gPrevD := GetKeyState("d","P")
        } else {
            gPrevUp := GetKeyState("Up","P")
            gPrevLeft := GetKeyState("Left","P")
            gPrevDown := GetKeyState("Down","P")
            gPrevRight := GetKeyState("Right","P")
        }
        Lazy_ResetElemPrev()
        return
    }

    if (!gWASDOn || gWASDPaused) {
        if (gLDown)
            ReleaseClick(false)
        Ghost_Cancel()
        gWASDState := 0
        gCapsTapState := 0
        return
    }

    ; Update points based on current game window (fix for windowed/borderless/fullscreen)
    Points_UpdateResolved()

    if (gCenterX = "" || gCenterY = "")
        return

    ; -------------------------------------------------
    ; Stop-walk quando outras teclas (skills) são pressionadas
    ; - Só aplica no modo continuo (Caps solto)
    ; - Se disparar, solta o LButton e (se Ghost ativo) teleporta o cursor pro retículo
    ; - Ativa latch pra não voltar a andar enquanto as teclas de movimento ainda estiverem seguradas
    ; -------------------------------------------------
    if ((gGhostTarget || gStopWalkEnabled || gAutoAttackMode) && !IsCapsHeld()) {
        StopWalk_PollOtherKeys()
        if (gStopWalkRequest) {
            gStopWalkRequest := false
            gStopWalkLatch := true

            ; Para movimento imediatamente
            if (gLDown)
                ReleaseClick(false)

            ; Finaliza Ghost com teleport (se estiver ativo)
            if (gGhostActive)
                Ghost_EndAndTeleport()

            ; Reseta estados
            gWASDState := 0
            gCapsTapState := 0

            ; Sincroniza estados de tecla pra não re-disparar edge instantâneo
            StopWalk_SyncPrev()
        }
    }

    useDist := GetActiveDistance()
    if (useDist <= 0)
        useDist := 1

    ; -------------------------------------------------
    ; Ler teclas + detectar "edge" (pra Caps tap)
    ; -------------------------------------------------
    edge := false
    dx := 0.0, dy := 0.0

    if (!gUseArrows) {
        w := GetKeyState("w","P")
        a := GetKeyState("a","P")
        s := GetKeyState("s","P")
        d := GetKeyState("d","P")

        edge := ( (w && !gPrevW) || (a && !gPrevA) || (s && !gPrevS) || (d && !gPrevD) )

        gPrevW := w, gPrevA := a, gPrevS := s, gPrevD := d

        dx := (d ? 1 : 0) - (a ? 1 : 0)
        dy := (s ? 1 : 0) - (w ? 1 : 0)
    } else {
        up := GetKeyState("Up","P")
        left := GetKeyState("Left","P")
        downk := GetKeyState("Down","P")
        right := GetKeyState("Right","P")

        edge := ( (up && !gPrevUp) || (left && !gPrevLeft) || (downk && !gPrevDown) || (right && !gPrevRight) )

        gPrevUp := up, gPrevLeft := left, gPrevDown := downk, gPrevRight := right

        dx := (right ? 1 : 0) - (left ? 1 : 0)
        dy := (downk ? 1 : 0) - (up ? 1 : 0)
    }

    ; Normaliza pra virar "circulo" (diagonal nao anda mais longe)
    mag := Sqrt(dx*dx + dy*dy)
    if (mag > 0.0001) {
        dx := dx / mag
        dy := dy / mag
    } else {
        dx := 0.0
        dy := 0.0
    }

    ; -------------------------------------------------
    ; Latch de parada: se Stop-walk foi acionado e as teclas de movimento ainda estão seguradas,
    ; não deixa voltar a andar até soltar tudo.
    ; -------------------------------------------------
    if (gStopWalkLatch) {
    ; Novo comportamento (Ghost Target):
    ; - Se o stop-walk foi acionado por uma tecla de skill, mantém parado mesmo segurando W/A/S/D.
    ; - MAS: se houver um novo "edge" de movimento (apertou alguma direção), o movimento volta IMEDIATO.
    if (edge && (dx != 0 || dy != 0)) {
        gStopWalkLatch := false
    } else if (dx != 0 || dy != 0) {
        dx := 0.0
        dy := 0.0
        edge := false
    } else {
        gStopWalkLatch := false
    }
}

    caps := IsCapsHeld()

    ; -------------------------------------------------
    ; Remember last movement vectors (used for circular StopDistance)
    ; Only for normal mode (Caps up). Caps-tap has its own discrete behavior.
    ; -------------------------------------------------
    if (!caps && (dx != 0 || dy != 0)) {
        gLastInputDx := dx
        gLastInputDy := dy
        gLastInputTick := A_TickCount

        ; Detect normalized diagonal (~0.707, ~0.707)
        if (Abs(Abs(dx) - 0.7071) < 0.035 && Abs(Abs(dy) - 0.7071) < 0.035) {
            gLastDiagDx := dx
            gLastDiagDy := dy
            gLastDiagTick := A_TickCount
        }
    }


    ; =================================================
    ; AUTO ATTACK MODE (Caps solto)
    ; - Mesmo esquema de override (skills/teclas param o movimento)
    ; - Adiciona LButton como override (pra auto-attack)
    ; - Quando você aperta WASD/Setas: double click na direção (não usa ClickX/ClickY)
    ; =================================================
    if (!caps && gAutoAttackMode) {

        ; Atualiza o retículo virtual enquanto o cursor está travado
        if (gGhostActive)
            Ghost_Tick()

        ; Sem input: para e devolve o cursor pro retículo (se Ghost ativo)
        if (dx = 0 && dy = 0) {
            if (gLDown)
                ReleaseClick(false)
            if (gGhostActive)
                Ghost_EndAndTeleport()
            gWASDState := 0
            return
        }

        ; Para segurar movimento continuo precisamos do Click point
        if (gClickX = "" || gClickY = "") {
            ; Ainda permite o double-click direcional (interromper auto-attack),
            ; mas sem hold continuo.
            tx := Round(gCenterX + dx * useDist)
            ty := Round(gCenterY + dy * useDist)
            if (gGhostTarget && gGhostActive)
                CursorLock_MoveTo(tx, ty)
            else
                MouseMove, %tx%, %ty%, 0

            ; Directional double-click is only needed when STARTING movement
            ; to break auto-attack. If we're already holding movement, don't
            ; click again (it would release the held LButton and stop walking).
            if (edge && !gLDown) {
                gIgnoreLButtonEdgesUntil := A_TickCount + 150
                SendEvent, {LButton}
                Sleep, 15
                SendEvent, {LButton}
            }
            return
        }

        ; Garante Ghost lock ativo (se Ghost Target ligado)
        if (gGhostTarget && !gGhostActive)
            Ghost_Begin(gClickX, gClickY)

        ; Direção alvo
        tx := Round(gCenterX + dx * useDist)
        ty := Round(gCenterY + dy * useDist)

        ; Se apertou uma direção (edge), faz double-click NA DIREÇÃO (não usa Click point)
        ; APENAS ao iniciar o movimento (gLDown=false). Enquanto já está andando,
        ; não clica de novo pra não soltar o LButton segurado.
        if (edge && !gLDown) {
            if (gGhostTarget && gGhostActive)
                CursorLock_MoveTo(tx, ty)
            else
                MouseMove, %tx%, %ty%, 0

            gIgnoreLButtonEdgesUntil := A_TickCount + 180
            SendEvent, {LButton}
            Sleep, 15
            SendEvent, {LButton}
        }

        ; Após interromper, se ainda estiver segurando a direção, entra em HOLD continuo
        if (!gLDown) {
            ; Vai pro Click point e segura o botão (walk-hold)
            if (gGhostTarget && gGhostActive)
                CursorLock_MoveTo(gClickX, gClickY)
            else
                MouseMove, %gClickX%, %gClickY%, 0

            gIgnoreLButtonEdgesUntil := A_TickCount + 220
            SendEvent, {LButton down}
            gLDown := true
            gHoldStartTick := A_TickCount
            gStopWalkPrevLButton := 1
        }

        ; Mantém andando enquanto segura WASD/Setas
        if (gGhostTarget && gGhostActive)
            CursorLock_MoveTo(tx, ty)
        else
            MouseMove, %tx%, %ty%, 0

        gWASDState := 3
        gLastDx := dx
        gLastDy := dy
        gHadMove := true
        return
    }

    ; =================================================
    ; CAPSLOCK HELD = TAP MODE (anti-spam 80ms)
    ; - Cada "tap" (edge) faz UM movimento curto
    ; - Mesmo spamando tecla, só roda 1x por cooldown
    ; =================================================
    if (caps) {
        ; Ghost Target não roda no modo Caps (tap). Cancela qualquer lock ativo.
        Ghost_Cancel()
        ; Para o modo continuo (se estava andando)
        if (gWASDState != 0) {
            gWASDState := 0
        }

        ; Se estava com LButton segurado do modo continuo, solta
        if (gLDown && gCapsTapState = 0) {
            ReleaseClick(false)
        }

        ; Precisa do click point (HP)
        if (gClickX = "" || gClickY = "")
            return

        ; ---- idle: espera edge + cooldown ----
        if (gCapsTapState = 0) {
            if (edge && (A_TickCount >= gCapsTapNextAllowedTick) && (dx != 0 || dy != 0)) {
                gCapsTapDirX := dx
                gCapsTapDirY := dy
                MouseMove, %gClickX%, %gClickY%, 0
                gCapsTapState := 1
                gCapsTapDueTick := A_TickCount + (gDownDelayMs > 0 ? gDownDelayMs : 0)
                gCapsTapNextAllowedTick := A_TickCount + gCapsTapCooldownMs
            }
            return
        }

        ; ---- wait down ----
        if (gCapsTapState = 1) {
            MouseMove, %gClickX%, %gClickY%, 0
            if (A_TickCount >= gCapsTapDueTick) {
                SendEvent, {LButton down}
                gLDown := true
                gHoldStartTick := A_TickCount
                gCapsTapState := 2
                gCapsTapDueTick := A_TickCount + (gClickMoveDelayMs > 0 ? gClickMoveDelayMs : 0)
            }
            return
        }

        ; ---- wait move delay (depois do down) ----
        if (gCapsTapState = 2) {
            MouseMove, %gClickX%, %gClickY%, 0
            if (A_TickCount >= gCapsTapDueTick) {
                tx := Round(gCenterX + gCapsTapDirX * useDist)
                ty := Round(gCenterY + gCapsTapDirY * useDist)
                if (gGhostTarget && gGhostActive)
        CursorLock_MoveTo(tx, ty)
    else
        MouseMove, %tx%, %ty%, 0

                ; salva direção (pra stopdist/diagnóstico)
                gLastDx := gCapsTapDirX
                gLastDy := gCapsTapDirY
                gHadMove := true

                gCapsTapState := 3
                gCapsTapDueTick := A_TickCount + (gCapsTapHoldMs > 0 ? gCapsTapHoldMs : 1)
            }
            return
        }

        ; ---- hold breve e solta ----
        if (gCapsTapState = 3) {
            tx := Round(gCenterX + gCapsTapDirX * useDist)
            ty := Round(gCenterY + gCapsTapDirY * useDist)
            MouseMove, %tx%, %ty%, 0

            if (A_TickCount >= gCapsTapDueTick) {
                SendEvent, {LButton up}
                gLDown := false
                gHoldStartTick := 0
                gCapsTapState := 0
            }
            return
        }

        return
    }

    ; =================================================
    ; NORMAL (Caps solto): Movimento continuo (sem acelerometro)
    ; =================================================

    ; Se estava no meio de um tap e soltou Caps, cancela seguro
    if (gCapsTapState != 0) {
        if (gLDown) {
            SendEvent, {LButton up}
            gLDown := false
        }
        gHoldStartTick := 0
        gCapsTapState := 0
    }

    ; Atualiza o retículo virtual enquanto o cursor está travado
    if (gGhostActive)
        Ghost_Tick()

    ; Sem input: para
    if (dx = 0 && dy = 0) {
        if (gLDown) {
            ; Decide stop direction using a short "diagonal latch".
            ; If the last direction right before release is axis-aligned but
            ; we had a diagonal very recently (within gDiagLatchMs), prefer the
            ; diagonal so StopDistance stays circular.
            stopDx := (gLastInputTick ? gLastInputDx : gLastDx)
            stopDy := (gLastInputTick ? gLastInputDy : gLastDy)

            isAxis := ((Abs(stopDx) < 0.22 || Abs(stopDy) < 0.22) && (Abs(stopDx) + Abs(stopDy) > 0.85))
            if (isAxis && gLastDiagTick && (A_TickCount - gLastDiagTick <= gDiagLatchMs)) {
                ; Only prefer the diagonal if it's "compatible" with the axis
                ; (same sign on the remaining component). This avoids latching
                ; an old diagonal when the player intentionally changed direction.
                sameX := ((stopDx > 0 && gLastDiagDx > 0) || (stopDx < 0 && gLastDiagDx < 0))
                sameY := ((stopDy > 0 && gLastDiagDy > 0) || (stopDy < 0 && gLastDiagDy < 0))
                if ((Abs(stopDx) < 0.22 && sameY) || (Abs(stopDy) < 0.22 && sameX)) {
                    stopDx := gLastDiagDx
                    stopDy := gLastDiagDy
                }
            }

            gStopDirX := stopDx
            gStopDirY := stopDy
            gStopDirValid := true

            ReleaseClick(true)
            ; Se Ghost Target estava ativo, devolve o cursor pro retículo e libera a mira
            if (gGhostActive)
                Ghost_EndAndTeleport()
        }
        gWASDState := 0
        return
    }

    ; ---- WAIT DOWN ----
    if (gWASDState = 1) {
        if (dx = 0 && dy = 0) {
            gWASDState := 0
            return
        }

        gWASDStartDx := dx
        gWASDStartDy := dy
        gLastDx := dx
        gLastDy := dy
        gHadMove := true

        if (gClickX != "" && gClickY != "") {
            if (gGhostTarget && (gGhostActive || Ghost_Begin(gClickX, gClickY)))
                CursorLock_MoveTo(gClickX, gClickY)
            else
                MouseMove, %gClickX%, %gClickY%, 0
        }

        if (A_TickCount >= gWASDDueTick) {
            SendEvent, {LButton down}
            gLDown := true
            gHoldStartTick := A_TickCount
            gWASDState := 2
            gWASDDueTick := A_TickCount + (gClickMoveDelayMs > 0 ? gClickMoveDelayMs : 0)
        }
        return
    }

    ; ---- WAIT MOVE DELAY (depois do down) ----
    if (gWASDState = 2) {
        if (gClickX != "" && gClickY != "") {
            if (gGhostTarget && (gGhostActive || Ghost_Begin(gClickX, gClickY)))
                CursorLock_MoveTo(gClickX, gClickY)
            else
                MouseMove, %gClickX%, %gClickY%, 0
        }

        if (dx != 0 || dy != 0) {
            gWASDStartDx := dx
            gWASDStartDy := dy
            gLastDx := dx
            gLastDy := dy
            gHadMove := true
        }

        if (A_TickCount >= gWASDDueTick) {
            gWASDState := 3
        }
        return
    }

    ; Se ainda não deu down, inicia state machine
    if (!gLDown) {
        if (gClickX = "" || gClickY = "")
            return
        ; Se Ghost Target estiver ativo, trava o cursor no click point e abre o retículo virtual
        if (gGhostTarget && Ghost_Begin(gClickX, gClickY)) {
            ; Cursor já está travado no click point
        } else {
            MouseMove, %gClickX%, %gClickY%, 0
        }
        gWASDState := 1
        gWASDDueTick := A_TickCount + (gDownDelayMs > 0 ? gDownDelayMs : 0)
        gWASDStartDx := dx
        gWASDStartDy := dy
        gLastDx := dx
        gLastDy := dy
        gHadMove := true
        return
    }

    ; Ativo: move direto pra direção (sem aceleração)
    gWASDState := 3
    gLastDx := dx
    gLastDy := dy
    gHadMove := true

    tx := Round(gCenterX + dx * useDist)
    ty := Round(gCenterY + dy * useDist)
    if (gGhostTarget && gGhostActive)
        CursorLock_MoveTo(tx, ty)
    else
        MouseMove, %tx%, %ty%, 0
return


ReleaseClick(considerStopAction := false) {
    global gLDown, gHoldStartTick, gStopMinHoldMs
    global gVelX, gVelY, gHadMove, gLastDx, gLastDy
    global gWASDState
    global gStopDirValid, gStopDirX, gStopDirY

    if (!gLDown)
        return

    if (considerStopAction) {
        held := 0
        if (gHoldStartTick)
            held := A_TickCount - gHoldStartTick

        if (held >= gStopMinHoldMs) {
            StopMoveDirectional()
            Sleep, 1
            gStopDirValid := false
        }
    }

    SendEvent, {LButton up}
    gLDown := false
    gHoldStartTick := 0

    ; Clear stop direction latch
    gStopDirValid := false
    gStopDirX := 0.0
    gStopDirY := 0.0

    ; Reset rampa (kept for compatibility; not used in this build)
    gVelX := 0.0
    gVelY := 0.0
    gHadMove := false
    gLastDx := 0
    gLastDy := 0
    gWASDState := 0
}

; ----------------------------------------------------------------------
; XDourada and Full Protection (FP) functions imported from KuganTools_v1.5
; These functions implement the timer bars, configuration GUI, and timer
; logic for the XDourada tab, as well as the search and reset logic for
; the Full Protection tab. They rely on global variables and settings
; defined in the auto-execute section above.

InitializeXDouradaHotkeys:
    Hotkey, ~%bar1Key%, ActivateBar1, On
    Hotkey, ~%bar2Key%, ActivateBar2, On
return

ActivateBar1:
    ; use gEnabled from KuganMovementTool to indicate macro is running
    if (xDouradaEnabled && gEnabled) {
        if (bar1Running)
            DestroyBar(1)
        bar1Running := 1
        remainingTime1 := bar1Seconds
        CreateBar(1, bar1X, bar1Y, bar1Color, bar1Seconds)
        SetTimer, UpdateTimers, 1000
    }
return

ActivateBar2:
    if (xDouradaEnabled && gEnabled) {
        if (bar2Running)
            DestroyBar(2)
        bar2Running := 1
        remainingTime2 := bar2Seconds
        CreateBar(2, bar2X, bar2Y, bar2Color, bar2Seconds)
        SetTimer, UpdateTimers, 1000
    }
return

CreateBar(barNumber, xPos, yPos, color, duration) {
    global
    Gui, Bar%barNumber%:New, +AlwaysOnTop -Caption +ToolWindow +E0x20 +LastFound
    Gui, Bar%barNumber%:Color, FFFFFF
    WinSet, TransColor, FFFFFF
    Gui, Bar%barNumber%:Margin, 0, 0
    Gui, Bar%barNumber%:Add, Progress, w%barWidth% h%barHeight% c%color% Background000000 vProgressBar%barNumber% Range0-%duration%, %duration%
    if (showNumbers) {
        textYPos := barHeight + 4
        Gui, Bar%barNumber%:Font, s12 c000000 bold q3, Consolas
        offsets := [[-2,-2], [0,-2], [2,-2], [-2,0], [2,0], [-2,2], [0,2], [2,2]]
        Loop 8 {
            xOffset := offsets[A_Index][1]
            yOffset := textYPos + offsets[A_Index][2]
            Gui, Bar%barNumber%:Add, Text, % "x" xOffset " y" yOffset " w" barWidth " Center BackgroundTrans vOutline" barNumber "_" A_Index, %duration%
        }
        Gui, Bar%barNumber%:Font, c%color% bold q3, Consolas
        Gui, Bar%barNumber%:Add, Text, % "x0 y" textYPos " w" barWidth " Center BackgroundTrans vTimeText" barNumber, %duration%
    }
    Gui, Bar%barNumber%:Show, x%xPos% y%yPos% NoActivate
}

DestroyBar(barNumber) {
    global
    Gui, Bar%barNumber%:Destroy
    bar%barNumber%Running := 0
    remainingTime%barNumber% := 0
}

UpdateTimers:
    needUpdate := false
    if (bar1Running) {
        remainingTime1 -= 1
        GuiControl, Bar1:, ProgressBar1, %remainingTime1%
        if (showNumbers) {
            Loop 8
                GuiControl, Bar1:, Outline1_%A_Index%, %remainingTime1%
            GuiControl, Bar1:, TimeText1, %remainingTime1%
        }
        if (remainingTime1 <= 0)
            DestroyBar(1)
        else if (remainingTime1 = 2 && BeepEnabled1)
            SoundBeep, 800, 300
        needUpdate := true
    }
    if (bar2Running) {
        remainingTime2 -= 1
        GuiControl, Bar2:, ProgressBar2, %remainingTime2%
        if (showNumbers) {
            Loop 8
                GuiControl, Bar2:, Outline2_%A_Index%, %remainingTime2%
            GuiControl, Bar2:, TimeText2, %remainingTime2%
        }
        if (remainingTime2 <= 0)
            DestroyBar(2)
        else if (remainingTime2 = 2 && BeepEnabled2)
            SoundBeep, 600, 300
        needUpdate := true
    }
    if (!needUpdate)
        SetTimer, UpdateTimers, Off
return

ShowConfigGUI:
    Gui, Config:New, , XDourada Configuration
    Gui, Font, s10, Segoe UI
    
    ; Bar 1
    Gui, Add, GroupBox, xm y10 w300 h170 Section, Bar 1
    Gui, Add, Text, xs+10 ys+25, Activation Key:
    Gui, Add, Hotkey, vNewBar1Key x+10 yp-3 w70, %bar1Key%
    Gui, Add, Text, xs+10 y+15, Position (X Y):
    Gui, Add, Edit, vNewBar1X x+10 yp-3 w50, %bar1X%
    Gui, Add, Edit, vNewBar1Y x+5 yp w50, %bar1Y%
    Gui, Add, Text, xs+10 y+15, Color:
    Gui, Add, Edit, vNewBar1Color x+10 yp-3 w100, %bar1Color%
    Gui, Add, Text, xs+10 y+15, Duration:
    Gui, Add, Edit, vNewBar1Seconds x+10 yp-3 w50, %bar1Seconds%
    Gui, Add, Text, xs+10 y+15, Sound Alert:
    Gui, Add, CheckBox, vNewBeepCheck1 x+10 yp-3 Checked%BeepEnabled1%, Enable
    
    ; Bar 2
    Gui, Add, GroupBox, xm y+20 w300 h170 Section, Bar 2
    Gui, Add, Text, xs+10 ys+25, Activation Key:
    Gui, Add, Hotkey, vNewBar2Key x+10 yp-3 w70, %bar2Key%
    Gui, Add, Text, xs+10 y+15, Position (X Y):
    Gui, Add, Edit, vNewBar2X x+10 yp-3 w50, %bar2X%
    Gui, Add, Edit, vNewBar2Y x+5 yp w50, %bar2Y%
    Gui, Add, Text, xs+10 y+15, Color:
    Gui, Add, Edit, vNewBar2Color x+10 yp-3 w100, %bar2Color%
    Gui, Add, Text, xs+10 y+15, Duration:
    Gui, Add, Edit, vNewBar2Seconds x+10 yp-3 w50, %bar2Seconds%
    Gui, Add, Text, xs+10 y+15, Sound Alert:
    Gui, Add, CheckBox, vNewBeepCheck2 x+10 yp-3 Checked%BeepEnabled2%, Enable
    
    ; Global
    Gui, Add, GroupBox, xm y+20 w300 h100 Section, Global
    Gui, Add, Text, xs+10 ys+25, Bar Width:
    Gui, Add, Edit, vNewBarWidth x+10 yp-3 w50, %barWidth%
    Gui, Add, Text, x+10 yp+3, Height:
    Gui, Add, Edit, vNewBarHeight x+10 yp-3 w50, %barHeight%
    Gui, Add, Text, xs+10 y+15, Show Numbers:
    Gui, Add, CheckBox, vNewShowNumbers x+10 yp-3 Checked%showNumbers%, Enable
    
    ; Buttons
    Gui, Add, Button, xm y+30 w80 Default gSaveBarConfig, Save
    Gui, Add, Button, x+20 yp w80 gCloseBarConfig, Cancel
    Gui, Show, AutoSize
return

SaveBarConfig:
    Gui, Submit
    Hotkey, ~%bar1Key%, ActivateBar1, Off
    bar1Key := NewBar1Key
    Hotkey, ~%bar1Key%, ActivateBar1, On
    Hotkey, ~%bar2Key%, ActivateBar2, Off
    bar2Key := NewBar2Key
    Hotkey, ~%bar2Key%, ActivateBar2, On
    bar1X := NewBar1X
    bar1Y := NewBar1Y
    bar1Color := NewBar1Color
    bar1Seconds := NewBar1Seconds
    BeepEnabled1 := (NewBeepCheck1 = 1) ? 1 : 0
    bar2X := NewBar2X
    bar2Y := NewBar2Y
    bar2Color := NewBar2Color
    bar2Seconds := NewBar2Seconds
    BeepEnabled2 := (NewBeepCheck2 = 1) ? 1 : 0
    barWidth := NewBarWidth
    barHeight := NewBarHeight
    showNumbers := NewShowNumbers
    IniWrite, %showNumbers%, %configFile%, XDourada, ShowNumbers
CloseBarConfig:
    Gui, Destroy
return

RemoveToolTip:
    ToolTip
return

ShowMouseColor:
    MouseGetPos, mx, my
    PixelGetColor, colorUnderPointer, %mx%, %my%, RGB
    if (!ColorTipCreated) {
        Gui, ColorTip:New, +AlwaysOnTop -Caption +ToolWindow +E0x20
        Gui, ColorTip:Margin, 4, 2
        Gui, ColorTip:Font, s8
        Gui, ColorTip:Add, Text, w80 vColorTipText
        ColorTipCreated := true
    }
    if (colorUnderPointer = searchColor) {
        Gui, ColorTip:Color, 00FF00
        Gui, ColorTip:Font, cFFFFFF
    } else {
        Gui, ColorTip:Color, FFFFFF
        Gui, ColorTip:Font, c000000
    }
    GuiControl, ColorTip:, ColorTipText, %colorUnderPointer%
    xPos := mx + 25
    yPos := my + 25
    Gui, ColorTip:Show, x%xPos% y%yPos% NoActivate
return

SendKey(key) {
    cleanKey := StrReplace(key, " ", "")
    if (RegExMatch(cleanKey, "i)^Alt\+(\d)$", m)) {
        digit := m1
        SendInput, {Alt down}
        Sleep, 30
        SendInput, %digit%
        Sleep, 30
        SendInput, {Alt up}
        return
    }
    if (RegExMatch(key, "i)^(F\d+|Numpad\d+)$") || StrLen(key) > 1) {
        SendInput, {%key%}
    } else {
        SendInput, %key%
    }
}

; === Full Protection Handlers ===

FP_SetTopLeft:
    Hotkey, ~LButton, FP_TopLeftHotkey, On
    ToolTip, Click the TOP-LEFT corner of the search area
return

FP_SetBottomRight:
    Hotkey, ~LButton, FP_BottomRightHotkey, On
    ToolTip, Click the BOTTOM-RIGHT corner of the search area
return

FP_TopLeftHotkey:
    MouseGetPos, tx, ty
    FP_searchArea.x1 := tx
    FP_searchArea.y1 := ty
    ToolTip
    Hotkey, ~LButton, Off
return

FP_BottomRightHotkey:
    MouseGetPos, bx, by
    FP_searchArea.x2 := bx
    FP_searchArea.y2 := by
    ToolTip
    Hotkey, ~LButton, Off
return

FP_SetIconPos:
    Hotkey, ~LButton, FP_IconPosHotkey, On
    ToolTip, Click where the icon should appear
return

FP_IconPosHotkey:
    MouseGetPos, ix, iy
    FP_iconPos.x := ix
    FP_iconPos.y := iy
    ToolTip
    Hotkey, ~LButton, Off
return

FP_TestIconLocation:
    FP_ShowTestIcon()
return

FP_StartStop:
    if (FP_isRunning) {
        FP_isRunning := false
        GuiControl,, FP_StatusText, Status: Stopped
        GuiControl,, FP_StartStopBtn, Start FP
        SetTimer, FP_MainLoop, Off
        SetTimer, FP_FlashIcon, Off
        Gui, %FP_iconGUI%:Destroy
        Gui, %FP_markerGUI%:Destroy
        FP_EnableMacroHotkeys(false)
    } else {
        if (FP_iconPos.x = 0 && FP_iconPos.y = 0) {
            MsgBox, Please set the icon position first!
            return
        }
        FP_isRunning := true
        FP_timerStart := 0
        FP_lastFound := 0
        GuiControl,, FP_StatusText, Status: Running
        GuiControl,, FP_StartStopBtn, Stop FP
        GuiControl,, FP_TimerText, Time: 10:00
        FP_ShowIcon()
        SetTimer, FP_MainLoop, 500
        FP_UpdateResetHotkey()
        FP_EnableMacroHotkeys(true)
    }
return

FP_ResetTimer:
    if (!FP_isRunning)
        return
    FP_timerStart := 0
    FP_lastFound := 0
    FP_isFlashing := false
    SetTimer, FP_FlashIcon, Off
    Gui, %FP_iconGUI%:Destroy
    Gui, %FP_markerGUI%:Destroy
    mins := Floor(FP_timerDuration / 60000)
    secs := Floor((FP_timerDuration // 1000) - mins * 60)
    GuiControl,, FP_TimerText, % "Time remaining: " mins ":" Format("{:02}", secs)
    FP_ShowIcon()
return

FP_UpdateResetHotkey() {
    global FP_resetMacroKey, FP_currentResetMacroHotkey, FP_isRunning
    if (FP_currentResetMacroHotkey)
        Hotkey, %FP_currentResetMacroHotkey%, FP_ResetTimer, Off
    FP_currentResetMacroHotkey := FP_resetMacroKey
    if (FP_isRunning && FP_currentResetMacroHotkey)
        Hotkey, %FP_currentResetMacroHotkey%, FP_ResetTimer, On
}

FP_EnableMacroHotkeys(enable := false) {
    global FP_currentResetMacroHotkey
    if (FP_currentResetMacroHotkey) {
        opt := enable ? "On" : "Off"
        Hotkey, %FP_currentResetMacroHotkey%, FP_ResetTimer, %opt%
    }
}

FP_ResetKeyChanged:
    GuiControlGet, FP_resetMacroKey,, FP_ResetMacroKey
    FP_resetMacroKey := Trim(FP_resetMacroKey)
    FP_UpdateResetHotkey()
return

FP_MainLoop:
    if (!FP_isRunning)
        return
    now := A_TickCount
    found := false
    if (ok := FindText(X, Y, FP_searchArea.x1, FP_searchArea.y1, FP_searchArea.x2, FP_searchArea.y2, 0, 0, TextPattern_FP)) {
        found := true
        FP_lastFound := now
        foundX := X
        foundY := Y
    }
    
    if (found) {
        Gui, %FP_iconGUI%:Destroy
        FP_isFlashing := false
        SetTimer, FP_FlashIcon, Off
        FP_ShowMarker(foundX, foundY)
        if (FP_timerStart = 0) {
            FP_timerStart := now
        }
    } else {
        if (FP_lastFound = 0) {
            missingDuration := FP_missingThreshold + 1
        } else {
            missingDuration := now - FP_lastFound
        }

        if (missingDuration >= FP_missingThreshold) {
            FP_ShowIcon()
            Gui, %FP_markerGUI%:Destroy
            if (FP_timerStart > 0) {
                FP_timerStart := 0
                FP_isFlashing := false
                SetTimer, FP_FlashIcon, Off
            }
        } else {
            Gui, %FP_iconGUI%:Destroy
            Gui, %FP_markerGUI%:Destroy
        }
    }
    
    if (FP_timerStart > 0) {
        elapsed := now - FP_timerStart
        if (elapsed >= FP_timerDuration) {
            FP_timerStart := 0
            GuiControl,, FP_TimerText, Time remaining: 00:00
            FP_isFlashing := false
            SetTimer, FP_FlashIcon, Off
            FP_ShowIcon()
            return
        }
        remaining := FP_timerDuration - elapsed
        mins := Floor(remaining / 60000)
        secs := Floor((remaining // 1000) - mins * 60)
        GuiControl,, FP_TimerText, % "Time remaining: " mins ":" Format("{:02}", secs)
        if (remaining < FP_warningTime && !FP_isFlashing) {
            FP_isFlashing := true
            FP_ShowIcon()
            SetTimer, FP_FlashIcon, 500
        }
    }
return

FP_FlashIcon:
    if (!FP_isRunning) {
        SetTimer, FP_FlashIcon, Off
        return
    }
    FP_iconFlashVisible := !FP_iconFlashVisible
    if (FP_iconFlashVisible) {
        Gui, %FP_iconGUI%:Show, NA
    } else {
        Gui, %FP_iconGUI%:Hide
    }
return

FP_ShowIcon() {
    global FP_iconGUI, FP_iconPos
    Gui, %FP_iconGUI%:Destroy
    if (FileExist("icons\\warning.png")) {
        iconFile := "icons\\warning.png"
    } else if (FileExist("icons\\fp1.png")) {
        iconFile := "icons\\fp1.png"
    } else {
        iconFile := "icons\\warning.png"
    }
    Gui, %FP_iconGUI%:New, -Caption +AlwaysOnTop +ToolWindow +E0x20
    Gui, %FP_iconGUI%:Margin, 0, 0
    Gui, %FP_iconGUI%:Add, Picture, x0 y0, % iconFile
    Gui, %FP_iconGUI%:Show, % "x" FP_iconPos.x " y" FP_iconPos.y " NA"
}

FP_ShowTestIcon() {
    if (FileExist("icons\\warning.png")) {
        iconFile := "icons\\warning.png"
    } else if (FileExist("icons\\fp1.png")) {
        iconFile := "icons\\fp1.png"
    } else {
        iconFile := "icons\\warning.png"
    }
    Gui, FP_TestIcon:New, -Caption +AlwaysOnTop +ToolWindow +E0x20
    Gui, FP_TestIcon:Margin, 0, 0
    Gui, FP_TestIcon:Add, Picture, x0 y0, % iconFile
    Gui, FP_TestIcon:Show, % "x" FP_iconPos.x " y" FP_iconPos.y " NA"
    FP_TestFlashCount := 6
    SetTimer, FP_TestFlash, 500
}

FP_TestFlash:
    FP_TestFlashCount--
    if (FP_TestFlashCount <= 0) {
        Gui, FP_TestIcon:Destroy
        SetTimer, FP_TestFlash, Off
    } else {
        if (WinExist("FP_TestIcon")) {
            if (WinActive("FP_TestIcon")) {
                Gui, FP_TestIcon:Hide
            } else {
                Gui, FP_TestIcon:Show, NA
            }
        }
    }
return

FP_ShowMarker(x, y) {
    global FP_markerGUI
    Gui, %FP_markerGUI%:Destroy
    Gui, %FP_markerGUI%:New, -Caption +AlwaysOnTop +ToolWindow
    Gui, %FP_markerGUI%:Color, Red
    Gui, %FP_markerGUI%:Show, % "x" x-10 " y" y-10 " w20 h20 NA"
    WinSet, Region, 0-0 w20 h20 E, %FP_markerGUI%
    SetTimer, FP_RemoveMarker, 3000
}

FP_RemoveMarker:
    Gui, %FP_markerGUI%:Destroy
    SetTimer, FP_RemoveMarker, Off
return

; ---------------------------------------------------------------------------
; Comandos tab handlers
; These functions send pre-defined or user-entered commands to the game chat.
; Each SendCommandN handler retrieves the text from its associated edit control
; and delegates the actual sending to SendChatCommand().  The UnlockFPS handler
; sends Ctrl+Home to the game.  SendChatCommand handles clipboard
; management, window activation, chat entry and restoring focus to this app.
; ---------------------------------------------------------------------------

SendCommand1:
    GuiControlGet, cmd,, Cmd1Edit
    if (cmd != "")
        SendChatCommand(cmd)
return

SendCommand2:
    GuiControlGet, cmd,, Cmd2Edit
    if (cmd != "")
        SendChatCommand(cmd)
return

SendCommand3:
    GuiControlGet, cmd,, Cmd3Edit
    if (cmd != "")
        SendChatCommand(cmd)
return

SendCommand4:
    GuiControlGet, cmd,, Cmd4Edit
    if (cmd != "")
        SendChatCommand(cmd)
return

SendCommand5:
    GuiControlGet, cmd,, Cmd5Edit
    if (cmd != "")
        SendChatCommand(cmd)
return

UnlockFPS:
    ; Activate the game window and send Ctrl+Home to unlock FPS.
    global gGameExe
    WinActivate, ahk_exe %gGameExe%
    WinWaitActive, ahk_exe %gGameExe%,, 2
    ; Brief delay to ensure the game is active before sending keystrokes.
    Sleep, 100
    ; Physically press Left Control + Home to the game.  Using the left control
    ; key explicitly helps some games detect the input.
    ; Press LCtrl down, press Home, then release LCtrl.
    SendInput, {LCtrl down}
    Sleep, 40
    SendInput, {Home}
    Sleep, 40
    SendInput, {LCtrl up}
    ; Return focus to this script's GUI (no maximize; just bring it back).
WinActivate, KuganTools_v1.3.21
WinWaitActive, KuganTools_v1.3.21,, 2
return

SendChatCommand(cmd) {
    ; Send a chat command into the game.  The command is copied to the clipboard,
    ; pasted into the game's chat, then the clipboard is restored and focus
    ; returns to this program.
    global gGameExe
    ; Save the original clipboard contents.
    ClipSaved := ClipboardAll
    ; Prepare the clipboard with the command.
    Clipboard := ""
    Clipboard := cmd
    ClipWait, 0.5
    ; Activate the game window.
    WinActivate, ahk_exe %gGameExe%
    WinWaitActive, ahk_exe %gGameExe%,, 2
    ; Open the chat, paste the command and send it.  Use SendInput and
    ; introduce small delays to ensure the game registers each key press.
    SendInput, {Enter}
    Sleep, 100
    SendInput, ^v
    Sleep, 100
    SendInput, {Enter}
    ; Some games require a second Enter to close the chat box.  Wait briefly
    ; then press Enter again to ensure the chat is closed.
    Sleep, 200
    SendInput, {Enter}
    ; Restore the previous clipboard.
    Sleep, 50
    Clipboard := ClipSaved
    ; Return focus to this script's GUI (no maximize; just bring it back).
WinActivate, KuganTools_v1.3.21
WinWaitActive, KuganTools_v1.3.21,, 2
}
