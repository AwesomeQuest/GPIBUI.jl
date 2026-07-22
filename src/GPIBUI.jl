module GPIBUI


include("args.jl")

import CImGui as ig, ModernGL, GLFW
import CImGui.CSyntax: @c, @cstatic
import ImPlot

global plotlock::ReentrantLock = ReentrantLock()
global gpiblock::ReentrantLock = ReentrantLock()

include("BetterSleep.jl")
using .BetterSleep
import .BetterSleep: now

include("save.jl")

global sleep_interupt_interval::Nano = millis(100)

using Instruments

global RM::UInt32 = ResourceManager()
global Keithley::GenericInstrument = GenericInstrument()
global Spectra::GenericInstrument = GenericInstrument()


# Global System State
const keithley_types = (
	"MODEL 2400",
	"MODEL 2470",
)
global selected_keithley_type::Int = 0

global is_connected::Bool = false
function nodeviceconnected()
	@error "No Devices Selected. Use the device selection menu to select the devices."
	return false
end

global spectra_is_read::Bool = false

global iv_is_sweeping::Ref{Bool}	= Ref(false)
global iv_cancel_sweep::Ref{Bool}	= Ref(false)

global rt_is_monitoring::Ref{Bool}	= Ref(false)
global rt_cancel_monitor::Ref{Bool}	= Ref(false)

global rt_sample_period::Nano = millis(100)

global event_list::Vector{String} = []

# Can be :datetime, :seconds, or :nanoseconds
global timestamp_mode::Symbol = :seconds

# Global data for storage
global iv_times::Vector{Nano}	 = []
global iv_currs::Vector{Float64} = []
global iv_volts::Vector{Float64} = []
global iv_waves::Vector{Float64} = []

global rt_times::Vector{Nano}	 = []
global rt_currs::Vector{Float64} = []
global rt_volts::Vector{Float64} = []
global rt_waves::Vector{Float64} = []

# Initialize Plot Axis Flags
global xflags = ImPlot.ImPlotAxisFlags_None | ImPlot.ImPlotAxisFlags_AutoFit
global yflags = ImPlot.ImPlotAxisFlags_None | ImPlot.ImPlotAxisFlags_AutoFit

global WINSCALE::Float32 = 1.0
global sidebarwidth = 200WINSCALE

global fontawesome::Ptr{ig.lib.ImFont} = C_NULL

include("manager.jl")
include("elements.jl")

function (@main)(ARGS)
	# @info "Start"
	global sleep_interupt_interval
	## Parse ARGS
	parsed = parse_commandline()
	if parsed["sleep_interupt_time"] !== nothing
		sleepii = parse(Int, parsed["sleep_interupt_time"])
		sleep_interupt_interval = millis(sleepii)
	end
	if parsed["debug"]
		ENV["JULIA_DEBUG"] = GPIBUI
	end

	@debug "Start Main"
	## Initialize CImGui
	ig.set_backend(:GlfwOpenGL3)

	ctx = ig.CreateContext()
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
	global fontawesome = ig.AddFontFromFileTTF(fonts, joinpath(@__DIR__,"..", "fonts", "Font Awesome 7 Free-Regular-400.otf"), 16)
	@assert default_font != C_NULL
	@assert fontawesome != C_NULL

	@debug "Rendering"
	ig.render(ctx; window_size=(100,100), window_title="Keithley 2470", on_exit=() -> ImPlot.DestroyContext(p_ctx)) do
		global WINSCALE
		global sidebarwidth
		WINSCALE = ig.GetWindowDpiScale()
		sidebarwidth = 200WINSCALE

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