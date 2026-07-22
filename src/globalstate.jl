# ═══════════════════════════════════════════
# Configuration structs
# ═══════════════════════════════════════════

@kwdef mutable struct SpectraConfig
	sample_rate::Nano				= millis(10)
	status_update_interval::Nano	= millis(1000)
	sleep_interrupt_interval::Nano	= millis(100)
end

@kwdef mutable struct KeithleyConfig
	sample_period::Nano				= millis(100)
	sleep_interrupt_interval::Nano	= millis(100)
end

# ═══════════════════════════════════════════
# Status / Controller structs
# ═══════════════════════════════════════════

struct SpectraStatus
	fresh::Bool
	nm::Float64
	nmmin::Float64
	nmjog::Float64
	turret::Int
	grating::Int
end

@kwdef mutable struct SpectraController
	config::SpectraConfig				= SpectraConfig()
	gpib::GenericInstrument				= GenericInstrument()
	input::Channel{String}				= Channel{String}(Inf)
	output::Channel{String}				= Channel{String}(Inf)
	kill::Threads.Atomic{Bool}			= Threads.Atomic{Bool}(false)
	(@atomic status::SpectraStatus)		= SpectraStatus(false,0,0,0,0,0)
	io_lock::ReentrantLock				= ReentrantLock()
	is_read::Bool						= false
end

@kwdef mutable struct KeithleyController
	config::KeithleyConfig	= KeithleyConfig()
	gpib::GenericInstrument = GenericInstrument()
	selected_type::Int		= -1
end

# ═══════════════════════════════════════════
# Data struct
# ═══════════════════════════════════════════

@kwdef mutable struct ExperimentData
	iv_times::Vector{Nano}		= []
	iv_currs::Vector{Float64}	= []
	iv_volts::Vector{Float64}	= []
	iv_waves::Vector{Float64}	= []
	rt_times::Vector{Nano}		= []
	rt_currs::Vector{Float64}	= []
	rt_volts::Vector{Float64}	= []
	rt_waves::Vector{Float64}	= []
	event_list::Vector{String}	= []
	timestamp_mode::Symbol		= :seconds # Can be :datetime, :seconds, or :nanoseconds
	lock::ReentrantLock			= ReentrantLock()
end

# ═══════════════════════════════════════════
# Processes struct
# ═══════════════════════════════════════════

@kwdef mutable struct Processes
	iv_active::Threads.Atomic{Bool} = Threads.Atomic{Bool}(false)
	iv_cancel::Threads.Atomic{Bool} = Threads.Atomic{Bool}(false)

	rt_active::Threads.Atomic{Bool} = Threads.Atomic{Bool}(false)
	rt_cancel::Threads.Atomic{Bool} = Threads.Atomic{Bool}(false)
end

# ═══════════════════════════════════════════
# UI struct
# ═══════════════════════════════════════════

@kwdef mutable struct UIConfig
	xflags::UInt32					= ImPlot.ImPlotAxisFlags_None | ImPlot.ImPlotAxisFlags_AutoFit
	yflags::UInt32					= ImPlot.ImPlotAxisFlags_None | ImPlot.ImPlotAxisFlags_AutoFit
	WINSCALE::Float32				= 1.0
	sidebarwidth::Float32			= 200.0
	fontawesome::Ptr{ig.lib.ImFont}	= C_NULL
	processes::Processes			= Processes()
	last_time_button_pressed::Nano	= seconds(0)
	waiting_tasks::Channel{Tuple{SpectraStatus, String}}	= Channel{Tuple{SpectraStatus, String}}(Inf)
end

# ═══════════════════════════════════════════
# Found Instruments struct
# ═══════════════════════════════════════════

@kwdef mutable struct FoundInstrs
	RM::Cuint								 = ResourceManager()
	instruments::Vector{String} 			 = []
	selected_keithley::Int32				 = 0
	selected_spectra::Int32					 = 0
	possible_keithley::Union{Int32, Nothing} = nothing
	possible_spectra::Union{Int32, Nothing}	 = nothing
end

# ═══════════════════════════════════════════
# Global singletons (module-level `const`)
# ═══════════════════════════════════════════

const GPIB_LOCK = ReentrantLock()
const PLOT_LOCK = ReentrantLock()
const SLEEP_INTERRUPT_INTERVAL::Nano = millis(100)

# Controllers constructed after GPIB instruments are opened
const SPECTRA = SpectraController()
const KEITHLEY = KeithleyController()

global CONNECTED::Threads.Atomic{Bool} = Threads.Atomic{Bool}(false)

# Pre-allocated data store
const DATA = ExperimentData()

const UI = UIConfig()

const INSTRS = FoundInstrs()

const KEITHLEY_TYPES = (
	"MODEL 2400",
	"MODEL 2470",
)

macro modeswitch(mode_val, block)
	modes = KEITHLEY_TYPES
    filter!(e -> !(e isa LineNumberNode), block.args)
    length(block.args) == length(modes) || error(
        "Expected $(length(modes)) expressions, got $(length(block.args))"
    )
    block.args[1].args[3] != modes[1] && throw(ArgumentError(
        "Incorrect Designator, \"$(block.args[1].args[3])\" is not equal to \"$(modes[1])\""
    ))
    result = Expr(:if, :($(esc(mode_val)) == $(modes[1])), esc(block.args[1].args[4]))
    cur = result
    for i in 2:length(modes)
        block.args[i].args[3] != modes[i] && throw(ArgumentError(
            "Incorrect Designator, \"$(block.args[i].args[3])\" is not equal to \"$(modes[i])\""
        ))
        branch = Expr(:elseif, :($(esc(mode_val)) == $(modes[i])), esc(block.args[i].args[4]))
        push!(cur.args, branch)
        cur = branch
    end
	push!(cur.args, :(error("unknown mode: ", $(esc(mode_val)))))
    return result
end