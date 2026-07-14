global spectra_input::Channel{String} = Channel{String}(Inf)
global spectra_output::Channel{String} = Channel{String}(Inf)
global kill_manager::Ref{Bool} = Ref(false)

global spectra_status::Threads.Atomic{UInt16} = Threads.Atomic{UInt16}(0)

global spectra_sample_rate::Nano = millis(40)

function initialize_spectra()
    # Things to get NM, NM/MIN, NM/JOG, GRATING, TURRET, GRATINGS, TURRETS

    nm = (ask_spectra("NM"))
    nmmin = (ask_spectra("NM/MIN"))
    nmjog = (ask_spectra("NM/JOG"))
    selectedG = (ask_spectra("GRATING"))
    selectedT = (ask_spectra("TURRET"))
    listG = split(ask_spectra("GRATINGS"), '\r', keepempty=false) .|> filter(isprint) .|> strip
    listT = split(ask_spectra("TURRETS"), '\r', keepempty=false) .|> filter(isprint) .|> strip
    filter!(!=(""), listT)

    # @info "NM       = $nm"
    # @info "NM/MIN   = $nmmin"
    # @info "NM/JOG   = $nmjog"
    # @info "GRATING  = $selectedG"
    # @info "TURRET   = $selectedT"
    # @info "GRATINGS = \n$(join(listG, '\n'))"
    # @info "TURRETS  = \n$(join(listT, '\n'))"

    return nm, nmmin, nmjog, selectedG, selectedT, listG, listT
end

# NOTE: NEVER try to read from the spectrapro 150 unless it is indicating 
# that you can read from it!
function spectramanager()
    global gpiblock
    CMDBIT = 0b0000_0001
    ERRBIT = 0b0000_0010
    RESBIT = 0b1000_0000
    global kill_manager
    while !kill_manager[]
        global Spectra
        S = spectra_status[] = statusbyte(Spectra)
        if S & ERRBIT != 0
            if S & RESBIT != 0
                output = ""
                @lock gpiblock output = read(Spectra)
                @error output
            else
                @warn "The Spectra is indicating an error but not has nothing to read"
            end
        elseif S & RESBIT != 0
            @lock gpiblock put!(spectra_output, read(Spectra))
        elseif S & CMDBIT != 0 && !isempty(spectra_input)
            @lock gpiblock write(Spectra, take!(spectra_input)*"\r")
        end
        global sleep_interupt_interval
        global spectra_sample_rate
        interuptsleep(spectra_sample_rate, kill_manager, sleep_interupt_interval)
    end
end


function ask_spectra(name)
    global spectra_input
    put!(spectra_input, "?"*name)
    return take!(spectra_output)
end