module GPIBUI

include("logging.jl")
include("args.jl")

import CImGui as ig, ModernGL, GLFW
import CImGui.CSyntax: @c, @cstatic
import ImPlot
include("settings.jl")

include("BetterSleep.jl")
using .BetterSleep
import .BetterSleep: now

include("save.jl")

using Instruments

include("globalstate.jl")

function nodeviceconnected()
	@error "No Devices Selected. Use the device selection menu to select the devices."
	return false
end

include("manager.jl")
include("elements.jl")

function (@main)(ARGS)
	
	
	## Parse ARGS
	parsed = parse_commandline()
	if parsed["sleep_interupt_time"] !== nothing
		sleepii = parse(Int, parsed["sleep_interupt_time"])
		KEITHLEY.config.sleep_interrupt_interval = millis(sleepii)
		SPECTRA.config.sleep_interrupt_interval = millis(sleepii)
	end
	if parsed["debug"]
		ENV["JULIA_DEBUG"] = GPIBUI
	end

	@debug "Start Main"
	## Initialize CImGui
	ig.set_backend(:GlfwOpenGL3)

	ctx = ig.CreateContext()

	# Create a settings handler for our custom settings
	handler = ig.lib.ImGuiSettingsHandler(
		pointer("GPIBUI"),
		ig.ImHashStr("GPIBUI"),
		C_NULL,  # ClearAllFn
		C_NULL,  # ReadInitFn
		@cfunction(my_read_open, Ptr{Cvoid},
			(Ptr{ig.lib.ImGuiContext}, Ptr{ig.lib.ImGuiSettingsHandler}, Ptr{Cchar})),
		@cfunction(my_read_line, Cvoid,
			(Ptr{ig.lib.ImGuiContext}, Ptr{ig.lib.ImGuiSettingsHandler}, Ptr{Cvoid}, Ptr{Cchar})),
		C_NULL,  # ApplyAllFn
		@cfunction(my_write_all, Cvoid,
			(Ptr{ig.lib.ImGuiContext}, Ptr{ig.lib.ImGuiSettingsHandler}, Ptr{ig.lib.ImGuiTextBuffer})),
		C_NULL   # UserData
	)

	# Ref(handler) gives a Ptr{ImGuiSettingsHandler} for the C function
	ig.AddSettingsHandler(Ref(handler))


	io = ig.GetIO()
	io.ConfigDpiScaleFonts = true
	io.ConfigDpiScaleViewports = true
	io.ConfigFlags = unsafe_load(io.ConfigFlags) | ig.lib.ImGuiConfigFlags_DockingEnable
	io.ConfigFlags = unsafe_load(io.ConfigFlags) | ig.lib.ImGuiConfigFlags_ViewportsEnable
	style = ig.GetStyle()
	p_ctx = ImPlot.CreateContext()

	## Add Icon fonts
	fonts = unsafe_load(ig.GetIO().Fonts)
	default_font = ig.AddFontDefault(fonts)
	UI.fontawesome = ig.AddFontFromFileTTF(fonts, joinpath(@__DIR__,"..", "fonts", "Font Awesome 7 Free-Regular-400.otf"), 16)
	@assert default_font != C_NULL
	@assert UI.fontawesome != C_NULL

	@debug "Rendering"
	ig.render(ctx; window_size=(100,100), window_title="Keithley 2470", on_exit=() -> ImPlot.DestroyContext(p_ctx)) do
		UI.WINSCALE = ig.GetWindowDpiScale()
		UI.sidebarwidth = 200UI.WINSCALE

		@cstatic first_frame = true begin
			if first_frame
				win = ig._current_window(Val{:GlfwOpenGL3}())
				GLFW.HideWindow(win)
			end
			first_frame = false
		end

		@cstatic exit_bool = true begin
			exit_bool || exit()
			@c ig.Begin("Plot Window", &exit_bool,
				ig.ImGuiWindowFlags_MenuBar |
				ig.ImGuiWindowFlags_NoCollapse )
		end

		@debug_once "Menu"
		menubar()

		ig.BeginGroup()

		if ig.BeginTabBar("IV and RealTime", ig.ImGuiTabBarFlags_NoCloseWithMiddleMouseButton)
			@debug_once "IV tab"
			if ig.BeginTabItem("I-V Sweep")
				ivtab()
				ig.EndTabItem()
			end
			
			@debug_once "RT tab"
			if ig.BeginTabItem("Realtime Monitor")
				rttab()
				ig.EndTabItem()
			end
			ig.EndTabBar()
		end
		
		ig.EndGroup()
		
		@debug_once "Logs"
		ig.SameLine()
		logs()

		ig.End()
	end

end

end # module GPIBUI