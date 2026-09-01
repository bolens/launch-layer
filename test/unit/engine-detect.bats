#!/usr/bin/env bash
# Unit tests for lib/steam/detect.sh engine heuristics.
load '../helpers.bash'

setup() {
	bats_unit_setup
	engine_detect_reset
}

teardown() {
	engine_detect_teardown
}

# --- Source / Unreal ---

@test "engine source2 detects gameinfo.gi" {
	engine_setup_fixture 40000001 "CS2 Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/game/csgo" && touch "$ENGINE_FIXTURE_DIR/game/csgo/gameinfo.gi"
	engine_run_detect 40000001 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint source2
}

@test "engine source detects gameinfo.txt" {
	engine_setup_fixture 40000002 "Portal Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/portal" && touch "$ENGINE_FIXTURE_DIR/portal/gameinfo.txt"
	engine_run_detect 40000002 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint source
}

@test "engine unreal detects Engine/Binaries" {
	engine_setup_fixture 40000003 "UE Game" UEGame
	mkdir -p "$ENGINE_FIXTURE_DIR/Engine/Binaries/Win64"
	engine_run_detect 40000003 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint unreal
}

@test "engine unreal detects UE3 sibling Binaries and Engine/Shaders" {
	engine_setup_fixture 40000003 "UE3 Gearbox Game" Pawpaw
	mkdir -p "$ENGINE_FIXTURE_DIR/Engine/Shaders/Binaries" \
		"$ENGINE_FIXTURE_DIR/Binaries/Win32" \
		"$ENGINE_FIXTURE_DIR/WillowGame/CookedPCConsole"
	engine_run_detect 40000003 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint unreal
}

# --- Defold ---

@test "engine defold detects game.arcd and game.arci" {
	engine_setup_fixture 40000004 "Defold Archive Game"
	touch "$ENGINE_FIXTURE_DIR/game.arcd" "$ENGINE_FIXTURE_DIR/game.arci"
	engine_run_detect 40000004 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint defold
}

@test "engine defold detects dmengine runtime" {
	engine_setup_fixture 40000005 "Defold Runtime Game"
	touch "$ENGINE_FIXTURE_DIR/dmengine.exe"
	engine_run_detect 40000005 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint defold
}

# --- Unity ---

@test "engine unity-il2cpp detects GameAssembly.dll" {
	engine_setup_fixture 40000006 "IL2CPP Game"
	touch "$ENGINE_FIXTURE_DIR/UnityPlayer.dll" "$ENGINE_FIXTURE_DIR/GameAssembly.dll"
	engine_run_detect 40000006 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint unity-il2cpp
}

@test "engine unity-il2cpp detects il2cpp_data directory" {
	engine_setup_fixture 40000007 "IL2CPP Data Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/il2cpp_data/Metadata"
	engine_run_detect 40000007 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint unity-il2cpp
}

@test "engine unity detects UnityPlayer.so" {
	engine_setup_fixture 40000008 "Unity Native Game"
	touch "$ENGINE_FIXTURE_DIR/UnityPlayer.so"
	engine_run_detect 40000008 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint unity
}

@test "engine unity detects UnityPlayer.dll" {
	engine_setup_fixture 40000009 "Unity Windows Game"
	touch "$ENGINE_FIXTURE_DIR/UnityPlayer.dll"
	engine_run_detect 40000009 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint unity
}

# --- Godot ---

@test "engine godot detects libgodot shared library" {
	engine_setup_fixture 40000010 "Godot Lib Game"
	touch "$ENGINE_FIXTURE_DIR/libgodot_linuxbsd.so"
	engine_run_detect 40000010 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint godot
}

@test "engine godot detects executable plus pck bundle" {
	engine_setup_fixture 40000011 "Godot PCK Game"
	touch "$ENGINE_FIXTURE_DIR/game.exe" "$ENGINE_FIXTURE_DIR/game.pck"
	engine_run_detect 40000011 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint godot
}

# --- CryEngine / Frostbite / REDengine ---

@test "engine cryengine detects CryEngine.dll" {
	engine_setup_fixture 40000012 "Crysis Game"
	touch "$ENGINE_FIXTURE_DIR/CryEngine.dll"
	engine_run_detect 40000012 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint cryengine
}

@test "engine cryengine detects CryEngine.so" {
	engine_setup_fixture 40000013 "CryEngine Linux Game"
	touch "$ENGINE_FIXTURE_DIR/CrySystem.so"
	engine_run_detect 40000013 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint cryengine
}

@test "engine frostbite detects Frostbite directory" {
	engine_setup_fixture 40000014 "Battlefield Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/Frostbite/Engine"
	engine_run_detect 40000014 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint frostbite
}

@test "engine frostbite detects Engine.BuildInfo dll" {
	engine_setup_fixture 40000015 "Frostbite BuildInfo Game"
	touch "$ENGINE_FIXTURE_DIR/Engine.BuildInfo_Win64_retail.dll"
	engine_run_detect 40000015 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint frostbite
}

@test "engine redengine detects r4game directory" {
	engine_setup_fixture 40000016 "Witcher Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/r4game"
	engine_run_detect 40000016 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint redengine
}

@test "engine redengine detects REDEngine dll" {
	engine_setup_fixture 40000017 "Cyberpunk Game"
	touch "$ENGINE_FIXTURE_DIR/REDEngine.dll"
	engine_run_detect 40000017 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint redengine
}

# --- Creation / RAGE / Anvil ---

@test "engine creation detects Bethesda archives in Data" {
	engine_setup_fixture 40000018 "Skyrim Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/Data" && touch "$ENGINE_FIXTURE_DIR/Data/Skyrim - Main.bsa"
	engine_run_detect 40000018 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint creation
}

@test "engine rage detects rpf archives" {
	engine_setup_fixture 40000019 "GTA Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/update/x64/dlcpacks" && touch "$ENGINE_FIXTURE_DIR/update/x64/dlcpacks/mpheist.rpf"
	engine_run_detect 40000019 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint rage
}

@test "engine anvil detects forge archives" {
	engine_setup_fixture 40000020 "AC Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/DataPC" && touch "$ENGINE_FIXTURE_DIR/DataPC/DataPC.forge"
	engine_run_detect 40000020 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint anvil
}

# --- GameMaker / Ren'Py / RPG Maker ---

@test "engine gamemaker detects data.win" {
	engine_setup_fixture 40000021 "GM Win Game"
	touch "$ENGINE_FIXTURE_DIR/data.win"
	engine_run_detect 40000021 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint gamemaker
}

@test "engine gamemaker detects options.ini and audiogroup" {
	engine_setup_fixture 40000022 "GM Linux Game"
	touch "$ENGINE_FIXTURE_DIR/options.ini" "$ENGINE_FIXTURE_DIR/audiogroup1.dat"
	engine_run_detect 40000022 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint gamemaker
}

@test "engine gamemaker detects game.unx export" {
	engine_setup_fixture 40000023 "GM Unix Game"
	touch "$ENGINE_FIXTURE_DIR/game.unx"
	engine_run_detect 40000023 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint gamemaker
}

@test "engine renpy detects renpy directory" {
	engine_setup_fixture 40000024 "VN Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/renpy/common"
	engine_run_detect 40000024 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint renpy
}

@test "engine renpy detects rpa archives" {
	engine_setup_fixture 40000025 "VN Archive Game"
	touch "$ENGINE_FIXTURE_DIR/archive.rpa"
	engine_run_detect 40000025 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint renpy
}

@test "engine rpgmaker detects MV/MZ js runtime" {
	engine_setup_fixture 40000026 "RPG MV Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/www/js" && touch "$ENGINE_FIXTURE_DIR/www/js/rpg_managers.js"
	engine_run_detect 40000026 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint rpgmaker
}

@test "engine rpgmaker detects XP/VX System/RPG_RT.exe" {
	engine_setup_fixture 40000027 "RPG XP Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/System" && touch "$ENGINE_FIXTURE_DIR/System/RPG_RT.exe"
	engine_run_detect 40000027 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint rpgmaker
}

@test "engine rpgmaker detects Game.rpgproj" {
	engine_setup_fixture 40000028 "RPG Project Game"
	touch "$ENGINE_FIXTURE_DIR/Game.rpgproj"
	engine_run_detect 40000028 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint rpgmaker
}

# --- Electron / NW.js / GDevelop ---

@test "engine electron detects resources/app.asar" {
	engine_setup_fixture 40000029 "Electron Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/resources" && touch "$ENGINE_FIXTURE_DIR/resources/app.asar"
	engine_run_detect 40000029 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint electron
}

@test "engine electron detects macOS Resources/app.asar in app bundle" {
	engine_setup_fixture 40000030 "Electron macOS Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/MyGame.app/Contents/Resources" && touch "$ENGINE_FIXTURE_DIR/MyGame.app/Contents/Resources/app.asar"
	engine_run_detect 40000030 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint electron
}

@test "engine nwjs detects nw runtime and package" {
	engine_setup_fixture 40000031 "NW.js Game"
	touch "$ENGINE_FIXTURE_DIR/nw.exe" "$ENGINE_FIXTURE_DIR/package.nw"
	engine_run_detect 40000031 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint nwjs
}

@test "engine gdevelop detects gdjs runtime" {
	engine_setup_fixture 40000032 "GDevelop Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/gdjs-evtsext/Runtime" && touch "$ENGINE_FIXTURE_DIR/gdjs-evtsext/Runtime/runtime.js"
	engine_run_detect 40000032 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint gdevelop
}

# --- MonoGame / Cocos2d / Java ---

@test "engine monogame detects FNA.dll" {
	engine_setup_fixture 40000033 "FNA Game"
	touch "$ENGINE_FIXTURE_DIR/FNA.dll"
	engine_run_detect 40000033 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint monogame
}

@test "engine monogame detects Content xnb assets" {
	engine_setup_fixture 40000034 "XNA Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/Content/Sprites" && touch "$ENGINE_FIXTURE_DIR/Content/Sprites/player.xnb"
	engine_run_detect 40000034 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint monogame
}

@test "engine cocos2d detects libcocos2d library" {
	engine_setup_fixture 40000035 "Cocos Game"
	touch "$ENGINE_FIXTURE_DIR/libcocos2d.so"
	engine_run_detect 40000035 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint cocos2d
}

@test "engine java detects bundled runtime java binary" {
	engine_setup_fixture 40000036 "Minecraft-style Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/runtime/java-runtime/bin"
	touch "$ENGINE_FIXTURE_DIR/runtime/java-runtime/bin/java"
	chmod +x "$ENGINE_FIXTURE_DIR/runtime/java-runtime/bin/java"
	engine_run_detect 40000036 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint java
}

@test "engine java detects lwjgl jar" {
	engine_setup_fixture 40000037 "LWJGL Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/lib" && touch "$ENGINE_FIXTURE_DIR/lib/lwjgl.jar"
	engine_run_detect 40000037 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint java
}

# --- Fusion / Panda3D / Torque / LÖVE ---

@test "engine fusion detects Extensions mfx" {
	engine_setup_fixture 40000038 "Fusion Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/Extensions" && touch "$ENGINE_FIXTURE_DIR/Extensions/Example.mfx"
	engine_run_detect 40000038 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint fusion
}

@test "engine fusion detects ccn data file" {
	engine_setup_fixture 40000039 "Fusion CCN Game"
	touch "$ENGINE_FIXTURE_DIR/Application.ccn"
	engine_run_detect 40000039 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint fusion
}

@test "engine panda3d detects libpanda library" {
	engine_setup_fixture 40000040 "Panda Game"
	touch "$ENGINE_FIXTURE_DIR/libpanda.so"
	engine_run_detect 40000040 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint panda3d
}

@test "engine torque detects torque.exe" {
	engine_setup_fixture 40000041 "Torque Game"
	touch "$ENGINE_FIXTURE_DIR/torque.exe"
	engine_run_detect 40000041 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint torque
}

@test "engine torque detects main.cs with torque binary" {
	engine_setup_fixture 40000042 "Torque Script Game"
	touch "$ENGINE_FIXTURE_DIR/main.cs" "$ENGINE_FIXTURE_DIR/TorqueGame.exe"
	engine_run_detect 40000042 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint torque
}

@test "engine love2d detects love.dll" {
	engine_setup_fixture 40000043 "Love DLL Game"
	touch "$ENGINE_FIXTURE_DIR/love.dll"
	engine_run_detect 40000043 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint love2d
}

@test "engine love2d detects love.so" {
	engine_setup_fixture 40000044 "Love SO Game"
	touch "$ENGINE_FIXTURE_DIR/love.so"
	engine_run_detect 40000044 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint love2d
}

# --- Adobe AIR / Build / id Tech / ScummVM ---

@test "engine adobe-air detects META-INF AIR application.xml" {
	engine_setup_fixture 40000045 "AIR Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/META-INF/AIR" && touch "$ENGINE_FIXTURE_DIR/META-INF/AIR/application.xml"
	engine_run_detect 40000045 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint adobe-air
}

@test "engine build detects grp archives" {
	engine_setup_fixture 40000046 "Duke Game"
	touch "$ENGINE_FIXTURE_DIR/duke3d.grp"
	engine_run_detect 40000046 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint build
}

@test "engine idtech detects pk4 archives" {
	engine_setup_fixture 40000047 "Doom Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/base" && touch "$ENGINE_FIXTURE_DIR/base/pak0.pk4"
	engine_run_detect 40000047 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint idtech
}

@test "engine idtech detects pk3 archives" {
	engine_setup_fixture 40000048 "Quake Game"
	touch "$ENGINE_FIXTURE_DIR/pak0.pk3"
	engine_run_detect 40000048 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint idtech
}

@test "engine scummvm detects scummvm binary" {
	engine_setup_fixture 40000049 "ScummVM Game"
	touch "$ENGINE_FIXTURE_DIR/scummvm.exe"
	engine_run_detect 40000049 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint scummvm
}

@test "engine dosbox detects DOSBox.exe in bundled directory" {
	engine_setup_fixture 40000050 "TES Arena Game" "The Elder Scrolls Arena"
	mkdir -p "$ENGINE_FIXTURE_DIR/DOSBox-0.74"
	touch "$ENGINE_FIXTURE_DIR/DOSBox-0.74/DOSBox.exe"
	engine_run_detect 40000050 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint dosbox
}

@test "engine ogre detects RenderSystem_GL and OctreeSceneManager plugins" {
	engine_setup_fixture 40000051 "Torchlight II Game" "Torchlight II"
	mkdir -p "$ENGINE_FIXTURE_DIR/lib64"
	touch "$ENGINE_FIXTURE_DIR/lib64/RenderSystem_GL.so" \
		"$ENGINE_FIXTURE_DIR/lib64/Plugin_OctreeSceneManager.so" \
		"$ENGINE_FIXTURE_DIR/lib64/libCEGUIFalagardWRBase.so"
	engine_run_detect 40000051 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint ogre
}

@test "engine sdl2 detects SDL2 and fmodstudio runtime stack" {
	engine_setup_fixture 40000052 "KarmaZoo Game" KarmaZoo
	touch "$ENGINE_FIXTURE_DIR/SDL2.dll" "$ENGINE_FIXTURE_DIR/fmodstudio.dll"
	engine_run_detect 40000052 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint sdl2
}

@test "engine openlara detects Tomb Raider I-III remaster launcher" {
	engine_setup_fixture 40000053 "TR I-III Remaster" "Tomb Raider I-III Remastered"
	touch "$ENGINE_FIXTURE_DIR/tomb123.exe" "$ENGINE_FIXTURE_DIR/PlayFabCore.Win32.dll"
	mkdir -p "$ENGINE_FIXTURE_DIR/1/ITEM" && touch "$ENGINE_FIXTURE_DIR/1/ITEM/LARA.TRM"
	engine_run_detect 40000053 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint openlara
}

@test "engine openlara detects Tomb Raider IV-VI remaster per-game modules" {
	engine_setup_fixture 40000054 "TR IV-VI Remaster" "Tomb Raider IV-VI Remastered"
	touch "$ENGINE_FIXTURE_DIR/tomb456.exe" "$ENGINE_FIXTURE_DIR/PlayFabCore.Win32.dll"
	mkdir -p "$ENGINE_FIXTURE_DIR/4/ITEM" && touch "$ENGINE_FIXTURE_DIR/4/tomb4.dll" "$ENGINE_FIXTURE_DIR/4/ITEM/PUZZLE.TRM"
	engine_run_detect 40000054 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint openlara
}

@test "engine unity detects _Data Managed bundle without UnityPlayer" {
	engine_setup_fixture 40000055 "Unity Data Game" iambread
	mkdir -p "$ENGINE_FIXTURE_DIR/IamBread_Data/Managed"
	touch "$ENGINE_FIXTURE_DIR/IamBread_Data/globalgamemanagers"
	engine_run_detect 40000055 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint unity
}

@test "engine godot detects steamsdk-godot export" {
	engine_setup_fixture 40000056 "Godot Steam SDK Game"
	touch "$ENGINE_FIXTURE_DIR/steamsdk-godot.dll" "$ENGINE_FIXTURE_DIR/game.exe"
	engine_run_detect 40000056 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint godot
}

@test "engine hashlink detects libhl and hlboot.dat" {
	engine_setup_fixture 40000057 "Dead Cells Game" "Dead Cells"
	touch "$ENGINE_FIXTURE_DIR/libhl.so" "$ENGINE_FIXTURE_DIR/hlboot.dat" "$ENGINE_FIXTURE_DIR/detect.hl"
	engine_run_detect 40000057 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint hashlink
}

@test "engine sfml detects sfml-graphics runtime" {
	engine_setup_fixture 40000058 "Dreadmyst Game" Dreadmyst
	mkdir -p "$ENGINE_FIXTURE_DIR/bin"
	touch "$ENGINE_FIXTURE_DIR/bin/sfml-graphics-2.dll" "$ENGINE_FIXTURE_DIR/bin/sfml-window-2.dll"
	engine_run_detect 40000058 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint sfml
}

@test "engine serious detects UserCfg.lua and gro archives" {
	engine_setup_fixture 40000059 "SS Fusion Game" "Serious Sam Fusion 2017"
	mkdir -p "$ENGINE_FIXTURE_DIR/Content/SeriousSam2017"
	touch "$ENGINE_FIXTURE_DIR/UserCfg.lua" "$ENGINE_FIXTURE_DIR/Content/CachedShaders_VLK.gro"
	engine_run_detect 40000059 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint serious
}

@test "engine hammerwatch detects res scenarios and PACKAGER" {
	engine_setup_fixture 40000060 "SSBD Game" "Serious Sams Bogus Detour"
	mkdir -p "$ENGINE_FIXTURE_DIR/res" "$ENGINE_FIXTURE_DIR/scenarios"
	touch "$ENGINE_FIXTURE_DIR/libGalaxy64.so" "$ENGINE_FIXTURE_DIR/PACKAGER"
	engine_run_detect 40000060 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint hammerwatch
}

@test "engine nms detects GAMEDATA and Binaries layout" {
	engine_setup_fixture 40000061 "NMS Game" "No Man's Sky"
	mkdir -p "$ENGINE_FIXTURE_DIR/GAMEDATA/PCBANKS" "$ENGINE_FIXTURE_DIR/Binaries"
	engine_run_detect 40000061 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint nms
}

@test "engine dotnet detects MAUI runtime" {
	engine_setup_fixture 40000062 "GnollHack Game" GnollHack
	touch "$ENGINE_FIXTURE_DIR/Microsoft.Maui.Controls.resources.dll"
	engine_run_detect 40000062 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint dotnet
}

@test "engine godot detects companion console exe export" {
	engine_setup_fixture 40000063 "Spin Hero Game" "Spin Hero"
	touch "$ENGINE_FIXTURE_DIR/Spin Hero.exe" "$ENGINE_FIXTURE_DIR/Spin Hero.console.exe" "$ENGINE_FIXTURE_DIR/steam_api64.dll"
	engine_run_detect 40000063 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint godot
}

@test "engine monogame detects spritefont assets" {
	engine_setup_fixture 40000064 "Touhou Crawl Game" "Touhou Crawl"
	mkdir -p "$ENGINE_FIXTURE_DIR/data/font"
	touch "$ENGINE_FIXTURE_DIR/data/font/HackGen_m.spritefont"
	engine_run_detect 40000064 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint monogame
}

@test "engine gog detects JamFiles wrapper port" {
	engine_setup_fixture 40000065 "LSL Game" "Leisure Suit Larry - Magna Cum Laude Uncut and Uncensored"
	mkdir -p "$ENGINE_FIXTURE_DIR/Data/JamFiles/PC"
	touch "$ENGINE_FIXTURE_DIR/goggame-1207659225.dll"
	engine_run_detect 40000065 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint gog
}

@test "engine titan detects Grim Dawn Engine.dll layout" {
	engine_setup_fixture 40000066 "Grim Dawn Game" "Grim Dawn"
	touch "$ENGINE_FIXTURE_DIR/Engine.dll" "$ENGINE_FIXTURE_DIR/Grim Dawn.exe"
	mkdir -p "$ENGINE_FIXTURE_DIR/Database"
	engine_run_detect 40000066 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint titan
}

@test "engine hammerwatch detects TiltedEngine.dll" {
	engine_setup_fixture 40000067 "Hammerwatch Game" Hammerwatch
	touch "$ENGINE_FIXTURE_DIR/TiltedEngine.dll" "$ENGINE_FIXTURE_DIR/assets.bin" "$ENGINE_FIXTURE_DIR/Hammerwatch.bin.x86_64"
	engine_run_detect 40000067 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint hammerwatch
}

@test "engine alephone detects Marathon alephone runtime" {
	engine_setup_fixture 40000068 "Classic Marathon Game" "Classic Marathon"
	touch "$ENGINE_FIXTURE_DIR/alephone" "$ENGINE_FIXTURE_DIR/Map.scen" "$ENGINE_FIXTURE_DIR/classic_marathon_launcher"
	chmod +x "$ENGINE_FIXTURE_DIR/alephone" "$ENGINE_FIXTURE_DIR/classic_marathon_launcher"
	engine_run_detect 40000068 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint alephone
}

@test "engine buny detects TangoPC and data.buny archives" {
	engine_setup_fixture 40000069 "SW Bounty Hunter Game" "STAR WARS Bounty Hunter"
	touch "$ENGINE_FIXTURE_DIR/TangoPC.exe" "$ENGINE_FIXTURE_DIR/data.buny"
	engine_run_detect 40000069 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint buny
}

@test "engine godot detects Godot string embedded in sparse exe export" {
	engine_setup_fixture 40000070 "Metal Goose Game" "Metal Goose"
	printf 'prefix Godot Engine suffix' >"$ENGINE_FIXTURE_DIR/Metal Goose.exe"
	engine_run_detect 40000070 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint godot
}

# --- Priority and negative behavior ---

@test "engine priority source2 wins over source when both markers exist" {
	engine_setup_fixture 40000101 "Dual Source Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/game/csgo" "$ENGINE_FIXTURE_DIR/portal"
	touch "$ENGINE_FIXTURE_DIR/game/csgo/gameinfo.gi" "$ENGINE_FIXTURE_DIR/portal/gameinfo.txt"
	engine_run_detect 40000101 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint source2
}

@test "engine priority unity-il2cpp wins over unity when both players exist" {
	engine_setup_fixture 40000102 "Dual Unity Game"
	touch "$ENGINE_FIXTURE_DIR/UnityPlayer.dll" "$ENGINE_FIXTURE_DIR/GameAssembly.dll"
	engine_run_detect 40000102 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint unity-il2cpp
}

@test "engine priority rpgmaker wins over nwjs when MV markers exist" {
	engine_setup_fixture 40000103 "RPG MV NW Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/www/js"
	touch "$ENGINE_FIXTURE_DIR/www/js/rpg_managers.js" "$ENGINE_FIXTURE_DIR/nw.exe" "$ENGINE_FIXTURE_DIR/package.nw"
	engine_run_detect 40000103 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint rpgmaker
}

@test "engine defold archive requires both arcd and arci" {
	engine_setup_fixture 40000104 "Incomplete Defold Game"
	touch "$ENGINE_FIXTURE_DIR/game.arcd"
	engine_run_markers "$ENGINE_FIXTURE_DIR"
	engine_assert_hint ""
}

@test "engine detect returns unknown for empty install directory" {
	engine_setup_fixture 40000105 "Empty Game"
	engine_run_detect 40000105 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint unknown
}

@test "engine detect returns unknown for missing appid" {
	local fake
	fake="$(mktemp -d)"
	ENGINE_FAKE_STEAM_ROOTS+=("$fake")
	engine_run_detect 49999999 "$fake"
	engine_assert_hint unknown
}

@test "engine detect resolves unity inside macOS app bundle MacOS directory" {
	engine_setup_fixture 40000106 "Unity Bundle Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/MyGame.app/Contents/MacOS"
	touch "$ENGINE_FIXTURE_DIR/MyGame.app/Contents/MacOS/UnityPlayer.dylib"
	engine_run_detect 40000106 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint unity
}

# --- Scan root helpers ---

@test "_engine_collect_scan_roots includes macOS app bundle innards" {
	engine_setup_fixture 40000201 "Scan Root Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/MyGame.app/Contents/MacOS" "$ENGINE_FIXTURE_DIR/MyGame.app/Contents/Frameworks"
	engine_run_collect_roots "$ENGINE_FIXTURE_DIR"
	[[ $status -eq 0 ]]
	[[ "$output" == *"MyGame.app/Contents/MacOS"* ]]
	[[ "$output" == *"MyGame.app/Contents/Frameworks"* ]]
}

@test "_engine_find searches inside macOS app bundle Frameworks" {
	engine_setup_fixture 40000202 "Framework Scan Game"
	mkdir -p "$ENGINE_FIXTURE_DIR/MyGame.app/Contents/Frameworks"
	touch "$ENGINE_FIXTURE_DIR/MyGame.app/Contents/Frameworks/UnityPlayer.dylib"
	engine_run_markers "$ENGINE_FIXTURE_DIR"
	engine_assert_hint unity
}

@test "engine blizzard detects Overwatch CASC layout" {
	engine_setup_fixture 40000301 "Overwatch Game" Overwatch
	touch "$ENGINE_FIXTURE_DIR/Overwatch_loader.dll" "$ENGINE_FIXTURE_DIR/vivoxsdk.dll"
	mkdir -p "$ENGINE_FIXTURE_DIR/cache/casc3" "$ENGINE_FIXTURE_DIR/BlizzardBrowser"
	engine_run_detect 40000301 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint blizzard
}

@test "engine solar2d detects Corona native runtime" {
	engine_setup_fixture 40000302 "Coromon Game" Coromon
	touch "$ENGINE_FIXTURE_DIR/CoronaLabs.Corona.Native.dll" "$ENGINE_FIXTURE_DIR/lua.dll"
	mkdir -p "$ENGINE_FIXTURE_DIR/Resources" && touch "$ENGINE_FIXTURE_DIR/Resources/resource.car"
	engine_run_detect 40000302 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint solar2d
}

@test "engine custom-cpp detects hlsl and gfx shader trees" {
	engine_setup_fixture 40000303 "Pico Park Game" PICO_PARK_ONLINE
	mkdir -p "$ENGINE_FIXTURE_DIR/resource/shader/hlsl" \
		"$ENGINE_FIXTURE_DIR/resource/shader/gfx"
	touch "$ENGINE_FIXTURE_DIR/resource/shader/hlsl/color_change_2d.vs" \
		"$ENGINE_FIXTURE_DIR/resource/shader/gfx/color_change_2d.ps"
	engine_run_detect 40000303 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint custom-cpp
}

@test "engine libgdx detects Packr jre jar manifest" {
	engine_setup_fixture 40000304 "Kakele Game" "Kakele Online - MMORPG"
	mkdir -p "$ENGINE_FIXTURE_DIR/jre/bin"
	touch "$ENGINE_FIXTURE_DIR/jre/bin/java" "$ENGINE_FIXTURE_DIR/kakele.jar"
	cat > "$ENGINE_FIXTURE_DIR/kakele.json" <<'EOF'
{
  "jrePath": "jre",
  "classPath": ["kakele.jar"],
  "mainClass": "mmorpg.main.SteamDesktopLauncher"
}
EOF
	engine_run_detect 40000304 "$ENGINE_FIXTURE_STEAM"
	engine_assert_hint libgdx
}

@test "collect_steam_library_roots reads libraryfolders.vdf via source_lib steam" {
	local tmp vdf
	tmp="$(mktemp -d)"
	vdf="$tmp/steamapps/libraryfolders.vdf"
	mkdir -p "$tmp/steamapps" /tmp/primary /tmp/secondary
	cat > "$vdf" <<'EOF'
"libraryfolders"
{
	"0"
	{
		"path"		"/tmp/primary"
	}
	"1"
	{
		"path"		"/tmp/secondary"
	}
}

EOF
	run env STEAM_ROOT="$tmp" CONFIG_DIR="${CONFIG_DIR:-$(launchlayer_root)}" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib steam
		collect_steam_library_roots | sort
	'
	[[ $status -eq 0 ]]
	[[ "$output" == *"/tmp/primary"* ]]
	[[ "$output" == *"/tmp/secondary"* ]]
	rm -rf "$tmp"
}

@test "unknown engine builds one bounded filesystem index" {
	local tmp calls
	tmp="$(mktemp -d)"
	calls="$tmp/find-calls"
	mkdir -p "$tmp/game/assets/a/b/c"
	touch "$tmp/game/assets/a/b/c/unknown.dat"
	run env ENGINE_FIND_CALLS="$calls" CONFIG_DIR="$CONFIG_DIR" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib steam config
		find() {
			printf "call\n" >> "$ENGINE_FIND_CALLS"
			command find "$@"
		}
		_detect_engine_markers "'"$tmp"'/game"
		wc -l < "$ENGINE_FIND_CALLS"
	'
	[[ $status -eq 0 ]]
	[[ "$output" =~ ^[0-6]$ ]]
}

@test "engine index cap falls back without missing markers" {
	local tmp
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/game/content"
	touch "$tmp/game/content/gameinfo.txt"
	run env LAUNCHLAYER_ENGINE_INDEX_MAX_ENTRIES=1 CONFIG_DIR="$CONFIG_DIR" bash -c '
		source "'"$BATS_TEST_DIRNAME"'/../helpers.bash"
		source_lib steam config
		_detect_engine_markers "'"$tmp"'/game"
	'
	[[ $status -eq 0 ]]
	[[ "$output" == source ]]
}
