module GPIBUI


using Match

using ArgParse

function parse_commandline()
	s = ArgParseSettings()

	@add_arg_table! s begin
		"sleep_interupt_time"
			help = "The time interval in milliseconds that the program " *
					"sleeps for between taking samples. It might be more " *
					"performant and accurate to set this value high but " *
					"it also means that you can't cancel a measurement " *
					"in less than `sleep_interupt_time` milliseconds"
	end
	parsed_args = parse_args(s) # the result is a Dict{String,Any}
	# println("Parsed args:")
	# for (key,val) in parsed_args
	# 	println("  $key  =>  $(repr(val))")
	# end
	return parsed_args
end

import CImGui as ig, ModernGL, GLFW
import CImGui.CSyntax: @c, @cstatic
import ImPlot

global plotlock = ReentrantLock()
global gpiblock = ReentrantLock()

using NativeFileDialog, DelimitedFiles

include("BetterSleep.jl")
using .BetterSleep
import .BetterSleep: now
using Dates, TimesDates

function savetofile(times, currs, volts, timestamp_mode, filepath)
	open(filepath, "w") do io
		isempty(times) && return
		time = copy(times)
		if timestamp_mode === :datetime
			timedatenow, nanonow = TimeDate(Dates.now()), BetterSleep.now()
			synthetic_first_time = timedatenow - Nanosecond((nanonow - time[1]).ns)
			time = [synthetic_first_time + Nanosecond((tt - time[1]).ns) for tt in time]
			timeunit = "[DateTime]"
		elseif timestamp_mode === :seconds
			time = (time .- [time[1]]) .|> x->x.ns/1e9
			timeunit = "[Seconds]"
		else
			time = time .|> x->x.ns
			timeunit = "[Nanoseconds]"
		end
		writedlm(io, ["TimeStamp "*timeunit "Voltage [V]" "Current [A]"], ',')
		writedlm(io, [time volts currs], ',')
	end
end

global sleep_interupt_interval::Nano = millis(100)

using Instruments

global RM::UInt32 = ResourceManager()
global Keithley::GenericInstrument = GenericInstrument()
global Spectra::GenericInstrument = GenericInstrument()


# Can be :datetime, :seconds, or :nanoseconds
global timestamp_mode::Symbol = :seconds


# Initialize Plot Axis Flags
global xflags = ImPlot.ImPlotAxisFlags_None | ImPlot.ImPlotAxisFlags_AutoFit
global yflags = ImPlot.ImPlotAxisFlags_None | ImPlot.ImPlotAxisFlags_AutoFit

global WINSCALE::Float32 = 1.0
global sidebarwidth = 100WINSCALE


function (@main)(ARGS)
	global sleep_interupt_interval
	## Parse ARGS
	parsed = parse_commandline()
	if parsed["sleep_interupt_time"] !== nothing
		sleepii = parse(Int, parsed["sleep_interupt_time"])
		sleep_interupt_interval = millis(sleepii)
	end

	
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

	ig.render(ctx; window_size=(100,100), window_title="Keithley 2470", on_exit=() -> ImPlot.DestroyContext(p_ctx)) do
		global WINSCALE
		WINSCALE = ig.GetWindowDpiScale()

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

		menubar()

		

		ig.End()
	end

end



function menubar()
	if ig.BeginMenuBar()
		if ig.BeginMenu("Timestamp Export Mode")
			global timestamp_mode
			selected::Int32 = @match timestamp_mode begin
				:datetime => 1
				:seconds => 2
				:nanoseconds => 3
				_ => -1
			end

			@c ig.RadioButton("DateTime Timestamps", &selected, 1)
			@c ig.RadioButton("Seconds since start of capture", &selected, 2)
			@c ig.RadioButton("Nanoseconds since start of capture", &selected, 3)

			global timestamp_mode
			timestamp_mode = [:datetime, :seconds, :nanoseconds][selected]
			ig.EndMenu()
		end

		if ig.BeginMenu("Device Selection")
			global RM
			instrs = nothing
			try
				instrs = find_resources(RM)
			catch
				RM = ResourceManager()
				instrs = find_resources(RM)
			end
			ig.BeginGroup()
			@cstatic selected_keithley::Cint = 0 selected_spectra::Cint = 0 begin
				@c ig.Combo("Keithley", &selected_keithley, instrs)
				@c ig.Combo("SpectraPro", &selected_spectra, instrs)
			end
			ig.EndGroup()
			ig.EndMenu()
		end

		ig.EndMenuBar()
	end
end


end # module GPIBUI
